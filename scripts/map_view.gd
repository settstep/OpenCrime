extends Control

signal point_selected(latitude: float, longitude: float)
signal map_error(message: String)

const TILE_SIZE := 256.0
const DataPaths = preload("res://scripts/data_paths.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const MapBlockGrid = preload("res://scripts/map_block_grid.gd")
const FALLBACK_CACHE_SECONDS := 604800
const USER_AGENT := "OpenCrime/0.21.1 (+https://github.com/settstep/OpenCrime)"

var CACHE_DIRECTORY := DataPaths.path("tile_cache")
var BLOCK_CACHE_DIRECTORY := PlaceStore.BLOCK_CACHE_DIRECTORY
var center := Vector2(47.7748417, 10.6034933)
var zoom := 15
var places: Array[Dictionary] = []
var cached_blocks: Array[PackedVector2Array] = []
var selected := center
var textures := {}
var pending: Array[Vector3i] = []
var failed := {}
var current_tile := Vector3i(-1, -1, -1)
var drag_start := Vector2.ZERO
var dragging := false
var moved := false
var request: HTTPRequest


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	request = HTTPRequest.new()
	request.timeout = 20.0
	request.body_size_limit = 2 * 1024 * 1024
	add_child(request)
	request.request_completed.connect(_on_tile_completed)
	resized.connect(_refresh)
	_refresh()


func set_places(value: Array[Dictionary]) -> void:
	places = value
	_load_cached_blocks()
	queue_redraw()


func select_place(place: Dictionary) -> void:
	center = Vector2(float(place.origin[0]), float(place.origin[1]))
	selected = center
	_refresh()


func _world_pixels(latitude: float, longitude: float) -> Vector2:
	var size_pixels := TILE_SIZE * pow(2.0, zoom)
	var latitude_radians := deg_to_rad(clampf(latitude, -85.0, 85.0))
	return Vector2((longitude + 180.0) / 360.0 * size_pixels, (1.0 - asinh(tan(latitude_radians)) / PI) / 2.0 * size_pixels)


func _coordinates(pixel: Vector2) -> Vector2:
	var size_pixels := TILE_SIZE * pow(2.0, zoom)
	var longitude := pixel.x / size_pixels * 360.0 - 180.0
	var latitude := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * pixel.y / size_pixels))))
	return Vector2(clampf(latitude, -85.0, 85.0), clampf(longitude, -180.0, 180.0))


func _load_cached_blocks() -> void:
	cached_blocks.clear()
	var global_cache_path := ProjectSettings.globalize_path(BLOCK_CACHE_DIRECTORY)
	if not DirAccess.dir_exists_absolute(global_cache_path):
		return
	var directory := DirAccess.open(BLOCK_CACHE_DIRECTORY)
	if directory == null:
		var message := "Kartenblock-Cache konnte nicht gelesen werden (Fehler %d): %s" % [DirAccess.get_open_error(), BLOCK_CACHE_DIRECTORY]
		push_warning(message)
		map_error.emit(message)
		return
	var filenames := directory.get_files()
	filenames.sort()
	for filename in filenames:
		var corners := _cached_block_corners(filename)
		if corners.size() == 4:
			cached_blocks.append(corners)


func _cached_block_corners(filename: String) -> PackedVector2Array:
	if not filename.begins_with("block_utm") or not filename.ends_with(".json"):
		return PackedVector2Array()
	var indices := filename.trim_suffix(".json").trim_prefix("block_utm").split("_", false)
	if indices.size() != 3:
		return PackedVector2Array()
	for index in indices:
		if not index.is_valid_int():
			return PackedVector2Array()
	var zone := int(indices[0])
	var easting_index := int(indices[1])
	var northing_index := int(indices[2])
	if zone < 1 or zone > 60 or easting_index < 0 or easting_index > 1000:
		return PackedVector2Array()
	var false_northing_blocks := int(MapBlockGrid.UTM_FALSE_NORTHING / MapBlockGrid.BLOCK_SIZE)
	var northern_hemisphere := northing_index >= 0
	if northing_index == 0:
		var cache_file := FileAccess.open(BLOCK_CACHE_DIRECTORY.path_join(filename), FileAccess.READ)
		if cache_file == null:
			return PackedVector2Array()
		var json := JSON.new()
		var parse_error := json.parse(cache_file.get_as_text())
		cache_file.close()
		if parse_error != OK or not json.data is Dictionary or json.data.get("id", "") != filename.trim_suffix(".json") or not json.data.get("origin", []) is Array:
			return PackedVector2Array()
		var origin: Array = json.data.origin
		if origin.size() != 2 or MapBlockGrid.zone_for_origin(origin) != zone:
			return PackedVector2Array()
		northern_hemisphere = MapBlockGrid.is_northern_hemisphere(origin)
	var actual_northing_index := northing_index
	if not northern_hemisphere:
		actual_northing_index += false_northing_blocks
	if actual_northing_index < 0 or actual_northing_index > false_northing_blocks:
		return PackedVector2Array()
	var west := float(easting_index) * MapBlockGrid.BLOCK_SIZE
	var east := west + MapBlockGrid.BLOCK_SIZE
	var south := float(actual_northing_index) * MapBlockGrid.BLOCK_SIZE
	var north := south + MapBlockGrid.BLOCK_SIZE
	var corners := PackedVector2Array()
	for projected in [[west, south], [east, south], [east, north], [west, north]]:
		var coordinate := MapBlockGrid.unproject(projected, zone, northern_hemisphere)
		if coordinate.size() != 2:
			return PackedVector2Array()
		corners.append(Vector2(float(coordinate[0]), float(coordinate[1])))
	return corners


