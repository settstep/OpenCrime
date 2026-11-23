extends CharacterBody3D

const SPEED := 10.0

var occupied := false
var uses_local_input := true
var movement_input := Vector2.ZERO

@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if occupied:
		input = movement_input
		if uses_local_input:
			input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if input != Vector2.ZERO:
		var desired_angle := atan2(-input.x, -input.y)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collision_shape.shape
		# Lift the test shape slightly so the ground does not block turning.
		query.transform = Transform3D(Basis(Vector3.UP, desired_angle), global_position + Vector3.UP * 0.05)
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			global_rotation.y = desired_angle
		else:
			input = Vector2.ZERO

	velocity.x = input.x * SPEED
	velocity.z = input.y * SPEED

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	move_and_slide()
