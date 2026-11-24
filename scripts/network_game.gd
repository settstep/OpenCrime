extends "res://scripts/main.gd"

const PlayerScene = preload("res://scenes/player.tscn")
const PlayerScript = preload("res://scripts/player.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const SNAPSHOT_INTERVAL := 0.05
const INPUT_TIMEOUT_MS := 1000

var dedicated := false
var players: Dictionary = {}
var inputs: Dictionary = {}
var input_times: Dictionary = {}
var slots: Dictionary = {}
var driver_id := 0
var pending_interactions: Array[int] = []
var snapshot_timer := 0.0
var connected := false
var players_container: Node3D


func _ready() -> void:
	super._ready()
	remove_child(player)
	player.queue_free()
	players_container = Node3D.new()
	players_container.name = "Players"
	add_child(players_container)
	car.uses_local_input = false

	if multiplayer.is_server():
		connected = true
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if dedicated:
			$HUD.hide()
		else:
			_add_server_player(1)
			status.text = "Server gestartet."
	else:
		car.set_physics_process(false)
		car.collision_layer = 0
		car.collision_mask = 0
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		status.text = "Verbinde mit dem Server ..."


func _process(_delta: float) -> void:
	if dedicated or not connected:
		return
	var local_id := multiplayer.get_unique_id()
	if driver_id == local_id:
		camera.global_position = car.global_position + Vector3(0, 20, 0)
	elif players.has(local_id):
		var local_player: CharacterBody3D = players[local_id]
		camera.global_position = local_player.global_position + Vector3(0, 20, 0)


func _unhandled_input(event: InputEvent) -> void:
	if dedicated:
		return
	if _handle_menu_input(event) or menu_open or not connected:
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		if multiplayer.is_server():
			pending_interactions.append(1)
		else:
			_request_interaction.rpc_id(1)


func _physics_process(delta: float) -> void:
	if not connected:
		return
	if multiplayer.is_server():
		if not dedicated:
			_set_input(1, _local_movement_input())
		for peer_id in players:
			var body: PlayerScript = players[peer_id]
			var direction := Vector2.ZERO
			if Time.get_ticks_msec() - int(input_times.get(peer_id, 0)) <= INPUT_TIMEOUT_MS:
				direction = inputs.get(peer_id, Vector2.ZERO)
			body.movement_input = direction
			if peer_id == driver_id:
				car.movement_input = direction
		for peer_id in pending_interactions:
			_interact(peer_id)
		pending_interactions.clear()
		snapshot_timer += delta
		if snapshot_timer >= SNAPSHOT_INTERVAL:
			snapshot_timer = 0.0
			_send_snapshot()
	else:
		var direction := _local_movement_input()
		_submit_input.rpc_id(1, direction)


func _is_network_game() -> bool:
	return true


func _local_movement_input() -> Vector2:
	if menu_open:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _on_peer_connected(peer_id: int) -> void:
	_add_server_player(peer_id)
	_verify_map_scale.rpc_id(peer_id, float(ProjectSettings.get_setting(OSMMap.SCALE_SETTING)))
	print("Spieler verbunden: ", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if driver_id == peer_id:
		driver_id = 0
		car.occupied = false
		car.movement_input = Vector2.ZERO
	if players.has(peer_id):
		players[peer_id].queue_free()
		players.erase(peer_id)
	inputs.erase(peer_id)
	input_times.erase(peer_id)
	slots.erase(peer_id)
	print("Spieler getrennt: ", peer_id)


func _add_server_player(peer_id: int) -> void:
	var slot := 0
	while slots.values().has(slot):
		slot += 1
	slots[peer_id] = slot
	var body := _create_player(peer_id)
	body.uses_local_input = false
	body.position = Vector3(float(slot % 3 - 1) * 1.5, 0.9, 2.0 + float(slot / 3) * 1.5)
	_set_input(peer_id, Vector2.ZERO)


func _create_player(peer_id: int) -> PlayerScript:
	var body: PlayerScript = PlayerScene.instantiate()
	body.name = "Peer_%d" % peer_id
	players_container.add_child(body)
	players[peer_id] = body
	return body


func _set_input(peer_id: int, direction: Vector2) -> void:
	if players.has(peer_id) and direction.is_finite():
		inputs[peer_id] = direction.limit_length(1.0)
		input_times[peer_id] = Time.get_ticks_msec()


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _submit_input(direction: Vector2) -> void:
	if multiplayer.is_server():
		_set_input(multiplayer.get_remote_sender_id(), direction)


@rpc("authority", "call_remote", "reliable")
func _verify_map_scale(server_scale: float) -> void:
	var local_scale := float(ProjectSettings.get_setting(OSMMap.SCALE_SETTING))
	if server_scale != local_scale:
		connected = false
		multiplayer.multiplayer_peer.close()
		status.text = "Kartenfaktor stimmt nicht mit dem Server überein (Server: %s, lokal: %s)." % [server_scale, local_scale]


@rpc("any_peer", "call_remote", "reliable")
func _request_interaction() -> void:
	if multiplayer.is_server():
		pending_interactions.append(multiplayer.get_remote_sender_id())


func _interact(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var body: PlayerScript = players[peer_id]
	if driver_id == peer_id:
		if VehicleInteraction.exit(body, car, player_collision_layer, player_collision_mask):
			driver_id = 0
			car.occupied = false
			car.movement_input = Vector2.ZERO
			_notify(peer_id, "")
		else:
			_notify(peer_id, "Hier ist kein sicherer Platz zum Aussteigen.")
	elif body.global_position.distance_to(car.global_position) > ENTER_DISTANCE:
		_notify(peer_id, "Gehe näher an das Auto heran.")
	elif driver_id != 0:
		_notify(peer_id, "Das Auto ist bereits besetzt.")
	else:
		driver_id = peer_id
		car.occupied = true
		VehicleInteraction.enter(body)
		_notify(peer_id, "")


func _notify(peer_id: int, message: String) -> void:
	if peer_id == 1:
		status.text = message
	else:
		_show_status.rpc_id(peer_id, message)


@rpc("authority", "call_remote", "reliable")
func _show_status(message: String) -> void:
	status.text = message


func _send_snapshot() -> void:
	if multiplayer.get_peers().is_empty():
		return
	var states := {}
	for peer_id in players:
		var body: PlayerScript = players[peer_id]
		states[peer_id] = [body.global_position, body.visible]
	_receive_snapshot.rpc(states, car.global_position, car.global_rotation.y, driver_id)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(states: Dictionary, car_position: Vector3, car_angle: float, current_driver: int) -> void:
	for peer_id in players.keys():
		if not states.has(peer_id):
			players[peer_id].queue_free()
			players.erase(peer_id)
	for peer_id in states:
		var body: PlayerScript
		if not players.has(peer_id):
			body = _create_player(peer_id)
			body.set_physics_process(false)
			body.collision_layer = 0
			body.collision_mask = 0
		else:
			body = players[peer_id]
		body.global_position = states[peer_id][0]
		body.visible = states[peer_id][1]
	car.global_position = car_position
	car.global_rotation.y = car_angle
	driver_id = current_driver


func _on_connected() -> void:
	connected = true
	status.text = "Mit dem Server verbunden."


func _on_connection_failed() -> void:
	connected = false
	status.text = "Verbindung fehlgeschlagen. Spiel neu starten und Adresse prüfen."


func _on_server_disconnected() -> void:
	if not connected:
		return
	connected = false
	status.text = "Serververbindung verloren. Spiel zum erneuten Verbinden neu starten."
