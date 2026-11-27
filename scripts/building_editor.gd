extends Control

const OSMMap = preload("res://scripts/osm_map.gd")

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
@onready var message: Label = $Panel/Layout/Message

var active := false
var selected: Array[StaticBody3D] = []
var pending_click := false
var click_position := Vector2.ZERO


func _ready() -> void:
	merge_button.pressed.connect(_merge)
	levels_button.pressed.connect(_apply_levels)
	floor_number.value_changed.connect(_floor_changed)
	hollow_button.pressed.connect(_hollow_floor)


func _input(event: InputEvent) -> void:
	if not measurement._can_interact():
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
	if active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	if active:
		queue_redraw()


func close_editor() -> void:
	active = false
	pending_click = false
	levels_input.release_focus()
	floor_number.get_line_edit().release_focus()
	_clear_selection()
	queue_redraw()


func _clear_selection() -> void:
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
			if child is MeshInstance3D and child.name.begins_with("Segment_"):
				child.visible = true
			elif child is MeshInstance3D and child.name.begins_with("FloorPreview_"):
				child.visible = false


func _floor_changed(_value: float) -> void:
	_update_floor_preview()
	queue_redraw()


func _update_floor_preview() -> void:
	_restore_preview()
	hollow_button.disabled = true
	if selected.size() != 1 or not is_instance_valid(selected[0]) or not floor_number.editable:
		return
	var building := selected[0]
	var floor_index := int(floor_number.value)
	var way: Dictionary = building.get_meta("measurement_way")
	var hollow := false
	for edit in way.get("_hollow_floors", []):
		hollow = hollow or int(edit.floor) == floor_index
	hollow_button.disabled = hollow
	for child in building.get_children():
		if child is MeshInstance3D and child.name.begins_with("Segment_"):
			var number := int(child.get_meta("floor_number", 0))
			child.visible = number <= floor_index and not (number == floor_index and hollow)
		elif child is MeshInstance3D and child.name.begins_with("FloorPreview_"):
			child.visible = child.name == "FloorPreview_%d" % floor_index


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
	var block_key: Variant = null
	for key in world.map_block_stream.loaded_blocks:
		if world.map_block_stream.loaded_blocks[key].node == building.get_parent():
			block_key = key
			break
	var result: String = world.call("_commit_building_hollow", building.get_meta("measurement_way"), chosen_floor)
	message.text = result
	if result == world.BUILDING_HOLLOW_SUCCESS and block_key != null and world.map_block_stream.loaded_blocks.has(block_key):
		_clear_selection()
		var map: Node3D = world.map_block_stream.loaded_blocks[block_key].node
		var replacement := map.get_node_or_null("Building_%d" % id) as StaticBody3D
		if replacement != null:
			selected.append(replacement)
			replacement.tree_exiting.connect(_clear_selection)
			floor_number.set_value_no_signal(chosen_floor)
			_update_selection()


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
		for index in points.size():
			var a := points[index] * factor
			var b := points[(index + 1) % points.size()] * factor
			var start := building.to_global(Vector3(a.x, height + 0.05, a.y))
			var end := building.to_global(Vector3(b.x, height + 0.05, b.y))
			if not camera.is_position_behind(start) and not camera.is_position_behind(end):
				draw_line(camera.unproject_position(start), camera.unproject_position(end), Color.CYAN, 3.0)
