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
var pending_interactions: Array[int] = []
var snapshot_timer := 0.0
var remote_car_speed := 0.0
var last_car_snapshot_ms := 0
var connected := false
var players_container: Node3D
var car_spawn_incomplete := false


func _ready() -> void:
	super._ready()
	remove_child(player)
	player.queue_free()
	players_container = Node3D.new()
	players_container.name = "Players"
	add_child(players_container)
	car.uses_local_input = false
	if multiplayer.is_server() and map_block_stream != null:
		map_block_stream.block_loaded.connect(_broadcast_map_block)

	if multiplayer.is_server():
		if place_data.is_empty():
			place_data = PlaceStore.find_by_id("thalhofen")
		connected = true
		_setup_missions(place_data)
		car_spawn_incomplete = not _spawn_cars(place_data, Vector3.ZERO)
		for vehicle in cars:
			vehicle.uses_local_input = false
		_setup_first_aid()
		_setup_medkit()
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		if dedicated:
			$HUD.hide()
		else:
			_add_server_player(1)
			status.text = "Server gestartet. " + CAR_SPAWN_WARNING if car_spawn_incomplete else "Server gestartet."
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
	if building_edits.load_failed:
		status.text = building_edits.error


func _process(delta: float) -> void:
	if dedicated or not connected or not map_ready:
		return
	var local_id := multiplayer.get_unique_id()
	var driven := _driven_car(local_id)
	if driven != null:
		var speed := _horizontal_speed(driven) if multiplayer.is_server() else remote_car_speed
		if not multiplayer.is_server() and Time.get_ticks_msec() - last_car_snapshot_ms > SNAPSHOT_TIMEOUT_MS:
			speed = 0.0
		_update_camera(driven, speed, delta)
		game_map.update_position(driven.global_position)
	elif players.has(local_id):
		var local_player: CharacterBody3D = players[local_id]
		_update_camera(local_player, 0.0, delta)
		game_map.update_position(local_player.global_position)
	if players.has(local_id):
		_show_health(players[local_id].health)
		_update_first_aid_prompt(players[local_id], driven != null)
		_update_inventory_prompt(players[local_id], driven != null)
	if map_open:
		_update_car_map()


func _unhandled_input(event: InputEvent) -> void:
	if dedicated:
		return
	if map_open or missions_open or _handle_menu_input(event) or menu_open or not connected or not map_ready:
		return
	if event.is_action_pressed("show_missions") and not event.is_echo():
		_open_missions()
		return
	if event.is_action_pressed("first_aid") and not event.is_echo():
		_request_first_aid()
		return
	if event.is_action_pressed("use_medkit") and not event.is_echo():
		_request_medkit_use()
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
			if _try_pickup_medkit(body, _driven_car(peer_id) == null):
				_notify(peer_id, "Erste-Hilfe-Paket aufgenommen.")
			var direction := Vector2.ZERO
			if Time.get_ticks_msec() - int(input_times.get(peer_id, 0)) <= INPUT_TIMEOUT_MS:
				direction = inputs.get(peer_id, Vector2.ZERO)
			body.movement_input = direction
			var vehicle := _driven_car(peer_id)
			if vehicle != null:
				vehicle.movement_input = direction
		for peer_id in pending_interactions:
			_interact(peer_id)
		pending_interactions.clear()
		if mission_ready:
			for peer_id in players:
				if players[peer_id].health > 0:
					mission_manager.visit(peer_id, players[peer_id].global_position, _driven_car(peer_id) == null)
		snapshot_timer += delta
		if snapshot_timer >= SNAPSHOT_INTERVAL:
			snapshot_timer = 0.0
			_send_snapshot()
	else:
		var direction := _local_movement_input()
		_submit_input.rpc_id(1, direction)


func _is_network_game() -> bool:
	return true


func _map_block_watch_positions() -> Array:
	var positions: Array = []
	for peer_id in players:
		var vehicle := _driven_car(peer_id)
		if vehicle != null:
			positions.append(vehicle.global_position)
		elif is_instance_valid(players[peer_id]):
			positions.append(players[peer_id].global_position)
		if multiplayer.is_server() and is_instance_valid(players[peer_id]):
			positions.append(players[peer_id].spawn_position)
	for vehicle in cars:
		if is_instance_valid(vehicle):
			positions.append(vehicle.global_position)
	for marker in [mission_marker, first_aid_marker, medkit_marker]:
		if is_instance_valid(marker) and marker.visible:
			positions.append(marker.global_position)
	return positions


