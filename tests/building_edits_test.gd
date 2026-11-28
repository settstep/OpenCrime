extends SceneTree

const BuildingEdits = preload("res://scripts/building_edits.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const DataPaths = preload("res://scripts/data_paths.gd")


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
	var concave := PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(8, 3), Vector2(3, 3), Vector2(3, 8), Vector2(0, 8)])
	if OSMMap._building_interior(concave, 0.3).is_empty():
		_fail("A concave footprint could not be hollowed.")
		return
	concave.reverse()
	if OSMMap._building_interior(concave, 0.3).is_empty():
		_fail("Reversing a concave footprint changed its hollowing behavior.")
		return
	var narrow := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0.5), Vector2(0, 0.5)])
	if not OSMMap._building_interior(narrow, 0.3).is_empty():
		_fail("A footprint too narrow for the walls was accepted.")
		return
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
	var single := BuildingEdits.new()
	if not single.set_data({"format": 1, "merges": []}):
		_fail("Older building-edit files without level edits were rejected.")
		return
	var osm_levels: Dictionary = a.duplicate(true)
	osm_levels.tags.erase("height")
	osm_levels.tags["building:levels"] = "2"
	var osm_hollow := single.prepare_hollow(osm_levels, 1, 0.3)
	if osm_hollow.has("error") or not single.set_data(osm_hollow.data):
		_fail("A building with an existing OSM level count could not be hollowed.")
		return
	var osm_place := {"ways": [osm_levels]}
	if single.apply(osm_place).ways[0].get("_hollow_floors", []).size() != 1 or osm_levels.has("_hollow_floors"):
		_fail("Hollowing an OSM building did not preserve the original data.")
		return
	single.set_data({"format": 1, "merges": []})
	if not single.prepare_levels(a, 0).has("error") or not single.prepare_levels(a, 1001).has("error"):
		_fail("Out-of-range level counts were accepted.")
		return
	var open_way: Dictionary = a.duplicate(true)
	open_way.geometry.pop_back()
	var open_edit: Dictionary = single.prepare_levels(open_way, 2)
	if open_edit.has("error") or not single.set_data(open_edit.data):
		_fail("A rendered unclosed building could not receive a level edit.")
		return
	single.set_data({"format": 1, "merges": []})
	var level_result: Dictionary = single.prepare_levels(a, 3)
	single.path = edits.path
	if level_result.has("error") or not single.save(level_result.data) or not single.load_file():
		_fail("Individual level edit could not be saved and reloaded.")
		return
	var adjusted: Dictionary = single.apply(place)
	var adjusted_a: Dictionary = adjusted.ways[0]
	if adjusted_a.tags.has("height") or adjusted_a.tags.get("building:levels") != "3" or OSMMap._building_height(adjusted_a.tags) != 9.0 or a.tags.height != "5" or single.level_edits[0].source.tags.height != "5":
		_fail("Level override did not preserve the original or override the explicit OSM height.")
		return
	var second_edit: Dictionary = single.prepare_levels(adjusted_a, 4)
	if second_edit.has("error") or second_edit.data.level_edits[0].source.tags.height != "5":
		_fail("Editing a level override lost the original OSM building.")
		return
	var merged_with_levels: Dictionary = single.prepare([adjusted_a, b])
	if merged_with_levels.has("error") or not merged_with_levels.data.level_edits.is_empty() or merged_with_levels.data.merges[0].result.tags.get("building:levels") != "3" or merged_with_levels.data.merges[0].sources[0].tags.height != "5":
		_fail("Merging an edited building lost its level override or original source.")
		return
	if not single.set_data(merged_with_levels.data):
		_fail("Merge containing an edited building was rejected.")
		return
	var merged_way: Dictionary = single.apply(place).ways[-1]
	var merged_levels: Dictionary = single.prepare_levels(merged_way, 4)
	if merged_levels.has("error") or merged_levels.data.merges[0].result.tags.get("building:levels") != "4" or merged_levels.data.merges[0].sources.size() != 2:
		_fail("Level edit on a merged building lost the original sources.")
		return
	single.set_data(level_result.data)
	single.scan_conflicts([changed])
	if not single.prepare_levels(adjusted_a, 4).has("error") or single.apply(place).ways[0].tags.has("building:levels") or not single.set_blocked([1]):
		_fail("A conflicted level edit was applied or allowed to be edited.")
		return
	single.scan_conflicts([place])
	if not single.prepare_hollow(adjusted_a, 4, 0.3).has("error") or not single.prepare_hollow(adjusted_a, 1, 0.0).has("error") or not single.prepare_hollow(adjusted_a, 1, 20.0).has("error"):
		_fail("Invalid floors or wall thicknesses were accepted.")
		return
	var hollow := single.prepare_hollow(adjusted_a, 2, 0.3)
	if hollow.has("error") or not single.save(hollow.data) or not single.load_file():
		_fail("A hollow floor could not be saved and reloaded: %s" % hollow)
		return
	var hollow_way: Dictionary = single.apply(place).ways[0]
	if hollow_way._hollow_floors.size() != 1 or int(hollow_way._hollow_floors[0].floor) != 2 or not is_equal_approx(float(hollow_way._hollow_floors[0].wall_thickness), 0.3):
		_fail("The saved hollow floor was not applied.")
		return
	if not single.prepare_hollow(hollow_way, 2, 0.3).has("error") or not single.prepare_levels(hollow_way, 1).has("error") or not single.prepare([hollow_way, b]).has("error") or not single.prepare([a, b]).has("error"):
		_fail("An existing room was overwritten by a duplicate edit, reduced level count or merge.")
		return
	var extended_levels := single.prepare_levels(hollow_way, 4)
	if extended_levels.has("error") or extended_levels.data.level_edits[0].hollow_floors.size() != 1:
		_fail("Increasing the level count discarded the hollow floor.")
		return
	if not single.prepare_wall(hollow_way, 1, Vector2(3, -0.6), 0.3).has("error") or not single.prepare_wall(hollow_way, 2, Vector2(3, -0.6), -1.0).has("error"):
		_fail("A wall was accepted on a solid floor or with an invalid thickness.")
		return
	var wall := single.prepare_wall(hollow_way, 2, Vector2(3, -0.6), 0.3)
	if wall.has("error") or not single.save(wall.data) or not single.load_file():
		_fail("An interior wall could not be saved and reloaded: %s" % wall)
		return
	hollow_way = single.apply(place).ways[0]
	if hollow_way._hollow_floors[0].get("walls", []).size() != 1 or single.prepare_levels(hollow_way, 4).data.level_edits[0].hollow_floors[0].walls.size() != 1:
		_fail("The saved wall was lost when applying or changing the floor count.")
		return
	var moved_wall := single.prepare_wall_change(hollow_way, 2, false, 0, 1.0, 0.5)
	if moved_wall.has("error") or not single.save(moved_wall.data) or not single.load_file():
		_fail("An interior wall change could not be saved and loaded: %s" % moved_wall)
		return
	hollow_way = single.apply(place).ways[0]
	if not is_equal_approx(float(hollow_way._hollow_floors[0].walls[0].thickness), 0.5):
		_fail("The edited interior wall thickness was not preserved.")
		return
	var moved_outer := single.prepare_wall_change(hollow_way, 2, true, 0, -0.5, 0.4)
	if moved_outer.has("error") or not single.save(moved_outer.data) or not single.load_file():
		_fail("An exterior wall change could not be saved and loaded: %s" % moved_outer)
		return
	hollow_way = single.apply(place).ways[0]
	if not hollow_way._hollow_floors[0].has("outline") or not is_equal_approx(float(hollow_way._hollow_floors[0].wall_thickness), 0.4):
		_fail("The per-floor exterior change was not preserved.")
		return
	var bad_data := single.data()
	bad_data.level_edits[0].hollow_floors[0].walls[0].thickness = -1
	if single.set_data(bad_data):
		_fail("Invalid saved wall data was accepted.")
		return
	single.scan_conflicts([changed])
	if single.apply(place).ways[0].has("_hollow_floors"):
		_fail("A conflicted hollow floor was applied.")
		return
	DataPaths.root_override = directory
	var defaults := BuildingEdits.load_wall_thickness()
	var config_path := directory.path_join("config/building_editor.json")
	if defaults.has("error") or not is_equal_approx(defaults.thickness, 0.3) or not FileAccess.file_exists(config_path):
		_fail("The default wall-thickness settings were not created.")
		return
	var config := FileAccess.open(config_path, FileAccess.WRITE)
	config.store_string("{\"wall_thickness_m\": 0.6}")
	config.close()
	var customized := BuildingEdits.load_wall_thickness()
	if customized.has("error") or not is_equal_approx(customized.thickness, 0.6):
		_fail("The configured wall thickness was not used.")
		return
	config = FileAccess.open(config_path, FileAccess.WRITE)
	config.store_string("{\"wall_thickness_m\": -1}")
	config.close()
	if not BuildingEdits.load_wall_thickness().has("error"):
		_fail("Invalid wall-thickness settings were accepted.")
		return
	if DirAccess.remove_absolute(config_path) != OK or DirAccess.remove_absolute(config_path.get_base_dir()) != OK:
		_fail("Test settings could not be cleaned up.")
		return
	if DirAccess.remove_absolute(edits.path) != OK or DirAccess.remove_absolute(directory) != OK:
		_fail("Test files could not be cleaned up.")
		return
	print("Building unions, persistence, original data and conflicts passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
