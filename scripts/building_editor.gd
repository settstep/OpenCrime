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
@onready var dimensions_panel: PanelContainer = $DimensionsPanel
@onready var wall_dimensions: Label = $DimensionsPanel/Layout/Scroll/Dimensions
@onready var wall_thickness_input: LineEdit = $WallProperties/Layout/Thickness/Input
@onready var wall_apply: Button = $WallProperties/Layout/Thickness/Apply
@onready var wall_split: Button = $WallProperties/Layout/Split
@onready var wall_merge: Button = $WallProperties/Layout/MergeWalls
@onready var wall_split_confirm: Button = $WallProperties/Layout/ConfirmSplit
@onready var wall_split_cancel: Button = $WallProperties/Layout/CancelSplit
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
var selected_segment := -1
var secondary_wall := {}
var split_preview := {}
var dragging_wall := false
var drag_start := Vector2.ZERO
var drag_axis := Vector2.ZERO
var drag_distance := 0.0
var drag_result := {}
var dimensions := {}


func _ready() -> void:
	merge_button.pressed.connect(_merge)
	levels_button.pressed.connect(_apply_levels)
	floor_number.value_changed.connect(_floor_changed)
	hollow_button.pressed.connect(_hollow_floor)
	wall_button.pressed.connect(_toggle_wall_mode)
	wall_apply.pressed.connect(_apply_wall_thickness)
	wall_split.pressed.connect(_preview_wall_split)
	wall_merge.pressed.connect(_merge_walls)
	wall_split_confirm.pressed.connect(_confirm_wall_split)
	wall_split_cancel.pressed.connect(_cancel_wall_split)
	wall_close.pressed.connect(_clear_wall_selection)


func _input(event: InputEvent) -> void:
	if not measurement._can_interact():
		return
	if active and not split_preview.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
			_cancel_wall_split()
			message.text = "Wandteilung abgebrochen."
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_wall_split()
			message.text = "Wandteilung abgebrochen."
			get_viewport().set_input_as_handled()
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
		if not split_preview.is_empty():
			get_viewport().set_input_as_handled()
			return
		if wall_mode:
			_place_wall(event.position)
			get_viewport().set_input_as_handled()
			return
		if _select_wall(event.position, event.shift_pressed):
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
	dimensions_panel.visible = wall_properties.visible
	if active:
		if wall_mode and (camera.global_transform != wall_camera_transform or camera.size != wall_camera_size):
			_update_wall_cursor(wall_screen_position)
		if dimensions.is_empty():
			_update_dimensions()
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
	_cancel_wall_split()
	_clear_secondary_wall()
	selected_wall = -1
	selected_segment = -1
	dragging_wall = false
	drag_result.clear()
	dimensions.clear()
	if is_instance_valid(wall_dimensions):
		wall_dimensions.text = ""
	if is_instance_valid(wall_thickness_input):
		wall_thickness_input.release_focus()
	queue_redraw()


func _clear_secondary_wall() -> void:
	secondary_wall.clear()
	if is_instance_valid(wall_merge):
		wall_merge.hide()
		wall_apply.disabled = false
		wall_split.disabled = false
		wall_thickness_input.editable = true
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


