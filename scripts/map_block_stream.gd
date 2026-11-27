extends Node

signal block_loaded(block: Vector2i, place: Dictionary, world_origin: Array)
signal block_unloaded(block: Vector2i)

const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const GameLog = preload("res://scripts/game_log.gd")

var CACHE_DIRECTORY := PlaceStore.BLOCK_CACHE_DIRECTORY
const USER_AGENT := "OpenCrime/0.21.1 (+https://github.com/settstep/OpenCrime)"
const MAX_RESPONSE_BYTES := 8 * 1024 * 1024
const MAX_CONCURRENT_DOWNLOADS := 1
const MIN_REQUEST_INTERVAL_MS := 1000
const RETRY_BASE_DELAY_MS := 2000
const RETRY_MAX_DELAY_MS := 120000
const RATE_LIMIT_FALLBACK_DELAY_MS := 60000
const MAX_RETRY_AFTER_DELAY_MS := 86400000
const MONTH_NUMBERS := {
	"jan": 1, "feb": 2, "mar": 3, "apr": 4,
	"may": 5, "jun": 6, "jul": 7, "aug": 8,
	"sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

var world: Node3D
var base_place: Dictionary = {}
var map_scale := 1.0
var desired_blocks: Dictionary = {}
var loaded_blocks: Dictionary = {}
var requests: Dictionary = {}
var pending_blocks: Array[Vector2i] = []
var failed_blocks: Dictionary = {}
var retry_attempts: Dictionary = {}
var ground_blocks: Dictionary = {}
var next_request_allowed_at_ms := 0
var base_block := Vector2i.ZERO
var boundary_center := Vector2i.ZERO
var pending_boundary_center := Vector2i.ZERO
var has_pending_boundary := false
var stream_status_message := ""


func configure(target_world: Node3D, place: Dictionary, scale_factor: float) -> void:
	world = target_world
	base_place = place
	map_scale = scale_factor
	GameLog.info("map", "stream started place=%s scale=%s" % [place.get("id", "unknown"), scale_factor])
	desired_blocks.clear()
	loaded_blocks.clear()
	ground_blocks.clear()
	base_block = Grid.block_for_position(Vector2.ZERO, map_scale, base_place.origin)
	boundary_center = base_block
	var base_node := world.get_node_or_null("OSMMap")
	if base_node != null:
		loaded_blocks[base_block] = {"node": base_node, "data": base_place}
	desired_blocks[base_block] = true
	_add_ground_block(base_block)
	var boundary := world.get_node_or_null("MapBoundary")
	if boundary != null:
		var boundary_offset := Grid.block_local_center(base_place.origin, base_block) * map_scale
		boundary.position = Vector3(boundary_offset.x, 0.0, boundary_offset.y)
	if world.call("_is_network_game"):
		if boundary != null:
			boundary.hide()
			boundary.collision_layer = 0
			boundary.collision_mask = 0
	_load_block(base_block)
	set_process(true)


func accept_remote_block(block: Vector2i, place: Dictionary) -> bool:
	if not PlaceStore.is_valid(place) or place.id != _block_id(block):
		return false
	var expected_origin := Grid.block_origin(base_place.origin, block)
	var expected_bounds := Grid.block_bounds(base_place.origin, block)
	for index in 2:
		if not is_equal_approx(float(place.origin[index]), float(expected_origin[index])):
			return false
	for index in 4:
		if not is_equal_approx(float(place.bounds[index]), float(expected_bounds[index])):
			return false
	if not _store_block(block, place):
		return false
	failed_blocks.erase(block)
	retry_attempts.erase(block)
	if desired_blocks.has(block):
		_replace_block(block, place)
	GameLog.info("osm", "remote block accepted block=%s ways=%d" % [Grid.key(block), place.ways.size()])
	return true


func loaded_blocks_for_transfer() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for block in loaded_blocks:
		var place: Dictionary = loaded_blocks[block].data
		if place.id == _block_id(block):
			result.append({"block": block, "place": place})
	return result


func _process(_delta: float) -> void:
	_start_queued_download()
	if world == null or base_place.is_empty() or not world.has_method("_map_block_watch_positions"):
		return
	var positions: Array = world.call("_map_block_watch_positions")
	if positions.is_empty():
		return
	var next: Dictionary = {}
	var center_positions: Array[Vector2i] = []
	for position in positions:
		if not position is Vector3 or not position.is_finite():
			continue
		var center := Grid.block_for_position(Vector2(position.x, position.z), map_scale, base_place.origin)
		center_positions.append(center)
		for block in Grid.blocks_around(center):
			next[block] = true
	if center_positions.is_empty():
		return
	_reconcile(next)
	if not world.call("_is_network_game"):
		_update_boundary(center_positions[0])


func _reconcile(next: Dictionary) -> void:
	for block in loaded_blocks.keys():
		if not next.has(block):
			var data: Dictionary = loaded_blocks[block]
			var node: Node3D = data.node
			if block == base_block and is_instance_valid(node) and node.name == "OSMMap":
				OSMMap.clear_block(node)
				node.set_meta("place", base_place)
			elif is_instance_valid(node):
				node.queue_free()
			loaded_blocks.erase(block)
			GameLog.info("map", "block unloaded block=%s" % Grid.key(block))
			block_unloaded.emit(block)
	for block in ground_blocks.keys():
		if not next.has(block):
			_remove_ground_block(block)
	desired_blocks = next
	for block in desired_blocks:
		_add_ground_block(block)
		if loaded_blocks.has(block) or requests.has(block):
			continue
		_load_block(block)


func _cache_path(block: Vector2i) -> String:
	return PlaceStore.block_cache_path(_block_id(block), CACHE_DIRECTORY)


static func retry_delay_ms(attempt: int) -> int:
	var delay := RETRY_BASE_DELAY_MS
	for _index in range(maxi(attempt - 1, 0)):
		if delay >= RETRY_MAX_DELAY_MS:
			break
		delay = mini(delay * 2, RETRY_MAX_DELAY_MS)
	return delay


static func retry_after_delay_ms(headers: PackedStringArray, now_unix: float = -1.0) -> int:
	for header in headers:
		var separator := header.find(":")
		if separator < 0 or header.substr(0, separator).strip_edges().to_lower() != "retry-after":
			continue
		var value := header.substr(separator + 1).strip_edges()
		if value.is_valid_int():
			return clampi(value.to_int() * 1000, 0, MAX_RETRY_AFTER_DELAY_MS)
		return _http_date_delay_ms(value, now_unix)
	return -1


static func retry_delay_for_response(attempt: int, code: int, headers: PackedStringArray, now_unix: float = -1.0) -> int:
	var delay := retry_delay_ms(attempt)
	var server_delay := retry_after_delay_ms(headers, now_unix)
	if server_delay >= 0:
		return maxi(delay, server_delay)
	if code == 429:
		return maxi(delay, RATE_LIMIT_FALLBACK_DELAY_MS)
	return delay


static func _http_date_delay_ms(value: String, now_unix: float) -> int:
	var parts := value.replace(",", "").split(" ", false)
	if parts.size() != 6 or parts[5].to_upper() != "GMT":
		return -1
	var month := int(MONTH_NUMBERS.get(parts[2].to_lower(), 0))
	var date_parts := parts[4].split(":", false)
	if month == 0 or date_parts.size() != 3 or not parts[1].is_valid_int() or not parts[3].is_valid_int():
		return -1
	for part in date_parts:
		if not part.is_valid_int():
			return -1
	var day := parts[1].to_int()
	var year := parts[3].to_int()
	var hour := date_parts[0].to_int()
	var minute := date_parts[1].to_int()
	var second := date_parts[2].to_int()
	if year < 1 or day < 1 or hour > 23 or minute > 59 or second > 59:
		return -1
	var days_in_month := 31
	if month == 2:
		var is_leap_year := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
		days_in_month = 29 if is_leap_year else 28
	elif month == 4 or month == 6 or month == 9 or month == 11:
		days_in_month = 30
	if day > days_in_month:
		return -1
	var target_unix := Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": second,
	})
	var current_unix := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	return clampi(ceili(maxf(float(target_unix) - current_unix, 0.0) * 1000.0), 0, MAX_RETRY_AFTER_DELAY_MS)


