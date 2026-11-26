extends SceneTree

const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const MapBlockStream = preload("res://scripts/map_block_stream.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	if Grid.block_for_position(Vector2(249.9, -250.0)) != Vector2i.ZERO:
		_fail("The origin block did not include its lower boundary.")
		return
	if Grid.block_for_position(Vector2(250.0, -250.1)) != Vector2i(1, -1):
		_fail("A block boundary was assigned to the wrong tile.")
		return
	if Grid.block_for_position(Vector2(550.0, -500.0), 1.1) != Vector2i(1, -1):
		_fail("The map scale was not applied to block coordinates.")
		return
	var window := Grid.blocks_around(Vector2i(3, -2))
	if window.size() != 9 or not window.has(Vector2i(4, -1)) or window.has(Vector2i(5, -2)):
		_fail("The active window is not a centered 3x3 block grid.")
		return
	var added := Grid.new_blocks(Grid.blocks_around(Vector2i.ZERO), Vector2i(1, 0))
	if added.size() != 3 or added.has(Vector2i.ZERO):
		_fail("Moving the window did not identify only its three new blocks.")
		return
	var origin := [47.7748417, 10.6034933]
	var block := Vector2i(2, -1)
	var bounds := Grid.block_bounds(origin, block)
	var center := Grid.block_origin(origin, block)
	if center[0] <= bounds[0] or center[0] >= bounds[2] or center[1] <= bounds[1] or center[1] >= bounds[3]:
		_fail("The geographic block origin is outside its bounds.")
		return
	var projected_width := OSMMap._project([center[0], bounds[3]], [center[0], bounds[1]]).x
	if absf(projected_width - Grid.BLOCK_SIZE) > 0.1:
		_fail("Geographic block bounds are not 500 meters wide.")
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
	var stream := MapBlockStream.new()
	stream.base_place = {"id": "window_ready_test"}
	for active_block in Grid.blocks_around(Vector2i.ZERO):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	if not stream._window_ready(Vector2i.ZERO):
		_fail("A complete loaded 3x3 area was not considered ready.")
		return
	stream.loaded_blocks[Vector2i.ZERO].data.id = "fallback_place"
	if stream._window_ready(Vector2i.ZERO):
		_fail("The small starting-place fallback incorrectly released the boundary.")
		return
	stream.loaded_blocks[Vector2i.ZERO].data.id = stream.call("_block_id", Vector2i.ZERO)
	stream.loaded_blocks.erase(Vector2i(1, 1))
	if stream._window_ready(Vector2i.ZERO):
		_fail("An incomplete 3x3 area was considered ready.")
		return
	if MapBlockStream.retry_delay_ms(1) != 2000 or MapBlockStream.retry_delay_ms(2) != 4000 or MapBlockStream.retry_delay_ms(5) != 30000 or MapBlockStream.retry_delay_ms(10) != 30000:
		_fail("Block retry delays are not exponentially increasing and capped.")
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
	for active_block in Grid.blocks_around(Vector2i.ZERO):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	stream._update_boundary(Vector2i(1, 0))
	if stream.boundary_center != Vector2i.ZERO or boundary.position != Vector3.ZERO or not status.text.contains("Lade Kartenbereich"):
		_fail("The boundary moved before the next 3x3 area was ready.")
		return
	for active_block in Grid.blocks_around(Vector2i(1, 0)):
		stream.loaded_blocks[active_block] = {"data": {"id": stream.call("_block_id", active_block)}}
	stream._update_boundary(Vector2i(1, 0))
	if stream.boundary_center != Vector2i(1, 0) or boundary.position.x != Grid.BLOCK_SIZE or not status.text.is_empty():
		_fail("The boundary did not advance after all nine blocks became ready.")
		return
	stream.free()
	world.free()
	print("Map block indexing, 3x3 transitions, geographic bounds and OSM validation passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