func _select_wall(screen_position: Vector2, add_selection := false) -> bool:
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
	var piece := -1
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
	if outside:
		var edge_map: Array = preview.get_meta("outer_edges")
		var edge: Dictionary = edge_map[wall]
		if edge.connector:
			message.text = "Automatische Verbindungswände können derzeit nicht einzeln bearbeitet werden."
			return true
		wall = int(edge.edge)
		piece = int(edge.segment)
	else:
		var plans: Array = preview.get_meta("wall_plans")
		var segments: Array = plans[wall].segments
		if segments.size() > 1:
			var closest := INF
			for index in segments.size():
				var projected := Geometry2D.get_closest_point_to_segment(cursor, segments[index][0], segments[index][1])
				var distance: float = cursor.distance_squared_to(projected)
				if distance < closest:
					closest = distance
					piece = index
			var widths: Array = floor_edit.walls[wall].get("thicknesses", [])
			var width: float = float(widths[piece]) if not widths.is_empty() else float(floor_edit.walls[wall].thickness)
			if closest > pow(width * 0.5 + 0.02, 2):
				message.text = "Automatische Verbindungswände können derzeit nicht einzeln bearbeitet werden."
				return true
	if add_selection and selected_wall >= 0:
		if wall == selected_wall and outside == selected_wall_outside and piece == selected_segment:
			_clear_secondary_wall()
			message.text = "Bitte ein anderes Wandteilstück auswählen."
			return true
		secondary_wall = {"wall": wall, "outside": outside, "segment": piece}
		dragging_wall = false
		drag_result.clear()
		wall_merge.show()
		wall_apply.disabled = true
		wall_split.disabled = true
		wall_thickness_input.editable = false
		message.text = "Die erste Wand bestimmt Position und Dicke."
		queue_redraw()
		return true
	_clear_secondary_wall()
	selected_wall = wall
	selected_wall_outside = outside
	selected_segment = piece
	dimensions.clear()
	dragging_wall = true
	drag_start = cursor
	drag_distance = 0.0
	drag_result.clear()
	if outside:
		var base: PackedVector2Array = BuildingWalls.floor_outline(OSMMap._building_points(building.get_meta("measurement_way"), building.get_meta("measurement_way").geometry[0]), floor_edit).base
		var tangent := (base[(wall + 1) % base.size()] - base[wall]).normalized()
		drag_axis = Vector2(-tangent.y, tangent.x)
		wall_thickness_input.text = str(float(floor_edit.wall_thickness) * 100.0)
	else:
		var plans: Array = preview.get_meta("wall_plans")
		drag_axis = (plans[wall].source[1] - plans[wall].source[0]).normalized()
		var widths: Array = floor_edit.walls[wall].get("thicknesses", [])
		var width: float = float(widths[piece]) if piece >= 0 and not widths.is_empty() else float(floor_edit.walls[wall].thickness)
		wall_thickness_input.text = str(width * 100.0)
	wall_properties.show()
	queue_redraw()
	return true


func _merge_walls() -> void:
	if secondary_wall.is_empty() or selected_wall < 0 or selected.size() != 1 or not is_instance_valid(selected[0]):
		message.text = "Bitte zwei geladene Wandteilstücke auswählen."
		return
	if bool(secondary_wall.outside) != selected_wall_outside or int(secondary_wall.wall) != selected_wall:
		message.text = "Nur benachbarte Teilstücke derselben aufgeteilten Wand können verbunden werden."
		return
	var building := selected[0]
	var way: Dictionary = building.get_meta("measurement_way")
	var chosen_floor := int(floor_number.value)
	var prepared: Dictionary = world.building_edits.prepare_wall_merge(way, chosen_floor, selected_wall_outside, selected_wall, selected_segment, int(secondary_wall.segment))
	if prepared.has("error"):
		message.text = prepared.error
		return
	var id := int(building.get_meta("measurement_osm_id"))
	var block_key: Variant = _selected_block_key(building)
	var wall := selected_wall
	var outside := selected_wall_outside
	var result: String = world.call("_commit_building_wall_merge", way, chosen_floor, outside, wall, selected_segment, int(secondary_wall.segment))
	message.text = result
	if result == world.BUILDING_WALL_MERGE_SUCCESS and _restore_building_selection(block_key, id, chosen_floor):
		selected_wall = wall
		selected_wall_outside = outside
		selected_segment = int(prepared.segment)
		wall_thickness_input.text = str(_selected_wall_thickness(_selected_floor_edit()) * 100.0)
		wall_properties.show()
	queue_redraw()


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
	var thickness := _selected_wall_thickness(floor_edit)
	var previous_error: String = drag_result.get("error", "")
	drag_result = world.building_edits.prepare_wall_change(building.get_meta("measurement_way"), int(floor_number.value), selected_wall_outside, selected_wall, drag_distance, thickness, selected_segment)
	dimensions.clear()
	if drag_result.has("error"):
		message.text = drag_result.error
	elif not previous_error.is_empty() and message.text == previous_error:
		message.text = ""
	queue_redraw()


