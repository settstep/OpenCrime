extends CharacterBody3D

const SPEED := 6.0


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	velocity.x = input.x * SPEED
	velocity.z = input.y * SPEED

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	move_and_slide()