func _window_ready(center: Vector2i) -> bool:
	for block in Grid.blocks_around(center):
		if not loaded_blocks.has(block):
			return false
		var place: Dictionary = loaded_blocks[block].data
		if place.get("id", "") != _block_id(block):
			return false
	return true


func _block_id(block: Vector2i) -> String:
	return "block_" + Grid.tile_id(block, base_place.origin)


func _load_block(block: Vector2i) -> void:
	if not bool(ProjectSettings.get_setting("opencrime/osm/download_blocks", true)):
		return
	if pending_blocks.has(block):
		return
	if failed_blocks.has(block) and Time.get_ticks_msec() < int(failed_blocks[block]):
		return
	failed_blocks.erase(block)
	var path := _cache_path(block)
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_fail_block(block, "Zwischengespeicherter Kartenblock konnte nicht gelesen werden (Fehler %d)." % FileAccess.get_open_error())
			return
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary and PlaceStore.is_valid(json.data) and json.data.id == _block_id(block):
			_replace_block(block, json.data)
			failed_blocks.erase(block)
			retry_attempts.erase(block)
			GameLog.info("osm", "cache loaded block=%s path=%s" % [Grid.key(block), path])
			return
		push_warning("Ungültiger Kartenblock-Cache wird erneut geladen: " + path)
		GameLog.warning("osm", "invalid cache block=%s path=%s" % [Grid.key(block), path])
	if world.call("_is_network_game") and not world.multiplayer.is_server():
		return
	if requests.size() >= MAX_CONCURRENT_DOWNLOADS:
		if not pending_blocks.has(block):
			pending_blocks.append(block)
		return
	if Time.get_ticks_msec() < next_request_allowed_at_ms:
		if not pending_blocks.has(block):
			pending_blocks.append(block)
		return
	_start_download(block)