func _reset_to_map() -> void:
	if not connected or not map_ready:
		status.text = "Zurücksetzen ist noch nicht verfügbar."
	elif multiplayer.is_server():
		_apply_reset_to_map(1)
	else:
		_request_reset_to_map_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_reset_to_map_rpc() -> void:
	if multiplayer.is_server():
		_apply_reset_to_map(multiplayer.get_remote_sender_id())


func _apply_reset_to_map(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	var body: PlayerScript = players[peer_id]
	var vehicle := _driven_car(peer_id)
	if vehicle != null:
		var center := body.spawn_position + Vector3(0, -0.4, -5)
		var placement := _find_safe_map_position(vehicle, center, 0.5, vehicle.collision_mask)
		if placement.is_empty():
			_notify(peer_id, "Kein freier Platz zum Zurücksetzen des Fahrzeugs gefunden.")
			return
		vehicle.global_position = placement.position
		vehicle.global_rotation.y = 0.0
		vehicle.velocity = Vector3.ZERO
		vehicle.movement_input = Vector2.ZERO
		_notify(peer_id, "Fahrzeug auf die Karte zurückgesetzt.")
		return
	if not _reset_player_to_map(body):
		_notify(peer_id, "Kein sicherer Platz auf der Karte zum Zurücksetzen gefunden.")
		return
	_notify(peer_id, "Spieler auf die Karte zurückgesetzt.")


func _request_first_aid() -> void:
	if multiplayer.is_server():
		_apply_first_aid(1)
	else:
		_request_first_aid_rpc.rpc_id(1)


func _request_medkit_use() -> void:
	if multiplayer.is_server():
		_apply_medkit_use(1)
	else:
		_request_medkit_use_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_medkit_use_rpc() -> void:
	if multiplayer.is_server():
		_apply_medkit_use(multiplayer.get_remote_sender_id())


func _apply_medkit_use(peer_id: int) -> void:
	if players.has(peer_id):
		_notify(peer_id, _use_medkit(players[peer_id], _driven_car(peer_id) != null))


@rpc("any_peer", "call_remote", "reliable")
func _request_first_aid_rpc() -> void:
	if multiplayer.is_server():
		_apply_first_aid(multiplayer.get_remote_sender_id())


func _apply_first_aid(peer_id: int) -> void:
	if players.has(peer_id):
		_notify(peer_id, _use_first_aid(peer_id, players[peer_id], _driven_car(peer_id) != null))


func _on_car_impact(speed: float, impacted_car: CarScript) -> void:
	if not multiplayer.is_server() or not players.has(impacted_car.driver_id):
		return
	var peer_id := impacted_car.driver_id
	if _damage_player(players[peer_id], speed):
		impacted_car.driver_id = 0
		impacted_car.occupied = false
		impacted_car.movement_input = Vector2.ZERO
		impacted_car.velocity = Vector3.ZERO
		_set_input(peer_id, Vector2.ZERO)
		while pending_interactions.has(peer_id):
			pending_interactions.erase(peer_id)
		_notify(peer_id, "Warte auf einen freien Startplatz zur Wiederbelebung.")


func _local_movement_input() -> Vector2:
	if menu_open or map_open or missions_open:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _on_peer_connected(peer_id: int) -> void:
	if building_edits.load_failed:
		push_error("Server kann Gebäudeänderungen nicht laden: " + building_edits.error)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
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
	_send_building_edits(peer_id)
	_receive_place.rpc_id(peer_id, compressed, first_aid, medkit_state)
	_add_server_player(peer_id)
	_send_loaded_map_blocks(peer_id)
	if car_spawn_incomplete:
		_notify(peer_id, CAR_SPAWN_WARNING)
	print("Spieler verbunden: ", peer_id)


func _send_building_edits(peer_id: int) -> void:
	var payload := {"edits": building_edits.data(), "blocked": building_edits.blocked_merges.keys()}
	var raw := JSON.stringify(payload, "", true, true).to_utf8_buffer()
	_receive_building_edits.rpc_id(peer_id, raw.compress(FileAccess.COMPRESSION_GZIP))


func _building_conflicts_changed() -> void:
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)


func _commit_building_merge(ways: Array) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_merge(ways)
	if result == BUILDING_MERGE_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_levels(way: Dictionary, levels: int) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_levels(way, levels)
	if result == BUILDING_LEVELS_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_hollow(way: Dictionary, floor_number: int) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_hollow(way, floor_number)
	if result == BUILDING_HOLLOW_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_wall(way: Dictionary, floor_number: int, cursor: Vector2, thickness: float) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_wall(way, floor_number, cursor, thickness)
	if result == BUILDING_WALL_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_wall_change(way: Dictionary, floor_number: int, outside: bool, wall_index: int, distance: float, thickness: float, segment_index := -1) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_wall_change(way, floor_number, outside, wall_index, distance, thickness, segment_index)
	if result == BUILDING_WALL_CHANGE_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_wall_split(way: Dictionary, floor_number: int, outside: bool, wall_index: int, segment_index: int) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_wall_split(way, floor_number, outside, wall_index, segment_index)
	if result == BUILDING_WALL_SPLIT_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