func _finish_wall_drag(screen_position: Vector2) -> void:
	_update_wall_drag(screen_position)
	dragging_wall = false
	if absf(drag_distance) < 0.01 or drag_result.is_empty() or drag_result.has("error"):
		drag_result.clear()
		queue_redraw()
		return
	var floor_edit := _selected_floor_edit()
	var thickness := _selected_wall_thickness(floor_edit)
	_commit_wall_change(drag_distance, thickness)


func _selected_wall_thickness(floor_edit: Dictionary) -> float:
	if selected_wall_outside:
		return float(floor_edit.wall_thickness)
	var wall: Dictionary = floor_edit.walls[selected_wall]
	var widths: Array = wall.get("thicknesses", [])
	if selected_segment >= 0 and not widths.is_empty():
		return float(widths[selected_segment])
	return float(wall.thickness)


func _preview_wall_split() -> void:
	if selected_wall < 0 or selected.size() != 1 or not is_instance_valid(selected[0]):
		message.text = "Bitte eine geladene Wand auswählen."
		return
	dragging_wall = false
	var building := selected[0]
	var result: Dictionary = world.building_edits.prepare_wall_split(building.get_meta("measurement_way"), int(floor_number.value), selected_wall_outside, selected_wall, selected_segment)
	if result.has("error"):
		message.text = result.error
		return
	split_preview = result
	wall_split.disabled = true
	wall_apply.disabled = true
	wall_thickness_input.editable = false
	wall_split_confirm.show()
	wall_split_cancel.show()
	message.text = "Wandteilung prüfen und bestätigen; Rechtsklick oder Esc bricht ab."
	queue_redraw()


func _cancel_wall_split() -> void:
	split_preview.clear()
	if is_instance_valid(wall_split):
		wall_split.disabled = false
		wall_apply.disabled = false
		wall_thickness_input.editable = true
		wall_split_confirm.hide()
		wall_split_cancel.hide()
	queue_redraw()


func _confirm_wall_split() -> void:
	if split_preview.is_empty() or selected_wall < 0 or selected.size() != 1 or not is_instance_valid(selected[0]):
		_cancel_wall_split()
		message.text = "Bitte eine geladene Wand auswählen."
		return
	var building := selected[0]
	var id := int(building.get_meta("measurement_osm_id"))
	var chosen_floor := int(floor_number.value)
	var block_key: Variant = _selected_block_key(building)
	var wall := selected_wall
	var outside := selected_wall_outside
	var piece := selected_segment
	var result: String = world.call("_commit_building_wall_split", building.get_meta("measurement_way"), chosen_floor, outside, wall, piece)
	message.text = result
	if result == world.BUILDING_WALL_SPLIT_SUCCESS and _restore_building_selection(block_key, id, chosen_floor):
		selected_wall = wall
		selected_wall_outside = outside
		selected_segment = maxi(piece, 0)
		wall_thickness_input.text = str(_selected_wall_thickness(_selected_floor_edit()) * 100.0)
		wall_properties.show()
	else:
		_cancel_wall_split()
	queue_redraw()


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
	var piece := selected_segment
	var result: String = world.call("_commit_building_wall_change", building.get_meta("measurement_way"), chosen_floor, outside, wall, distance, thickness, piece)
	message.text = result
	drag_result.clear()
	if result == world.BUILDING_WALL_CHANGE_SUCCESS and _restore_building_selection(block_key, id, chosen_floor):
		selected_wall = wall
		selected_wall_outside = outside
		selected_segment = piece
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