func _refresh() -> void:
	pending.clear()
	failed.clear()
	var top_left := _world_pixels(center.x, center.y) - size / 2.0
	var count := 1 << zoom
	var first_x := maxi(0, floori(top_left.x / TILE_SIZE))
	var first_y := maxi(0, floori(top_left.y / TILE_SIZE))
	var last_x := mini(count - 1, floori((top_left.x + size.x) / TILE_SIZE))
	var last_y := mini(count - 1, floori((top_left.y + size.y) / TILE_SIZE))
	var visible_keys := {}
	for x in range(first_x, last_x + 1):
		for y in range(first_y, last_y + 1):
			var tile := Vector3i(zoom, x, y)
			var key := _key(tile)
			visible_keys[key] = true
			if not textures.has(key):
				_load_cached(tile)
			if (not textures.has(key) or not _cache_fresh(tile)) and tile != current_tile:
				pending.append(tile)
	for key in textures.keys():
		if not visible_keys.has(key):
			textures.erase(key)
	queue_redraw()
	_start_next()


func _key(tile: Vector3i) -> String:
	return "%d_%d_%d" % [tile.x, tile.y, tile.z]


func _tile_path(tile: Vector3i) -> String:
	return CACHE_DIRECTORY.path_join(_key(tile) + ".png")


func _metadata(tile: Vector3i) -> Dictionary:
	var path := CACHE_DIRECTORY.path_join(_key(tile) + ".json")
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _cache_fresh(tile: Vector3i) -> bool:
	var path := _tile_path(tile)
	if not FileAccess.file_exists(path):
		return false
	var metadata := _metadata(tile)
	var expires := float(metadata.get("expires", FileAccess.get_modified_time(path) + FALLBACK_CACHE_SECONDS))
	return Time.get_unix_time_from_system() < expires


func _load_cached(tile: Vector3i) -> void:
	var file := FileAccess.open(_tile_path(tile), FileAccess.READ)
	if file == null:
		return
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) == OK:
		textures[_key(tile)] = ImageTexture.create_from_image(image)


func _start_next() -> void:
	if not is_inside_tree() or not is_visible_in_tree() or current_tile.x >= 0 or DisplayServer.get_name() == "headless":
		return
	while not pending.is_empty():
		var tile: Vector3i = pending.pop_front()
		if failed.has(_key(tile)) or (textures.has(_key(tile)) and _cache_fresh(tile)):
			continue
		current_tile = tile
		var template: String = ProjectSettings.get_setting("opencrime/osm/tile_url")
		var url := template.replace("{z}", str(tile.x)).replace("{x}", str(tile.y)).replace("{y}", str(tile.z))
		var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: image/png"])
		var metadata := _metadata(tile)
		if metadata.has("etag"):
			headers.append("If-None-Match: " + str(metadata.etag))
		if metadata.has("last_modified"):
			headers.append("If-Modified-Since: " + str(metadata.last_modified))
		var error := request.request(url, headers)
		if error != OK:
			failed[_key(tile)] = true
			current_tile = Vector3i(-1, -1, -1)
			map_error.emit("Kartenkachel konnte nicht angefordert werden (Fehler %d)." % error)
			continue
		return


