extends CharacterBody3D

const SPEED := 6.0
const MAX_HEALTH := 100
const RESPAWN_HEALTH := 25
const MAX_MEDKITS := 5
const MEDKIT_HEALING := 50

var uses_local_input := true
var movement_input := Vector2.ZERO
var health := MAX_HEALTH
var medkits := 0
var spawn_position := Vector3.ZERO


func _physics_process(delta: float) -> void:
	var input := movement_input
	if uses_local_input:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	velocity.x = input.x * SPEED
	velocity.z = input.y * SPEED

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	move_and_slide()
