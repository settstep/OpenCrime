extends SceneTree

const BuildingEdits = preload("res://scripts/building_edits.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")


func _initialize() -> void:
	call_deferred("_test")


func _rectangle(id: int, left: float, right: float, origin: Array) -> Dictionary:
	var zone := Grid.zone_for_origin(origin)
	var projected := Grid.project(origin, zone, true)
	var geometry := []
	for point in [Vector2(left, 0), Vector2(right, 0), Vector2(right, 10), Vector2(left, 10), Vector2(left, 0)]:
		geometry.append(Grid.unproject([projected[0] + point.x, projected[1] + point.y], zone, true))
	return {"id": id, "tags": {"building": "yes", "height": "5"}, "geometry": geometry}


func _test() -> void:
	var origin := [47.7748417, 10.6034933]
	var a := _rectangle(1, 0, 10, origin)
	var b := _rectangle(2, 10, 20, origin)
	var c := _rectangle(3, 20, 30, origin)
	var isolated := _rectangle(4, 40, 50, origin)
	var edits := BuildingEdits.new()
	var result: Dictionary = edits.prepare([a, c, b])
	if result.has("error"):
		_fail("Adjacent buildings could not be merged in arbitrary selection order: " + result.error)
		return
	var merge: Dictionary = result.data.merges[0]
	var polygon := PackedVector2Array()
	for coordinate in merge.result.geometry:
		polygon.append(OSMMap._project(coordinate, origin))
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	if absf(bounds.size.x - 30.0) > 0.02 or absf(bounds.size.y - 10.0) > 0.02 or merge.sources.size() != 3 or merge.result.geometry.size() != 5:
		_fail("Merged outline does not match the combined original footprint.")
		return
	if not edits.prepare([a, isolated]).has("error"):
		_fail("Disconnected buildings must not be joined.")
		return
	var directory := ProjectSettings.globalize_path("user://building_edits_test_" + Crypto.new().generate_random_bytes(8).hex_encode())
	edits.path = directory.path_join("buildings.json")
	if not edits.save(result.data):
		_fail("Could not save building diffs: " + edits.error)
		return
	var reloaded := BuildingEdits.new()
	reloaded.path = edits.path
	if not reloaded.load_file() or reloaded.merges.size() != 1:
		_fail("Saved building diffs did not reload.")
		return
	var place := {"id": "test", "name": "Test", "origin": origin, "bounds": [47.77, 10.60, 47.78, 10.61], "ways": [a, b, c]}
	var effective: Dictionary = reloaded.apply(place)
	if place.ways.size() != 3 or effective.ways.size() != 1 or effective.ways[0]._edit_sources.size() != 3:
		_fail("Applying diffs changed originals or did not replace all buildings: %s vs %s" % [JSON.stringify(a.geometry, "", true, true), JSON.stringify(reloaded.merges[0].sources[0].geometry, "", true, true)])
		return
	var partial: Dictionary = place.duplicate(true)
	partial.ways = [b]
	if reloaded.apply(partial).ways.size() != 1 or not reloaded.apply(partial).ways[0].has("_edit_sources"):
		_fail("A block containing only one source did not receive the merged building.")
		return
	var changed: Dictionary = place.duplicate(true)
	changed.ways[0].geometry[0][0] += 0.001
	if reloaded.apply(changed).ways.size() != 3:
		_fail("A changed OSM source was overwritten without reporting the conflict.")
		return
	if not reloaded.scan_conflicts([partial, changed]) or reloaded.apply(partial).ways[0].has("_edit_sources"):
		_fail("A conflict in another loaded block did not disable the entire merge.")
		return
	if not reloaded.prepare([changed.ways[1], c]).has("error"):
		_fail("Editing a conflicted source silently discarded an existing merge.")
		return
	reloaded.scan_conflicts([place])
	var extension := _rectangle(5, 30, 40, origin)
	var extended: Dictionary = reloaded.prepare([effective.ways[0], extension])
	if extended.has("error") or extended.data.merges.size() != 1 or extended.data.merges[0].sources.size() != 4:
		_fail("An existing merge could not be extended while retaining original sources.")
		return
	if not reloaded.save(extended.data):
		_fail("Existing diff file could not be replaced: " + reloaded.error)
		return
	if DirAccess.remove_absolute(edits.path) != OK or DirAccess.remove_absolute(directory) != OK:
		_fail("Test files could not be cleaned up.")
		return
	print("Building unions, persistence, original data and conflicts passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
