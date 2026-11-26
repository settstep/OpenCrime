extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _frames(count: int) -> void:
	for index in count:
		await physics_frame


func _test() -> void:
	var street_start := OSMMap._project([47.7748417, 10.6034933])
	var street_end := OSMMap._project([47.7749824, 10.6033296])
	if absf(street_start.distance_to(street_end) - 19.88) > 0.1:
		_fail("The street segment is not projected at approximately one unit per meter.")
		return
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world):
		_fail("The map data could not be loaded.")
		return
	root.add_child(world)
	for i in range(10):
		await physics_frame
	var map: Node3D = world.get_node("OSMMap")
	var building: StaticBody3D = map.get_node_or_null("Building_232702900")
	if building == null or map.get_child_count() < 100:
		_fail("Expected buildings and road segments in Thalhofen.")
		return
	if not world.get_node("HUD/OSMCredit").text.contains("OpenStreetMap"):
		_fail("Map attribution is missing.")
		return
	var player: CharacterBody3D = world.get_node("Player")
	if not player.is_on_floor():
		_fail("Player did not spawn on the ground.")
		return
	var space := world.get_world_3d().direct_space_state
	var wall_query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -10), Vector3(25, 1, -10))
	var wall := space.intersect_ray(wall_query)
	if wall.is_empty() or wall.collider != building:
		_fail("The OSM building does not have a usable collision wall.")
		return
	var start := player.position
	Input.action_press("move_forward")
	for i in range(20):
		await physics_frame
	Input.action_release("move_forward")
	if player.position.z >= start.z - 1.0:
		_fail("Player cannot move from the OSM map spawn.")
		return
	var half_extent := 750.0 * float(ProjectSettings.get_setting(OSMMap.SCALE_SETTING))
	world.map_block_stream.set_process(false)
	world.map_block_stream._update_boundary(Vector2i.ZERO)
	player.uses_local_input = false
	player.global_position = Vector3(half_extent - 8.0, 0.9, half_extent - 80.0)
	player.velocity = Vector3.ZERO
	await _frames(3)
	var player_edge_start: float = player.global_position.x
	player.movement_input = Vector2.RIGHT
	await _frames(120)
	player.movement_input = Vector2.ZERO
	if player.global_position.x >= half_extent or player.global_position.x <= player_edge_start + 5.0 or not player.is_on_floor():
		_fail("The map boundary did not keep the player safely inside.")
		return
	world.car.uses_local_input = false
	world.car.occupied = true
	world.car.global_position = Vector3(half_extent - 20.0, 0.5, -half_extent + 80.0)
	world.car.velocity = Vector3.ZERO
	await _frames(3)
	var car_edge_start: float = world.car.global_position.x
	world.car.movement_input = Vector2.RIGHT
	await _frames(120)
	world.car.movement_input = Vector2.ZERO
	world.car.occupied = false
	if world.car.global_position.x >= half_extent or world.car.global_position.x <= car_edge_start + 10.0 or not world.car.is_on_floor():
		_fail("The map boundary did not keep the vehicle safely inside.")
		return
	print("OSM map geometry, attribution, spawn and boundary collisions passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