func _floor_geometry(building: StaticBody3D, preview: MeshInstance3D) -> Dictionary:
	var offset: Vector2 = preview.get_meta("wall_origin", Vector2.ZERO)
	var interior := PackedVector2Array()
	for point in preview.get_meta("interior_points", PackedVector2Array()):
		interior.append(point - offset)
	var geometry := {
		"outline": preview.get_meta("local_outline"),
		"interior": interior,
		"offset": offset,
		"polygons": preview.get_meta("wall_polygons", []),
		"plans": preview.get_meta("wall_plans", []),
		"regions": preview.get_meta("wall_regions", []),
		"edges": preview.get_meta("outer_edges", []),
		"edit": _selected_floor_edit(),
	}
	var drag_edit := _drag_floor_edit(building) if dragging_wall else {}
	if not drag_edit.is_empty():
		var way: Dictionary = building.get_meta("measurement_way")
		var original := OSMMap._building_points(way, way.geometry[0])
		var footprint := BuildingWalls.floor_outline(original, drag_edit)
		if not footprint.has("error"):
			var drag_inner := OSMMap._building_interior(footprint.outline, float(drag_edit.wall_thickness))
			var drag_walls := BuildingWalls.build(drag_inner, drag_edit.get("walls", []))
			if not drag_walls.has("error"):
				geometry.outline = footprint.outline
				geometry.interior = drag_inner
				geometry.polygons = drag_walls.walls
				geometry.plans = drag_walls.plans
				geometry.regions = drag_walls.regions
				geometry.edges = footprint.edges
				geometry.edit = drag_edit
	return geometry


static func _wall_line(a: Vector2, b: Vector2, radius: float, outside: bool, wall: int, piece: int, connector := false) -> Dictionary:
	return {"start": a, "end": b, "radius": radius, "outside": outside, "wall": wall, "piece": piece, "connector": connector}


static func _walls_touch(first: Dictionary, second: Dictionary) -> bool:
	var a: Vector2 = first.start
	var b: Vector2 = first.end
	var c: Vector2 = second.start
	var d: Vector2 = second.end
	var epsilon := BuildingWalls.EPSILON * 10.0
	if absf((b - a).normalized().cross((d - c).normalized())) < 0.001:
		return minf(minf(a.distance_to(c), a.distance_to(d)), minf(b.distance_to(c), b.distance_to(d))) <= epsilon
	for point in [c, d]:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= float(first.radius) + epsilon:
			return true
	for point in [a, b]:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, c, d)) <= float(second.radius) + epsilon:
			return true
	return false


static func _region_touches_wall(region: PackedVector2Array, wall: Dictionary) -> bool:
	var start: Vector2 = wall.start
	var end: Vector2 = wall.end
	var length := start.distance_to(end)
	var direction := (end - start).normalized()
	for index in region.size():
		var a := region[index]
		var b := region[(index + 1) % region.size()]
		if a.distance_to(b) <= BuildingWalls.EPSILON or absf((b - a).normalized().cross(direction)) > 0.001:
			continue
		if absf((a - start).cross(direction)) > float(wall.radius) + BuildingWalls.EPSILON * 10.0:
			continue
		var from := (a - start).dot(direction)
		var to := (b - start).dot(direction)
		if minf(length, maxf(from, to)) - maxf(0.0, minf(from, to)) > BuildingWalls.EPSILON * 10.0:
			return true
	return false


static func _wall_dimensions(geometry: Dictionary, outside: bool, wall_index: int, segment_index: int) -> Dictionary:
	var outline: PackedVector2Array = geometry.outline
	var edges: Array = geometry.edges
	var edit: Dictionary = geometry.edit
	var plans: Array = geometry.plans
	var lines := []
	for index in edges.size():
		var edge: Dictionary = edges[index]
		lines.append(_wall_line(outline[index], outline[(index + 1) % outline.size()], float(edit.wall_thickness), true, int(edge.edge), int(edge.segment), edge.connector))
	for index in plans.size():
		var segments: Array = plans[index].segments
		var wall: Dictionary = edit.walls[index]
		var widths: Array = wall.get("thicknesses", [])
		for part in segments.size():
			var width: float = float(widths[part]) if not widths.is_empty() else float(wall.thickness)
			if part > 0 and segments[part - 1][1].distance_to(segments[part][0]) > BuildingWalls.EPSILON:
				var previous_width: float = float(widths[part - 1]) if not widths.is_empty() else float(wall.thickness)
				lines.append(_wall_line(segments[part - 1][1], segments[part][0], maxf(width, previous_width) * 0.5, false, index, -1, true))
			lines.append(_wall_line(segments[part][0], segments[part][1], width * 0.5, false, index, part if segments.size() > 1 else -1))
	var selected_line := {}
	for line in lines:
		if not line.connector and line.outside == outside and int(line.wall) == wall_index and int(line.piece) == segment_index:
			selected_line = line
			break
	if selected_line.is_empty():
		return {"walls": [], "rooms": []}
	var walls := [selected_line]
	for line in lines:
		if not is_same(line, selected_line) and _walls_touch(selected_line, line):
			walls.append(line)
	var room_lines := []
	var room_number := 0
	for region in geometry.regions:
		if not _region_touches_wall(region, selected_line):
			continue
		room_number += 1
		for index in region.size():
			var a: Vector2 = region[index]
			var b: Vector2 = region[(index + 1) % region.size()]
			if a.distance_to(b) > BuildingWalls.EPSILON:
				room_lines.append({"start": a, "end": b, "room": room_number})
	return {"walls": walls, "rooms": room_lines}


