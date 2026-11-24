extends SceneTree

const Selection = preload("res://scenes/place_selection.tscn")
const PlaceStore = preload("res://scripts/place_store.gd")


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
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		_fail("Could not start local HTTP test server.")
		return
	ProjectSettings.set_setting("opencrime/osm/overpass_url", "http://127.0.0.1:%d/interpreter" % server.get_local_port())
	var selection := Selection.instantiate()
	root.add_child(selection)
	await process_frame
	var latitude := 20.0 + float(Time.get_ticks_usec() % 1000000) / 10000000.0
	var longitude := 30.0
	selection._on_map_selected(latitude, longitude)
	selection._on_start_pressed()
	if not await _respond(server, 500, "{}") or not await _wait_request(selection) or not selection.info.text.contains("fehlgeschlagen"):
		_fail("HTTP error was not shown.")
		return
	var chosen := []
	selection.place_chosen.connect(func(place: Dictionary): chosen.append(place))
	selection._on_start_pressed()
	var response := {"elements": [{"type": "way", "id": 123, "tags": {"highway": "residential"}, "geometry": [{"lat": latitude - 0.0005, "lon": longitude}, {"lat": latitude + 0.0005, "lon": longitude}]}]}
	if not await _respond(server, 200, JSON.stringify(response)) or not await _wait_request(selection) or chosen.size() != 1:
		_fail("Valid download was not selected.")
		return
	var id: String = chosen[0].id
	var loaded := PlaceStore.find_by_id(id)
	var path: String = PlaceStore.DIRECTORY.path_join(id + ".json")
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if loaded.is_empty() or error != OK:
		_fail("Downloaded place was not persisted.")
		return
	print("HTTP error, download and persistence passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
