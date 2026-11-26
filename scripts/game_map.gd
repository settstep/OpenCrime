extends Control

signal close_requested

const OSMMap = preload("res://scripts/osm_map.gd")
const WORLD_SIZE := 450.0
const CELL_SIZE := 10.0
const REVEAL_RADIUS := 30.0
const GRID_SIZE := 45
const MIN_ZOOM := 1.0
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.25

@onready var canvas: Control = $Margin/Layout/MapContainer/Canvas
@onready var drawing: Control = $Margin/Layout/MapContainer/Canvas/Drawing
@onready var title: Label = $Margin/Layout/Header/Title
@onready var close_button: Button = $Margin/Layout/Header/Close
@onready var center_button: Button = $Margin/Layout/Header/Center

var configured := false
var map_scale := 1.0
var zoom := 1.0
var view_center := Vector2.ZERO
var dragging := false
var features: Array[Dictionary] = []
var explored := {}
var player_position := Vector2.ZERO
var has_position := false
var mission_target := Vector2.ZERO
var has_mission_target := false
var first_aid_position := Vector2.ZERO
var has_first_aid := false
var car_positions: Array[Vector2] = []
var medkit_position := Vector2.ZERO
var has_medkit := false


func _ready() -> void:
	canvas.clip_contents = true
	drawing.draw.connect(_draw_map)
	canvas.gui_input.connect(_on_canvas_input)
	visibility_changed.connect(_on_visibility_changed)
	close_button.pressed.connect(func(): close_requested.emit())
	center_button.pressed.connect(_center_on_player)


func configure(place: Dictionary, scale_factor: float) -> void:
	configured = true
	map_scale = scale_factor
	zoom = MIN_ZOOM
	view_center = Vector2.ZERO
	dragging = false
	features.clear()
	explored.clear()
	has_position = false
	title.text = "Karte – " + place.name
	for way in place.ways:
		var tags: Dictionary = way.tags
		var kind := ""
		if tags.has("building"):
			kind = "building"
		elif tags.get("amenity", "") == "parking" and tags.get("parking", "") in ["", "surface"] and tags.get("area", "") != "no":
			kind = "parking"
		elif tags.get("highway", "") in OSMMap.PEDESTRIAN_WAYS and tags.get("area", "") == "yes":
			kind = "pedestrian_area"
		elif tags.has("highway") and tags.get("area", "") != "yes":
			kind = "pedestrian" if tags.highway in OSMMap.PEDESTRIAN_WAYS else "road"
		if kind.is_empty():
			continue
		var points := PackedVector2Array()
		for coordinate in way.geometry:
			var point := OSMMap._project(coordinate, place.origin) * map_scale
			if points.is_empty() or point.distance_to(points[points.size() - 1]) > 0.01 * map_scale:
				points.append(point)
		if kind in ["building", "parking", "pedestrian_area"]:
			if kind == "building" and way.geometry.size() < 3:
				continue
			if kind != "building" and (way.geometry.size() < 4 or way.geometry[0] != way.geometry[-1]):
				continue
			if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < 0.01 * map_scale:
				points.remove_at(points.size() - 1)
			var triangles := Geometry2D.triangulate_polygon(points)
			if triangles.is_empty():
				continue
			features.append({"kind": kind, "points": points, "triangles": triangles})
		elif points.size() >= 2:
			features.append({"kind": kind, "points": points, "width": OSMMap._road_width(tags) * map_scale})
	drawing.queue_redraw()


func update_position(position: Vector3) -> void:
	if not configured or not position.is_finite():
		return
	player_position = Vector2(position.x, position.z)
	has_position = true
	var half := WORLD_SIZE * map_scale / 2.0
	var cell := CELL_SIZE * map_scale
	var radius := REVEAL_RADIUS * map_scale
	var first_x := maxi(0, floori((player_position.x - radius + half) / cell))
	var last_x := mini(GRID_SIZE - 1, floori((player_position.x + radius + half) / cell))
	var first_y := maxi(0, floori((player_position.y - radius + half) / cell))
	var last_y := mini(GRID_SIZE - 1, floori((player_position.y + radius + half) / cell))
	for x in range(first_x, last_x + 1):
		for y in range(first_y, last_y + 1):
			var corner := Vector2(x, y) * cell - Vector2.ONE * half
			var nearest := player_position.clamp(corner, corner + Vector2.ONE * cell)
			if player_position.distance_squared_to(nearest) <= radius * radius:
				explored[Vector2i(x, y)] = true
	if visible:
		drawing.queue_redraw()


func set_mission_target(target: Vector2, enabled: bool) -> void:
	mission_target = target
	has_mission_target = enabled
	if visible:
		drawing.queue_redraw()


func set_first_aid(position: Vector2, enabled: bool) -> void:
	first_aid_position = position
	has_first_aid = enabled
	if visible:
		drawing.queue_redraw()


func set_cars(positions: Array[Vector2]) -> void:
	car_positions = positions
	if visible:
		drawing.queue_redraw()


func set_medkit(position: Vector2, enabled: bool) -> void:
	medkit_position = position
	has_medkit = enabled
	if visible:
		drawing.queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("show_map") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_requested.emit()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		dragging = false


func _map_factor() -> float:
	return canvas.size.x * zoom / (WORLD_SIZE * map_scale)


func _set_view_center(center: Vector2) -> void:
	var half := WORLD_SIZE * map_scale / 2.0
	var limit := Vector2(half, half)
	if has_position:
		limit = limit.max(player_position.abs())
	view_center = center.clamp(-limit, limit)
	drawing.queue_redraw()


