extends Control

const OSMMap = preload("res://scripts/osm_map.gd")
const BuildingEdits = preload("res://scripts/building_edits.gd")
const BuildingWalls = preload("res://scripts/building_walls.gd")

@onready var world: Node3D = get_parent().get_parent()
@onready var camera: Camera3D = world.get_node("Camera3D")
@onready var measurement: Control = world.get_node("HUD/BuildingMeasurement")
@onready var panel: PanelContainer = $Panel
@onready var selection_label: Label = $Panel/Layout/Selection
@onready var merge_button: Button = $Panel/Layout/Merge
@onready var levels_input: LineEdit = $Panel/Layout/Levels/Input
@onready var levels_button: Button = $Panel/Layout/Levels/Apply
@onready var floor_number: SpinBox = $Panel/Layout/Floor/Number
@onready var hollow_button: Button = $Panel/Layout/Floor/Hollow
@onready var wall_button: Button = $Panel/Layout/Wall
@onready var message: Label = $Panel/Layout/Message
@onready var wall_properties: PanelContainer = $WallProperties
@onready var wall_thickness_input: LineEdit = $WallProperties/Layout/Thickness/Input
@onready var wall_apply: Button = $WallProperties/Layout/Thickness/Apply
@onready var wall_close: Button = $WallProperties/Layout/Close

var active := false
var selected: Array[StaticBody3D] = []
var pending_click := false
var click_position := Vector2.ZERO
var wall_mode := false
var wall_thickness := 0.0
var wall_preview := {}
var wall_screen_position := Vector2.ZERO
var wall_camera_transform := Transform3D.IDENTITY
var wall_camera_size := 0.0
var selected_wall := -1
var selected_wall_outside := false
var dragging_wall := false
var drag_start := Vector2.ZERO
var drag_axis := Vector2.ZERO
var drag_distance := 0.0
var drag_result := {}


func _ready() -> void:
	merge_button.pressed.connect(_merge)
	levels_button.pressed.connect(_apply_levels)
	floor_number.value_changed.connect(_floor_changed)
	hollow_button.pressed.connect(_hollow_floor)
	wall_button.pressed.connect(_toggle_wall_mode)
	wall_apply.pressed.connect(_apply_wall_thickness)
	wall_close.pressed.connect(_clear_wall_selection)


func _input(event: InputEvent) -> void:
	if not measurement._can_interact():
		return
	if active and dragging_wall and event is InputEventMouseMotion:
		_update_wall_drag(event.position)
		get_viewport().set_input_as_handled()
		return
	if active and dragging_wall and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish_wall_drag(event.position)
		get_viewport().set_input_as_handled()
		return
	if active and wall_mode and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_cancel_wall_mode()
		message.text = "Wandmodus beendet."
		return
	if active and selected_wall >= 0 and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_clear_wall_selection()
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and (event.keycode == KEY_F5 or event.physical_keycode == KEY_F5):
		get_viewport().set_input_as_handled()
		if world.call("_is_network_game") and not multiplayer.is_server():
			world.status.text = "Nur der Server-Host kann Gebäude bearbeiten."
			return
		if world.building_edits.load_failed:
			world.status.text = world.building_edits.error
			return
		if active:
			close_editor()
		else:
			measurement.active = false
			measurement._clear_selection()
			active = true
			message.text = ""
		return


func _unhandled_input(event: InputEvent) -> void:
	if not measurement._can_interact():
		return
	if active and wall_mode and event is InputEventMouseMotion:
		_update_wall_cursor(event.position)
		return
	if active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if wall_mode:
			_place_wall(event.position)
			get_viewport().set_input_as_handled()
			return
		if _select_wall(event.position):
			get_viewport().set_input_as_handled()
			return
		_clear_wall_selection()
		click_position = event.position
		pending_click = true
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not pending_click:
		return
	pending_click = false
	if not active or not measurement._can_interact():
		return
	var origin := camera.project_ray_origin(click_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(click_position) * camera.far, OSMMap.BUILDING_PICK_LAYER)
	query.hit_back_faces = true
	query.hit_from_inside = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var building := hit.get("collider") as StaticBody3D
	if building == null or not building.has_meta("measurement_way"):
		return
	var id := int(building.get_meta("measurement_osm_id"))
	for existing in selected:
		if int(existing.get_meta("measurement_osm_id")) == id:
			_restore_preview()
			selected.erase(existing)
			existing.tree_exiting.disconnect(_clear_selection)
			_update_selection()
			return
	_restore_preview()
	selected.append(building)
	building.tree_exiting.connect(_clear_selection)
	_update_selection()


