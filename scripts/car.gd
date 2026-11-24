extends CharacterBody3D

signal impact(speed: float)

const SPEED := 18.0
const DAMAGE_SPEED := 7.0

var occupied := false
var uses_local_input := true
var movement_input := Vector2.ZERO
var impact_contacts := {}

@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _physics_process(delta: float) -> void:
	var previous_velocity := get_real_velocity()
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
	var contacts := {}
	if occupied:
		var impact_speed := 0.0
		for index in get_slide_collision_count():
			var collision := get_slide_collision(index)
			var normal := collision.get_normal()
			var horizontal_normal := Vector3(normal.x, 0, normal.z)
			if horizontal_normal.length_squared() > 0.01:
				var collider_id := collision.get_collider_id()
				contacts[collider_id] = true
				if not impact_contacts.has(collider_id):
					horizontal_normal = horizontal_normal.normalized()
					impact_speed = maxf(impact_speed, -previous_velocity.dot(horizontal_normal))
		if impact_speed > DAMAGE_SPEED:
			impact.emit(impact_speed)
	impact_contacts = contacts