func _on_tile_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var tile := current_tile
	current_tile = Vector3i(-1, -1, -1)
	var key := _key(tile)
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 304):
		failed[key] = true
		map_error.emit("Kartenkacheln nicht verfügbar (HTTP %d, Fehler %d)." % [code, result])
		_start_next()
		return
	if code == 200:
		var image := Image.new()
		if image.load_png_from_buffer(body) != OK:
			failed[key] = true
			map_error.emit("Ungültige Kartenkachel erhalten.")
			_start_next()
			return
		textures[key] = ImageTexture.create_from_image(image)
	elif not textures.has(key):
		failed[key] = true
		map_error.emit("Kartenkachel fehlt trotz Cache-Bestätigung.")
		_start_next()
		return
	var meta := _metadata(tile)
	var max_age := FALLBACK_CACHE_SECONDS
	var no_store := false
	var no_cache := false
	var age := 0
	for header in headers:
		var separator := header.find(":")
		if separator < 0:
			continue
		var name := header.substr(0, separator).strip_edges().to_lower()
		var value := header.substr(separator + 1).strip_edges()
		if name == "cache-control":
			for directive in value.to_lower().split(","):
				var item := directive.strip_edges()
				if item == "no-store":
					no_store = true
				elif item == "no-cache":
					no_cache = true
				elif item.begins_with("max-age=") and item.trim_prefix("max-age=").is_valid_int():
					max_age = maxi(0, int(item.trim_prefix("max-age=")))
		elif name == "etag":
			meta["etag"] = value
		elif name == "last-modified":
			meta["last_modified"] = value
		elif name == "age" and value.is_valid_int():
			age = maxi(0, int(value))
	if not no_store:
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
		if error == OK and code == 200:
			var file := FileAccess.open(_tile_path(tile), FileAccess.WRITE)
			if file == null:
				error = FileAccess.get_open_error()
			else:
				file.store_buffer(body)
				error = file.get_error()
		if error == OK:
			meta["expires"] = Time.get_unix_time_from_system() + (0 if no_cache else maxi(0, max_age - age))
			var file := FileAccess.open(CACHE_DIRECTORY.path_join(key + ".json"), FileAccess.WRITE)
			if file == null:
				error = FileAccess.get_open_error()
			else:
				file.store_string(JSON.stringify(meta))
				error = file.get_error()
		if error != OK:
			map_error.emit("Karten-Cache konnte nicht gespeichert werden (Fehler %d)." % error)
	else:
		for path in [_tile_path(tile), CACHE_DIRECTORY.path_join(key + ".json")]:
			if FileAccess.file_exists(path):
				var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				if error != OK:
					map_error.emit("Karten-Cache konnte nicht entfernt werden (Fehler %d)." % error)
	queue_redraw()
	_start_next()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.18, 0.2))
	var top_left := _world_pixels(center.x, center.y) - size / 2.0
	for key in textures:
		var parts: PackedStringArray = key.split("_")
		if int(parts[0]) != zoom:
			continue
		var position := Vector2(int(parts[1]), int(parts[2])) * TILE_SIZE - top_left
		if Rect2(position, Vector2(TILE_SIZE, TILE_SIZE)).intersects(Rect2(Vector2.ZERO, size)):
			draw_texture(textures[key], position)
	_draw_cached_blocks(top_left)
	for place in places:
		var position := _world_pixels(float(place.origin[0]), float(place.origin[1])) - top_left
		if Rect2(Vector2.ZERO, size).has_point(position):
			draw_circle(position, 7.0, Color(0.1, 0.45, 0.95))
	var marker := _world_pixels(selected.x, selected.y) - top_left
	if Rect2(Vector2.ZERO, size).has_point(marker):
		draw_circle(marker, 5.0, Color(0.95, 0.18, 0.12))


func _draw_cached_blocks(top_left: Vector2) -> void:
	var view_rect := Rect2(Vector2.ZERO, size)
	for block in cached_blocks:
		var points := _cached_block_screen_points(block, top_left)
		if points.size() != 4:
			continue
		var minimum := points[0]
		var maximum := points[0]
		for point in points:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		if not view_rect.intersects(Rect2(minimum, maximum - minimum)):
			continue
		draw_colored_polygon(points, Color(0.1, 0.8, 0.25, 0.22))
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, Color(0.15, 0.95, 0.35, 0.8), 1.5, true)


func _cached_block_screen_points(block: PackedVector2Array, top_left: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var world_width := TILE_SIZE * pow(2.0, zoom)
	var center_pixel := _world_pixels(center.x, center.y)
	for coordinate in block:
		var pixel := _world_pixels(coordinate.x, coordinate.y)
		if pixel.x - center_pixel.x > world_width / 2.0:
			pixel.x -= world_width
		elif pixel.x - center_pixel.x < -world_width / 2.0:
			pixel.x += world_width
		points.append(pixel - top_left)
	return points


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				moved = false
				drag_start = event.position
			elif dragging:
				dragging = false
				if not moved:
					selected = _coordinates(_world_pixels(center.x, center.y) + event.position - size / 2.0)
					point_selected.emit(selected.x, selected.y)
					queue_redraw()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom = clampi(zoom + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 2, 18)
			_refresh()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_start) > 3.0:
			moved = true
		if moved:
			center = _coordinates(_world_pixels(center.x, center.y) - event.relative)
			_refresh()
