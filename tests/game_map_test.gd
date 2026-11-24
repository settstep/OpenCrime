extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	call_deferred("_test")


func _key(action: String) -> void:
	var event: InputEvent
	if action == "show_map":
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		event = key
	else:
		var input := InputEventAction.new()
		input.action = action
		event = input
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _test() -> void:
	var world := MainScene.instantiate()
	if not OSMMap.populate(world):
		_fail("Unable to load place.")
		return
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	var map = world.game_map
	if not map.configured or not map.has_position or map.explored.is_empty() or map.explored.has(Vector2i(40, 40)):
		_fail("Initial exploration is missing or reveals the whole map.")
		return
	var initial_cells: Array = map.explored.keys()
	world.player.global_position = Vector3(100, 0.9, 100)
	world._process(0.0)
	if map.player_position.distance_to(Vector2(100, 100)) > 0.01 or map.explored.size() <= initial_cells.size():
		_fail("Walking did not update position and exploration.")
		return
	for cell in initial_cells:
		if not map.explored.has(cell):
			_fail("Previously explored areas were forgotten.")
			return
	world.in_car = true
	world.car.global_position = Vector3(-100, 0.5, -100)
	world._process(0.0)
	if map.player_position.distance_to(Vector2(-100, -100)) > 0.01:
		_fail("The map did not follow the occupied car.")
		return
	world.in_car = false
	await _key("show_map")
	if not world.map_open or not map.visible or not paused:
		_fail("M did not open the map and pause single-player.")
		return
	if map.canvas.size.x <= 0.0 or not is_equal_approx(map.canvas.size.x, map.canvas.size.y):
		_fail("The map canvas does not preserve its square proportions.")
		return
	var center: Vector2 = map._map_point(Vector2.ZERO, map.canvas.size.x / (map.WORLD_SIZE * map.map_scale))
	if center.distance_to(map.canvas.size / 2.0) > 0.01:
		_fail("World coordinates are not aligned with the map.")
		return
	await _key("ui_cancel")
	if world.map_open or map.visible or paused or world.menu_open:
		_fail("Escape did not close the map without opening the menu.")
		return
	await _key("show_map")
	await _key("show_map")
	if world.map_open or paused:
		_fail("M did not close the map.")
		return
	await _key("show_map")
	map.close_button.pressed.emit()
	await process_frame
	if world.map_open or paused or map.visible:
		_fail("The close button did not close the map.")
		return
	var place: Dictionary = world.get_node("OSMMap").get_meta("place")
	var scaled_cells := {}
	var scaled_marker := Vector2.ZERO
	for factor in [0.5, 2.0]:
		map.configure(place, factor)
		map.update_position(Vector3(50.0 * factor, 0, -50.0 * factor))
		var marker: Vector2 = map._map_point(map.player_position, map.canvas.size.x / (map.WORLD_SIZE * factor))
		if not scaled_cells.is_empty() and (map.explored != scaled_cells or marker.distance_to(scaled_marker) > 0.01):
			_fail("Map projection or exploration changes incorrectly with the map factor.")
			return
		scaled_cells = map.explored.duplicate()
		scaled_marker = marker
	var second := MainScene.instantiate()
	if not OSMMap.populate(second):
		_fail("Second session could not load.")
		return
	root.add_child(second)
	if not second.game_map.explored.is_empty():
		_fail("Exploration leaked into a new session.")
		return
	second.queue_free()
	print("Map, exploration, position, pause and session reset passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
