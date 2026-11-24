extends Node3D

const CarScript = preload("res://scripts/car.gd")
const VehicleInteraction = preload("res://scripts/vehicle_interaction.gd")
const GameMapScene = preload("res://scenes/game_map.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const Missions = preload("res://scripts/missions.gd")
const MissionUI = preload("res://scenes/mission_ui.tscn")
const ENTER_DISTANCE := 3.5
const AUTOSAVE_INTERVAL := 30.0
const CAMERA_BASE_SIZE := 20.0
const CAMERA_MAX_SIZE := 40.0
const CAMERA_ZOOM_START_SPEED := 6.0
const CAMERA_ZOOM_MAX_SPEED := 25.0
const CAMERA_ZOOM_RESPONSE := 3.0

@onready var player: CharacterBody3D = $Player
@onready var car: CarScript = $Car
@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $HUD/Status

var in_car := false
var menu_open := false
var map_open := false
var game_map: Control
var interact_requested := false
var player_collision_layer: int
var player_collision_mask: int
var save_id := ""
var restore_data: Dictionary = {}
var save_created_at := ""
var autosave_timer := 0.0
var save_error_dialog: AcceptDialog
var mission_manager: Missions
var mission_ui: Control
var mission_marker: MeshInstance3D
var missions_open := false
var mission_ready := false


func _ready() -> void:
	player_collision_layer = player.collision_layer
	player_collision_mask = player.collision_mask
	game_map = GameMapScene.instantiate()
	game_map.hide()
	game_map.close_requested.connect(_close_map)
	$HUD.add_child(game_map)
	mission_ui = MissionUI.instantiate()
	$HUD.add_child(mission_ui)
	mission_ui.accept_requested.connect(_on_mission_accept)
	mission_ui.defer_requested.connect(_on_mission_defer)
	mission_ui.invite_requested.connect(_on_mission_invite)
	mission_ui.close_requested.connect(_close_missions)
	mission_marker = MeshInstance3D.new()
	mission_marker.name = "MissionMarker"
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(1.0, 0.6, 1.0)
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(1.0, 0.8, 0.1)
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mesh.material = marker_material
	mission_marker.mesh = marker_mesh
	mission_marker.hide()
	add_child(mission_marker)
	var map := get_node_or_null("OSMMap")
	if map != null and map.has_meta("place"):
		_configure_map(map.get_meta("place"))
	if not save_id.is_empty():
		get_tree().set_auto_accept_quit(false)
		if restore_data.is_empty():
			save_created_at = Time.get_datetime_string_from_system()
		else:
			_restore_game(restore_data)
	if not _is_network_game() and map != null and map.has_meta("place"):
		_setup_missions(map.get_meta("place"))
		if mission_ready:
			if not mission_manager.add_player(1, restore_data.get("mission", {})):
				mission_ready = false
				mission_ui.show_error(mission_manager.error)


func _process(delta: float) -> void:
	var target := car if in_car else player
	_update_camera(target, _horizontal_speed(car) if in_car else 0.0, delta)
	game_map.update_position(target.global_position)
	if not save_id.is_empty():
		autosave_timer += delta
		if autosave_timer >= AUTOSAVE_INTERVAL:
			autosave_timer = 0.0
			save_game()


func _horizontal_speed(body: CharacterBody3D) -> float:
	var velocity := body.get_real_velocity()
	return Vector2(velocity.x, velocity.z).length()


func _update_camera(target: Node3D, speed: float, delta: float) -> void:
	var fraction := clampf((speed - CAMERA_ZOOM_START_SPEED) / (CAMERA_ZOOM_MAX_SPEED - CAMERA_ZOOM_START_SPEED), 0.0, 1.0)
	var target_size := lerpf(CAMERA_BASE_SIZE, CAMERA_MAX_SIZE, fraction)
	camera.size = lerpf(camera.size, target_size, 1.0 - exp(-CAMERA_ZOOM_RESPONSE * delta))
	camera.global_position = target.global_position + Vector3(0, camera.size, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not save_id.is_empty() and not _is_network_game():
		_quit_game()


func _exit_tree() -> void:
	if not save_id.is_empty() and not _is_network_game():
		get_tree().set_auto_accept_quit(true)


func _unhandled_input(event: InputEvent) -> void:
	if map_open or missions_open or _handle_menu_input(event) or menu_open:
		return
	if event.is_action_pressed("show_missions") and not event.is_echo():
		_open_missions()
		return
	if event.is_action_pressed("show_map") and not event.is_echo():
		_open_map()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		interact_requested = true


func _handle_menu_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and not menu_open:
		_open_pause_menu()
		return true
	return false


func _is_network_game() -> bool:
	return false


func _configure_map(place: Dictionary) -> void:
	game_map.configure(place, float(ProjectSettings.get_setting("opencrime/osm/scale")))


func _setup_missions(place: Dictionary) -> void:
	mission_manager = Missions.new()
	mission_manager.changed.connect(_on_mission_changed)
	mission_manager.notification.connect(_on_mission_notification)
	mission_ready = mission_manager.setup(place, float(ProjectSettings.get_setting("opencrime/osm/scale")))
	if not mission_ready:
		mission_ui.show_error(mission_manager.error)


func _on_mission_changed(peer_id: int) -> void:
	if peer_id == 1 and mission_manager.players.has(peer_id):
		_show_mission_state(mission_manager.view_for(peer_id), peer_id)


func _on_mission_notification(peer_id: int, text: String) -> void:
	if peer_id == 1:
		_mission_result(text)


func _show_mission_state(state: Dictionary, peer_id: int) -> void:
	mission_ui.update_state(state, peer_id)
	var id: String = state.player.active
	if id.is_empty() or not state.missions.has(id):
		mission_marker.hide()
		game_map.set_mission_target(Vector2.ZERO, false)
		return
	var mission: Dictionary = state.missions[id]
	var point: Array = mission.pickup if mission.stage == 0 else mission.destination
	var target := Vector2(float(point[0]), float(point[1]))
	mission_marker.position = Vector3(target.x, 0.4, target.y)
	mission_marker.show()
	game_map.set_mission_target(target, true)


func _on_mission_accept(id: String) -> void:
	_mission_result(mission_manager.accept(1, id) if mission_ready else "Aufträge sind nicht verfügbar.")


func _on_mission_defer(id: String) -> void:
	_mission_result(mission_manager.defer_offer(1, id) if mission_ready else "Aufträge sind nicht verfügbar.")


func _on_mission_invite(_peer_id: int) -> void:
	_mission_result("Weiterleiten ist nur im Multiplayer möglich.")


func _mission_result(result: String) -> void:
	mission_ui.show_error(result)


func _open_missions() -> void:
	if not mission_ready and not _is_network_game():
		status.text = "Aufträge sind für diesen Ort nicht verfügbar."
		return
	missions_open = true
	interact_requested = false
	mission_ui.panel.show()
	if not _is_network_game():
		get_tree().paused = true


func _close_missions() -> void:
	mission_ui.panel.hide()
	missions_open = false
	if not _is_network_game():
		get_tree().paused = false


func _open_map() -> void:
	if not game_map.configured:
		status.text = "Für diesen Ort sind noch keine Kartendaten verfügbar."
		return
	map_open = true
	interact_requested = false
	mission_ui.hide()
	game_map.show()
	game_map.drawing.queue_redraw()
	game_map.close_button.grab_focus()
	if not _is_network_game():
		get_tree().paused = true


func _close_map() -> void:
	game_map.hide()
	mission_ui.show()
	map_open = false
	if not _is_network_game():
		get_tree().paused = false


func _open_pause_menu() -> void:
	menu_open = true
	interact_requested = false
	var layer := CanvasLayer.new()
	layer.name = "PauseMenu"
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	var menu := menu_scene.instantiate()
	menu.in_game = true
	menu.can_save = not _is_network_game() and not save_id.is_empty()
	menu.resume_requested.connect(_resume_game)
	menu.return_to_menu_requested.connect(_return_to_main_menu)
	menu.save_requested.connect(_on_save_requested)
	menu.save_as_requested.connect(_on_save_as_requested)
	menu.quit_requested.connect(_quit_game)
	layer.add_child(menu)
	if not _is_network_game():
		get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	menu_open = false
	$PauseMenu.queue_free()


func _return_to_main_menu() -> void:
	if not _is_network_game() and not save_id.is_empty() and not save_game():
		return
	get_tree().paused = false
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)
	if _is_network_game():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	var menu_scene: PackedScene = load("res://scenes/menu.tscn")
	var menu := menu_scene.instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	queue_free()


func _on_save_requested() -> void:
	if save_game():
		$PauseMenu/Menu/Panel/Options/Message.text = "Spielstand gespeichert."


func _on_save_as_requested() -> void:
	var new_id := SaveStore.new_id()
	if new_id.is_empty():
		_save_error("Ein neuer Spielstand konnte nicht angelegt werden.")
		return
	var previous_id := save_id
	var previous_created_at := save_created_at
	save_id = new_id
	save_created_at = Time.get_datetime_string_from_system()
	if save_game():
		$PauseMenu/Menu/Panel/Options/Message.text = "Neuer Spielstand gespeichert."
	else:
		save_id = previous_id
		save_created_at = previous_created_at


func _quit_game() -> void:
	if not _is_network_game() and not save_id.is_empty() and not save_game():
		return
	get_tree().quit()


func save_game() -> bool:
	var map := get_node_or_null("OSMMap")
	if save_id.is_empty() or map == null or not map.has_meta("place"):
		_save_error("Spielstand konnte nicht erstellt werden: Ortsdaten fehlen.")
		return false
	var target := car if in_car else player
	game_map.update_position(target.global_position)
	var explored: Array = []
	for cell: Vector2i in game_map.explored:
		explored.append([cell.x, cell.y])
	var data := {
		"format": SaveStore.FORMAT_VERSION,
		"id": save_id,
		"created_at": save_created_at,
		"saved_at": Time.get_datetime_string_from_system(),
		"place": map.get_meta("place"),
		"scale": game_map.map_scale,
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"car_position": [car.global_position.x, car.global_position.y, car.global_position.z],
		"car_rotation": car.global_rotation.y,
		"in_car": in_car,
		"explored": explored,
	}
	if mission_ready and mission_manager.players.has(1):
		data["mission"] = mission_manager.save_for(1)
	elif restore_data.has("mission"):
		data["mission"] = restore_data.mission
	var error := SaveStore.write_slot(data)
	if error != OK:
		_save_error("Spielstand konnte nicht gespeichert werden (Fehler %d)." % error)
		return false
	return true


func _save_error(message: String) -> void:
	push_error(message)
	status.text = message
	var menu := get_node_or_null("PauseMenu/Menu")
	if menu != null:
		menu.get_node("Panel/Options/Message").text = message
	if not is_instance_valid(save_error_dialog):
		save_error_dialog = AcceptDialog.new()
		save_error_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		save_error_dialog.title = "Speicherfehler"
		$HUD.add_child(save_error_dialog)
	save_error_dialog.dialog_text = message
	if not save_error_dialog.visible:
		save_error_dialog.popup_centered()


func _restore_game(data: Dictionary) -> void:
	save_created_at = data.created_at
	var position: Array = data.player_position
	player.global_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	position = data.car_position
	car.global_position = Vector3(float(position[0]), float(position[1]), float(position[2]))
	car.global_rotation.y = float(data.car_rotation)
	for cell in data.explored:
		game_map.explored[Vector2i(int(cell[0]), int(cell[1]))] = true
	if data.in_car:
		in_car = true
		car.occupied = true
		VehicleInteraction.enter(player)


func _physics_process(_delta: float) -> void:
	if mission_ready:
		mission_manager.visit(1, player.global_position, not in_car)
	if not interact_requested:
		return
	interact_requested = false

	if in_car:
		_exit_car()
	elif player.global_position.distance_to(car.global_position) <= ENTER_DISTANCE:
		_enter_car()
	else:
		status.text = "Gehe näher an das Auto heran."


func _enter_car() -> void:
	in_car = true
	car.occupied = true
	VehicleInteraction.enter(player)
	status.text = ""


func _exit_car() -> void:
	if VehicleInteraction.exit(player, car, player_collision_layer, player_collision_mask):
		car.occupied = false
		in_car = false
		status.text = ""
	else:
		status.text = "Hier ist kein sicherer Platz zum Aussteigen."
