extends RefCounted

const EXIT_OFFSETS := [
	Vector3(1.7, 0.45, 0),
	Vector3(-1.7, 0.45, 0),
	Vector3(0, 0.45, 2.4),
	Vector3(0, 0.45, -2.4),
]


static func enter(player: CharacterBody3D) -> void:
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	player.hide()


static func exit(player: CharacterBody3D, car: CharacterBody3D, collision_layer: int, collision_mask: int) -> bool:
	if not car.is_on_floor():
		return false

	var space := car.get_world_3d().direct_space_state
	var player_shape: CollisionShape3D = player.get_node("CollisionShape3D")
	for offset in EXIT_OFFSETS:
		var position: Vector3 = car.global_position + car.global_basis * offset
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player_shape.shape
		query.transform = Transform3D(Basis.IDENTITY, position)
		query.collision_mask = collision_mask
		query.exclude = [player.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue

		var floor_query := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 1.1, collision_mask, [player.get_rid(), car.get_rid()])
		var floor_hit := space.intersect_ray(floor_query)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP) < 0.7:
			continue

		player.global_position = position
		player.collision_layer = collision_layer
		player.collision_mask = collision_mask
		player.show()
		player.set_physics_process(true)
		return true

	return false
