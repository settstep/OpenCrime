extends "res://scripts/main.gd"

const PlayerScene = preload("res://scenes/player.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const SNAPSHOT_INTERVAL := 0.05
const INPUT_TIMEOUT_MS := 1000
const SNAPSHOT_TIMEOUT_MS := 1000
const MAX_PLACE_BYTES := 8 * 1024 * 1024
const MAX_COMPRESSED_BYTES := 4 * 1024 * 1024

var dedicated := false
var place_data: Dictionary = {}
var client_waiting_for_map := false
var map_ready := true
var players: Dictionary = {}
var inputs: Dictionary = {}
var input_times: Dictionary = {}
var slots: Dictionary = {}
var driver_id := 0
var pending_interactions: Array[int] = []
var snapshot_timer := 0.0
var remote_car_speed := 0.0
var last_car_snapshot_ms := 0
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
		if place_data.is_empty():
			place_data = PlaceStore.find_by_id("thalhofen")
		connected = true
		_setup_missions(place_data)
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if dedicated:
			$HUD.hide()
		else:
			_add_server_player(1)
			status.text = "Server gestartet."
	else:
		map_ready = not client_waiting_for_map
		if not map_ready:
			for node_name in ["Ground", "Road", "Building1", "Building2", "Car"]:
				get_node(node_name).hide()
		car.set_physics_process(false)
		car.collision_layer = 0
		car.collision_mask = 0
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		status.text = "Verbinde mit dem Server ..."


func _process(delta: float) -> void:
	if dedicated or not connected or not map_ready:
		return
	var local_id := multiplayer.get_unique_id()
	if driver_id == local_id:
		var speed := _horizontal_speed(car) if multiplayer.is_server() else remote_car_speed
		if not multiplayer.is_server() and Time.get_ticks_msec() - last_car_snapshot_ms > SNAPSHOT_TIMEOUT_MS:
			speed = 0.0
		_update_camera(car, speed, delta)
		game_map.update_position(car.global_position)
	elif players.has(local_id):
		var local_player: CharacterBody3D = players[local_id]
		_update_camera(local_player, 0.0, delta)
		game_map.update_position(local_player.global_position)
	if players.has(local_id):
		_show_health(players[local_id].health)


func _unhandled_input(event: InputEvent) -> void:
	if dedicated:
		return
	if map_open or missions_open or _handle_menu_input(event) or menu_open or not connected or not map_ready:
		return
	if event.is_action_pressed("show_missions") and not event.is_echo():
		_open_missions()
		return
	if event.is_action_pressed("show_map") and not event.is_echo():
		_open_map()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		if multiplayer.is_server():
			pending_interactions.append(1)
		else:
			_request_interaction.rpc_id(1)


func _physics_process(delta: float) -> void:
	if not connected or not map_ready:
		return
	if multiplayer.is_server():
		if not dedicated:
			_set_input(1, _local_movement_input())
		for peer_id in players:
			var body: PlayerScript = players[peer_id]
			if body.health == 0:
				if _try_respawn(body):
					_notify(peer_id, "Am Startpunkt mit 25 % Lebensenergie wiederbelebt.")
				continue
			var direction := Vector2.ZERO
			if Time.get_ticks_msec() - int(input_times.get(peer_id, 0)) <= INPUT_TIMEOUT_MS:
				direction = inputs.get(peer_id, Vector2.ZERO)
			body.movement_input = direction
			if peer_id == driver_id:
				car.movement_input = direction
		for peer_id in pending_interactions:
			_interact(peer_id)
		pending_interactions.clear()
		if mission_ready:
			for peer_id in players:
				if players[peer_id].health > 0:
					mission_manager.visit(peer_id, players[peer_id].global_position, driver_id != peer_id)
		snapshot_timer += delta
		if snapshot_timer >= SNAPSHOT_INTERVAL:
			snapshot_timer = 0.0
			_send_snapshot()
	else:
		var direction := _local_movement_input()
		_submit_input.rpc_id(1, direction)


func _is_network_game() -> bool:
	return true


func _on_car_impact(speed: float) -> void:
	if not multiplayer.is_server() or not players.has(driver_id):
		return
	var peer_id := driver_id
	if _damage_player(players[peer_id], speed):
		driver_id = 0
		car.occupied = false
		car.movement_input = Vector2.ZERO
		car.velocity = Vector3.ZERO
		_set_input(peer_id, Vector2.ZERO)
		while pending_interactions.has(peer_id):
			pending_interactions.erase(peer_id)
		_notify(peer_id, "Warte auf einen freien Startplatz zur Wiederbelebung.")


func _local_movement_input() -> Vector2:
	if menu_open or map_open or missions_open:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _on_peer_connected(peer_id: int) -> void:
	var raw := JSON.stringify(place_data).to_utf8_buffer()
	if raw.size() > MAX_PLACE_BYTES:
		push_error("Server-Ort ist für die Übertragung zu groß.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	var compressed := raw.compress(FileAccess.COMPRESSION_GZIP)
	if compressed.size() > MAX_COMPRESSED_BYTES:
		push_error("Komprimierter Server-Ort ist für die Übertragung zu groß.")
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_verify_map_scale.rpc_id(peer_id, float(ProjectSettings.get_setting(OSMMap.SCALE_SETTING)))
	_receive_place.rpc_id(peer_id, compressed)
	_add_server_player(peer_id)
	print("Spieler verbunden: ", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mission_ready:
		mission_manager.remove_player(peer_id)
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
	body.spawn_position = body.global_position
	_set_input(peer_id, Vector2.ZERO)
	if mission_ready:
		var added := mission_manager.add_player(peer_id)
		mission_manager._notify_all()
		if not added:
			_send_mission_error(peer_id, mission_manager.error)
	else:
		_send_mission_error(peer_id, mission_manager.error)


func _on_mission_changed(peer_id: int) -> void:
	if not mission_manager.players.has(peer_id):
		return
	var state: Dictionary = mission_manager.view_for(peer_id)
	if peer_id == 1 and not dedicated:
		_show_mission_state(state, peer_id)
	else:
		_receive_mission_state.rpc_id(peer_id, state)


func _on_mission_notification(peer_id: int, text: String) -> void:
	_send_mission_error(peer_id, text)


@rpc("authority", "call_remote", "reliable")
func _receive_mission_state(state: Dictionary) -> void:
	_show_mission_state(state, multiplayer.get_unique_id())


func _send_mission_error(peer_id: int, text: String) -> void:
	if peer_id == 1 and not dedicated:
		_mission_result(text)
	else:
		_receive_mission_error.rpc_id(peer_id, text)


@rpc("authority", "call_remote", "reliable")
func _receive_mission_error(text: String) -> void:
	_mission_result(text)


func _on_mission_accept(id: String) -> void:
	_request_mission_action("accept", id, 0)


func _on_mission_defer(id: String) -> void:
	_request_mission_action("defer", id, 0)


func _on_mission_invite(peer_id: int) -> void:
	_request_mission_action("invite", "", peer_id)


func _request_mission_action(action: String, id: String, other: int) -> void:
	if multiplayer.is_server():
		_apply_mission_action(1, action, id, other)
	else:
		_mission_action.rpc_id(1, action, id, other)


@rpc("any_peer", "call_remote", "reliable")
func _mission_action(action: String, id: String, other: int) -> void:
	if multiplayer.is_server():
		_apply_mission_action(multiplayer.get_remote_sender_id(), action, id, other)


func _apply_mission_action(peer_id: int, action: String, id: String, other: int) -> void:
	if not mission_ready:
		_send_mission_error(peer_id, "Aufträge sind nicht verfügbar.")
		return
	var result := ""
	match action:
		"accept":
			result = mission_manager.accept(peer_id, id)
		"defer":
			result = mission_manager.defer_offer(peer_id, id)
		"invite":
			result = mission_manager.invite(peer_id, other)
		_:
			result = "Unbekannte Auftragsaktion."
	_send_mission_error(peer_id, result)


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


@rpc("authority", "call_remote", "reliable")
func _receive_place(compressed: PackedByteArray) -> void:
	if not connected:
		return
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED_BYTES:
		_reject_place("Server-Ort ist zu groß oder leer.")
		return
	var data := compressed.decompress_dynamic(MAX_PLACE_BYTES, FileAccess.COMPRESSION_GZIP)
	var json := JSON.new()
	if data.is_empty() or json.parse(data.get_string_from_utf8()) != OK or not json.data is Dictionary or not PlaceStore.is_valid(json.data):
		_reject_place("Server hat ungültige Ortsdaten gesendet.")
		return
	if not OSMMap.populate(self, json.data):
		_reject_place("Server-Ort konnte nicht aufgebaut werden.")
		return
	place_data = json.data
	_configure_map(place_data)
	map_ready = true
	$Ground.show()
	car.show()
	status.text = "Mit dem Server verbunden: " + place_data.name


func _reject_place(message: String) -> void:
	connected = false
	multiplayer.multiplayer_peer.close()
	status.text = message
	push_error(message)


@rpc("any_peer", "call_remote", "reliable")
func _request_interaction() -> void:
	if multiplayer.is_server():
		pending_interactions.append(multiplayer.get_remote_sender_id())


func _interact(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var body: PlayerScript = players[peer_id]
	if body.health == 0:
		return
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
		states[peer_id] = [body.global_position, body.visible, body.health]
	_receive_snapshot.rpc(states, car.global_position, car.global_rotation.y, driver_id, _horizontal_speed(car))


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(states: Dictionary, car_position: Vector3, car_angle: float, current_driver: int, car_speed: float) -> void:
	if not map_ready:
		return
	if not is_finite(car_speed) or car_speed < 0.0:
		push_error("Ungültige Fahrzeuggeschwindigkeit vom Server.")
		return
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
		body.health = states[peer_id][2]
	car.global_position = car_position
	car.global_rotation.y = car_angle
	driver_id = current_driver
	remote_car_speed = car_speed
	last_car_snapshot_ms = Time.get_ticks_msec()


func _on_connected() -> void:
	connected = true
	status.text = "Verbunden – lade Server-Ort ..." if not map_ready else "Mit dem Server verbunden."


func _on_connection_failed() -> void:
	connected = false
	status.text = "Verbindung fehlgeschlagen. Spiel neu starten und Adresse prüfen."


func _on_server_disconnected() -> void:
	if not connected:
		return
	connected = false
	status.text = "Serververbindung verloren. Spiel zum erneuten Verbinden neu starten."
