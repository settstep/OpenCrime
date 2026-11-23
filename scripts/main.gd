extends Node3D

const CarScript = preload("res://scripts/car.gd")
const VehicleInteraction = preload("res://scripts/vehicle_interaction.gd")
const ENTER_DISTANCE := 3.5

@onready var player: CharacterBody3D = $Player
@onready var car: CarScript = $Car
@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $HUD/Status

var in_car := false
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
	if event.is_action_pressed("interact") and not event.is_echo():
		interact_requested = true


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
