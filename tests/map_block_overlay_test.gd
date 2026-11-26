extends SceneTree

const Grid = preload("res://scripts/map_block_grid.gd")
const MapView = preload("res://scripts/map_view.gd")
const PlaceStore = preload("res://scripts/place_store.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var test_directory := "user://map_block_overlay_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var origins: Array[Array] = [
		[47.7748417, 10.6034933],
		[-33.8688, 151.2093],
		[0.001, 9.2],
	]
	for origin in origins:
		var block := Grid.block_at_origin(origin)
		var block_id := "block_" + Grid.tile_id(block, origin)
		var place := PlaceStore.from_overpass_block(
			{"elements": []},
			Grid.block_origin(origin, block),
			Grid.block_bounds(origin, block),
			block_id
		)
		if place.is_empty() or PlaceStore.write_block_cache(block_id, place, test_directory) != OK:
			_fail("Could not create a valid test block cache.")
			return

	var map := Control.new()
	map.set_script(MapView)
	map.BLOCK_CACHE_DIRECTORY = test_directory
	map.size = Vector2(800, 800)
	root.add_child(map)
	map.map_error.connect(func(message: String): _fail(message))
	var no_places: Array[Dictionary] = []
	map.set_places(no_places)
	await process_frame
	if map.cached_blocks.size() != origins.size():
		_fail("The world map did not discover every cached UTM block.")
		return

	for origin in origins:
		var block := Grid.block_at_origin(origin)
		var expected := Grid.block_origin(origin, block)
		var expected_center := Vector2(float(expected[0]), float(expected[1]))
		var found := false
		for polygon: PackedVector2Array in map.cached_blocks:
			if polygon.size() != 4:
				continue
			var center := Vector2.ZERO
			for corner in polygon:
				center += corner
			center /= float(polygon.size())
			if center.distance_to(expected_center) < 0.001:
				found = true
				break
		if not found:
			_fail("A cached UTM block was projected to the wrong geographic area.")
			return

	map.center = Vector2(47.7748417, 10.6034933)
	var top_left: Vector2 = map._world_pixels(map.center.x, map.center.y) - map.size / 2.0
	var screen_points: PackedVector2Array = map._cached_block_screen_points(map.cached_blocks[0], top_left)
	if screen_points.size() != 4:
		_fail("The cached block did not produce a world-map polygon.")
		return
	for point in screen_points:
		if not point.is_finite():
			_fail("A cached block polygon contained invalid screen coordinates.")
			return

	map.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(ProjectSettings.globalize_path(test_directory)):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory).path_join(filename)) != OK:
			_fail("The temporary cache file could not be removed.")
			return
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory)) != OK:
		_fail("The temporary cache directory could not be removed.")
		return
	print("Cached UTM block discovery and world-map projection passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
