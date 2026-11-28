extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const DataPaths = preload("res://scripts/data_paths.gd")
const BuildingEditor = preload("res://scripts/building_editor.gd")
const BuildingWalls = preload("res://scripts/building_walls.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _way(id: int, left: float, origin: Array) -> Dictionary:
	var zone := Grid.zone_for_origin(origin)
	var projected := Grid.project(origin, zone, true)
	var geometry := []
	for point in [Vector2(left, 0), Vector2(left + 10, 0), Vector2(left + 10, 10), Vector2(left, 10), Vector2(left, 0)]:
		geometry.append(Grid.unproject([projected[0] + point.x, projected[1] + point.y], zone, true))
	return {"id": id, "tags": {"building": "yes", "height": "5"}, "geometry": geometry}


func _can_leave_wall(player: CharacterBody3D) -> bool:
	player.movement_input = Vector2(1, 1).normalized()
	var start := player.global_position
	for frame in 20:
		await physics_frame
	var sliding := player.global_position
	player.movement_input = Vector2.LEFT
	for frame in 20:
		await physics_frame
	player.movement_input = Vector2.ZERO
	return sliding.z > start.z + 0.8 and sliding.x < 0.0 and player.global_position.x < sliding.x - 1.0


func _has_floors(building: StaticBody3D, count: int, scale_factor: float) -> bool:
	for index in count:
		var visual := building.get_node_or_null("Segment_%d" % (index + 1)) as MeshInstance3D
		var collider := building.get_node_or_null("SegmentCollision_%d" % (index + 1)) as CollisionShape3D
		var height := 3.0 * scale_factor
		if visual == null or collider == null or visual.get_meta("floor_number", 0) != index + 1 or collider.get_meta("floor_number", 0) != index + 1:
			return false
		if not is_equal_approx(visual.position.y, index * height) or not is_equal_approx(collider.position.y, index * height) or not is_equal_approx(visual.mesh.get_aabb().size.y, height):
			return false
		var bounds := AABB(collider.shape.get_faces()[0], Vector3.ZERO)
		for point in collider.shape.get_faces():
			bounds = bounds.expand(point)
		if not is_equal_approx(bounds.size.y, height):
			return false
	return true


func _contains(polygons: Array[PackedVector2Array], point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _has_dimension(lines: Array, length: float) -> bool:
	for line in lines:
		if absf(line.start.distance_to(line.end) - length) < 0.02:
			return true
	return false


func _test() -> void:
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var interior := OSMMap._building_interior(outline, 0.3)
	var outer_geometry := BuildingWalls.floor_outline(outline, {})
	var dimension_geometry := {
		"outline": outline,
		"edges": outer_geometry.edges,
		"edit": {"wall_thickness": 0.3, "walls": []},
		"plans": [],
		"regions": [interior],
	}
	var outside_dimensions := BuildingEditor._wall_dimensions(dimension_geometry, true, 0, -1)
	if outside_dimensions.walls.size() != 3 or outside_dimensions.rooms.size() != 4 or not _has_dimension(outside_dimensions.walls, 10.0) or not _has_dimension(outside_dimensions.rooms, 9.4):
		_fail("Exterior wall and adjoining room dimensions were incorrect: %s" % outside_dimensions)
		return
	var dimension_walls := [
		{"cursor": [3.0, 0.5], "thickness": 0.3},
		{"cursor": [0.5, 5.0], "thickness": 0.3},
	]
	var built_dimensions := BuildingWalls.build(interior, dimension_walls)
	if built_dimensions.has("error"):
		_fail("Could not build rooms for dimension tests: %s" % built_dimensions)
		return
	dimension_geometry.edit.walls = dimension_walls
	dimension_geometry.plans = built_dimensions.plans
	dimension_geometry.regions = built_dimensions.regions
	var wall_dimensions := BuildingEditor._wall_dimensions(dimension_geometry, false, 0, -1)
	if wall_dimensions.walls.size() != 4 or not _has_dimension(wall_dimensions.walls, 9.4) or not _has_dimension(wall_dimensions.rooms, 2.55) or not _has_dimension(wall_dimensions.rooms, 6.55):
		_fail("Interior wall, connected wall or room dimensions were incorrect: %s" % wall_dimensions)
		return
	var moved_dimensions := BuildingWalls.adjust_walls(interior, interior, dimension_walls, 0, 1.0, 0.3)
	if moved_dimensions.has("error"):
		_fail("Could not move a wall for dimension tests: %s" % moved_dimensions)
		return
	var moved_build := BuildingWalls.build(interior, moved_dimensions.walls)
	dimension_geometry.edit.walls = moved_dimensions.walls
	dimension_geometry.plans = moved_build.plans
	dimension_geometry.regions = moved_build.regions
	var shifted_dimensions := BuildingEditor._wall_dimensions(dimension_geometry, false, 0, -1)
	if not _has_dimension(shifted_dimensions.rooms, 3.55) or not _has_dimension(shifted_dimensions.rooms, 5.55):
		_fail("Room dimensions did not change with the shifted partition: %s" % shifted_dimensions)
		return
	var piece_walls := [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 1.0], "thicknesses": [0.3, 0.6]}]
	var built_piece := BuildingWalls.build(interior, piece_walls)
	if built_piece.has("error"):
		_fail("Could not build a stepped wall for dimension tests: %s" % built_piece)
		return
	dimension_geometry.edit.walls = piece_walls
	dimension_geometry.plans = built_piece.plans
	dimension_geometry.regions = built_piece.regions
	var interior_piece_dimensions := BuildingEditor._wall_dimensions(dimension_geometry, false, 0, 1)
	if interior_piece_dimensions.walls.is_empty() or not _has_dimension(interior_piece_dimensions.walls, 4.7) or not _has_dimension(interior_piece_dimensions.walls, 1.0) or interior_piece_dimensions.rooms.is_empty():
		_fail("A selected interior wall piece and its connector were not measured: %s" % interior_piece_dimensions)
		return
	var outer_selection := BuildingEditor._exterior_wall_selection(outline, interior, 0, 0.3)
	if not _contains(outer_selection, Vector2(5, 0.01)) or not _contains(outer_selection, Vector2(5, 0.29)) or not _contains(outer_selection, Vector2(0.25, 0.1)) or _contains(outer_selection, Vector2(0.1, 0.25)) or _contains(outer_selection, Vector2(5, 0.31)):
		_fail("The exterior selection does not cover exactly the selected wall surface.")
		return
	var stepped := BuildingWalls.floor_outline(outline, {"outer_splits": [{"edge": 0, "cuts": [0.5], "offsets": [0.0, -1.0]}]})
	var stepped_interior := OSMMap._building_interior(stepped.outline, 0.3)
	var stepped_geometry := {
		"outline": stepped.outline,
		"edges": stepped.edges,
		"edit": {"wall_thickness": 0.3, "walls": []},
		"plans": [],
		"regions": [stepped_interior],
	}
	var piece_dimensions := BuildingEditor._wall_dimensions(stepped_geometry, true, 0, 0)
	if piece_dimensions.walls.size() != 3 or not _has_dimension(piece_dimensions.walls, 5.0) or not _has_dimension(piece_dimensions.walls, 1.0) or piece_dimensions.rooms.is_empty():
		_fail("The selected exterior piece and its connector were not measured: %s" % piece_dimensions)
		return
	var exterior_selection_piece := BuildingEditor._exterior_wall_selection(stepped.outline, stepped_interior, 0, 0.3)
	if not _contains(exterior_selection_piece, Vector2(2.5, 0.15)) or _contains(exterior_selection_piece, Vector2(7.5, -0.85)):
		_fail("An exterior wall piece did not receive its own selection surface.")
		return
	var rotated := PackedVector2Array()
	for point in outline:
		rotated.append(point.rotated(0.6))
	rotated.reverse()
	var rotated_selection := BuildingEditor._exterior_wall_selection(rotated, OSMMap._building_interior(rotated, 0.3), 2, 0.3)
	if not _contains(rotated_selection, Vector2(5, 0.15).rotated(0.6)) or _contains(rotated_selection, Vector2(5, 0.31).rotated(0.6)):
		_fail("A reversed, rotated exterior wall did not receive the correct selection surface.")
		return
	var rotated_cursor := Vector2(3, 0.5).rotated(0.6)
	var rotated_walls := [{"cursor": [rotated_cursor.x, rotated_cursor.y], "thickness": 0.3}]
	var rotated_interior := OSMMap._building_interior(rotated, 0.3)
	var rotated_build := BuildingWalls.build(rotated_interior, rotated_walls)
	if rotated_build.has("error"):
		_fail("Could not build a rotated wall for dimension tests: %s" % rotated_build)
		return
	var rotated_geometry := {
		"outline": rotated,
		"edges": BuildingWalls.floor_outline(rotated, {}).edges,
		"edit": {"wall_thickness": 0.3, "walls": rotated_walls},
		"plans": rotated_build.plans,
		"regions": rotated_build.regions,
	}
	var rotated_dimensions := BuildingEditor._wall_dimensions(rotated_geometry, false, 0, -1)
	if rotated_dimensions.walls.size() != 3 or not _has_dimension(rotated_dimensions.rooms, 2.55) or not _has_dimension(rotated_dimensions.rooms, 6.55):
		_fail("Measurements changed for a rotated, reversed outline: %s" % rotated_dimensions)
		return
	var concave := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 3), Vector2(4, 3), Vector2(4, 8), Vector2(0, 8)])
	var concave_selection := BuildingEditor._exterior_wall_selection(concave, OSMMap._building_interior(concave, 0.3), 3, 0.3)
	if not _contains(concave_selection, Vector2(3.71, 5)) or not _contains(concave_selection, Vector2(3.99, 5)) or _contains(concave_selection, Vector2(3.69, 5)):
		_fail("A concave exterior wall was not marked across its full thickness.")
		return
	var split_wall := BuildingWalls.build(outline, [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 1.0], "thicknesses": [0.3, 0.6]}])
	var interior_piece := BuildingEditor._interior_piece_selection(split_wall.walls[0], split_wall.plans[0].segments[1], 0.6)
	if not _contains(interior_piece, Vector2(4.29, 8)) or not _contains(interior_piece, Vector2(3.71, 8)) or _contains(interior_piece, Vector2(3, 2)) or _contains(interior_piece, Vector2(4.31, 8)):
		_fail("The interior piece selection did not match its individual thickness.")
		return
	var directory := ProjectSettings.globalize_path("user://building_editor_test_" + Crypto.new().generate_random_bytes(8).hex_encode())
	DataPaths.root_override = directory
	var origin := [47.7748417, 10.6034933]
	var a := _way(1, 0, origin)
	var b := _way(2, 10, origin)
	var place := {"id": "test", "name": "Test", "origin": origin, "bounds": [47.77, 10.60, 47.78, 10.61], "ways": [a, b]}
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world, place):
		_fail("Test map could not be built.")
		return
	root.add_child(world)
	world.set_process(false)
	world.map_block_stream.set_process(false)
	world.player.position = Vector3(-20, 0.9, 0)
	var camera: Camera3D = world.get_node("Camera3D")
	camera.size = 50
	camera.global_position = Vector3(13, 50, -6.5)
	await physics_frame
	await physics_frame
	var editor: Control = world.get_node("HUD/BuildingEditor")
	var measurement: Control = world.get_node("HUD/BuildingMeasurement")
	var key := InputEventKey.new()
	key.keycode = KEY_F5
	key.pressed = true
	root.push_input(key, true)
	await process_frame
	await process_frame
	if not editor.active or not editor.panel.visible:
		_fail("F5 did not open the building editor.")
		return
	var first_click := InputEventMouseButton.new()
	first_click.button_index = MOUSE_BUTTON_LEFT
	first_click.pressed = true
	first_click.position = camera.unproject_position(Vector3(6.5, 6.5, -6.5))
	root.push_input(first_click, true)
	await physics_frame
	await physics_frame
	if editor.selected.size() != 1 or editor.levels_button.disabled or not editor.levels_input.text.is_empty():
		_fail("Selecting one building did not enable the empty level input.")
		return
	editor.levels_input.text = "0"
	editor.levels_button.pressed.emit()
	if not editor.message.text.contains("1 bis 1000") or FileAccess.file_exists(world.building_edits.path):
		_fail("Invalid levels were not rejected without saving.")
		return
	editor.levels_input.text = "2"
	editor.levels_input.grab_focus()
	editor.levels_button.pressed.emit()
	await physics_frame
	await physics_frame
	var first_building: StaticBody3D = world.get_node("OSMMap/Building_1")
	if absf(float(first_building.get_meta("measurement_height")) - 7.8) > 0.01 or not _has_floors(first_building, 2, 1.3):
		_fail("Level edit did not change the scaled building height.")
		return
	root.push_input(key, true)
	if editor.active:
		_fail("F5 did not close the editor after editing levels.")
		return
	var position_before: Vector3 = world.player.global_position
	Input.action_press("move_forward")
	for frame in 8:
		await physics_frame
	Input.action_release("move_forward")
	if world.player.global_position.distance_to(position_before) < 0.1:
		_fail("The player could not move after editing levels and leaving the editor.")
		return
	world.player.uses_local_input = false
	world.car.global_position = Vector3(-100, 0.5, -100)
	world.player.global_position = Vector3(-0.4, 0.9, -6.5)
	world.player.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	root.push_input(key, true)
	await process_frame
	await process_frame
	for center in [Vector3(6.5, 6.5, -6.5), Vector3(19.5, 6.5, -6.5)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = camera.unproject_position(center)
		root.push_input(click, true)
		await physics_frame
		await physics_frame
	if editor.selected.size() != 2 or editor.merge_button.disabled:
		_fail("Clicking two buildings did not select both.")
		return
	editor.merge_button.pressed.emit()
	await physics_frame
	await physics_frame
	if not editor.selected.is_empty() or world.get_node_or_null("OSMMap/Building_2") != null or not FileAccess.file_exists(world.building_edits.path):
		_fail("Merge did not update the map, clear the selection and persist the diff.")
		return
	root.push_input(key, true)
	if editor.active or not await _can_leave_wall(world.player):
		_fail("Player could not slide and move away from the merged building after closing the editor.")
		return
	root.push_input(key, true)
	await process_frame
	root.push_input(first_click, true)
	await physics_frame
	await physics_frame
	if editor.selected.size() != 1 or editor.levels_input.text != "2":
		_fail("The merged building did not retain the first building's level count.")
		return
	editor.levels_input.text = "4"
	editor.levels_button.pressed.emit()
	await physics_frame
	await physics_frame
	var merged_building: StaticBody3D = world.get_node("OSMMap/Building_1")
	if absf(float(merged_building.get_meta("measurement_height")) - 15.6) > 0.01 or not _has_floors(merged_building, 4, 1.3):
		_fail("Merged building did not adopt the edited level count.")
		return
	for floor_index in 4:
		var y := (floor_index + 0.5) * 3.9
		var query := PhysicsRayQueryParameters3D.create(Vector3(-2, y, -6.5), Vector3(2, y, -6.5), OSMMap.BUILDING_PICK_LAYER)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != merged_building:
			_fail("The merged building did not have a collision on floor %d." % (floor_index + 1))
			return
		var owner_id := merged_building.shape_find_owner(hit.shape)
		var shape_node := merged_building.shape_owner_get_owner(owner_id) as CollisionShape3D
		if shape_node == null or shape_node.get_meta("floor_number", 0) != floor_index + 1:
			_fail("The collision did not identify floor %d." % (floor_index + 1))
			return
	root.push_input(first_click, true)
	await physics_frame
	await physics_frame
	if editor.selected.size() != 1 or not editor.floor_number.editable or editor.hollow_button.disabled:
		_fail("The floor selector was not enabled for the merged building.")
		return
	editor.floor_number.value = 2
	if merged_building.get_node("Segment_3").visible:
		_fail("Floors above the selected floor were not hidden in the editor.")
		return
	editor.hollow_button.pressed.emit()
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	if editor.selected.size() != 1 or editor.floor_number.value != 2 or not editor.hollow_button.disabled or not merged_building.has_node("FloorPreview_2") or not merged_building.get_node("FloorPreview_2").visible or merged_building.get_node("Segment_2").visible or merged_building.get_node("Segment_3").visible:
		_fail("Hollowing the floor did not retain selection and show the open preview: " + editor.message.text)
		return
	var saved_floor: Array = world.building_edits.merges[0].hollow_floors
	if saved_floor.size() != 1 or int(saved_floor[0].floor) != 2 or not is_equal_approx(float(saved_floor[0].wall_thickness), 0.3):
		_fail("The selected floor and default wall thickness were not persisted.")
		return
	var inner_query := PhysicsRayQueryParameters3D.create(Vector3(6.5, 5.85, -6.5), Vector3(-2, 5.85, -6.5), OSMMap.BUILDING_PICK_LAYER)
	var inner_hit := world.get_world_3d().direct_space_state.intersect_ray(inner_query)
	if inner_hit.is_empty() or absf(inner_hit.position.x - 0.39) > 0.02:
		_fail("Interior wall collision does not have the requested scaled thickness: %s" % inner_hit)
		return
	world.player.global_position = Vector3(3.0, 4.8, -6.5)
	world.player.velocity = Vector3.ZERO
	world.player.movement_input = Vector2.LEFT
	for frame in 40:
		await physics_frame
	var inside_wall: Vector3 = world.player.global_position
	world.player.movement_input = Vector2(-1, 1).normalized()
	for frame in 20:
		await physics_frame
	var inside_slide: Vector3 = world.player.global_position
	world.player.movement_input = Vector2.RIGHT
	for frame in 20:
		await physics_frame
	world.player.movement_input = Vector2.ZERO
	if inside_wall.x < 0.75 or inside_wall.x > 1.0 or absf(inside_wall.y - 4.8) > 0.1 or inside_slide.z < inside_wall.z + 0.8 or world.player.global_position.x < inside_slide.x + 1.0:
		_fail("Player could not collide, slide and move away inside the hollow floor: %s -> %s -> %s" % [inside_wall, inside_slide, world.player.global_position])
		return
	world.player.global_position = Vector3(-2, 0.9, -6.5)
	world.player.velocity = Vector3.ZERO
	editor.wall_button.pressed.emit()
	if not editor.wall_mode:
		_fail("Wall mode could not be started on a hollow floor.")
		return
	var first_wall_position := camera.unproject_position(Vector3(10.4, 7.8, -12.2))
	var move := InputEventMouseMotion.new()
	move.position = first_wall_position
	root.push_input(move, true)
	if editor.wall_preview.is_empty() or editor.wall_preview.has("error"):
		_fail("The wall preview was not shown at the cursor: %s" % editor.wall_preview)
		return
	var wall_click := InputEventMouseButton.new()
	wall_click.button_index = MOUSE_BUTTON_LEFT
	wall_click.pressed = true
	wall_click.position = first_wall_position
	root.push_input(wall_click, true)
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	if not editor.wall_mode or editor.selected.size() != 1 or not merged_building.has_node("InteriorWall_2_1"):
		_fail("The first wall was not saved or the editor lost its selection: " + editor.message.text)
		return
	var second_wall_position := camera.unproject_position(Vector3(0.8, 7.8, -9.0))
	move.position = second_wall_position
	root.push_input(move, true)
	if editor.wall_preview.has("error") or editor.wall_preview.is_empty():
		_fail("The second wall preview was invalid: %s" % editor.wall_preview)
		return
	wall_click.position = second_wall_position
	root.push_input(wall_click, true)
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	var saved_walls: Array = world.building_edits.merges[0].hollow_floors[0].walls
	if saved_walls.size() != 2 or not merged_building.has_node("InteriorWall_2_2"):
		_fail("The second interior wall was not persisted.")
		return
	var wall_query := PhysicsRayQueryParameters3D.create(Vector3(2, 5.85, -6), Vector3(14, 5.85, -6), OSMMap.BUILDING_PICK_LAYER)
	wall_query.hit_back_faces = false
	var wall_hit := world.get_world_3d().direct_space_state.intersect_ray(wall_query)
	if wall_hit.is_empty() or absf(wall_hit.position.x - 10.205) > 0.05:
		_fail("The first interior wall has incorrect collision or thickness: %s" % wall_hit)
		return
	var other_side_query := PhysicsRayQueryParameters3D.create(Vector3(14, 5.85, -6), Vector3(2, 5.85, -6), OSMMap.BUILDING_PICK_LAYER)
	other_side_query.hit_back_faces = false
	var other_side_hit := world.get_world_3d().direct_space_state.intersect_ray(other_side_query)
	if other_side_hit.is_empty() or absf(other_side_hit.position.x - 10.595) > 0.05:
		_fail("The interior wall does not collide from both sides: %s" % other_side_hit)
		return
	var second_wall_query := PhysicsRayQueryParameters3D.create(Vector3(3, 5.85, -7), Vector3(3, 5.85, -11), OSMMap.BUILDING_PICK_LAYER)
	var second_wall_hit := world.get_world_3d().direct_space_state.intersect_ray(second_wall_query)
	if second_wall_hit.is_empty() or absf(second_wall_hit.position.z + 8.805) > 0.05:
		_fail("The second interior wall has incorrect collision: %s" % second_wall_hit)
		return
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	if editor.wall_mode or editor.selected.size() != 1 or world.menu_open:
		_fail("Escape did not cancel wall mode without opening the menu.")
		return
	world.player.global_position = Vector3(8, 4.8, -5)
	world.player.velocity = Vector3.ZERO
	world.player.movement_input = Vector2.RIGHT
	for frame in 30:
		await physics_frame
	var partition_wall: Vector3 = world.player.global_position
	world.player.movement_input = Vector2(1, 1).normalized()
	for frame in 20:
		await physics_frame
	var partition_slide: Vector3 = world.player.global_position
	world.player.movement_input = Vector2.LEFT
	for frame in 20:
		await physics_frame
	world.player.movement_input = Vector2.ZERO
	if absf(partition_wall.x - 9.805) > 0.1 or partition_slide.z < partition_wall.z + 0.8 or world.player.global_position.x > partition_slide.x - 1.0:
		_fail("Player could not slide and move away from the new wall: %s -> %s -> %s" % [partition_wall, partition_slide, world.player.global_position])
		return
	var select_wall := InputEventMouseButton.new()
	select_wall.button_index = MOUSE_BUTTON_LEFT
	select_wall.pressed = true
	select_wall.position = camera.unproject_position(Vector3(10.4, 7.8, -6.0))
	root.push_input(select_wall, true)
	if editor.selected_wall != 0 or editor.selected_wall_outside or not editor.wall_properties.visible:
		_fail("Clicking the interior wall did not select it and show its properties.")
		return
	await process_frame
	await process_frame
	var dimensions_before: String = editor.wall_dimensions.text
	if editor.dimensions.is_empty() or editor.dimensions.walls.is_empty():
		_fail("The selected wall did not produce dimension data.")
		return
	var first_line: Dictionary = editor.dimensions.walls[0]
	var first_length: float = first_line.start.distance_to(first_line.end)
	var expected_wall_text := "W1: %.2f m | %.2f SE" % [first_length, first_length * float(merged_building.get_meta("measurement_scale"))]
	if not dimensions_before.contains(expected_wall_text) or not dimensions_before.contains("R1:"):
		_fail("Wall and room dimensions were not displayed in both units.")
		return
	move.position = camera.unproject_position(Vector3(11.7, 7.8, -6.0))
	root.push_input(move, true)
	if editor.drag_result.has("error") or editor.drag_result.is_empty():
		_fail("Dragging the interior wall did not produce a valid preview: %s; positions %s -> %s; dragging %s" % [editor.drag_result, select_wall.position, move.position, editor.dragging_wall])
		return
	await process_frame
	await process_frame
	if editor.wall_dimensions.text == dimensions_before:
		_fail("Room measurements did not update during the drag preview.")
		return
	var valid_preview_dimensions: String = editor.wall_dimensions.text
	editor._update_wall_drag(camera.unproject_position(Vector3(100.0, 7.8, -6.0)))
	await process_frame
	await process_frame
	if not editor.drag_result.has("error") or editor.wall_dimensions.text != dimensions_before:
		_fail("An invalid drag did not retain the saved wall dimensions.")
		return
	editor._update_wall_drag(move.position)
	await process_frame
	await process_frame
	if editor.drag_result.has("error") or editor.wall_dimensions.text != valid_preview_dimensions or not editor.message.text.is_empty():
		_fail("Valid preview dimensions were not restored after an invalid drag.")
		return
	var release_wall := InputEventMouseButton.new()
	release_wall.button_index = MOUSE_BUTTON_LEFT
	release_wall.pressed = false
	release_wall.position = move.position
	root.push_input(release_wall, true)
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or editor.selected_wall != 0:
		_fail("The wall drag was not saved: " + editor.message.text)
		return
	editor.wall_thickness_input.text = "0"
	editor.wall_apply.pressed.emit()
	if not editor.message.text.contains("gültige Wanddicke") or not is_equal_approx(float(world.building_edits.merges[0].hollow_floors[0].walls[0].thickness), 0.3):
		_fail("An invalid thickness was not rejected without changing the saved wall.")
		return
	editor.wall_thickness_input.text = "50"
	editor.wall_apply.pressed.emit()
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	var edited_floor: Dictionary = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or absf(float(edited_floor.walls[0].thickness) - 0.5) > 0.001:
		_fail("The wall thickness was not saved from the popup: " + editor.message.text)
		return
	var moved_query := PhysicsRayQueryParameters3D.create(Vector3(2, 5.85, -6), Vector3(14, 5.85, -6), OSMMap.BUILDING_PICK_LAYER)
	var moved_hit := world.get_world_3d().direct_space_state.intersect_ray(moved_query)
	if moved_hit.is_empty() or absf(moved_hit.position.x - 11.375) > 0.06:
		_fail("The edited wall collision was not rebuilt: %s" % moved_hit)
		return
	select_wall.position = camera.unproject_position(Vector3(0.195, 7.8, -4.0))
	root.push_input(select_wall, true)
	if editor.selected_wall < 0 or not editor.selected_wall_outside:
		_fail("Clicking an exterior wall did not open its properties.")
		return
	editor.wall_thickness_input.text = "40"
	editor.wall_apply.pressed.emit()
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or absf(float(edited_floor.wall_thickness) - 0.4) > 0.001:
		_fail("The exterior wall thickness was not saved for the floor: " + editor.message.text)
		return
	select_wall.position = camera.unproject_position(Vector3(0.26, 7.8, -4.0))
	root.push_input(select_wall, true)
	await process_frame
	await process_frame
	var exterior_dimensions_before: String = editor.wall_dimensions.text
	if not exterior_dimensions_before.contains("W1:") or not exterior_dimensions_before.contains("R1:"):
		_fail("The exterior wall selection did not show wall and room dimensions.")
		return
	move.position = camera.unproject_position(Vector3(-0.39, 7.8, -4.0))
	root.push_input(move, true)
	if editor.drag_result.has("error") or editor.drag_result.is_empty():
		_fail("Dragging the exterior wall did not produce a valid preview: %s" % editor.drag_result)
		return
	await process_frame
	await process_frame
	if editor.wall_dimensions.text == exterior_dimensions_before:
		_fail("Room dimensions did not update during the exterior wall preview.")
		return
	var saved_before_interrupted_drag := JSON.stringify(world.building_edits.data())
	editor.floor_number.set_value_no_signal(1)
	release_wall.position = move.position
	root.push_input(release_wall, true)
	if editor.dragging_wall or editor.selected_wall != -1 or not editor.drag_result.is_empty() or editor.message.text.is_empty() or JSON.stringify(world.building_edits.data()) != saved_before_interrupted_drag:
		_fail("An unavailable floor did not cancel the wall drag without saving.")
		return
	editor.floor_number.set_value_no_signal(2)
	editor._update_floor_preview()
	select_wall.position = camera.unproject_position(Vector3(0.26, 7.8, -4.0))
	root.push_input(select_wall, true)
	root.push_input(move, true)
	if not editor.dragging_wall or editor.drag_result.is_empty() or editor.drag_result.has("error"):
		_fail("The exterior wall could not be dragged again after cancellation.")
		return
	var original_way: Dictionary = merged_building.get_meta("measurement_way").duplicate(true)
	var unavailable_way := original_way.duplicate(true)
	unavailable_way.erase("_hollow_floors")
	merged_building.set_meta("measurement_way", unavailable_way)
	root.push_input(move, true)
	if editor.dragging_wall or editor.selected_wall != -1 or editor.message.text.is_empty() or JSON.stringify(world.building_edits.data()) != saved_before_interrupted_drag:
		_fail("Missing floor metadata did not cancel the wall drag without saving.")
		return
	var block_key: Variant = editor._selected_block_key(merged_building)
	if editor._restore_building_selection(block_key, 1, 2) or not editor.selected.is_empty() or editor.message.text.is_empty():
		_fail("A building without the edited floor was incorrectly restored.")
		return
	merged_building.set_meta("measurement_way", original_way)
	if not editor._restore_building_selection(block_key, 1, 2):
		_fail("The building selection could not be restored after the floor returned.")
		return
	root.push_input(select_wall, true)
	editor.selected_segment = 99
	root.push_input(move, true)
	if editor.dragging_wall or editor.selected_wall != -1 or editor.message.text.is_empty() or JSON.stringify(world.building_edits.data()) != saved_before_interrupted_drag:
		_fail("An unavailable wall segment did not cancel the wall drag without saving.")
		return
	root.push_input(select_wall, true)
	editor.selected_wall_outside = false
	editor.selected_wall = 99
	root.push_input(move, true)
	if editor.dragging_wall or editor.selected_wall != -1 or editor.message.text.is_empty() or JSON.stringify(world.building_edits.data()) != saved_before_interrupted_drag:
		_fail("An unavailable interior wall did not cancel the wall drag without saving.")
		return
	root.push_input(select_wall, true)
	root.push_input(move, true)
	if not editor.dragging_wall or editor.drag_result.is_empty() or editor.drag_result.has("error"):
		_fail("The exterior wall could not be dragged after restoring its floor.")
		return
	var camera_transform := camera.global_transform
	camera.global_rotation = Vector3.ZERO
	release_wall.position = root.get_visible_rect().get_center()
	root.push_input(release_wall, true)
	camera.global_transform = camera_transform
	if editor.dragging_wall or not editor.drag_result.has("error") or editor.message.text.is_empty() or JSON.stringify(world.building_edits.data()) != saved_before_interrupted_drag:
		_fail("An unreachable floor cursor committed a stale wall drag preview.")
		return
	root.push_input(select_wall, true)
	root.push_input(move, true)
	release_wall.position = move.position
	root.push_input(release_wall, true)
	await physics_frame
	await physics_frame
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS:
		_fail("The exterior wall drag was not saved: " + editor.message.text)
		return
	var moved_outer_query := PhysicsRayQueryParameters3D.create(Vector3(3, 5.85, -4), Vector3(-2, 5.85, -4), OSMMap.BUILDING_PICK_LAYER)
	var moved_outer_hit := world.get_world_3d().direct_space_state.intersect_ray(moved_outer_query)
	if moved_outer_hit.is_empty() or absf(moved_outer_hit.position.x + 0.13) > 0.06:
		_fail("The moved exterior wall did not rebuild its collision: %s" % moved_outer_hit)
		return
	editor._clear_wall_selection()
	await process_frame
	await process_frame
	if not editor.wall_dimensions.text.is_empty() or editor.dimensions_panel.visible:
		_fail("Wall measurements remained visible after clearing the selection.")
		return
	select_wall.position = camera.unproject_position(Vector3(11.7, 7.8, -5.0))
	root.push_input(select_wall, true)
	release_wall.position = select_wall.position
	root.push_input(release_wall, true)
	if editor.selected_wall != 0 or editor.selected_wall_outside:
		_fail("Could not select the partition for splitting.")
		return
	var before_split := JSON.stringify(world.building_edits.data())
	editor.wall_split.pressed.emit()
	if editor.split_preview.is_empty() or editor.split_preview.preview.size() != 2 or JSON.stringify(world.building_edits.data()) != before_split:
		_fail("The split preview was missing or changed saved data.")
		return
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	root.push_input(right_click, true)
	if not editor.split_preview.is_empty() or JSON.stringify(world.building_edits.data()) != before_split:
		_fail("Right-click did not cancel the split preview without changes.")
		return
	editor.wall_split.pressed.emit()
	root.push_input(cancel, true)
	if not editor.split_preview.is_empty() or JSON.stringify(world.building_edits.data()) != before_split or world.menu_open:
		_fail("Escape did not cancel the split preview without changes.")
		return
	editor.wall_split.pressed.emit()
	editor.wall_split_confirm.pressed.emit()
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_SPLIT_SUCCESS or edited_floor.walls[0].get("cuts", []).size() != 1 or editor.selected_segment != 0:
		_fail("The confirmed wall split was not persisted: " + editor.message.text)
		return
	select_wall.position = camera.unproject_position(Vector3(11.7, 7.8, -5.0))
	root.push_input(select_wall, true)
	if editor.selected_segment < 0:
		_fail("An interior wall segment could not be selected.")
		return
	var moved_piece_index: int = editor.selected_segment
	move.position = camera.unproject_position(Vector3(12.35, 7.8, -5.0))
	root.push_input(move, true)
	release_wall.position = move.position
	root.push_input(release_wall, true)
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or absf(float(edited_floor.walls[0].offsets[moved_piece_index])) < 0.4:
		_fail("A split wall segment did not move with its connector: " + editor.message.text)
		return
	merged_building = world.get_node("OSMMap/Building_1")
	var split_floor: MeshInstance3D = merged_building.get_node("FloorPreview_2")
	var split_segments: Array = split_floor.get_meta("wall_plans")[0].segments
	var connector_start: Vector2 = split_segments[0][1]
	var connector_end: Vector2 = split_segments[1][0]
	var connector_middle := (connector_start + connector_end) * 0.5
	var connector_normal := (connector_end - connector_start).normalized().orthogonal()
	var wall_origin: Vector2 = split_floor.get_meta("wall_origin")
	var wall_scale: float = merged_building.get_meta("measurement_scale")
	var connector_from := connector_middle + connector_normal + wall_origin
	var connector_to := connector_middle - connector_normal + wall_origin
	var connector_query := PhysicsRayQueryParameters3D.create(merged_building.to_global(Vector3(connector_from.x * wall_scale, 5.85, connector_from.y * wall_scale)), merged_building.to_global(Vector3(connector_to.x * wall_scale, 5.85, connector_to.y * wall_scale)), OSMMap.BUILDING_PICK_LAYER)
	var connector_hit := world.get_world_3d().direct_space_state.intersect_ray(connector_query)
	if connector_start.distance_to(connector_end) < 0.4 or connector_hit.is_empty():
		_fail("The automatic connecting wall did not have collision: %s" % connector_hit)
		return
	editor.wall_thickness_input.text = "60"
	editor.wall_apply.pressed.emit()
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or absf(float(edited_floor.walls[0].thicknesses[moved_piece_index]) - 0.6) > 0.001:
		_fail("A split wall segment did not retain its own thickness: " + editor.message.text)
		return
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	shift_click.position = camera.unproject_position(Vector3(-0.39, 7.8, -4.0))
	root.push_input(shift_click, true)
	if editor.secondary_wall.is_empty() or not editor.wall_merge.visible or not editor.secondary_wall.outside:
		_fail("Shift-click did not add a second wall.")
		return
	var before_merge := JSON.stringify(world.building_edits.data())
	editor.wall_merge.pressed.emit()
	if editor.message.text != "Nur benachbarte Teilstücke derselben aufgeteilten Wand können verbunden werden." or JSON.stringify(world.building_edits.data()) != before_merge:
		_fail("Unrelated walls were not rejected without changing saved data.")
		return
	merged_building = world.get_node("OSMMap/Building_1")
	split_floor = merged_building.get_node("FloorPreview_2")
	split_segments = split_floor.get_meta("wall_plans")[0].segments
	var first_middle: Vector2 = (split_segments[moved_piece_index][0] + split_segments[moved_piece_index][1]) * 0.5
	var other_middle: Vector2 = (split_segments[1 - moved_piece_index][0] + split_segments[1 - moved_piece_index][1]) * 0.5
	var other_position := (other_middle + wall_origin) * wall_scale
	shift_click.position = camera.unproject_position(merged_building.to_global(Vector3(other_position.x, 7.8, other_position.y)))
	root.push_input(shift_click, true)
	if editor.selected_segment != moved_piece_index or int(editor.secondary_wall.segment) == moved_piece_index or editor.dragging_wall:
		_fail("Shift-click did not preserve the first wall selection.")
		return
	editor.wall_merge.pressed.emit()
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_MERGE_SUCCESS or edited_floor.walls[0].has("cuts") or absf(float(edited_floor.walls[0].thickness) - 0.6) > 0.001 or not editor.secondary_wall.is_empty() or editor.wall_merge.visible:
		_fail("The selected wall pieces were not merged with the first piece's thickness: " + editor.message.text)
		return
	merged_building = world.get_node("OSMMap/Building_1")
	split_floor = merged_building.get_node("FloorPreview_2")
	var merged_segment: Array = split_floor.get_meta("wall_plans")[0].segments[0]
	if first_middle.distance_to(Geometry2D.get_closest_point_to_segment(first_middle, merged_segment[0], merged_segment[1])) > 0.02:
		_fail("The first selected wall piece moved when joining.")
		return
	editor._clear_wall_selection()
	select_wall.position = camera.unproject_position(Vector3(-0.39, 7.8, -4.0))
	root.push_input(select_wall, true)
	release_wall.position = select_wall.position
	root.push_input(release_wall, true)
	if editor.selected_wall < 0 or not editor.selected_wall_outside:
		_fail("Could not select the exterior wall for splitting.")
		return
	var exterior_edge: int = editor.selected_wall
	editor.wall_split.pressed.emit()
	if editor.split_preview.is_empty() or editor.split_preview.preview.size() != 2:
		_fail("The exterior wall split preview was not shown: " + editor.message.text)
		return
	editor.wall_split_confirm.pressed.emit()
	await physics_frame
	await physics_frame
	if editor.message.text != world.BUILDING_WALL_SPLIT_SUCCESS:
		_fail("The exterior wall split was not persisted: " + editor.message.text)
		return
	select_wall.position = camera.unproject_position(Vector3(-0.39, 7.8, -4.0))
	root.push_input(select_wall, true)
	if not editor.selected_wall_outside or editor.selected_wall != exterior_edge or editor.selected_segment < 0:
		_fail("A split exterior wall segment could not be selected.")
		return
	var exterior_piece: int = editor.selected_segment
	move.position = camera.unproject_position(Vector3(-1.04, 7.8, -4.0))
	root.push_input(move, true)
	release_wall.position = move.position
	root.push_input(release_wall, true)
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_CHANGE_SUCCESS or absf(float(edited_floor.outer_splits[0].offsets[exterior_piece])) < 0.4:
		_fail("An exterior wall segment did not move with its connector: " + editor.message.text)
		return
	var exterior_offset: float = edited_floor.outer_splits[0].offsets[exterior_piece]
	merged_building = world.get_node("OSMMap/Building_1")
	var exterior_preview: MeshInstance3D = merged_building.get_node("FloorPreview_2")
	var outer_edges: Array = exterior_preview.get_meta("outer_edges")
	var outer_outline: PackedVector2Array = exterior_preview.get_meta("local_outline")
	var other_exterior := Vector2.ZERO
	var found_other := false
	for index in outer_edges.size():
		if not outer_edges[index].connector and int(outer_edges[index].edge) == exterior_edge and int(outer_edges[index].segment) != exterior_piece:
			var edge_start := outer_outline[index]
			var edge_end := outer_outline[(index + 1) % outer_outline.size()]
			other_exterior = (edge_start + edge_end) * 0.5
			var inward := (outer_outline[(index + 1) % outer_outline.size()] - outer_outline[index]).normalized().orthogonal()
			if not Geometry2D.is_point_in_polygon(other_exterior + inward * 0.01, outer_outline):
				inward = -inward
			for fraction in [0.15, 0.3, 0.5, 0.7, 0.85]:
				var candidate: Vector2 = edge_start.lerp(edge_end, fraction) + inward * 0.2
				var position := (candidate + wall_origin) * wall_scale
				var screen := camera.unproject_position(merged_building.to_global(Vector3(position.x, 7.8, position.y)))
				if not editor.wall_properties.get_global_rect().has_point(screen) and not editor.panel.get_global_rect().has_point(screen) and not editor.dimensions_panel.get_global_rect().has_point(screen):
					other_exterior = candidate
					found_other = true
					break
			break
	if not found_other:
		_fail("The other exterior wall piece was not found.")
		return
	other_position = (other_exterior + wall_origin) * wall_scale
	shift_click.position = camera.unproject_position(merged_building.to_global(Vector3(other_position.x, 7.8, other_position.y)))
	root.push_input(shift_click, true)
	if editor.secondary_wall.is_empty() or not editor.secondary_wall.outside or not editor.wall_merge.visible:
		_fail("Shift-click did not select the other exterior wall piece: %s %s %s %s" % [editor.secondary_wall, editor.message.text, shift_click.position, other_exterior])
		return
	editor.wall_merge.pressed.emit()
	await physics_frame
	await physics_frame
	edited_floor = world.building_edits.merges[0].hollow_floors[0]
	if editor.message.text != world.BUILDING_WALL_MERGE_SUCCESS or not edited_floor.outer_splits[0].cuts.is_empty() or absf(float(edited_floor.outer_splits[0].offsets[0]) - exterior_offset) > 0.001:
		_fail("Exterior wall pieces were not merged at the first piece's position: " + editor.message.text)
		return
	editor._clear_wall_selection()
	world.player.global_position = Vector3(-2, 0.9, -6.5)
	world.player.velocity = Vector3.ZERO
	var settings_file := FileAccess.open(directory.path_join("config/building_editor.json"), FileAccess.WRITE)
	if settings_file == null:
		_fail("Could not change the wall-thickness settings.")
		return
	settings_file.store_string("{\"wall_thickness_m\": 0.6}")
	settings_file.close()
	editor.floor_number.value = 4
	editor.hollow_button.pressed.emit()
	await physics_frame
	await physics_frame
	merged_building = world.get_node("OSMMap/Building_1")
	if not merged_building.has_node("FloorPreview_4") or editor.selected.size() != 1:
		_fail("A second floor could not be hollowed independently.")
		return
	var both_floors: Array = world.building_edits.merges[0].hollow_floors
	if both_floors.size() != 2 or not is_equal_approx(float(both_floors[0].wall_thickness), 0.4) or not is_equal_approx(float(both_floors[1].wall_thickness), 0.6):
		_fail("Changed settings did not apply only to the newly hollowed floor.")
		return
	var upper_wall_query := PhysicsRayQueryParameters3D.create(Vector3(6.5, 14.0, -6.5), Vector3(-2, 14.0, -6.5), OSMMap.BUILDING_PICK_LAYER)
	var upper_wall_hit := world.get_world_3d().direct_space_state.intersect_ray(upper_wall_query)
	if upper_wall_hit.is_empty() or absf(upper_wall_hit.position.x - 0.78) > 0.02:
		_fail("The custom wall thickness did not affect the new floor collision: %s" % upper_wall_hit)
		return
	var ceiling_query := PhysicsRayQueryParameters3D.create(Vector3(6.5, 14.0, -6.5), Vector3(6.5, 17.0, -6.5), OSMMap.BUILDING_PICK_LAYER)
	ceiling_query.hit_back_faces = false
	var ceiling_hit := world.get_world_3d().direct_space_state.intersect_ray(ceiling_query)
	if ceiling_hit.is_empty() or absf(ceiling_hit.position.y - 15.6) > 0.02:
		_fail("The hollow top floor is missing its interior ceiling collision: %s" % ceiling_hit)
		return
	key.keycode = KEY_F4
	root.push_input(key, true)
	await process_frame
	await process_frame
	if editor.active or not measurement.active:
		_fail("Switching from the editor to measurement failed.")
		return
	if not merged_building.get_node("Segment_4").visible or merged_building.get_node("FloorPreview_4").visible:
		_fail("Closing the editor did not restore the normal building view.")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(13, 6.5, -6.5))
	root.push_input(click, true)
	await physics_frame
	await physics_frame
	if measurement.selected_building == null or not measurement.sides.text.contains("20.00 m (OSM) | 26.00 Spieleinheiten"):
		_fail("Merged building could not be measured.")
		return
	var changed: Dictionary = place.duplicate(true)
	changed.ways[1].geometry[0][0] += 0.00001
	changed.ways[1].geometry[-1][0] += 0.00001
	var other_block: Vector2i = world.map_block_stream.base_block + Vector2i.RIGHT
	world.map_block_stream.desired_blocks[other_block] = true
	world.map_block_stream._activate_block(other_block, changed)
	await process_frame
	await process_frame
	if world.get_node_or_null("OSMMap/Building_2") == null:
		_fail("A conflict in another loaded block did not restore original buildings.")
		return
	world.map_block_stream._reconcile({world.map_block_stream.base_block: true})
	await process_frame
	await process_frame
	if world.get_node_or_null("OSMMap/Building_2") != null:
		_fail("Unloading a conflicting block did not restore the merge.")
		return
	var path: String = world.building_edits.path
	world.free()
	var reloaded: Node3D = MainScene.instantiate()
	if not OSMMap.populate(reloaded, place):
		_fail("Original test map could not be rebuilt.")
		return
	root.add_child(reloaded)
	if reloaded.get_node_or_null("OSMMap/Building_1") == null or reloaded.get_node_or_null("OSMMap/Building_2") != null:
		_fail("Saved merge was not reapplied when the map was reopened.")
		return
	if absf(float(reloaded.get_node("OSMMap/Building_1").get_meta("measurement_height")) - 15.6) > 0.01 or not _has_floors(reloaded.get_node("OSMMap/Building_1"), 4, 1.3) or not reloaded.get_node("OSMMap/Building_1").has_node("FloorPreview_2") or not reloaded.get_node("OSMMap/Building_1").has_node("FloorPreview_4") or not reloaded.get_node("OSMMap/Building_1").has_node("InteriorWall_2_2"):
		_fail("Level override was not restored after reopening the map.")
		return
	var restored_floor: Dictionary = reloaded.building_edits.merges[0].hollow_floors[0]
	if not restored_floor.has("outline") or not is_equal_approx(float(restored_floor.wall_thickness), 0.4) or not is_equal_approx(float(restored_floor.walls[0].thickness), 0.6) or restored_floor.walls[0].has("cuts"):
		_fail("Edited wall position or thickness was not restored after reopening the map.")
		return
	reloaded.set_process(false)
	reloaded.map_block_stream.set_process(false)
	reloaded.player.uses_local_input = false
	reloaded.car.global_position = Vector3(-100, 0.5, -100)
	reloaded.player.global_position = Vector3(-0.4, 0.9, -6.5)
	reloaded.player.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame
	if not await _can_leave_wall(reloaded.player):
		_fail("Player could not slide and move away from the restored merged building.")
		return
	reloaded.map_block_stream.desired_blocks[other_block] = true
	reloaded.map_block_stream._activate_block(other_block, place)
	var neighbor_map: Node3D = reloaded.map_block_stream.loaded_blocks[other_block].node
	var neighbor: StaticBody3D = neighbor_map.get_node("Building_1")
	var reloaded_editor: Control = reloaded.get_node("HUD/BuildingEditor")
	reloaded_editor.active = true
	reloaded_editor.selected.append(neighbor)
	neighbor.tree_exiting.connect(reloaded_editor._clear_selection)
	reloaded_editor._update_selection()
	reloaded_editor.floor_number.value = 1
	reloaded_editor.hollow_button.pressed.emit()
	await process_frame
	await process_frame
	var rebuilt_neighbor: StaticBody3D = reloaded.map_block_stream.loaded_blocks[other_block].node.get_node("Building_1")
	if reloaded_editor.selected.size() != 1 or reloaded_editor.selected[0] != rebuilt_neighbor or not rebuilt_neighbor.get_node("FloorPreview_1").visible:
		_fail("A hollowed floor in a streamed block lost its selection or preview.")
		return
	var before_reset := JSON.stringify(reloaded.building_edits.data())
	reloaded_editor.reset_floor_button.pressed.emit()
	if not reloaded_editor.reset_confirmation.visible:
		_fail("Resetting a floor did not request confirmation.")
		return
	reloaded_editor.reset_confirmation.canceled.emit()
	if reloaded_editor.reset_confirmation.visible or JSON.stringify(reloaded.building_edits.data()) != before_reset:
		_fail("Cancelling a floor reset changed saved edits.")
		return
	reloaded_editor.reset_floor_button.pressed.emit()
	reloaded_editor.floor_number.value = 2
	reloaded_editor.reset_confirmation.confirmed.emit()
	if JSON.stringify(reloaded.building_edits.data()) != before_reset or not reloaded_editor.message.text.contains("Auswahl hat sich geändert"):
		_fail("A floor reset affected a different selection after confirmation.")
		return
	reloaded_editor.floor_number.value = 1
	reloaded_editor.reset_floor_button.pressed.emit()
	var block_entry: Dictionary = reloaded.map_block_stream.loaded_blocks[other_block]
	var original_block: Node3D = block_entry.node
	block_entry.node = reloaded.get_node("OSMMap")
	reloaded_editor.reset_confirmation.confirmed.emit()
	block_entry.node = original_block
	if JSON.stringify(reloaded.building_edits.data()) != before_reset or not reloaded_editor.message.text.contains("Auswahl hat sich geändert"):
		_fail("A floor reset accepted a selection from a replaced block.")
		return
	reloaded_editor.reset_floor_button.pressed.emit()
	reloaded_editor.reset_confirmation.confirmed.emit()
	await process_frame
	await process_frame
	rebuilt_neighbor = reloaded.map_block_stream.loaded_blocks[other_block].node.get_node("Building_1")
	if reloaded_editor.message.text != reloaded.BUILDING_RESET_FLOOR_SUCCESS or reloaded_editor.selected.size() != 1 or reloaded_editor.selected[0] != rebuilt_neighbor or reloaded_editor.floor_number.value != 1 or rebuilt_neighbor.has_node("FloorPreview_1") or not rebuilt_neighbor.get_node("Segment_1").visible or not rebuilt_neighbor.has_node("FloorPreview_2") or not rebuilt_neighbor.has_node("FloorPreview_4") or reloaded_editor.reset_floor_button.disabled == false:
		_fail("Floor reset did not restore a solid floor while preserving other floors and the selection.")
		return
	before_reset = JSON.stringify(reloaded.building_edits.data())
	reloaded_editor.reset_building_button.pressed.emit()
	if not reloaded_editor.reset_confirmation.visible or not reloaded_editor.reset_confirmation.dialog_text.contains("Zusammengefasste Gebäude"):
		_fail("Building reset did not explain and request confirmation.")
		return
	reloaded_editor.reset_confirmation.canceled.emit()
	if JSON.stringify(reloaded.building_edits.data()) != before_reset:
		_fail("Cancelling building reset changed saved edits.")
		return
	reloaded_editor.reset_building_button.pressed.emit()
	reloaded_editor.reset_confirmation.confirmed.emit()
	await process_frame
	await process_frame
	var original_a: StaticBody3D = reloaded.get_node_or_null("OSMMap/Building_1")
	var original_b: StaticBody3D = reloaded.get_node_or_null("OSMMap/Building_2")
	if reloaded_editor.message.text != reloaded.BUILDING_RESET_SUCCESS or original_a == null or original_b == null or original_a.get_meta("measurement_way") != a or original_b.get_meta("measurement_way") != b or not reloaded.building_edits.merges.is_empty():
		_fail("Building reset did not restore the original OSM buildings.")
		return
	var reset_reloaded := BuildingEditor.BuildingEdits.new()
	reset_reloaded.path = reloaded.building_edits.path
	if not reset_reloaded.load_file() or not reset_reloaded.merges.is_empty():
		_fail("Building reset did not survive reloading.")
		return
	reloaded_editor.close_editor()
	reloaded.free()
	var config_path: String = directory.path_join("config/building_editor.json")
	if DirAccess.remove_absolute(config_path) != OK or DirAccess.remove_absolute(config_path.get_base_dir()) != OK or DirAccess.remove_absolute(path) != OK or DirAccess.remove_absolute(path.get_base_dir()) != OK or DirAccess.remove_absolute(directory) != OK:
		_fail("Could not clean up editor test files.")
		return
	print("Building editor input, saved merge and measurement passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
