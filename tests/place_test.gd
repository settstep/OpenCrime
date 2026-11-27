extends SceneTree

const PlaceStore = preload("res://scripts/place_store.gd")
const Selection = preload("res://scenes/place_selection.tscn")

var original_block_directory := ""


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var places := PlaceStore.available_places()
	if PlaceStore.find_by_id("thalhofen").is_empty() or PlaceStore.find_by_id("gendarmenmarkt").is_empty():
		_fail("Bundled places are unavailable.")
		return
	original_block_directory = PlaceStore.BLOCK_CACHE_DIRECTORY
	PlaceStore.BLOCK_CACHE_DIRECTORY = "user://place_test_empty_cache_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var selection := Selection.instantiate()
	root.add_child(selection)
	await process_frame
	selection._on_map_selected(47.7748417, 10.6034933)
	var chosen := []
	selection.place_chosen.connect(func(place: Dictionary): chosen.append(place))
	selection._on_start_pressed()
	if chosen.size() != 1 or chosen[0].id != "thalhofen" or selection.request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_fail("A saved place was not selected offline.")
		return
	var map = selection.map
	var coordinate: Vector2 = map._coordinates(map._world_pixels(47.77, 10.60))
	if coordinate.distance_to(Vector2(47.77, 10.60)) > 0.0001:
		_fail("Map projection does not round-trip.")
		return
	var latitude := 20.0 + float(Time.get_ticks_usec() % 1000000) / 10000000.0
	var longitude := 30.0
	var bounds := [latitude - 0.001, longitude - 0.001, latitude + 0.001, longitude + 0.001]
	var response := {"elements": [{"type": "way", "id": 123, "tags": {"highway": "residential"}, "geometry": [{"lat": latitude - 0.0005, "lon": longitude}, {"lat": latitude + 0.0005, "lon": longitude}]}]}
	var place := PlaceStore.from_overpass(response, latitude, longitude, bounds, "Testort")
	if place.is_empty() or place.ways[0].id != 123:
		_fail("Valid Overpass data was not converted.")
		return
	var path: String = PlaceStore.DIRECTORY.path_join(place.id + ".json")
	if FileAccess.file_exists(path):
		_fail("Test place already exists; refusing to overwrite it.")
		return
	if PlaceStore.save_place(place) != OK:
		_fail("Place could not be saved.")
		return
	var loaded := PlaceStore.find_by_id(place.id)
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error != OK or loaded.get("id") != place.id or loaded.get("ways", []).size() != 1 or PlaceStore.save_place({}) != ERR_INVALID_DATA:
		_fail("Place persistence or validation failed.")
		return
	response.elements[0].geometry[0].lat = "invalid"
	if not PlaceStore.from_overpass(response, latitude, longitude, bounds, "Test").is_empty():
		_fail("Invalid coordinates were accepted.")
		return
	response.elements[0].geometry[0].lat = latitude - 0.0005
	response.elements.append({"type": "way", "id": 124, "tags": {"building": "yes"}, "geometry": [
		{"lat": latitude - 0.0001, "lon": longitude - 0.0001},
		{"lat": latitude - 0.0001, "lon": longitude + 0.0001},
		{"lat": latitude + 0.0001, "lon": longitude + 0.0001},
		{"lat": latitude + 0.0001, "lon": longitude - 0.0001},
	]})
	if not PlaceStore.from_overpass(response, latitude, longitude, bounds, "Test").is_empty():
		_fail("A start inside a building was accepted.")
		return
	PlaceStore.BLOCK_CACHE_DIRECTORY = original_block_directory
	print("Saved places, offline selection, projection and persistence passed")
	quit(0)


func _fail(reason: String) -> void:
	if not original_block_directory.is_empty():
		PlaceStore.BLOCK_CACHE_DIRECTORY = original_block_directory
	push_error(reason)
	quit(1)
