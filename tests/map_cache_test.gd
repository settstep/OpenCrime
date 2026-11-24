extends SceneTree

const MapView = preload("res://scripts/map_view.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var map := Control.new()
	map.set_script(MapView)
	root.add_child(map)
	await process_frame
	var tile := Vector3i(19, int(Time.get_ticks_usec() % 1000000000), 999999)
	var image_path: String = map._tile_path(tile)
	var metadata_path: String = map.CACHE_DIRECTORY.path_join(map._key(tile) + ".json")
	if FileAccess.file_exists(image_path) or FileAccess.file_exists(metadata_path):
		_fail("Test cache files already exist.")
		return
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	map.current_tile = tile
	map._on_tile_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(["Cache-Control: max-age=3600", "ETag: test"]), image.save_png_to_buffer())
	if not FileAccess.file_exists(image_path) or not map._cache_fresh(tile) or map._metadata(tile).get("etag") != "test":
		_fail("A cacheable tile was not saved.")
		return
	map.current_tile = tile
	map._on_tile_completed(HTTPRequest.RESULT_SUCCESS, 304, PackedStringArray(["Cache-Control: no-cache, max-age=3600"]), PackedByteArray())
	if map._cache_fresh(tile):
		_fail("no-cache must require revalidation.")
		return
	map.current_tile = tile
	map._on_tile_completed(HTTPRequest.RESULT_SUCCESS, 304, PackedStringArray(["Cache-Control: no-store"]), PackedByteArray())
	if FileAccess.file_exists(image_path) or FileAccess.file_exists(metadata_path):
		_fail("no-store did not remove the cached tile.")
		return
	print("Tile cache and HTTP cache directives passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