func _update_dimensions() -> void:
	dimensions.clear()
	if selected_wall < 0 or selected.size() != 1 or not is_instance_valid(selected[0]):
		wall_dimensions.text = ""
		return
	var building := selected[0]
	var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
	if preview == null or not preview.has_meta("wall_regions"):
		wall_dimensions.text = ""
		return
	var geometry := _floor_geometry(building, preview)
	dimensions = _wall_dimensions(geometry, selected_wall_outside, selected_wall, selected_segment)
	if dimensions.walls.is_empty():
		wall_dimensions.text = "Die ausgewählte Wand konnte nicht vermessen werden."
		return
	var factor: float = building.get_meta("measurement_scale")
	var text := PackedStringArray()
	for index in dimensions.walls.size():
		var line: Dictionary = dimensions.walls[index]
		var length: float = line.start.distance_to(line.end)
		var description := " (ausgewählt)" if index == 0 else ""
		text.append("W%d: %.2f m | %.2f SE%s" % [index + 1, length, length * factor, description])
	for index in dimensions.rooms.size():
		var line: Dictionary = dimensions.rooms[index]
		var length: float = line.start.distance_to(line.end)
		text.append("R%d: %.2f m | %.2f SE (Raum %d)" % [index + 1, length, length * factor, line.room])
	if dimensions.rooms.is_empty():
		text.append("Kein angrenzender Raum konnte vermessen werden.")
	var formatted := "\n".join(text)
	if wall_dimensions.text != formatted:
		wall_dimensions.text = formatted


static func _clip_selection_side(polygon: PackedVector2Array, origin: Vector2, direction: Vector2, inside: Vector2) -> PackedVector2Array:
	var clipped := PackedVector2Array()
	var sign := signf(direction.cross(inside - origin))
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var side_a := direction.cross(a - origin) * sign
		var side_b := direction.cross(b - origin) * sign
		if side_a >= 0.0:
			clipped.append(a)
		if (side_a < 0.0 and side_b > 0.0) or (side_a > 0.0 and side_b < 0.0):
			clipped.append(a.lerp(b, side_a / (side_a - side_b)))
	return clipped


static func _exterior_wall_selection(outline: PackedVector2Array, interior: PackedVector2Array, edge: int, thickness: float) -> Array[PackedVector2Array]:
	var start := outline[edge]
	var end := outline[(edge + 1) % outline.size()]
	var tangent := (end - start).normalized()
	var inward := tangent.orthogonal()
	if not Geometry2D.is_point_in_polygon((start + end) * 0.5 + inward * BuildingWalls.EPSILON * 10.0, outline):
		inward = -inward
	var previous := (start - outline[(edge + outline.size() - 1) % outline.size()]).normalized().orthogonal()
	var next := (outline[(edge + 2) % outline.size()] - end).normalized().orthogonal()
	# All edge normals must face the same side of the outline.
	if tangent.orthogonal().dot(inward) < 0.0:
		previous = -previous
		next = -next
	if (previous + inward).length() < 0.001:
		previous = inward
	if (next + inward).length() < 0.001:
		next = inward
	var reach := 0.0
	for point in outline:
		reach = maxf(reach, point.distance_to(start))
	reach += thickness + 1.0
	var strip := PackedVector2Array([
		start - tangent * reach, end + tangent * reach,
		end + tangent * reach + inward * thickness, start - tangent * reach + inward * thickness,
	])
	var midpoint := (start + end) * 0.5
	strip = _clip_selection_side(strip, start, (inward + previous).normalized(), midpoint)
	strip = _clip_selection_side(strip, end, (inward + next).normalized(), midpoint)
	var result: Array[PackedVector2Array] = []
	if strip.size() < 3:
		return result
	for section in Geometry2D.intersect_polygons(outline, strip):
		for wall in Geometry2D.clip_polygons(section, interior):
			if wall.size() >= 3:
				result.append(wall)
	return result


