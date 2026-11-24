extends Control

signal point_selected(latitude: float, longitude: float)
signal map_error(message: String)

const TILE_SIZE := 256.0
const CACHE_DIRECTORY := "user://tile_cache"
const FALLBACK_CACHE_SECONDS := 604800
const USER_AGENT := "OpenCrime/0.12 (+https://github.com/settstep/OpenCrime)"

var center := Vector2(47.7748417, 10.6034933)
var zoom := 15
var places: Array[Dictionary] = []
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
	for place in places:
		var position := _world_pixels(float(place.origin[0]), float(place.origin[1])) - top_left
		if Rect2(Vector2.ZERO, size).has_point(position):
			draw_circle(position, 7.0, Color(0.1, 0.45, 0.95))
	var marker := _world_pixels(selected.x, selected.y) - top_left
	if Rect2(Vector2.ZERO, size).has_point(marker):
		draw_circle(marker, 5.0, Color(0.95, 0.18, 0.12))


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