func _start_download(block: Vector2i) -> void:
	if not desired_blocks.has(block) or requests.size() >= MAX_CONCURRENT_DOWNLOADS:
		return
	if Time.get_ticks_msec() < next_request_allowed_at_ms:
		if not pending_blocks.has(block):
			pending_blocks.append(block)
		return
	var bounds := Grid.block_bounds(base_place.origin, block)
	var query := PlaceStore.block_query(bounds)
	if query.is_empty():
		_fail_block(block, "OSM-Abfrage für Kartenblock %s konnte nicht erstellt werden." % Grid.key(block))
		return
	var endpoint: String = ProjectSettings.get_setting("opencrime/osm/overpass_url")
	GameLog.info("osm", "request started block=%s bounds=%s" % [Grid.key(block), str(bounds)])
	var request := HTTPRequest.new()
	request.timeout = 90.0
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	request.request_completed.connect(_on_download_completed.bind(block, request))
	requests[block] = request
	next_request_allowed_at_ms = Time.get_ticks_msec() + MIN_REQUEST_INTERVAL_MS
	var error := request.request(endpoint + "?data=" + query.uri_encode(), PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"]))
	if error != OK:
		requests.erase(block)
		request.queue_free()
		_fail_block(block, "OSM-Anfrage für Kartenblock %s konnte nicht gestartet werden (Fehler %d)." % [Grid.key(block), error])
		_start_queued_download()


func _on_download_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, block: Vector2i, request: HTTPRequest) -> void:
	requests.erase(block)
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		var attempt := int(retry_attempts.get(block, 0)) + 1
		var retry_delay := retry_delay_for_response(attempt, code, headers)
		var retry_after := retry_after_delay_ms(headers)
		if code == 429 or code == 503 or retry_after >= 0:
			var cooldown := retry_delay if code == 429 or code == 503 else retry_after
			_apply_request_cooldown(cooldown)
		_fail_block(block, "OSM-Download für Kartenblock %s fehlgeschlagen (HTTP %d, Fehler %d)." % [Grid.key(block), code, result], retry_delay)
		_start_queued_download()
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		_fail_block(block, "OSM-Dienst lieferte ungültige Daten für Kartenblock %s." % Grid.key(block))
		_start_queued_download()
		return
	var place := PlaceStore.from_overpass_block(json.data, Grid.block_origin(base_place.origin, block), Grid.block_bounds(base_place.origin, block), _block_id(block))
	if place.is_empty():
		_fail_block(block, "OSM-Daten für Kartenblock %s sind ungültig." % Grid.key(block))
		_start_queued_download()
		return
	if not _store_block(block, place):
		_start_queued_download()
		return
	failed_blocks.erase(block)
	retry_attempts.erase(block)
	GameLog.info("osm", "block downloaded block=%s ways=%d point_features=%d bytes=%d" % [Grid.key(block), place.ways.size(), place.nodes.size(), body.size()])
	if desired_blocks.has(block):
		if block == base_block:
			_replace_block(block, place)
		else:
			_activate_block(block, place)
	if _window_ready(boundary_center):
		_clear_stream_status()
	_start_queued_download()


