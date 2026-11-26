extends SceneTree

const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")


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
	print("Map block indexing, 3x3 transitions, geographic bounds and OSM validation passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
