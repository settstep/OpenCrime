extends Control

const OSMMap = preload("res://scripts/osm_map.gd")

@onready var world: Node3D = get_parent().get_parent()
@onready var camera: Camera3D = world.get_node("Camera3D")
@onready var measurement: Control = world.get_node("HUD/BuildingMeasurement")
@onready var panel: PanelContainer = $Panel
@onready var selection_label: Label = $Panel/Layout/Selection
@onready var merge_button: Button = $Panel/Layout/Merge
@onready var message: Label = $Panel/Layout/Message

var active := false
var selected: Array[StaticBody3D] = []
var pending_click := false
var click_position := Vector2.ZERO


func _ready() -> void:
	merge_button.pressed.connect(_merge)


func _unhandled_input(event: InputEvent) -> void:
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
			selected.erase(existing)
			existing.tree_exiting.disconnect(_clear_selection)
			_update_selection()
			return
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
	_clear_selection()
	queue_redraw()


func _clear_selection() -> void:
	for building in selected:
		if is_instance_valid(building) and building.tree_exiting.is_connected(_clear_selection):
			building.tree_exiting.disconnect(_clear_selection)
	selected.clear()
	_update_selection()


func _update_selection() -> void:
	selection_label.text = "%d Gebäude ausgewählt." % selected.size()
	merge_button.disabled = selected.size() < 2
	queue_redraw()


func _merge() -> void:
	var ways := []
	for building in selected:
		if not is_instance_valid(building) or not building.is_inside_tree():
			_clear_selection()
			message.text = "Ein Gebäude ist nicht mehr geladen. Bitte erneut auswählen."
			return
		ways.append(building.get_meta("measurement_way"))
	message.text = world.call("_commit_building_merge", ways)


func _draw() -> void:
	if not active or not measurement._can_interact():
		return
	for building in selected:
		if not is_instance_valid(building) or not building.is_inside_tree():
			continue
		var points: PackedVector2Array = building.get_meta("measurement_points")
		var factor: float = building.get_meta("measurement_scale")
		var height: float = building.get_meta("measurement_height")
		for index in points.size():
			var a := points[index] * factor
			var b := points[(index + 1) % points.size()] * factor
			var start := building.to_global(Vector3(a.x, height + 0.05, a.y))
			var end := building.to_global(Vector3(b.x, height + 0.05, b.y))
			if not camera.is_position_behind(start) and not camera.is_position_behind(end):
				draw_line(camera.unproject_position(start), camera.unproject_position(end), Color.CYAN, 3.0)