func _process(_delta: float) -> void:
	panel.visible = active and measurement._can_interact()
	wall_properties.visible = active and selected_wall >= 0 and measurement._can_interact()
	if active:
		if wall_mode and (camera.global_transform != wall_camera_transform or camera.size != wall_camera_size):
			_update_wall_cursor(wall_screen_position)
		queue_redraw()


func close_editor() -> void:
	active = false
	pending_click = false
	levels_input.release_focus()
	floor_number.get_line_edit().release_focus()
	_clear_selection()
	queue_redraw()


func _clear_selection() -> void:
	_cancel_wall_mode()
	_clear_wall_selection()
	_restore_preview()
	for building in selected:
		if is_instance_valid(building) and building.tree_exiting.is_connected(_clear_selection):
			building.tree_exiting.disconnect(_clear_selection)
	selected.clear()
	_update_selection()


func _update_selection() -> void:
	selection_label.text = "%d Gebäude ausgewählt." % selected.size()
	merge_button.disabled = selected.size() < 2
	levels_input.editable = selected.size() == 1
	levels_button.disabled = selected.size() != 1
	levels_input.text = ""
	floor_number.editable = false
	hollow_button.disabled = true
	wall_button.disabled = true
	if selected.size() == 1 and is_instance_valid(selected[0]):
		var way: Dictionary = selected[0].get_meta("measurement_way")
		var levels := str(way.tags.get("building:levels", "")).strip_edges()
		if levels.is_valid_int() and levels.to_int() >= 1 and levels.to_int() <= 1000:
			levels_input.text = levels
		var count := OSMMap._floor_count(way.tags)
		if count > 0:
			floor_number.max_value = count
			floor_number.set_value_no_signal(clampf(floor_number.value, 1, count))
			floor_number.editable = true
			_update_floor_preview()
	queue_redraw()


func _restore_preview() -> void:
	for building in selected:
		if not is_instance_valid(building):
			continue
		for child in building.get_children():
			if child is MeshInstance3D and (child.name.begins_with("Segment_") or child.name.begins_with("InteriorWall_")):
				child.visible = true
			elif child is MeshInstance3D and child.name.begins_with("FloorPreview_"):
				child.visible = false


func _floor_changed(_value: float) -> void:
	_cancel_wall_mode()
	_clear_wall_selection()
	_update_floor_preview()
	queue_redraw()


func _update_floor_preview() -> void:
	_restore_preview()
	hollow_button.disabled = true
	wall_button.disabled = true
	if selected.size() != 1 or not is_instance_valid(selected[0]) or not floor_number.editable:
		return
	var building := selected[0]
	var floor_index := int(floor_number.value)
	var way: Dictionary = building.get_meta("measurement_way")
	var hollow := false
	for edit in way.get("_hollow_floors", []):
		hollow = hollow or int(edit.floor) == floor_index
	hollow_button.disabled = hollow
	wall_button.disabled = not hollow
	for child in building.get_children():
		if child is MeshInstance3D and child.name.begins_with("Segment_"):
			var number := int(child.get_meta("floor_number", 0))
			child.visible = number <= floor_index and not (number == floor_index and hollow)
		elif child is MeshInstance3D and child.name.begins_with("FloorPreview_"):
			child.visible = child.name == "FloorPreview_%d" % floor_index
		elif child is MeshInstance3D and child.name.begins_with("InteriorWall_"):
			child.visible = int(child.get_meta("floor_number", 0)) <= floor_index