func _store_block(block: Vector2i, place: Dictionary) -> bool:
	var error := PlaceStore.write_block_cache(_block_id(block), place, CACHE_DIRECTORY)
	if error != OK:
		_fail_block(block, "Kartenblock konnte nicht zwischengespeichert werden (Fehler %d)." % error)
		return false
	return true


func _start_queued_download() -> void:
	if requests.size() >= MAX_CONCURRENT_DOWNLOADS or Time.get_ticks_msec() < next_request_allowed_at_ms:
		return
	while not pending_blocks.is_empty() and requests.size() < MAX_CONCURRENT_DOWNLOADS:
		var block: Vector2i = pending_blocks.pop_front()
		var is_loaded: bool = loaded_blocks.has(block) and block != base_block
		if desired_blocks.has(block) and not is_loaded and not requests.has(block):
			_start_download(block)
			return


func _apply_request_cooldown(delay_ms: int) -> void:
	next_request_allowed_at_ms = maxi(next_request_allowed_at_ms, Time.get_ticks_msec() + delay_ms)


func _activate_block(block: Vector2i, place: Dictionary) -> void:
	if not desired_blocks.has(block) or loaded_blocks.has(block):
		return
	var node: Node3D
	if block == base_block and world.get_node_or_null("OSMMap") != null:
		node = world.get_node("OSMMap")
		if not OSMMap.replace_block(node, place, map_scale):
			_report_error("Kartenblock %s konnte nicht aufgebaut werden." % Grid.key(block))
			return
	else:
		node = OSMMap.create_block(place, map_scale)
		if node == null:
			_report_error("Kartenblock %s konnte nicht aufgebaut werden." % Grid.key(block))
			return
		node.name = "MapBlock_%s" % Grid.key(block)
	var projected := OSMMap._project(place.origin, base_place.origin) * map_scale
	node.position = _to_world_position(projected)
	world.add_child(node)
	loaded_blocks[block] = {"node": node, "data": place}
	GameLog.info("map", "block activated block=%s ways=%d" % [Grid.key(block), place.ways.size()])
	block_loaded.emit(block, place, base_place.origin)


