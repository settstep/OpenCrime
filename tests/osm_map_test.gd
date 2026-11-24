extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world):
		_fail("The map data could not be loaded.")
		return
	root.add_child(world)
	for i in range(10):
		await physics_frame
	var map: Node3D = world.get_node("OSMMap")
	var church: StaticBody3D = map.get_node("Building_43347597")
	var concert_hall: StaticBody3D = map.get_node("Building_217512230")
	if church == null or concert_hall == null or map.get_child_count() < 10:
		_fail("Expected OSM buildings and road segments.")
		return
	if not world.get_node("HUD/OSMCredit").text.contains("OpenStreetMap"):
		_fail("Map attribution is missing.")
		return
	var player: CharacterBody3D = world.get_node("Player")
	if not player.is_on_floor():
		_fail("Player did not spawn on the ground.")
		return
	var space := world.get_world_3d().direct_space_state
	var wall_query := PhysicsRayQueryParameters3D.create(Vector3(45, 1, 30), Vector3(95, 1, 30))
	var wall := space.intersect_ray(wall_query)
	if wall.is_empty() or wall.collider != church:
		_fail("The OSM church does not have a usable collision wall.")
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