func _merge() -> void:
	var ways := []
	for building in selected:
		if not is_instance_valid(building) or not building.is_inside_tree():
			_clear_selection()
			message.text = "Ein Gebäude ist nicht mehr geladen. Bitte erneut auswählen."
			return
		ways.append(building.get_meta("measurement_way"))
	message.text = world.call("_commit_building_merge", ways)


func _apply_levels() -> void:
	if selected.size() != 1 or not is_instance_valid(selected[0]) or not selected[0].is_inside_tree():
		message.text = "Bitte genau ein geladenes Gebäude auswählen."
		return
	var value := levels_input.text.strip_edges()
	if not value.is_valid_int() or value.to_int() < 1 or value.to_int() > 1000:
		message.text = "Bitte eine ganze Etagenzahl von 1 bis 1000 eingeben."
		return
	message.text = world.call("_commit_building_levels", selected[0].get_meta("measurement_way"), value.to_int())


func _hollow_floor() -> void:
	if selected.size() != 1 or not is_instance_valid(selected[0]) or not selected[0].is_inside_tree() or not floor_number.editable:
		message.text = "Bitte genau ein Gebäude und eine Etage auswählen."
		return
	var building := selected[0]
	var id := int(building.get_meta("measurement_osm_id"))
	var chosen_floor := int(floor_number.value)
	var block_key: Variant = _selected_block_key(building)
	var result: String = world.call("_commit_building_hollow", building.get_meta("measurement_way"), chosen_floor)
	message.text = result
	if result == world.BUILDING_HOLLOW_SUCCESS:
		_restore_building_selection(block_key, id, chosen_floor)


func _selected_block_key(building: StaticBody3D) -> Variant:
	var block_key: Variant = null
	for key in world.map_block_stream.loaded_blocks:
		if world.map_block_stream.loaded_blocks[key].node == building.get_parent():
			block_key = key
			break
	return block_key


func _restore_building_selection(block_key: Variant, id: int, chosen_floor: int) -> bool:
	if block_key == null or not world.map_block_stream.loaded_blocks.has(block_key):
		return false
	_clear_selection()
	var map: Node3D = world.map_block_stream.loaded_blocks[block_key].node
	var replacement := map.get_node_or_null("Building_%d" % id) as StaticBody3D
	if replacement == null:
		return false
	selected.append(replacement)
	replacement.tree_exiting.connect(_clear_selection)
	floor_number.set_value_no_signal(chosen_floor)
	_update_selection()
	return true


func _toggle_wall_mode() -> void:
	if wall_mode:
		_cancel_wall_mode()
		message.text = "Wandmodus beendet."
		return
	if selected.size() != 1 or not is_instance_valid(selected[0]) or wall_button.disabled:
		message.text = "Bitte eine ausgehöhlte Etage auswählen."
		return
	var settings := BuildingEdits.load_wall_thickness()
	if settings.has("error"):
		message.text = settings.error
		return
	_clear_wall_selection()
	wall_thickness = settings.thickness
	wall_mode = true
	wall_button.text = "Wandmodus beenden"
	message.text = "Maus zur Raumwand bewegen, klicken zum Platzieren; Esc beendet den Wandmodus."
	_update_wall_cursor(get_viewport().get_mouse_position())


func _cancel_wall_mode() -> void:
	wall_mode = false
	wall_preview.clear()
	if is_instance_valid(wall_button):
		wall_button.text = "Wand hinzufügen"
	queue_redraw()


func _clear_wall_selection() -> void:
	selected_wall = -1
	dragging_wall = false
	drag_result.clear()
	if is_instance_valid(wall_thickness_input):
		wall_thickness_input.release_focus()
	queue_redraw()


func _floor_cursor(screen_position: Vector2, building: StaticBody3D, preview: MeshInstance3D) -> Variant:
	var scale_factor: float = building.get_meta("measurement_scale")
	var height := floor_number.value * OSMMap.LEVEL_HEIGHT * scale_factor
	var plane := Plane(Vector3.UP, building.to_global(Vector3(0, height, 0)).y)
	var position: Variant = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if position == null:
		return null
	var local := building.to_local(position)
	return Vector2(local.x, local.z) / scale_factor - preview.get_meta("wall_origin")