static func _interior_piece_selection(polygon: PackedVector2Array, segment: Array, thickness: float) -> Array[PackedVector2Array]:
	var direction: Vector2 = (segment[1] - segment[0]).normalized()
	var half_width := direction.orthogonal() * thickness * 0.5
	var strip := PackedVector2Array([
		segment[0] - half_width, segment[1] - half_width,
		segment[1] + half_width, segment[0] + half_width,
	])
	return Geometry2D.intersect_polygons(polygon, strip)


func _draw() -> void:
	if not active or not measurement._can_interact():
		return
	for building in selected:
		if not is_instance_valid(building) or not building.is_inside_tree():
			continue
		var points: PackedVector2Array = building.get_meta("measurement_points")
		var factor: float = building.get_meta("measurement_scale")
		var height: float = building.get_meta("measurement_height")
		var selection_edges: Array = []
		if selected.size() == 1 and floor_number.editable:
			height = float(floor_number.value) * OSMMap.LEVEL_HEIGHT * factor
			var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
			if preview != null:
				var geometry := _floor_geometry(building, preview)
				var offset: Vector2 = geometry.offset
				var inner := PackedVector2Array()
				points = PackedVector2Array()
				for point in geometry.outline:
					points.append(point + offset)
				for point in geometry.interior:
					inner.append(point + offset)
				var polygons: Array = geometry.polygons
				var plans: Array = geometry.plans
				var outer_edges: Array = geometry.edges
				selection_edges = outer_edges
				var floor_edit: Dictionary = geometry.edit
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
							var color := Color(0.31, 0.24, 0.17)
							if not selected_wall_outside and selected_wall == index and selected_segment < 0:
								color = Color.YELLOW
							elif not secondary_wall.is_empty() and not secondary_wall.outside and int(secondary_wall.wall) == index and int(secondary_wall.segment) < 0:
								color = Color.ORANGE
							draw_colored_polygon(wall_screen, color)
					var selections := [{"wall": selected_wall, "outside": selected_wall_outside, "segment": selected_segment, "color": Color.YELLOW}]
					if not secondary_wall.is_empty():
						var other := secondary_wall.duplicate()
						other["color"] = Color.ORANGE
						selections.append(other)
					for selection in selections:
						var wall_index: int = selection.wall
						var segment: int = selection.segment
						if not selection.outside and segment >= 0 and wall_index >= 0 and wall_index < plans.size() and segment < plans[wall_index].segments.size():
							var wall: Dictionary = floor_edit.walls[wall_index]
							var widths: Array = wall.get("thicknesses", [])
							var thickness: float = float(widths[segment]) if not widths.is_empty() else float(wall.thickness)
							for piece in _interior_piece_selection(polygons[wall_index], plans[wall_index].segments[segment], thickness):
								var selected_polygon := _screen_polygon(building, piece, offset, factor, height)
								if selected_polygon.size() >= 3:
									draw_colored_polygon(selected_polygon, selection.color)
						elif selection.outside and wall_index >= 0:
							for index in outer_edges.size():
								var edge: Dictionary = outer_edges[index]
								if not edge.connector and int(edge.edge) == wall_index and int(edge.segment) == segment:
									for piece in _exterior_wall_selection(points, inner, index, float(floor_edit.wall_thickness)):
										var selected_polygon := _screen_polygon(building, piece, Vector2.ZERO, factor, height)
										if selected_polygon.size() >= 3:
											draw_colored_polygon(selected_polygon, selection.color)
					if not split_preview.is_empty():
						var colors := [Color.CORNFLOWER_BLUE, Color.ORANGE, Color.LIME_GREEN, Color.MEDIUM_PURPLE]
						for index in split_preview.preview.size():
							var piece := _screen_polygon(building, PackedVector2Array(split_preview.preview[index]), offset, factor, height)
							if piece.size() == 2:
								draw_line(piece[0], piece[1], colors[index % colors.size()], 6.0)
					if wall_mode and not wall_preview.is_empty() and not wall_preview.has("error"):
						var candidate := _screen_polygon(building, wall_preview.polygon, offset, factor, height)
						if candidate.size() >= 3:
							draw_colored_polygon(candidate, Color(1.0, 0.8, 0.1, 0.8))
						var source := _screen_polygon(building, PackedVector2Array(wall_preview.source), offset, factor, height)
						if source.size() == 2:
							draw_line(source[0], source[1], Color.YELLOW, 3.0)
		for index in points.size():
			if index < selection_edges.size() and selected_wall_outside and selected_wall >= 0:
				var edge: Dictionary = selection_edges[index]
				if not edge.connector and int(edge.edge) == selected_wall and int(edge.segment) == selected_segment:
					continue
			if index < selection_edges.size() and not secondary_wall.is_empty() and secondary_wall.outside:
				var edge: Dictionary = selection_edges[index]
				if not edge.connector and int(edge.edge) == int(secondary_wall.wall) and int(edge.segment) == int(secondary_wall.segment):
					continue
			var a := points[index] * factor
			var b := points[(index + 1) % points.size()] * factor
			var start := building.to_global(Vector3(a.x, height + 0.05, a.y))
			var end := building.to_global(Vector3(b.x, height + 0.05, b.y))
			if not camera.is_position_behind(start) and not camera.is_position_behind(end):
				draw_line(camera.unproject_position(start), camera.unproject_position(end), Color.CYAN, 3.0)
		if selected.size() == 1 and not dimensions.is_empty() and selected_wall >= 0:
			var preview := building.get_node_or_null("FloorPreview_%d" % int(floor_number.value)) as MeshInstance3D
			if preview != null:
				var offset: Vector2 = preview.get_meta("wall_origin", Vector2.ZERO)
				_draw_dimensions(building, dimensions.get("walls", []), offset, factor, height, "W", Color.ORANGE)
				_draw_dimensions(building, dimensions.get("rooms", []), offset, factor, height, "R", Color.CYAN)


