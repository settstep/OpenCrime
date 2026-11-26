extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const MapBlockGrid = preload("res://scripts/map_block_grid.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
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


func _mouse_button(canvas: Control, button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = canvas.get_global_transform_with_canvas() * position
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	root.push_input(event, true)
	await process_frame


func _mouse_motion(canvas: Control, position: Vector2, relative: Vector2, button_mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.get_global_transform_with_canvas() * position
	event.global_position = event.position
	event.relative = relative
	event.button_mask = button_mask
	root.push_input(event, true)
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
	var marker_position := Vector2(500, 500)
	var cell_size: float = map.CELL_SIZE * map.map_scale
	var marker_cell := Vector2i(floori(marker_position.x / cell_size), floori(marker_position.y / cell_size))
	var marker_rect := Rect2(Vector2(-100000, -100000), Vector2(200000, 200000))
	if map._is_position_explored(marker_position) or map._object_marker_is_visible(marker_position, map._map_factor(), marker_rect):
		_fail("An object marker was visible before its map cell was explored.")
		return
	if not map._position_is_in_view(marker_position, map._map_factor(), marker_rect):
		_fail("An unexplored mission target was hidden despite being within the map view.")
		return
	map.explored[marker_cell] = true
	if not map._is_position_explored(marker_position) or not map._object_marker_is_visible(marker_position, map._map_factor(), marker_rect):
		_fail("An object marker did not become visible after its map cell was explored.")
		return
	map.explored.erase(marker_cell)
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
	map.update_position(Vector3(510 * map.map_scale, 0, -260 * map.map_scale))
	var distant_block := MapBlockGrid.block_for_position(Vector2(510, -260), map.map_scale, map.place_origin)
	var expected_window_center: Vector2 = MapBlockGrid.block_local_center(map.place_origin, distant_block) * map.map_scale
	if map.window_center != expected_window_center or not map.explored.has(Vector2i(51, -26)) or not map.explored.has(initial_cells[0]):
		_fail("The map window or exploration did not follow a distant block.")
		return
	map.update_position(Vector3(-100, 0, -100))
	await _key("show_map")
	if not world.map_open or not map.visible or not paused:
		_fail("M did not open the map and pause single-player.")
		return
	if map.canvas.size.x <= 0.0 or not is_equal_approx(map.canvas.size.x, map.canvas.size.y) or not map.canvas.clip_contents or map.drawing.get_parent() != map.canvas:
		_fail("The map canvas does not preserve its square proportions.")
		return
	var center: Vector2 = map._map_point(map.view_center, map._map_factor())
	if center.distance_to(map.canvas.size / 2.0) > 0.01:
		_fail("World coordinates are not aligned with the map.")
		return
	var explored_before: Dictionary = map.explored.duplicate()
	var cursor: Vector2 = map.canvas.size / 2.0 + Vector2(30, -20)
	var world_at_cursor: Vector2 = map.view_center + (cursor - map.canvas.size / 2.0) / map._map_factor()
	await _mouse_motion(map.canvas, cursor, Vector2.ZERO)
	await _mouse_button(map.canvas, MOUSE_BUTTON_WHEEL_UP, true, cursor)
	await _mouse_button(map.canvas, MOUSE_BUTTON_WHEEL_UP, false, cursor)
	if map.zoom <= 1.0 or map._map_point(world_at_cursor, map._map_factor()).distance_to(cursor) > 0.01:
		_fail("Wheel zoom did not preserve the position beneath the cursor.")
		return
	var before_drag: Vector2 = map.view_center
	var drag := Vector2(40, 25)
	var drag_factor: float = map._map_factor()
	await _mouse_button(map.canvas, MOUSE_BUTTON_LEFT, true, cursor)
	await _mouse_motion(map.canvas, cursor + drag, drag, MOUSE_BUTTON_MASK_LEFT)
	await _mouse_button(map.canvas, MOUSE_BUTTON_LEFT, false, cursor + drag)
	if map.dragging or map.view_center.distance_to(before_drag - drag / drag_factor) > 0.01:
		_fail("Dragging did not move the map correctly.")
		return
	await _mouse_button(map.canvas, MOUSE_BUTTON_LEFT, true, cursor + drag)
	await _mouse_motion(map.canvas, Vector2(-10, cursor.y), Vector2(-100, 0), MOUSE_BUTTON_MASK_LEFT)
	await _mouse_button(map.canvas, MOUSE_BUTTON_LEFT, false, Vector2(-10, cursor.y))
	if map.dragging:
		_fail("Releasing the mouse outside the map did not stop dragging.")
		return
	var cell_corner: Vector2 = Vector2(-75, -75) * map.CELL_SIZE * map.map_scale
	var cell_rect: Rect2 = map._cell_rect(-75, -75, map._map_factor())
	if cell_rect.position.distance_to(map._map_point(cell_corner, map._map_factor())) > 0.01 or not is_equal_approx(cell_rect.size.x, map.CELL_SIZE * map.map_scale * map._map_factor()) or map.explored != explored_before:
		_fail("Zooming or dragging misaligned or changed the exploration grid.")
		return
	var zoom_before: float = map.zoom
	map.center_button.pressed.emit()
	if map.view_center.distance_to(map.player_position) > 0.01 or not is_equal_approx(map.zoom, zoom_before) or map._map_point(map.player_position, map._map_factor()).distance_to(map.canvas.size / 2.0) > 0.01:
		_fail("The position button did not center the player at the current zoom.")
		return
	for i in 50:
		map.canvas.gui_input.emit(_wheel(MOUSE_BUTTON_WHEEL_UP, map.canvas.size / 2.0))
	await process_frame
	if not is_equal_approx(map.zoom, map.MAX_ZOOM):
		_fail("Zoom exceeded or failed to reach its maximum.")
		return
	for i in 50:
		map.canvas.gui_input.emit(_wheel(MOUSE_BUTTON_WHEEL_DOWN, map.canvas.size / 2.0))
	if not is_equal_approx(map.zoom, map.MIN_ZOOM):
		_fail("Zoom exceeded or failed to reach its minimum.")
		return
	map._set_view_center(Vector2(100000, -100000))
	var half: float = map.WORLD_SIZE * map.map_scale / 2.0
	if map.view_center.distance_to(Vector2(half, -half)) > 0.01:
		_fail("Panning was not bounded to the map.")
		return
	var current_position: Vector2 = map.player_position
	map.update_position(Vector3(half + 20.0, 0, 0))
	map.center_button.pressed.emit()
	if map.view_center.distance_to(map.player_position) > 0.01:
		_fail("The position button did not center a player outside the map.")
		return
	map.update_position(Vector3(current_position.x, 0, current_position.y))
	map.center_button.pressed.emit()
	map.canvas.gui_input.emit(_wheel(MOUSE_BUTTON_WHEEL_UP, map.canvas.size / 2.0))
	var saved_zoom: float = map.zoom
	await _mouse_motion(map.canvas, cursor, Vector2.ZERO)
	await _mouse_button(map.canvas, MOUSE_BUTTON_LEFT, true, cursor)
	await _key("ui_cancel")
	if world.map_open or map.visible or paused or world.menu_open or map.dragging:
		_fail("Escape did not close the map without opening the menu.")
		return
	var saved_center: Vector2 = map.view_center
	await _key("show_map")
	if map.view_center != saved_center or not is_equal_approx(map.zoom, saved_zoom):
		_fail("Reopening the map did not preserve the view.")
		return
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
		var marker: Vector2 = map._map_point(map.player_position, map._map_factor())
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


func _wheel(button: MouseButton, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = position
	return event


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