func _selected_floor_edit() -> Dictionary:
	if selected.size() != 1 or not is_instance_valid(selected[0]):
		return {}
	var way: Dictionary = selected[0].get_meta("measurement_way")
	for edit in way.get("_hollow_floors", []):
		if int(edit.floor) == int(floor_number.value):
			return edit
	return {}


func _select_wall(screen_position: Vector2) -> bool:
	if selected.size() != 1 or not is_instance_valid(selected[0]) or not floor_number.editable:
		return false
	var building := selected[0]
	var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
	if preview == null or not preview.has_meta("wall_polygons"):
		return false
	var cursor: Variant = _floor_cursor(screen_position, building, preview)
	if cursor == null:
		return false
	var floor_edit := _selected_floor_edit()
	if floor_edit.is_empty():
		return false
	var polygons: Array = preview.get_meta("wall_polygons")
	var wall := -1
	var outside := false
	for index in polygons.size():
		if Geometry2D.is_point_in_polygon(cursor, polygons[index]):
			wall = index
			break
	var outline: PackedVector2Array = preview.get_meta("local_outline")
	var interior := OSMMap._building_interior(outline, float(floor_edit.wall_thickness))
	if wall < 0 and Geometry2D.is_point_in_polygon(cursor, outline) and not Geometry2D.is_point_in_polygon(cursor, interior):
		var closest := INF
		for index in outline.size():
			var point := Geometry2D.get_closest_point_to_segment(cursor, outline[index], outline[(index + 1) % outline.size()])
			var distance: float = cursor.distance_squared_to(point)
			if distance < closest:
				closest = distance
				wall = index
		outside = wall >= 0
	if wall < 0:
		return false
	selected_wall = wall
	selected_wall_outside = outside
	dragging_wall = true
	drag_start = cursor
	drag_distance = 0.0
	drag_result.clear()
	if outside:
		var tangent := (outline[(wall + 1) % outline.size()] - outline[wall]).normalized()
		drag_axis = Vector2(-tangent.y, tangent.x)
		wall_thickness_input.text = str(float(floor_edit.wall_thickness) * 100.0)
	else:
		var plans: Array = preview.get_meta("wall_plans")
		drag_axis = (plans[wall].source[1] - plans[wall].source[0]).normalized()
		wall_thickness_input.text = str(float(floor_edit.walls[wall].thickness) * 100.0)
	wall_properties.show()
	queue_redraw()
	return true


func _update_wall_drag(screen_position: Vector2) -> void:
	if not dragging_wall or selected.size() != 1 or not is_instance_valid(selected[0]):
		return
	var building := selected[0]
	var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
	if preview == null:
		return
	var cursor: Variant = _floor_cursor(screen_position, building, preview)
	if cursor == null:
		return
	drag_distance = (cursor - drag_start).dot(drag_axis)
	var floor_edit := _selected_floor_edit()
	var thickness: float = floor_edit.wall_thickness if selected_wall_outside else floor_edit.walls[selected_wall].thickness
	drag_result = world.building_edits.prepare_wall_change(building.get_meta("measurement_way"), int(floor_number.value), selected_wall_outside, selected_wall, drag_distance, thickness)
	if drag_result.has("error"):
		message.text = drag_result.error
	queue_redraw()


func _finish_wall_drag(screen_position: Vector2) -> void:
	_update_wall_drag(screen_position)
	dragging_wall = false
	if absf(drag_distance) < 0.01 or drag_result.is_empty() or drag_result.has("error"):
		drag_result.clear()
		queue_redraw()
		return
	var floor_edit := _selected_floor_edit()
	var thickness: float = floor_edit.wall_thickness if selected_wall_outside else floor_edit.walls[selected_wall].thickness
	_commit_wall_change(drag_distance, thickness)


func _apply_wall_thickness() -> void:
	var value := wall_thickness_input.text.strip_edges()
	if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float() <= 0.0 or value.to_float() > 100000.0:
		message.text = "Bitte eine gültige Wanddicke in Zentimetern eingeben."
		return
	_commit_wall_change(0.0, value.to_float() / 100.0)


