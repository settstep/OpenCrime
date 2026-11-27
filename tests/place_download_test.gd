extends SceneTree

const Selection = preload("res://scenes/place_selection.tscn")
const PlaceStore = preload("res://scripts/place_store.gd")
const Grid = preload("res://scripts/map_block_grid.gd")

var last_request := ""
var original_places_directory := ""
var original_block_directory := ""
var test_places_directory := ""
var test_block_directory := ""
var saved_place_path := ""
var saved_block_path := ""
var test_server: TCPServer

func _initialize() -> void:
	call_deferred("_test")


func _respond(server: TCPServer, code: int, body: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not server.is_connection_available() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not server.is_connection_available():
		return false
	var connection := server.take_connection()
	while connection.get_available_bytes() == 0 and Time.get_ticks_msec() < deadline:
		connection.poll()
		await process_frame
	var received := connection.get_data(connection.get_available_bytes())
	if received[0] != OK:
		return false
	last_request = received[1].get_string_from_utf8()
	var data := body.to_utf8_buffer()
	connection.put_data(("HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, data.size()]).to_utf8_buffer())
	connection.put_data(data)
	await create_timer(0.1).timeout
	connection.disconnect_from_host()
	return true


func _wait_request(selection: Control) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while selection.start_button.disabled and Time.get_ticks_msec() < deadline:
		await process_frame
	return not selection.start_button.disabled


func _test() -> void:
	original_places_directory = PlaceStore.DIRECTORY
	original_block_directory = PlaceStore.BLOCK_CACHE_DIRECTORY
	var test_suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	test_places_directory = "user://place_download_test_" + test_suffix + "/places"
	test_block_directory = "user://place_download_test_" + test_suffix + "/map_blocks"
	PlaceStore.DIRECTORY = test_places_directory
	PlaceStore.BLOCK_CACHE_DIRECTORY = test_block_directory
	test_server = TCPServer.new()
	if test_server.listen(0, "127.0.0.1") != OK:
		_fail("Could not start local HTTP test server.")
		return
	ProjectSettings.set_setting("opencrime/osm/overpass_url", "http://127.0.0.1:%d/interpreter" % test_server.get_local_port())
	var selection := Selection.instantiate()
	root.add_child(selection)
	await process_frame
	var latitude := 20.0 + float(Time.get_ticks_usec() % 1000000) / 10000000.0
	var longitude := 30.0
	selection._on_map_selected(latitude, longitude)
	if not selection.info.text.contains("1 × 1 km"):
		_fail("The new-place information did not describe the 1km UTM block.")
		return
	selection._on_start_pressed()
	if not await _respond(test_server, 500, "{}") or not await _wait_request(selection) or not selection.info.text.contains("fehlgeschlagen"):
		_fail("HTTP error was not shown.")
		return
	var chosen := []
	selection.place_chosen.connect(func(place: Dictionary): chosen.append(place))
	selection._on_start_pressed()
	var selected_origin := [latitude, longitude]
	var block := Grid.block_at_origin(selected_origin)
	var block_id := "block_" + Grid.tile_id(block, selected_origin)
	var expected_bounds := Grid.block_bounds(selected_origin, block)
	var latitude_delta := 165.0 / 111320.0
	var longitude_delta := 165.0 / (111320.0 * cos(deg_to_rad(latitude)))
	var expected_place_bounds := [
		latitude - latitude_delta,
		longitude - longitude_delta,
		latitude + latitude_delta,
		longitude + longitude_delta,
	]
	var expected_query := PlaceStore.block_query(expected_bounds)
	if not last_request.contains(expected_query.uri_encode()) or not expected_query.contains('node["emergency"~"^(fire_hydrant|defibrillator)$"]') or not expected_query.contains('node["traffic_sign"]'):
		_fail("The Overpass query did not request the selected 1km UTM block.")
		return
	var response := {"elements": [
		{"type": "way", "id": 123, "tags": {"highway": "residential"}, "geometry": [{"lat": latitude - 0.0005, "lon": longitude}, {"lat": latitude + 0.0005, "lon": longitude}]},
		{"type": "node", "id": 125, "tags": {"highway": "traffic_signals"}, "lat": latitude + 0.0001, "lon": longitude + 0.0001},
		{"type": "node", "id": 126, "tags": {"emergency": "fire_hydrant"}, "lat": latitude + 0.0002, "lon": longitude + 0.0002},
		{"type": "way", "id": 124, "tags": {"amenity": "parking"}, "geometry": [
			{"lat": latitude + 0.0005, "lon": longitude + 0.0005},
			{"lat": latitude + 0.0006, "lon": longitude + 0.0005},
			{"lat": latitude + 0.0006, "lon": longitude + 0.0006},
			{"lat": latitude + 0.0005, "lon": longitude + 0.0005},
		]},
	]}
	if not await _respond(test_server, 200, JSON.stringify(response)) or not await _wait_request(selection) or chosen.size() != 1:
		_fail("Valid download was not selected.")
		return
	var id: String = chosen[0].id
	saved_place_path = PlaceStore.DIRECTORY.path_join(id + ".json")
	saved_block_path = PlaceStore.block_cache_path(block_id)
	var loaded := PlaceStore.find_by_id(id)
	var cached_block := PlaceStore.read_block_cache(block, selected_origin)
	if loaded.is_empty() or loaded.ways.size() != 2 or loaded.ways[1].tags.get("amenity") != "parking" or loaded.nodes.size() != 2:
		_fail("Downloaded place did not retain roads, parking, and point features.")
		return
	if Grid.block_at_origin(loaded.origin) != block:
		_fail("The saved safe start point did not belong to the downloaded UTM block.")
		return
	if cached_block.get("id", "") != block_id or cached_block.ways.size() != 2 or cached_block.nodes.size() != 2 or cached_block.get("block_data_version", 0) != PlaceStore.BLOCK_DATA_VERSION:
		_fail("The complete, versioned UTM block was not cached before the game started.")
		return
	for index in 4:
		if not is_equal_approx(float(loaded.bounds[index]), float(expected_place_bounds[index])) or not is_equal_approx(float(cached_block.bounds[index]), float(expected_bounds[index])):
			_fail("The saved place area or canonical block bounds are incorrect.")
			return
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_place_path))
	if remove_error != OK:
		_fail("Could not remove the saved place before testing the block-cache hit.")
		return
	var outdated_block := cached_block.duplicate(true)
	outdated_block.erase("block_data_version")
	outdated_block.erase("nodes")
	if PlaceStore.write_block_cache(block_id, outdated_block) != OK:
		_fail("Could not prepare an outdated cache block for the manual-refresh test.")
		return
	selection.queue_free()
	await process_frame
	var cached_selection := Selection.instantiate()
	root.add_child(cached_selection)
	await process_frame
	var cached_chosen := []
	cached_selection.place_chosen.connect(func(place: Dictionary): cached_chosen.append(place))
	cached_selection._on_map_selected(latitude, longitude)
	if not cached_selection.info.text.contains("fehlen noch") or cached_selection.name_field.editable or not cached_selection.refresh_button.visible:
		_fail("A cached block did not select the direct, unnamed start mode.")
		return
	cached_selection._on_start_pressed()
	if cached_chosen.size() != 1 or cached_selection.request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_fail("A cached UTM block did not allow starting without an HTTP request.")
		return
	var cached_place_path: String = PlaceStore.DIRECTORY.path_join(cached_chosen[0].id + ".json")
	if FileAccess.file_exists(cached_place_path):
		_fail("Starting from a cached block created a saved place.")
		return
	var chosen_origin: Array = cached_chosen[0].origin
	var longitude_scale := 111320.0 * cos(deg_to_rad(latitude))
	var spawn_distance := Vector2(
		(float(chosen_origin[1]) - longitude) * longitude_scale,
		(latitude - float(chosen_origin[0])) * 111320.0
	).length()
	if spawn_distance > 100.0:
		_fail("The cached-block start was not near the clicked coordinates.")
		return
	cached_selection._on_refresh_pressed()
	if not await _respond(test_server, 200, JSON.stringify(response)) or not await _wait_request(cached_selection):
		_fail("A manual refresh did not download the selected cached block.")
		return
	var refreshed_block := PlaceStore.read_block_cache(block, selected_origin)
	if refreshed_block.get("block_data_version", 0) != PlaceStore.BLOCK_DATA_VERSION or refreshed_block.get("nodes", []).size() != 2:
		_fail("The manual refresh did not replace the old cache with traffic and emergency objects.")
		return
	if not cached_selection.info.text.contains("aktualisiert") or FileAccess.file_exists(cached_place_path):
		_fail("Manual refresh did not report success or created a saved place.")
		return
	cached_selection.queue_free()
	await process_frame
	var reopened_selection := Selection.instantiate()
	root.add_child(reopened_selection)
	await process_frame
	var reopened_chosen := []
	reopened_selection.place_chosen.connect(func(place: Dictionary): reopened_chosen.append(place))
	reopened_selection._on_map_selected(latitude, longitude)
	if not reopened_selection.info.text.contains("Gecachter") or reopened_selection.info.text.contains("fehlen noch"):
		_fail("A refreshed block was not recognized when reopening the place selection.")
		return
	reopened_selection._on_start_pressed()
	if reopened_chosen.size() != 1 or reopened_selection.request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_fail("The refreshed block did not allow starting without another download.")
		return
	_cleanup(reopened_selection)
	print("OSM traffic/emergency download, cache-version refresh, and direct cached start passed")
	quit(0)


func _cleanup(selection: Control = null) -> void:
	if selection != null and is_instance_valid(selection):
		selection.queue_free()
	if test_server != null and test_server.is_listening():
		test_server.stop()
	for path in [saved_place_path, saved_block_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for directory in [test_places_directory, test_block_directory]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	for directory in [test_places_directory.get_base_dir(), test_block_directory.get_base_dir()]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	PlaceStore.DIRECTORY = original_places_directory
	PlaceStore.BLOCK_CACHE_DIRECTORY = original_block_directory


func _fail(reason: String) -> void:
	_cleanup()
	push_error(reason)
	quit(1)
