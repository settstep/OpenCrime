extends SceneTree

const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const MapBlockStream = preload("res://scripts/map_block_stream.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var origin := [47.7748417, 10.6034933]
	var zone := Grid.zone_for_origin(origin)
	if zone != 32 or not Grid.is_northern_hemisphere(origin):
		_fail("The selected place was assigned to the wrong UTM zone.")
		return
	var projected := Grid.project(origin, zone, true)
	var geographic := Grid.unproject(projected, zone, true)
	if geographic.size() != 2 or absf(geographic[0] - origin[0]) > 0.000001 or absf(geographic[1] - origin[1]) > 0.000001:
		_fail("UTM coordinates did not round-trip.")
		return
	var southern_origin := [-33.8688, 151.2093]
	var southern_zone := Grid.zone_for_origin(southern_origin)
	var southern_projected := Grid.project(southern_origin, southern_zone, false)
	var southern_geographic := Grid.unproject(southern_projected, southern_zone, false)
	if southern_zone != 56 or absf(southern_geographic[0] - southern_origin[0]) > 0.000001 or absf(southern_geographic[1] - southern_origin[1]) > 0.000001:
		_fail("Southern-hemisphere UTM coordinates did not round-trip.")
		return

	var block := Grid.block_at_origin(origin)
	if Grid.block_for_position(Vector2.ZERO, 1.0, origin) != block:
		_fail("The selected coordinate was not assigned to its UTM block.")
		return
	var center := Grid.block_origin(origin, block)
	var bounds := Grid.block_bounds(origin, block)
	if center.size() != 2 or bounds.size() != 4 or center[0] <= bounds[0] or center[0] >= bounds[2] or center[1] <= bounds[1] or center[1] >= bounds[3]:
		_fail("The UTM block center is outside its geographic bounds.")
		return
	var center_projected := Grid.project(center, zone, true)
	var east_center := Grid.project(Grid.block_origin(origin, block + Vector2i.RIGHT), zone, true)
	var north_center := Grid.project(Grid.block_origin(origin, block + Vector2i(0, 1)), zone, true)
	if absf(east_center[0] - center_projected[0] - Grid.BLOCK_SIZE) > 0.001 or absf(north_center[1] - center_projected[1] - Grid.BLOCK_SIZE) > 0.001:
		_fail("Neighboring UTM blocks are not 1,000 meters apart.")
		return
	var nearby_origin := Grid.unproject([center_projected[0] + 10.0, center_projected[1] + 10.0], zone, true)
	var same_block := Grid.block_at_origin(nearby_origin)
	if same_block != block or Grid.tile_id(same_block, nearby_origin) != Grid.tile_id(block, origin):
		_fail("A block ID changed when the same area was selected from another point.")
		return
	var equator_coordinate := [0.0001, 9.2]
	var northern_reference := [0.001, 9.2]
	var southern_reference := [-0.001, 9.2]
	if Grid.tile_id(Grid.block_for_coordinate(equator_coordinate, northern_reference), northern_reference) != Grid.tile_id(Grid.block_for_coordinate(equator_coordinate, southern_reference), southern_reference):
		_fail("UTM false northing changed a block ID across the equator.")
		return
	var window := Grid.blocks_around(block)
	if window.size() != 9 or not window.has(block + Vector2i(1, 1)) or window.has(block + Vector2i(2, 0)):
		_fail("The active window is not a centered 3x3 block grid.")
		return
	var added := Grid.new_blocks(Grid.blocks_around(block), block + Vector2i.RIGHT)
	if added.size() != 3 or added.has(block):
		_fail("Moving the window did not identify only its three new blocks.")
		return
	var data := PlaceStore.from_overpass_block(
		{"elements": [{"type": "way", "id": 1, "tags": {"highway": "residential"}, "geometry": [{"lat": center[0], "lon": center[1]}]}]},
		center,
		bounds,
		"block_test"
	)
	if not PlaceStore.is_valid(data) or data.ways.size() != 1:
		_fail("Valid block OSM data was rejected.")
		return
	var json_data: Variant = JSON.parse_string(JSON.stringify(data))
	if not json_data is Dictionary or not PlaceStore.is_valid(json_data) or PlaceStore.block_needs_refresh(json_data):
		_fail("A current block became invalid or outdated after JSON serialization.")
		return
	for invalid_version in [0, -1, 1.5, "2", true, null]:
		var invalid_data: Dictionary = data.duplicate(true)
		invalid_data["block_data_version"] = invalid_version
		if PlaceStore.is_valid(invalid_data):
			_fail("An invalid block data version was accepted: %s" % str(invalid_version))
			return
	var legacy_data: Dictionary = data.duplicate(true)
	legacy_data.erase("block_data_version")
	legacy_data.erase("nodes")
	if not PlaceStore.is_valid(legacy_data) or not PlaceStore.block_needs_refresh(legacy_data):
		_fail("A legacy block was not readable and marked for refresh.")
		return

	var stream := MapBlockStream.new()
	stream.base_place = {"id": "window_ready_test", "origin": origin}
	stream.base_block = block
	var cache_path := stream._cache_path(block)
	stream.base_place.id = "different_selected_place"
	if stream._cache_path(block) != cache_path:
		_fail("The OSM block cache path still depends on the selected place.")
		return
	for active_block in Grid.blocks_around(block):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	if not stream._window_ready(block):
		_fail("A complete loaded 3x3 area was not considered ready.")
		return
	stream.loaded_blocks[block].data.id = "fallback_place"
	if stream._window_ready(block):
		_fail("The small starting-place fallback incorrectly released the boundary.")
		return
	stream.loaded_blocks[block].data.id = stream.call("_block_id", block)
	stream.loaded_blocks.erase(block + Vector2i(1, 1))
	if stream._window_ready(block):
		_fail("An incomplete 3x3 area was considered ready.")
		return
	if MapBlockStream.retry_delay_ms(1) != 2000 or MapBlockStream.retry_delay_ms(2) != 4000 or MapBlockStream.retry_delay_ms(5) != 32000 or MapBlockStream.retry_delay_ms(6) != 64000 or MapBlockStream.retry_delay_ms(10) != 120000:
		_fail("Block retry delays are not exponentially increasing and capped.")
		return
	if MapBlockStream.retry_after_delay_ms(PackedStringArray(["retry-after: 30"]), 0.0) != 30000:
		_fail("A numeric Retry-After header was not parsed.")
		return
	if MapBlockStream.retry_after_delay_ms(PackedStringArray(["Retry-After: Thu, 01 Jan 1970 00:01:00 GMT"]), 0.0) != 60000:
		_fail("An HTTP-date Retry-After header was not parsed.")
		return
	if MapBlockStream.retry_after_delay_ms(PackedStringArray(["Retry-After: not-a-date"]), 0.0) != -1:
		_fail("An invalid Retry-After header was accepted.")
		return
	if MapBlockStream.retry_after_delay_ms(PackedStringArray(["Retry-After: Mon, 31 Feb 1970 00:01:00 GMT"]), 0.0) != -1:
		_fail("An invalid HTTP-date Retry-After header was accepted.")
		return
	if MapBlockStream.retry_delay_for_response(1, 429, PackedStringArray(), 0.0) != 60000:
		_fail("A rate-limited response did not receive the fallback cooldown.")
		return
	if MapBlockStream.retry_delay_for_response(2, 429, PackedStringArray(["Retry-After: 90"]), 0.0) != 90000:
		_fail("A rate-limited response did not honor Retry-After.")
		return
	if MapBlockStream.retry_delay_for_response(4, 429, PackedStringArray(["Retry-After: 3"]), 0.0) != 16000:
		_fail("A short Retry-After value bypassed the exponential rate-limit backoff.")
		return

	var world := Node3D.new()
	var boundary := Node3D.new()
	boundary.name = "MapBoundary"
	world.add_child(boundary)
	var hud := Node.new()
	hud.name = "HUD"
	var status := Label.new()
	status.name = "Status"
	hud.add_child(status)
	world.add_child(hud)
	stream.world = world
	stream.loaded_blocks.clear()
	stream.base_place.origin = origin
	var original_cache_directory: String = stream.CACHE_DIRECTORY
	var test_cache_directory := "user://map_block_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	stream.CACHE_DIRECTORY = test_cache_directory
	var cache_data := PlaceStore.from_overpass_block(
		{"elements": []},
		Grid.block_origin(origin, block),
		Grid.block_bounds(origin, block),
		stream.call("_block_id", block)
	)
	if cache_data.is_empty() or not stream.call("_store_block", block, cache_data) or PlaceStore.read_block_cache(block, origin, test_cache_directory).get("id", "") != stream.call("_block_id", block):
		_fail("The map stream did not persist a validated block in the shared cache.")
		return
	var cached_path := stream._cache_path(block)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(cached_path)) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(test_cache_directory)) != OK:
		_fail("The map block cache test data could not be removed.")
		return
	stream.CACHE_DIRECTORY = original_cache_directory
	stream.boundary_center = block
	for active_block in Grid.blocks_around(block):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	var old_boundary_position := Grid.block_local_center(origin, block)
	boundary.position = Vector3(old_boundary_position.x, 0.0, old_boundary_position.y)
	var next_block := block + Vector2i.RIGHT
	stream._update_boundary(next_block)
	if stream.boundary_center != block or not status.text.contains("Lade Kartenbereich"):
		_fail("The boundary moved before the next 3x3 area was ready.")
		return
	for active_block in Grid.blocks_around(next_block):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	stream._update_boundary(next_block)
	var new_boundary_position := Grid.block_local_center(origin, next_block)
	if stream.boundary_center != next_block or absf(boundary.position.x - new_boundary_position.x) > 0.001 or not status.text.is_empty():
		_fail("The boundary did not advance after all nine blocks became ready.")
		return
	stream.free()
	world.free()
	print("UTM map block IDs, 1km grid, 3x3 transitions, retries and OSM validation passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