func _commit_building_wall_merge(way: Dictionary, floor_number: int, outside: bool, wall_index: int, first: int, second: int) -> String:
	if not multiplayer.is_server():
		return "Nur der Server-Host kann Gebäude bearbeiten."
	var result := super._commit_building_wall_merge(way, floor_number, outside, wall_index, first, second)
	if result == BUILDING_WALL_MERGE_SUCCESS:
		for peer_id in multiplayer.get_peers():
			_send_building_edits(peer_id)
	return result


@rpc("authority", "call_remote", "reliable")
func _receive_building_edits(compressed: PackedByteArray) -> void:
	if multiplayer.is_server() or not connected:
		return
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED_BYTES:
		_reject_place("Server-Gebäudeänderungen sind zu groß oder leer.")
		return
	var raw := compressed.decompress_dynamic(MAX_COMPRESSED_BYTES, FileAccess.COMPRESSION_GZIP)
	var json := JSON.new()
	if raw.is_empty() or json.parse(raw.get_string_from_utf8()) != OK or not json.data is Dictionary or not building_edits.set_data(json.data.get("edits")) or not building_edits.set_blocked(json.data.get("blocked")):
		_reject_place("Server hat ungültige Gebäudeänderungen gesendet.")
		return
	if map_ready:
		_refresh_building_edits()


func _send_loaded_map_blocks(peer_id: int) -> void:
	if map_block_stream == null:
		return
	var blocks: Array = map_block_stream.call("loaded_blocks_for_transfer")
	for entry in blocks:
		_send_map_block(peer_id, entry.block, entry.place)


func _request_server_map_block(block: Vector2i) -> bool:
	if not connected:
		return false
	_request_map_block.rpc_id(1, block)
	return true


@rpc("any_peer", "call_remote", "reliable")
func _request_map_block(block: Vector2i) -> void:
	if not multiplayer.is_server() or map_block_stream == null or not map_block_stream.loaded_blocks.has(block):
		return
	var place: Dictionary = map_block_stream.loaded_blocks[block].data
	if place.id == map_block_stream._block_id(block):
		_send_map_block(multiplayer.get_remote_sender_id(), block, place)


func _broadcast_map_block(block: Vector2i, place: Dictionary, _world_origin: Array) -> void:
	if refreshing_building_edits:
		return
	for peer_id in multiplayer.get_peers():
		_send_map_block(peer_id, block, place)


func _send_map_block(peer_id: int, block: Vector2i, place: Dictionary) -> void:
	var raw := JSON.stringify(place).to_utf8_buffer()
	if raw.size() > MAX_PLACE_BYTES:
		_notify(peer_id, "Kartenblock %s ist für die Übertragung zu groß." % [block])
		return
	var compressed := raw.compress(FileAccess.COMPRESSION_GZIP)
	if compressed.size() > MAX_COMPRESSED_BYTES:
		_notify(peer_id, "Kartenblock %s ist komprimiert für die Übertragung zu groß." % [block])
		return
	_receive_map_block.rpc_id(peer_id, block, compressed)


func _on_peer_disconnected(peer_id: int) -> void:
	if mission_ready:
		mission_manager.remove_player(peer_id)
	var vehicle := _driven_car(peer_id)
	if vehicle != null:
		vehicle.driver_id = 0
		vehicle.occupied = false
		vehicle.movement_input = Vector2.ZERO
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
func _receive_place(compressed: PackedByteArray, aid_state: Dictionary, kit_state: Dictionary) -> void:
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
	if not FirstAid.valid_state(aid_state):
		_reject_place("Server hat ungültige Erste-Hilfe-Daten gesendet.")
		return
	if not _valid_medkit_state(kit_state):
		_reject_place("Server hat ungültige Erste-Hilfe-Paket-Daten gesendet.")
		return
	if not OSMMap.populate(self, json.data):
		_reject_place("Server-Ort konnte nicht aufgebaut werden.")
		return
	place_data = json.data
	_configure_map(place_data)
	_set_first_aid(aid_state)
	_set_medkit_state(kit_state)
	map_ready = true
	$Ground.show()
	car.show()
	status.text = "Mit dem Server verbunden: " + place_data.name