func _draw_dimensions(building: StaticBody3D, lines: Array, offset: Vector2, factor: float, height: float, prefix: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	for index in lines.size():
		var line: Dictionary = lines[index]
		var screen := _screen_polygon(building, PackedVector2Array([line.start, line.end]), offset, factor, height)
		if screen.size() != 2 or screen[0].distance_to(screen[1]) < 0.1:
			continue
		var normal := (screen[1] - screen[0]).normalized().orthogonal()
		draw_line(screen[0], screen[1], color, 2.0)
		draw_line(screen[0] - normal * 4.0, screen[0] + normal * 4.0, color, 2.0)
		draw_line(screen[1] - normal * 4.0, screen[1] + normal * 4.0, color, 2.0)
		var midpoint := (screen[0] + screen[1]) * 0.5 + normal * (14.0 if prefix == "R" else -14.0)
		var number := prefix + str(index + 1)
		var text_size := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_circle(midpoint, maxf(10.0, text_size.x * 0.5 + 4.0), Color(0, 0, 0, 0.85))
		draw_string(font, midpoint + Vector2(-text_size.x * 0.5, 5.0), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _screen_polygon(building: StaticBody3D, points: PackedVector2Array, offset: Vector2, factor: float, height: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		var position := (point + offset) * factor
		var world_point := building.to_global(Vector3(position.x, height + 0.03, position.y))
		if camera.is_position_behind(world_point):
			return PackedVector2Array()
		result.append(camera.unproject_position(world_point))
	return result
