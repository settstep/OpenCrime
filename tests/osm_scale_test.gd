extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	call_deferred("_test")


func _map_metrics(scale_factor: float) -> Dictionary:
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, scale_factor)
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world):
		world.free()
		return {}
	var map: Node3D = world.get_node("OSMMap")
	var building: StaticBody3D = map.get_node("Building_232702900")
	var visual: MeshInstance3D = building.get_child(0)
	var collision: CollisionShape3D = building.get_child(1)
	var road: MeshInstance3D
	for child in map.get_children():
		if child is MeshInstance3D:
			road = child
			break
	var ground: CollisionShape3D = world.get_node("Ground/CollisionShape3D")
	var player: CharacterBody3D = world.get_node("Player")
	var car: CharacterBody3D = world.get_node("Car")
	var result := {
		"building": visual.mesh.get_aabb(),
		"collision": collision.shape.get_faces(),
		"road_position": road.position,
		"road_size": road.mesh.size,
		"ground_size": ground.shape.size,
		"player_position": player.position,
		"car_position": car.position,
	}
	world.free()
	return result


func _face_bounds(faces: PackedVector3Array) -> AABB:
	var bounds := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		bounds = bounds.expand(vertex)
	return bounds


func _test() -> void:
	var original: Variant = ProjectSettings.get_setting(OSMMap.SCALE_SETTING)
	var base := _map_metrics(1.0)
	for factor in [0.5, 2.0]:
		var scaled := _map_metrics(factor)
		if base.is_empty() or scaled.is_empty():
			_fail("The scaled map could not be loaded.")
			return
		var base_building: AABB = base.building
		var scaled_building: AABB = scaled.building
		if not scaled_building.position.is_equal_approx(base_building.position * factor) or not scaled_building.size.is_equal_approx(base_building.size * factor):
			_fail("Building geometry did not scale correctly.")
			return
		var base_faces: PackedVector3Array = base.collision
		var scaled_faces: PackedVector3Array = scaled.collision
		if scaled_faces.size() != base_faces.size():
			_fail("Scaled building collision changed topology.")
			return
		var base_collision := _face_bounds(base_faces)
		var scaled_collision := _face_bounds(scaled_faces)
		if scaled_collision.position.distance_to(base_collision.position * factor) > 0.001 or scaled_collision.size.distance_to(base_collision.size * factor) > 0.001:
			_fail("Building collision did not scale with its mesh: %s vs %s (factor %s)." % [base_collision, scaled_collision, factor])
			return
		var base_road: Vector3 = base.road_size
		var scaled_road: Vector3 = scaled.road_size
		var base_position: Vector3 = base.road_position
		var scaled_position: Vector3 = scaled.road_position
		if not is_equal_approx(scaled_road.x, base_road.x * factor) or not is_equal_approx(scaled_road.z, base_road.z * factor) or not is_equal_approx(scaled_position.x, base_position.x * factor) or not is_equal_approx(scaled_position.z, base_position.z * factor):
			_fail("Road dimensions or positions did not scale correctly.")
			return
		var base_ground: Vector3 = base.ground_size
		var scaled_ground: Vector3 = scaled.ground_size
		if not is_equal_approx(scaled_ground.x, base_ground.x * factor) or not is_equal_approx(scaled_ground.z, base_ground.z * factor) or not is_equal_approx(scaled_ground.y, base_ground.y):
			_fail("Ground dimensions did not scale correctly.")
			return
		if scaled.player_position != base.player_position or scaled.car_position != base.car_position:
			_fail("The player or car spawn moved with the map.")
			return
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world):
		_fail("The scaled collision test map could not be loaded.")
		return
	root.add_child(world)
	for i in range(10):
		await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -20), Vector3(50, 1, -20))
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != world.get_node("OSMMap/Building_232702900"):
		_fail("Physics did not hit the scaled building at its new position.")
		return
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, original)
	print("OSM scale affects map geometry and collision, not player or car")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
