extends Control

signal close_requested

const OSMMap = preload("res://scripts/osm_map.gd")
const WORLD_SIZE := 450.0
const CELL_SIZE := 10.0
const REVEAL_RADIUS := 30.0
const GRID_SIZE := 45

@onready var canvas: Control = $Margin/Layout/MapContainer/Canvas
@onready var title: Label = $Margin/Layout/Header/Title
@onready var close_button: Button = $Margin/Layout/Header/Close

var configured := false
var map_scale := 1.0
var features: Array[Dictionary] = []
var explored := {}
var player_position := Vector2.ZERO
var has_position := false


func _ready() -> void:
	canvas.clip_contents = true
	canvas.draw.connect(_draw_map)
	close_button.pressed.connect(func(): close_requested.emit())


func configure(place: Dictionary, scale_factor: float) -> void:
	configured = true
	map_scale = scale_factor
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
	canvas.queue_redraw()


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
		canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("show_map") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_requested.emit()


func _map_point(point: Vector2, factor: float) -> Vector2:
	return canvas.size / 2.0 + point * factor


func _draw_map() -> void:
	if not configured:
		return
	var factor := canvas.size.x / (WORLD_SIZE * map_scale)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.35, 0.52, 0.31))
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
						canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), color)
			else:
				var width := maxf(1.0, feature.width * factor)
				canvas.draw_polyline(points, color, width, true)
				for point in points:
					canvas.draw_circle(point, width / 2.0, color)
	var cell_pixels := canvas.size.x / GRID_SIZE
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			if not explored.has(Vector2i(x, y)):
				canvas.draw_rect(Rect2(Vector2(x, y) * cell_pixels, Vector2.ONE * (cell_pixels + 0.5)), Color(0.04, 0.05, 0.07))
	if has_position:
		var marker := _map_point(player_position, factor)
		if Rect2(Vector2.ZERO, canvas.size).has_point(marker):
			canvas.draw_circle(marker, 7.0, Color.WHITE)
			canvas.draw_circle(marker, 5.0, Color(0.12, 0.55, 1.0))
