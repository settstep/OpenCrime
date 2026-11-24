extends Node3D

const CarScript = preload("res://scripts/car.gd")
const VehicleInteraction = preload("res://scripts/vehicle_interaction.gd")
const ENTER_DISTANCE := 3.5

@onready var player: CharacterBody3D = $Player
@onready var car: CarScript = $Car
@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $HUD/Status

var in_car := false
var menu_open := false
var interact_requested := false
var player_collision_layer: int
var player_collision_mask: int


func _ready() -> void:
	player_collision_layer = player.collision_layer
	player_collision_mask = player.collision_mask


func _process(_delta: float) -> void:
	var target := car if in_car else player
	camera.global_position = target.global_position + Vector3(0, 20, 0)


func _unhandled_input(event: InputEvent) -> void:
	if _handle_menu_input(event) or menu_open:
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
	menu.resume_requested.connect(_resume_game)
	menu.return_to_menu_requested.connect(_return_to_main_menu)
	layer.add_child(menu)
	if not _is_network_game():
		get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	menu_open = false
	$PauseMenu.queue_free()


func _return_to_main_menu() -> void:
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