@rpc("authority", "call_remote", "reliable")
func _receive_map_block(block: Vector2i, compressed: PackedByteArray) -> void:
	if multiplayer.is_server() or not connected or not map_ready:
		return
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED_BYTES:
		_report_map_block_error("Server-Kartenblock ist zu groß oder leer.")
		return
	var data := compressed.decompress_dynamic(MAX_PLACE_BYTES, FileAccess.COMPRESSION_GZIP)
	var json := JSON.new()
	if data.is_empty() or json.parse(data.get_string_from_utf8()) != OK or not json.data is Dictionary or not PlaceStore.is_valid(json.data):
		_report_map_block_error("Server hat ungültige Daten für einen Kartenblock gesendet.")
		return
	if map_block_stream == null or not map_block_stream.call("accept_remote_block", block, json.data):
		_report_map_block_error("Server-Kartenblock passt nicht zum aktiven Kartenausschnitt.")


func _report_map_block_error(message: String) -> void:
	push_error(message)
	status.text = message


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
	var vehicle := _driven_car(peer_id)
	if vehicle != null:
		if VehicleInteraction.exit(body, vehicle, player_collision_layer, player_collision_mask):
			vehicle.driver_id = 0
			vehicle.occupied = false
			vehicle.movement_input = Vector2.ZERO
			_notify(peer_id, "")
		else:
			_notify(peer_id, "Hier ist kein sicherer Platz zum Aussteigen.")
	else:
		vehicle = _nearest_car(body.global_position)
		if vehicle == null:
			_notify(peer_id, "Gehe näher an ein Auto heran.")
		elif vehicle.driver_id != 0:
			_notify(peer_id, "Das Auto ist bereits besetzt.")
		else:
			vehicle.driver_id = peer_id
			vehicle.occupied = true
			VehicleInteraction.enter(body)
			_notify(peer_id, "")


func _driven_car(peer_id: int) -> CarScript:
	if peer_id != 0:
		for vehicle in cars:
			if vehicle.driver_id == peer_id:
				return vehicle
	return null


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
		states[peer_id] = [body.global_position, body.visible, body.health, body.medkits]
	var vehicle_states := []
	for vehicle in cars:
		vehicle_states.append([vehicle.global_position, vehicle.global_rotation.y, vehicle.driver_id, _horizontal_speed(vehicle)])
	_receive_snapshot.rpc(states, vehicle_states, bool(medkit_state.get("available", false)))


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(states: Dictionary, vehicle_states: Array, pickup_available: bool) -> void:
	if not map_ready:
		return
	if vehicle_states.is_empty() or vehicle_states.size() > SaveStore.MAX_VEHICLES:
		push_error("Ungültige Fahrzeugliste vom Server.")
		return
	for peer_id in states:
		var state: Variant = states[peer_id]
		if not state is Array or state.size() != 4 or not state[0] is Vector3 or not state[0].is_finite() or not state[1] is bool or not state[2] is int or state[2] < 0 or state[2] > PlayerScript.MAX_HEALTH or not state[3] is int or state[3] < 0 or state[3] > PlayerScript.MAX_MEDKITS:
			push_error("Ungültiger Spielerzustand vom Server.")
			return
	for state in vehicle_states:
		if not state is Array or state.size() != 4 or not state[0] is Vector3 or not state[0].is_finite() or not (state[1] is float or state[1] is int) or not is_finite(float(state[1])) or not state[2] is int or not (state[3] is float or state[3] is int) or not is_finite(float(state[3])) or state[3] < 0:
			push_error("Ungültiger Fahrzeugzustand vom Server.")
			return
	if not pickup_available:
		medkit_state.available = false
	elif not medkit_state.get("available", false):
		push_error("Der Server hat ein bereits aufgenommenes Erste-Hilfe-Paket wieder aktiviert.")
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
		body.medkits = states[peer_id][3]
	_set_medkit_state(medkit_state)
	while cars.size() < vehicle_states.size():
		var vehicle := _create_car(Vector3.ZERO)
		vehicle.uses_local_input = false
		vehicle.set_physics_process(false)
		vehicle.collision_layer = 0
		vehicle.collision_mask = 0
	while cars.size() > vehicle_states.size():
		cars.pop_back().queue_free()
	remote_car_speed = 0.0
	for index in vehicle_states.size():
		var vehicle := cars[index]
		var state: Array = vehicle_states[index]
		vehicle.global_position = state[0]
		vehicle.global_rotation.y = state[1]
		vehicle.driver_id = state[2]
		vehicle.occupied = vehicle.driver_id != 0
		if vehicle.driver_id == multiplayer.get_unique_id():
			remote_car_speed = state[3]
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