func _commit_wall_change(distance: float, thickness: float) -> void:
	if selected_wall < 0 or selected.size() != 1 or not is_instance_valid(selected[0]):
		_clear_wall_selection()
		message.text = "Bitte eine geladene Wand auswählen."
		return
	var building := selected[0]
	var id := int(building.get_meta("measurement_osm_id"))
	var chosen_floor := int(floor_number.value)
	var block_key: Variant = _selected_block_key(building)
	var wall := selected_wall
	var outside := selected_wall_outside
	var result: String = world.call("_commit_building_wall_change", building.get_meta("measurement_way"), chosen_floor, outside, wall, distance, thickness)
	message.text = result
	drag_result.clear()
	if result == world.BUILDING_WALL_CHANGE_SUCCESS and _restore_building_selection(block_key, id, chosen_floor):
		selected_wall = wall
		selected_wall_outside = outside
		wall_thickness_input.text = str(thickness * 100.0)
		wall_properties.show()
	queue_redraw()


func _update_wall_cursor(screen_position: Vector2) -> void:
	wall_screen_position = screen_position
	wall_camera_transform = camera.global_transform
	wall_camera_size = camera.size
	wall_preview.clear()
	if not wall_mode or selected.size() != 1 or not is_instance_valid(selected[0]):
		return
	var building := selected[0]
	var floor_preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
	if floor_preview == null or not floor_preview.has_meta("wall_regions"):
		return
	var scale_factor: float = building.get_meta("measurement_scale")
	var height := floor_number.value * OSMMap.LEVEL_HEIGHT * scale_factor
	var plane := Plane(Vector3.UP, building.to_global(Vector3(0, height, 0)).y)
	var position: Variant = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if position == null:
		return
	var local := building.to_local(position)
	var offset: Vector2 = floor_preview.get_meta("wall_origin")
	var cursor := Vector2(local.x, local.z) / scale_factor - offset
	var regions: Array[PackedVector2Array] = floor_preview.get_meta("wall_regions")
	wall_preview = BuildingWalls.plan_wall(regions, cursor, wall_thickness)
	wall_preview["cursor"] = cursor
	queue_redraw()


func _place_wall(screen_position: Vector2) -> void:
	_update_wall_cursor(screen_position)
	if wall_preview.is_empty() or wall_preview.has("error"):
		message.text = wall_preview.get("error", "An dieser Position ist keine Wand möglich.")
		return
	if selected.size() != 1 or not is_instance_valid(selected[0]):
		_cancel_wall_mode()
		message.text = "Das Gebäude ist nicht mehr geladen."
		return
	var building := selected[0]
	var id := int(building.get_meta("measurement_osm_id"))
	var chosen_floor := int(floor_number.value)
	var block_key: Variant = _selected_block_key(building)
	var cursor: Vector2 = wall_preview.cursor
	var result: String = world.call("_commit_building_wall", building.get_meta("measurement_way"), chosen_floor, cursor, wall_thickness)
	message.text = result
	if result == world.BUILDING_WALL_SUCCESS and _restore_building_selection(block_key, id, chosen_floor):
		wall_mode = true
		wall_button.text = "Wandmodus beenden"
		_update_wall_cursor(screen_position)


func _drag_floor_edit(building: StaticBody3D) -> Dictionary:
	if not drag_result.has("data"):
		return {}
	var id := int(building.get_meta("measurement_osm_id"))
	for merge in drag_result.data.merges:
		if int(merge.result.id) == id:
			for edit in merge.get("hollow_floors", []):
				if int(edit.floor) == int(floor_number.value):
					return edit
	for entry in drag_result.data.level_edits:
		if int(entry.source.id) == id:
			for edit in entry.get("hollow_floors", []):
				if int(edit.floor) == int(floor_number.value):
					return edit
	return {}