func _replace_block(block: Vector2i, place: Dictionary) -> void:
	if block == base_block:
		var base_node := world.get_node_or_null("OSMMap")
		if base_node == null:
			_activate_block(block, place)
			return
		if loaded_blocks.has(block):
			block_unloaded.emit(block)
		if not OSMMap.replace_block(base_node, place, map_scale):
			_report_error("Kartenblock %s konnte nicht aufgebaut werden." % Grid.key(block))
			return
		base_node.position = _to_world_position(OSMMap._project(place.origin, base_place.origin) * map_scale)
		loaded_blocks[block] = {"node": base_node, "data": place}
		GameLog.info("map", "block replaced block=%s ways=%d" % [Grid.key(block), place.ways.size()])
		block_loaded.emit(block, place, base_place.origin)
		return
	if loaded_blocks.has(block):
		var previous: Dictionary = loaded_blocks[block]
		var previous_node: Node3D = previous.node
		if is_instance_valid(previous_node):
			previous_node.queue_free()
		loaded_blocks.erase(block)
		block_unloaded.emit(block)
	_activate_block(block, place)


func _to_world_position(offset: Vector2) -> Vector3:
	return Vector3(offset.x, 0.0, offset.y)


func _add_ground_block(block: Vector2i) -> void:
	if block == base_block or ground_blocks.has(block):
		return
	var ground: StaticBody3D = world.get_node("Ground")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GroundMesh_%s" % Grid.key(block)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(Grid.BLOCK_SIZE * map_scale, 1.0, Grid.BLOCK_SIZE * map_scale)
	var base_mesh: MeshInstance3D = ground.get_node("MeshInstance3D")
	mesh.material = base_mesh.mesh.material
	mesh_instance.mesh = mesh
	var block_offset := Grid.block_local_center(base_place.origin, block) * map_scale
	mesh_instance.position = Vector3(block_offset.x, 0.0, block_offset.y)
	ground.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.name = "GroundCollision_%s" % Grid.key(block)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	collision.shape = shape
	collision.position = mesh_instance.position
	ground.add_child(collision)
	ground_blocks[block] = [mesh_instance, collision]


func _remove_ground_block(block: Vector2i) -> void:
	if not ground_blocks.has(block):
		return
	for node in ground_blocks[block]:
		if is_instance_valid(node):
			node.queue_free()
	ground_blocks.erase(block)


func _update_boundary(center: Vector2i) -> void:
	if center == boundary_center:
		if has_pending_boundary:
			has_pending_boundary = false
			if stream_status_message.begins_with("Lade Kartenbereich"):
				_clear_stream_status()
		return
	if not _window_ready(center):
		if not has_pending_boundary or pending_boundary_center != center:
			pending_boundary_center = center
			has_pending_boundary = true
			_set_stream_status("Lade Kartenbereich %s; der bisherige Spielfeldrand bleibt aktiv." % Grid.key(center))
			GameLog.info("map", "boundary shift waiting center=%s" % Grid.key(center))
		return
	boundary_center = center
	has_pending_boundary = false
	var block_offset := Grid.block_local_center(base_place.origin, center) * map_scale
	var offset := Vector3(block_offset.x, 0.0, block_offset.y)
	var boundary := world.get_node_or_null("MapBoundary")
	if boundary != null:
		boundary.position = offset
	GameLog.info("map", "boundary moved center=%s" % Grid.key(center))
	_clear_stream_status()


func _report_error(message: String) -> void:
	push_warning(message)
	GameLog.error("osm", message)
	_set_stream_status(message)


func _set_stream_status(message: String) -> void:
	stream_status_message = message
	if world != null and world.has_node("HUD/Status"):
		world.get_node("HUD/Status").text = message


func _clear_stream_status() -> void:
	if stream_status_message.is_empty():
		return
	if world != null and world.has_node("HUD/Status"):
		var status: Label = world.get_node("HUD/Status")
		if status.text == stream_status_message:
			status.text = ""
	stream_status_message = ""


func _fail_block(block: Vector2i, message: String, minimum_delay_ms: int = 0) -> void:
	var attempt := int(retry_attempts.get(block, 0)) + 1
	retry_attempts[block] = attempt
	var delay := maxi(retry_delay_ms(attempt), minimum_delay_ms)
	failed_blocks[block] = Time.get_ticks_msec() + delay
	var retry_message := "%s Automatischer Versuch %d in %d Sekunden." % [message, attempt, ceili(float(delay) / 1000.0)]
	_report_error(retry_message)
