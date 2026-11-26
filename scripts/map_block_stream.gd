extends Node

signal block_loaded(block: Vector2i, place: Dictionary, world_origin: Array)
signal block_unloaded(block: Vector2i)

const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")

const CACHE_DIRECTORY := "user://map_blocks"
const USER_AGENT := "OpenCrime/0.15 (+https://github.com/settstep/OpenCrime)"
const MAX_RESPONSE_BYTES := 8 * 1024 * 1024
const MAX_CONCURRENT_DOWNLOADS := 2
const RETRY_DELAY_MS := 30000

var world: Node3D
var base_place: Dictionary = {}
var map_scale := 1.0
var desired_blocks: Dictionary = {}
var loaded_blocks: Dictionary = {}
var requests: Dictionary = {}
var pending_blocks: Array[Vector2i] = []
var failed_blocks: Dictionary = {}
var ground_blocks: Dictionary = {}
var boundary_center := Vector2i.ZERO


func configure(target_world: Node3D, place: Dictionary, scale_factor: float) -> void:
	world = target_world
	base_place = place
	map_scale = scale_factor
	desired_blocks.clear()
	loaded_blocks.clear()
	ground_blocks.clear()
	var base_node := world.get_node_or_null("OSMMap")
	if base_node != null:
		loaded_blocks[Vector2i.ZERO] = {"node": base_node, "data": base_place}
	desired_blocks[Vector2i.ZERO] = true
	_add_ground_block(Vector2i.ZERO)
	if world.call("_is_network_game"):
		var boundary := world.get_node_or_null("MapBoundary")
		if boundary != null:
			boundary.hide()
			boundary.collision_layer = 0
			boundary.collision_mask = 0
	_load_block(Vector2i.ZERO)
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
	if desired_blocks.has(block):
		_replace_block(block, place)
	return true


func loaded_blocks_for_transfer() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for block in loaded_blocks:
		var place: Dictionary = loaded_blocks[block].data
		if place.id == _block_id(block):
			result.append({"block": block, "place": place})
	return result


func _process(_delta: float) -> void:
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
		var center := Grid.block_for_position(Vector2(position.x, position.z), map_scale)
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
			if block == Vector2i.ZERO and is_instance_valid(node) and node.name == "OSMMap":
				OSMMap.clear_block(node)
				node.set_meta("place", base_place)
			elif is_instance_valid(node):
				node.queue_free()
			loaded_blocks.erase(block)
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
	var place_key := str(base_place.id).sha256_text().substr(0, 16)
	return CACHE_DIRECTORY.path_join("%s_%s.json" % [place_key, Grid.key(block)])


func _block_id(block: Vector2i) -> String:
	return "block_" + str(base_place.id).sha256_text().substr(0, 12) + "_" + Grid.key(block)


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
			return
		push_warning("Ungültiger Kartenblock-Cache wird erneut geladen: " + path)
	if world.call("_is_network_game") and not world.multiplayer.is_server():
		return
	if requests.size() >= MAX_CONCURRENT_DOWNLOADS:
		if not pending_blocks.has(block):
			pending_blocks.append(block)
		return
	_start_download(block)


func _start_download(block: Vector2i) -> void:
	if not desired_blocks.has(block) or requests.size() >= MAX_CONCURRENT_DOWNLOADS:
		return
	var bounds := Grid.block_bounds(base_place.origin, block)
	var bbox := "%.7f,%.7f,%.7f,%.7f" % bounds
	var query := '[out:json][timeout:60];(way["highway"](%s);way["building"](%s);way["amenity"="parking"](%s););out body geom;' % [bbox, bbox, bbox]
	var endpoint: String = ProjectSettings.get_setting("opencrime/osm/overpass_url")
	var request := HTTPRequest.new()
	request.timeout = 90.0
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	request.request_completed.connect(_on_download_completed.bind(block, request))
	requests[block] = request
	var error := request.request(endpoint + "?data=" + query.uri_encode(), PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"]))
	if error != OK:
		requests.erase(block)
		request.queue_free()
		_fail_block(block, "OSM-Anfrage für Kartenblock %s konnte nicht gestartet werden (Fehler %d)." % [Grid.key(block), error])
		_start_queued_download()


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, block: Vector2i, request: HTTPRequest) -> void:
	requests.erase(block)
	request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail_block(block, "OSM-Download für Kartenblock %s fehlgeschlagen (HTTP %d, Fehler %d)." % [Grid.key(block), code, result])
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
	if desired_blocks.has(block):
		if block == Vector2i.ZERO:
			_replace_block(block, place)
		else:
			_activate_block(block, place)
	_start_queued_download()


func _store_block(block: Vector2i, place: Dictionary) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
	if directory_error != OK:
		_fail_block(block, "Kartenblock-Cache konnte nicht erstellt werden (Fehler %d)." % directory_error)
		return false
	var path := _cache_path(block)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail_block(block, "Kartenblock konnte nicht zwischengespeichert werden (Fehler %d)." % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(place))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_fail_block(block, "Kartenblock-Cache konnte nicht geschrieben werden (Fehler %d)." % write_error)
		return false
	return true


func _start_queued_download() -> void:
	while not pending_blocks.is_empty() and requests.size() < MAX_CONCURRENT_DOWNLOADS:
		var block: Vector2i = pending_blocks.pop_front()
		var is_loaded: bool = loaded_blocks.has(block) and block != Vector2i.ZERO
		if desired_blocks.has(block) and not is_loaded and not requests.has(block):
			_start_download(block)


func _activate_block(block: Vector2i, place: Dictionary) -> void:
	if not desired_blocks.has(block) or loaded_blocks.has(block):
		return
	var node: Node3D
	if block == Vector2i.ZERO and world.get_node_or_null("OSMMap") != null:
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
	block_loaded.emit(block, place, base_place.origin)


func _replace_block(block: Vector2i, place: Dictionary) -> void:
	if block == Vector2i.ZERO:
		var base_node := world.get_node_or_null("OSMMap")
		if base_node == null:
			_activate_block(block, place)
			return
		if loaded_blocks.has(block):
			block_unloaded.emit(block)
		if not OSMMap.replace_block(base_node, place, map_scale):
			_report_error("Kartenblock %s konnte nicht aufgebaut werden." % Grid.key(block))
			return
		loaded_blocks[block] = {"node": base_node, "data": place}
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
	if block == Vector2i.ZERO or ground_blocks.has(block):
		return
	var ground: StaticBody3D = world.get_node("Ground")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GroundMesh_%s" % Grid.key(block)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(Grid.BLOCK_SIZE * map_scale, 1.0, Grid.BLOCK_SIZE * map_scale)
	var base_mesh: MeshInstance3D = ground.get_node("MeshInstance3D")
	mesh.material = base_mesh.mesh.material
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(float(block.x) * Grid.BLOCK_SIZE * map_scale, 0.0, float(block.y) * Grid.BLOCK_SIZE * map_scale)
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
		return
	boundary_center = center
	var offset := Vector3(float(center.x) * Grid.BLOCK_SIZE * map_scale, 0.0, float(center.y) * Grid.BLOCK_SIZE * map_scale)
	var boundary := world.get_node_or_null("MapBoundary")
	if boundary != null:
		boundary.position = offset


func _report_error(message: String) -> void:
	push_warning(message)
	if world != null and world.has_node("HUD/Status"):
		world.get_node("HUD/Status").text = message


func _fail_block(block: Vector2i, message: String) -> void:
	failed_blocks[block] = Time.get_ticks_msec() + RETRY_DELAY_MS
	_report_error(message)