func _center_on_player() -> void:
	_set_view_center(player_position if has_position else Vector2.ZERO)


func _on_canvas_input(event: InputEvent) -> void:
	if not configured or canvas.size.x <= 0.0:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var cursor_offset: Vector2 = event.position - canvas.size / 2.0
			var world_under_cursor := view_center + cursor_offset / _map_factor()
			zoom = clampf(zoom * (ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP), MIN_ZOOM, MAX_ZOOM)
			_set_view_center(world_under_cursor - cursor_offset / _map_factor())
	elif event is InputEventMouseMotion and dragging:
		_set_view_center(view_center - event.relative / _map_factor())


func _map_point(point: Vector2, factor: float) -> Vector2:
	return canvas.size / 2.0 + (point - view_center) * factor


func _cell_rect(x: int, y: int, factor: float) -> Rect2:
	var half := WORLD_SIZE * map_scale / 2.0
	var cell := CELL_SIZE * map_scale
	var corner := Vector2(x, y) * cell - Vector2.ONE * half
	return Rect2(_map_point(corner, factor), Vector2.ONE * cell * factor)


func _draw_outside(bounds: Rect2) -> void:
	var left := clampf(bounds.position.x, 0.0, canvas.size.x)
	var top := clampf(bounds.position.y, 0.0, canvas.size.y)
	var right := clampf(bounds.end.x, 0.0, canvas.size.x)
	var bottom := clampf(bounds.end.y, 0.0, canvas.size.y)
	var color := Color(0.08, 0.09, 0.11)
	for rect in [
		Rect2(0, 0, canvas.size.x, top),
		Rect2(0, bottom, canvas.size.x, canvas.size.y - bottom),
		Rect2(0, top, left, bottom - top),
		Rect2(right, top, canvas.size.x - right, bottom - top),
	]:
		drawing.draw_rect(rect, color)


func _draw_map() -> void:
	if not configured:
		return
	var factor := _map_factor()
	var half := WORLD_SIZE * map_scale / 2.0
	var bounds := Rect2(_map_point(Vector2(-half, -half), factor), Vector2.ONE * WORLD_SIZE * map_scale * factor)
	drawing.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.08, 0.09, 0.11))
	drawing.draw_rect(bounds, Color(0.35, 0.52, 0.31))
	for kind in ["parking", "pedestrian_area", "pedestrian", "road", "building"]:
		for feature in features:
			if feature.kind != kind:
				continue
			var color := Color(0.27, 0.28, 0.30)
			match kind:
				"parking":
					color = Color(0.37, 0.38, 0.39)
				"pedestrian", "pedestrian_area":
					color = Color(0.57, 0.57, 0.54)
				"building":
					color = Color(0.73, 0.62, 0.48)
			var points := PackedVector2Array()
			for point in feature.points:
				points.append(_map_point(point, factor))
			if feature.has("triangles"):
				var triangles: PackedInt32Array = feature.triangles
				for index in range(0, triangles.size(), 3):
					var a := points[triangles[index]]
					var b := points[triangles[index + 1]]
					var c := points[triangles[index + 2]]
					if absf((b - a).cross(c - a)) > 0.01:
						drawing.draw_primitive(PackedVector2Array([a, b, c]), PackedColorArray([color, color, color]), PackedVector2Array())
			else:
				var width := maxf(1.0, feature.width * factor)
				drawing.draw_polyline(points, color, width, true)
				for point in points:
					drawing.draw_circle(point, width / 2.0, color)
	_draw_outside(bounds)
	var visible_rect := Rect2(Vector2.ZERO, canvas.size)
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if not explored.has(Vector2i(x, y)):
				var cell_rect := _cell_rect(x, y, factor)
				if visible_rect.intersects(cell_rect):
					cell_rect.size += Vector2.ONE * 0.5
					drawing.draw_rect(cell_rect, Color(0.04, 0.05, 0.07))
	if has_mission_target:
		var target := _map_point(mission_target, factor)
		if visible_rect.has_point(target):
			drawing.draw_circle(target, 8.0, Color(1.0, 0.85, 0.1))
	if has_first_aid:
		var point := _map_point(first_aid_position, factor)
		if visible_rect.has_point(point):
			drawing.draw_circle(point, 8.0, Color(0.1, 0.65, 0.25))
			drawing.draw_line(point + Vector2(-4, 0), point + Vector2(4, 0), Color.WHITE, 2.0)
			drawing.draw_line(point + Vector2(0, -4), point + Vector2(0, 4), Color.WHITE, 2.0)
	for position in car_positions:
		var point := _map_point(position, factor)
		if visible_rect.has_point(point):
			drawing.draw_circle(point, 5.0, Color(1.0, 0.45, 0.1))
	if has_medkit:
		var point := _map_point(medkit_position, factor)
		if visible_rect.has_point(point):
			drawing.draw_rect(Rect2(point - Vector2(6, 6), Vector2(12, 12)), Color(1.0, 0.8, 0.1))
			drawing.draw_line(point + Vector2(-3, 0), point + Vector2(3, 0), Color.WHITE, 2.0)
			drawing.draw_line(point + Vector2(0, -3), point + Vector2(0, 3), Color.WHITE, 2.0)
	if has_position:
		var marker := _map_point(player_position, factor)
		if Rect2(Vector2.ZERO, canvas.size).has_point(marker):
			drawing.draw_circle(marker, 7.0, Color.WHITE)
			drawing.draw_circle(marker, 5.0, Color(0.12, 0.55, 1.0))