func _draw() -> void:
	if not active or not measurement._can_interact():
		return
	for building in selected:
		if not is_instance_valid(building) or not building.is_inside_tree():
			continue
		var points: PackedVector2Array = building.get_meta("measurement_points")
		var factor: float = building.get_meta("measurement_scale")
		var height: float = building.get_meta("measurement_height")
		if selected.size() == 1 and floor_number.editable:
			height = float(floor_number.value) * OSMMap.LEVEL_HEIGHT * factor
			var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
			if preview != null:
				var inner: PackedVector2Array = preview.get_meta("interior_points")
				points = preview.get_meta("outer_points", points)
				var offset: Vector2 = preview.get_meta("wall_origin", Vector2.ZERO)
				var polygons: Array = preview.get_meta("wall_polygons", [])
				var drag_edit := _drag_floor_edit(building) if dragging_wall else {}
				if not drag_edit.is_empty():
					var way: Dictionary = building.get_meta("measurement_way")
					var original := OSMMap._building_points(way, way.geometry[0])
					var footprint := BuildingWalls.floor_outline(original, drag_edit)
					if not footprint.has("error"):
						var drag_inner := OSMMap._building_interior(footprint.outline, float(drag_edit.wall_thickness))
						var drag_walls := BuildingWalls.build(drag_inner, drag_edit.get("walls", []))
						if not drag_walls.has("error"):
							points = PackedVector2Array()
							inner = PackedVector2Array()
							for point in footprint.outline:
								points.append(point + offset)
							for point in drag_inner:
								inner.append(point + offset)
							polygons = drag_walls.walls
				var outer_screen := PackedVector2Array()
				var inner_screen := PackedVector2Array()
				var visible := true
				for point in points:
					var world_point := building.to_global(Vector3(point.x * factor, height + 0.02, point.y * factor))
					if camera.is_position_behind(world_point):
						visible = false
						break
					outer_screen.append(camera.unproject_position(world_point))
				if visible:
					for point in inner:
						inner_screen.append(camera.unproject_position(building.to_global(Vector3(point.x * factor, height + 0.02, point.y * factor))))
				if visible and inner_screen.size() >= 3:
					draw_colored_polygon(outer_screen, Color(0.31, 0.24, 0.17))
					draw_colored_polygon(inner_screen, Color(0.78, 0.74, 0.66))
					for index in polygons.size():
						var polygon: PackedVector2Array = polygons[index]
						var wall_screen := _screen_polygon(building, polygon, offset, factor, height)
						if wall_screen.size() >= 3:
							draw_colored_polygon(wall_screen, Color.YELLOW if not selected_wall_outside and selected_wall == index else Color(0.31, 0.24, 0.17))
					if selected_wall_outside and selected_wall >= 0 and selected_wall < points.size():
						draw_line(outer_screen[selected_wall], outer_screen[(selected_wall + 1) % points.size()], Color.YELLOW, 5.0)
					if wall_mode and not wall_preview.is_empty() and not wall_preview.has("error"):
						var candidate := _screen_polygon(building, wall_preview.polygon, offset, factor, height)
						if candidate.size() >= 3:
							draw_colored_polygon(candidate, Color(1.0, 0.8, 0.1, 0.8))
						var source := _screen_polygon(building, PackedVector2Array(wall_preview.source), offset, factor, height)
						if source.size() == 2:
							draw_line(source[0], source[1], Color.YELLOW, 3.0)
		for index in points.size():
			var a := points[index] * factor
			var b := points[(index + 1) % points.size()] * factor
			var start := building.to_global(Vector3(a.x, height + 0.05, a.y))
			var end := building.to_global(Vector3(b.x, height + 0.05, b.y))
			if not camera.is_position_behind(start) and not camera.is_position_behind(end):
				draw_line(camera.unproject_position(start), camera.unproject_position(end), Color.CYAN, 3.0)


func _screen_polygon(building: StaticBody3D, points: PackedVector2Array, offset: Vector2, factor: float, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		var position := (point + offset) * factor
		var world_point := building.to_global(Vector3(position.x, height + 0.03, position.y))
		if camera.is_position_behind(world_point):
			return PackedVector2Array()
		result.append(camera.unproject_position(world_point))
	return result
