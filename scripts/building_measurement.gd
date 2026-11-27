extends Control

const OSMMap = preload("res://scripts/osm_map.gd")

@onready var world: Node3D = get_parent().get_parent()
@onready var camera: Camera3D = world.get_node("Camera3D")
@onready var panel: PanelContainer = $Panel
@onready var info: Label = $Panel/Layout/Info
@onready var sides: Label = $Panel/Layout/Scroll/Sides

var active := false
var selected_building: StaticBody3D
var pending_click := false
var click_position := Vector2.ZERO


func _can_interact() -> bool:
	if get_tree().paused or world.is_queued_for_deletion() or world.get("menu_open") or world.get("map_open") or world.get("missions_open"):
		return false
	if world.call("_is_network_game"):
		return not world.get("dedicated") and world.get("connected") and world.get("map_ready")
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not _can_interact():
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.alt_pressed and (event.keycode == KEY_F4 or event.physical_keycode == KEY_F4):
		active = not active
		pending_click = false
		if not active:
			_clear_selection()
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_position = event.position
		pending_click = true
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not pending_click:
		return
	pending_click = false
	if not active or not _can_interact():
		return
	var origin := camera.project_ray_origin(click_position)
	var end := origin + camera.project_ray_normal(click_position) * camera.far
	var query := PhysicsRayQueryParameters3D.create(origin, end, OSMMap.BUILDING_PICK_LAYER)
	query.hit_back_faces = true
	query.hit_from_inside = true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var building := hit.get("collider") as StaticBody3D
	if building == null or not building.has_meta("measurement_points"):
		_clear_selection()
		return
	_select_building(building)


func _process(_delta: float) -> void:
	var show_measurement := active and _can_interact()
	panel.visible = show_measurement
	if selected_building != null and (not is_instance_valid(selected_building) or not selected_building.is_inside_tree()):
		_clear_selection()
	if active:
		queue_redraw()


func _select_building(building: StaticBody3D) -> void:
	_clear_selection()
	selected_building = building
	building.tree_exiting.connect(_clear_selection)
	var points: PackedVector2Array = building.get_meta("measurement_points")
	var scale_factor: float = building.get_meta("measurement_scale")
	info.text = "OSM-Gebäude %s · Kartenfaktor %.2f\nNummern markieren die Seiten im Spiel." % [str(building.get_meta("measurement_osm_id")), scale_factor]
	var lines := PackedStringArray()
	for index in points.size():
		var length := points[index].distance_to(points[(index + 1) % points.size()])
		lines.append("Seite %d: %.2f m (OSM) | %.2f Spieleinheiten" % [index + 1, length, length * scale_factor])
	sides.text = "\n".join(lines)
	$Panel/Layout/Scroll.scroll_vertical = 0
	queue_redraw()


func _clear_selection() -> void:
	if is_instance_valid(selected_building) and selected_building.tree_exiting.is_connected(_clear_selection):
		selected_building.tree_exiting.disconnect(_clear_selection)
	selected_building = null
	info.text = "Ein Gebäude anklicken."
	sides.text = ""
	queue_redraw()


func _draw() -> void:
	if not active or not _can_interact() or not is_instance_valid(selected_building) or not selected_building.is_inside_tree():
		return
	var points: PackedVector2Array = selected_building.get_meta("measurement_points")
	var scale_factor: float = selected_building.get_meta("measurement_scale")
	var height: float = selected_building.get_meta("measurement_height")
	var font := ThemeDB.fallback_font
	for index in points.size():
		var a := points[index] * scale_factor
		var b := points[(index + 1) % points.size()] * scale_factor
		var start := selected_building.to_global(Vector3(a.x, height + 0.05, a.y))
		var end := selected_building.to_global(Vector3(b.x, height + 0.05, b.y))
		if camera.is_position_behind(start) or camera.is_position_behind(end):
			continue
		var screen_start := camera.unproject_position(start)
		var screen_end := camera.unproject_position(end)
		draw_line(screen_start, screen_end, Color.YELLOW, 2.0)
		var midpoint := (screen_start + screen_end) / 2.0
		var number := str(index + 1)
		var text_size := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_circle(midpoint, maxf(10.0, text_size.x / 2.0 + 4.0), Color(0, 0, 0, 0.85))
		draw_string(font, midpoint + Vector2(-text_size.x / 2.0, 5.0), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
