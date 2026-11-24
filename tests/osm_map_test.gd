extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	call_deferred("_test")


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
	print("OSM map geometry, attribution, spawn and collision passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
