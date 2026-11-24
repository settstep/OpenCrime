extends Node3D

const CarScript = preload("res://scripts/car.gd")
const VehicleInteraction = preload("res://scripts/vehicle_interaction.gd")
const GameMapScene = preload("res://scenes/game_map.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const ENTER_DISTANCE := 3.5
const AUTOSAVE_INTERVAL := 30.0

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


func _ready() -> void:
	player_collision_layer = player.collision_layer
	player_collision_mask = player.collision_mask
	game_map = GameMapScene.instantiate()
	game_map.hide()
	game_map.close_requested.connect(_close_map)
	$HUD.add_child(game_map)
	var map := get_node_or_null("OSMMap")
	if map != null and map.has_meta("place"):
		_configure_map(map.get_meta("place"))
	if not save_id.is_empty():
		get_tree().set_auto_accept_quit(false)
		if restore_data.is_empty():
			save_created_at = Time.get_datetime_string_from_system()
		else:
			_restore_game(restore_data)


func _process(delta: float) -> void:
	var target := car if in_car else player
	camera.global_position = target.global_position + Vector3(0, 20, 0)
	game_map.update_position(target.global_position)
	if not save_id.is_empty():
		autosave_timer += delta
		if autosave_timer >= AUTOSAVE_INTERVAL:
			autosave_timer = 0.0
			save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not save_id.is_empty() and not _is_network_game():
		_quit_game()


func _exit_tree() -> void:
	if not save_id.is_empty() and not _is_network_game():
		get_tree().set_auto_accept_quit(true)


func _unhandled_input(event: InputEvent) -> void:
	if map_open or _handle_menu_input(event) or menu_open:
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


func _open_map() -> void:
	if not game_map.configured:
		status.text = "Für diesen Ort sind noch keine Kartendaten verfügbar."
		return
	map_open = true
	interact_requested = false
	game_map.show()
	game_map.canvas.queue_redraw()
	game_map.close_button.grab_focus()
	if not _is_network_game():
		get_tree().paused = true


func _close_map() -> void:
	game_map.hide()
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
