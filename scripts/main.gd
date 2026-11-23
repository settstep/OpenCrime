extends Node3D

const CarScript = preload("res://scripts/car.gd")
const ENTER_DISTANCE := 3.5
const EXIT_OFFSETS := [
	Vector3(1.7, 0.45, 0),
	Vector3(-1.7, 0.45, 0),
	Vector3(0, 0.45, 2.4),
	Vector3(0, 0.45, -2.4),
]

@onready var player: CharacterBody3D = $Player
@onready var car: CarScript = $Car
@onready var camera: Camera3D = $Camera3D
@onready var status: Label = $HUD/Status
@onready var player_shape: CollisionShape3D = $Player/CollisionShape3D

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
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	player.hide()
	status.text = ""


func _exit_car() -> void:
	if not car.is_on_floor():
		status.text = "Hier ist kein sicherer Platz zum Aussteigen."
		return

	var space := get_world_3d().direct_space_state
	for offset in EXIT_OFFSETS:
		var position: Vector3 = car.global_position + car.global_basis * offset
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player_shape.shape
		query.transform = Transform3D(Basis.IDENTITY, position)
		query.collision_mask = player_collision_mask
		query.exclude = [player.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue

		var floor_query := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 1.1, player_collision_mask, [player.get_rid(), car.get_rid()])
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.7:
			continue

		player.global_position = position
		player.collision_layer = player_collision_layer
		player.collision_mask = player_collision_mask
		player.show()
		player.set_physics_process(true)
		car.occupied = false
		in_car = false
		status.text = ""
		return

	status.text = "Hier ist kein sicherer Platz zum Aussteigen."
