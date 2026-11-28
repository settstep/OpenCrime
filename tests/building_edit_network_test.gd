extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const BuildingEdits = preload("res://scripts/building_edits.gd")
const DataPaths = preload("res://scripts/data_paths.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const Grid = preload("res://scripts/map_block_grid.gd")

var role := ""
var directory := ""
var world: Node3D


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _way(id: int, left: float, origin: Array) -> Dictionary:
	var projected := Grid.project(origin, Grid.zone_for_origin(origin), true)
	var geometry := []
	for point in [Vector2(left, 0), Vector2(left + 10, 0), Vector2(left + 10, 10), Vector2(left, 10), Vector2(left, 0)]:
		geometry.append(Grid.unproject([projected[0] + point.x, projected[1] + point.y], Grid.zone_for_origin(origin), true))
	return {"id": id, "tags": {"building": "yes", "height": "5"}, "geometry": geometry}


func _test() -> void:
	var port := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--root="):
			directory = arg.trim_prefix("--root=")
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	if role not in ["host", "client"] or directory.is_empty() or port == 0:
		_fail("Missing test arguments.")
		return
	DataPaths.root_override = directory.path_join(role)
	PlaceStore.BLOCK_CACHE_DIRECTORY = DataPaths.path("map_blocks")
	var origin := [47.7748417, 10.6034933]
	var a := _way(1, 0, origin)
	var b := _way(2, 10, origin)
	var c := _way(3, 20, origin)
	var place := {"id": "test", "name": "Test", "origin": origin, "bounds": [47.77, 10.60, 47.78, 10.61], "ways": [a, b, c]}
	var peer := ENetMultiplayerPeer.new()
	if role == "host":
		var edits := BuildingEdits.new()
		var prepared: Dictionary = edits.prepare([a, b])
		if prepared.has("error") or not edits.save(prepared.data):
			_fail("Could not prepare persisted host edits.")
			return
		var levels: Dictionary = edits.prepare_levels(c, 2)
		if levels.has("error") or not edits.save(levels.data):
			_fail("Could not prepare persisted host level edit.")
			return
		if peer.create_server(port, 4) != OK:
			_fail("Could not start test server.")
			return
	else:
		if peer.create_client("127.0.0.1", port) != OK:
			_fail("Could not connect test client.")
			return
	root.multiplayer.multiplayer_peer = peer
	world = MainScene.instantiate()
	if role == "host" and not OSMMap.populate(world, place):
		_fail("Could not build host map.")
		return
	world.set_script(NetworkGame)
	if role == "host":
		world.place_data = place
	else:
		world.client_waiting_for_map = true
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 20000
	if role == "host":
		while not FileAccess.file_exists(directory.path_join("ready.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("ready.flag")):
			_fail("Client did not receive the initial server edit.")
			return
		world.map_block_stream.set_process(false)
		var extra_block: Vector2i = world.map_block_stream.base_block + Vector2i(5, 0)
		var extra := {
			"id": "block_" + Grid.tile_id(extra_block, origin),
			"name": "Extra",
			"origin": Grid.block_origin(origin, extra_block),
			"bounds": Grid.block_bounds(origin, extra_block),
			"ways": [],
		}
		world.map_block_stream.desired_blocks[extra_block] = true
		world.refreshing_building_edits = true
		world.map_block_stream._activate_block(extra_block, extra)
		world.refreshing_building_edits = false
		var block_ready := FileAccess.open(directory.path_join("block_ready.flag"), FileAccess.WRITE)
		block_ready.close()
		while not FileAccess.file_exists(directory.path_join("block_received.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("block_received.flag")):
			_fail("Client could not request an already loaded server block.")
			return
		var standalone: StaticBody3D = world.get_node("OSMMap/Building_3")
		var standalone_message: String = world._commit_building_levels(standalone.get_meta("measurement_way"), 3)
		if standalone_message != "Etagenzahl wurde gespeichert." or world.get_node("OSMMap/Building_3").get_child_count() != 6:
			_fail("Live standalone level edit failed: " + standalone_message)
			return
		while not FileAccess.file_exists(directory.path_join("standalone_levels.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("standalone_levels.flag")):
			_fail("Client did not receive the standalone level edit.")
			return
		var building: StaticBody3D = world.get_node("OSMMap/Building_1")
		var level_message: String = world._commit_building_levels(building.get_meta("measurement_way"), 4)
		if level_message != "Etagenzahl wurde gespeichert." or world.get_node("OSMMap/Building_1").get_child_count() != 8:
			_fail("Live server level edit failed: " + level_message)
			return
		while not FileAccess.file_exists(directory.path_join("levels.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("levels.flag")):
			_fail("Client did not receive the live level edit.")
			return
		building = world.get_node("OSMMap/Building_1")
		var result: String = world._commit_building_merge([building.get_meta("measurement_way"), c])
		if result != "Gebäude wurden zusammengefasst und gespeichert.":
			_fail("Live server edit failed: " + result)
			return
		while not FileAccess.file_exists(directory.path_join("done.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("done.flag")):
			_fail("Client did not receive the live server edit.")
			return
		building = world.get_node("OSMMap/Building_1")
		var hollow_message: String = world._commit_building_hollow(building.get_meta("measurement_way"), 2)
		if hollow_message != "Etage wurde ausgehöhlt und gespeichert." or not world.get_node("OSMMap/Building_1").has_node("FloorPreview_2"):
			_fail("Live server floor edit failed: " + hollow_message)
			return
		while not FileAccess.file_exists(directory.path_join("hollow.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("hollow.flag")):
			_fail("Client did not receive the hollow floor.")
			return
		building = world.get_node("OSMMap/Building_1")
		var edited_way: Dictionary = building.get_meta("measurement_way")
		var local_points := OSMMap._building_points(edited_way, edited_way.geometry[0])
		var interior := OSMMap._building_interior(local_points, 0.3)
		var cursor := (interior[0] + interior[1]) * 0.5
		var wall_message: String = world._commit_building_wall(edited_way, 2, cursor, 0.3)
		if wall_message != "Innenwand wurde gespeichert." or not world.get_node("OSMMap/Building_1").has_node("InteriorWall_2_1"):
			_fail("Live server wall edit failed: " + wall_message)
			return
		while not FileAccess.file_exists(directory.path_join("wall.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("wall.flag")):
			_fail("Client did not receive the interior wall.")
			return
		building = world.get_node("OSMMap/Building_1")
		var changed_wall_message: String = world._commit_building_wall_change(building.get_meta("measurement_way"), 2, false, 0, 1.0, 0.5)
		if changed_wall_message != world.BUILDING_WALL_CHANGE_SUCCESS:
			_fail("Live server wall change failed: " + changed_wall_message)
			return
		while not FileAccess.file_exists(directory.path_join("wall_changed.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("wall_changed.flag")):
			_fail("Client did not receive the changed interior wall.")
			return
		building = world.get_node("OSMMap/Building_1")
		var changed_outer_message: String = world._commit_building_wall_change(building.get_meta("measurement_way"), 2, true, 0, -0.5, 0.4)
		if changed_outer_message != world.BUILDING_WALL_CHANGE_SUCCESS:
			_fail("Live server exterior wall change failed: %s; points: %s" % [changed_outer_message, OSMMap._building_points(building.get_meta("measurement_way"), building.get_meta("measurement_way").geometry[0])])
			return
		while not FileAccess.file_exists(directory.path_join("outer_changed.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("outer_changed.flag")):
			_fail("Client did not receive the changed exterior wall.")
			return
		building = world.get_node("OSMMap/Building_1")
		var split_message: String = world._commit_building_wall_split(building.get_meta("measurement_way"), 2, false, 0, 0)
		if split_message != world.BUILDING_WALL_SPLIT_SUCCESS:
			_fail("Live server interior wall split failed: " + split_message)
			return
		while not FileAccess.file_exists(directory.path_join("split.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("split.flag")):
			_fail("Client did not receive the interior wall split.")
			return
		building = world.get_node("OSMMap/Building_1")
		var moved_piece_message: String = world._commit_building_wall_change(building.get_meta("measurement_way"), 2, false, 0, 0.5, 0.5, 1)
		if moved_piece_message != world.BUILDING_WALL_CHANGE_SUCCESS:
			_fail("Live server wall segment move failed: " + moved_piece_message)
			return
		while not FileAccess.file_exists(directory.path_join("piece_moved.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("piece_moved.flag")):
			_fail("Client did not receive the wall segment move.")
			return
		building = world.get_node("OSMMap/Building_1")
		var joined_message: String = world._commit_building_wall_merge(building.get_meta("measurement_way"), 2, false, 0, 0, 1)
		if joined_message != world.BUILDING_WALL_MERGE_SUCCESS:
			_fail("Live server interior wall merge failed: " + joined_message)
			return
		while not FileAccess.file_exists(directory.path_join("wall_joined.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("wall_joined.flag")):
			_fail("Client did not receive the interior wall merge.")
			return
		building = world.get_node("OSMMap/Building_1")
		var split_outer_message: String = world._commit_building_wall_split(building.get_meta("measurement_way"), 2, true, 0, -1)
		if split_outer_message != world.BUILDING_WALL_SPLIT_SUCCESS:
			_fail("Live server exterior wall split failed: " + split_outer_message)
			return
		while not FileAccess.file_exists(directory.path_join("outer_split.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("outer_split.flag")):
			_fail("Client did not receive the exterior wall split.")
			return
		building = world.get_node("OSMMap/Building_1")
		var moved_outer_piece: String = world._commit_building_wall_change(building.get_meta("measurement_way"), 2, true, 0, -0.3, 0.4, 0)
		if moved_outer_piece != world.BUILDING_WALL_CHANGE_SUCCESS:
			_fail("Live server exterior wall segment move failed: " + moved_outer_piece)
			return
		while not FileAccess.file_exists(directory.path_join("outer_piece_moved.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("outer_piece_moved.flag")):
			_fail("Client did not receive the exterior wall segment move.")
			return
		building = world.get_node("OSMMap/Building_1")
		var joined_outer_message: String = world._commit_building_wall_merge(building.get_meta("measurement_way"), 2, true, 0, 0, 1)
		if joined_outer_message != world.BUILDING_WALL_MERGE_SUCCESS:
			_fail("Live server exterior wall merge failed: " + joined_outer_message)
			return
		while not FileAccess.file_exists(directory.path_join("outer_joined.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("outer_joined.flag")):
			_fail("Client did not receive the exterior wall merge.")
			return
		building = world.get_node("OSMMap/Building_1")
		var floor_reset_message: String = world._commit_building_reset_floor(building.get_meta("measurement_way"), 2)
		if floor_reset_message != world.BUILDING_RESET_FLOOR_SUCCESS or world.get_node("OSMMap/Building_1").has_node("FloorPreview_2"):
			_fail("Live server floor reset failed: " + floor_reset_message)
			return
		while not FileAccess.file_exists(directory.path_join("floor_reset.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("floor_reset.flag")):
			_fail("Client did not receive the floor reset.")
			return
		var changed: Dictionary = place.duplicate(true)
		changed.ways[0].geometry[0][0] += 0.00001
		changed.ways[0].geometry[-1][0] += 0.00001
		var other_block: Vector2i = world.map_block_stream.base_block + Vector2i.RIGHT
		world.map_block_stream.desired_blocks[other_block] = true
		world.refreshing_building_edits = true
		world.map_block_stream._activate_block(other_block, changed)
		world.refreshing_building_edits = false
		world._check_building_conflicts()
		while not FileAccess.file_exists(directory.path_join("conflict.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("conflict.flag")):
			_fail("Client did not receive the server's OSM conflict.")
			return
		var conflicted_source: StaticBody3D = world.get_node("OSMMap/Building_2")
		var building_reset_message: String = world._commit_building_reset(conflicted_source.get_meta("measurement_way"))
		if building_reset_message != world.BUILDING_RESET_SUCCESS or not world.building_edits.merges.is_empty() or not world.building_edits.blocked_merges.is_empty():
			_fail("Live server conflicted building reset failed: " + building_reset_message)
			return
		while not FileAccess.file_exists(directory.path_join("building_reset.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("building_reset.flag")):
			_fail("Client did not receive the building reset.")
			return
	else:
		while Time.get_ticks_msec() < deadline:
			if world.map_ready and world.building_edits.merges.size() == 1 and world.get_node_or_null("OSMMap/Building_1") != null:
				break
			await process_frame
		if not world.map_ready or world.building_edits.merges.size() != 1 or world.get_node_or_null("OSMMap/Building_2") != null:
			_fail("Initial server edit was not applied to the client map.")
			return
		if FileAccess.file_exists(world.building_edits.path):
			_fail("Server edits were incorrectly saved as the client's local edits.")
			return
		var initial_c: StaticBody3D = world.get_node("OSMMap/Building_3")
		if absf(float(initial_c.get_meta("measurement_height")) - 7.8) > 0.01 or initial_c.get_child_count() != 4 or world._commit_building_levels(initial_c.get_meta("measurement_way"), 3) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("Initial level edit was not received or the client was allowed to edit.")
			return
		var ready := FileAccess.open(directory.path_join("ready.flag"), FileAccess.WRITE)
		ready.close()
		world.map_block_stream.set_process(false)
		while not FileAccess.file_exists(directory.path_join("block_ready.flag")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not FileAccess.file_exists(directory.path_join("block_ready.flag")):
			_fail("Server did not prepare a block for the client request.")
			return
		var extra_block: Vector2i = world.map_block_stream.base_block + Vector2i(5, 0)
		world.map_block_stream.desired_blocks[extra_block] = true
		world.map_block_stream._load_block(extra_block)
		while not world.map_block_stream.loaded_blocks.has(extra_block) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not world.map_block_stream.loaded_blocks.has(extra_block):
			_fail("Requested server block was not loaded on the client.")
			return
		var block_received := FileAccess.open(directory.path_join("block_received.flag"), FileAccess.WRITE)
		block_received.close()
		while Time.get_ticks_msec() < deadline:
			if int(world.building_edits.level_edits[0].levels) == 3:
				break
			await process_frame
		if int(world.building_edits.level_edits[0].levels) != 3 or absf(float(world.get_node("OSMMap/Building_3").get_meta("measurement_height")) - 11.7) > 0.01 or world.get_node("OSMMap/Building_3").get_child_count() != 6:
			_fail("Live standalone level edit was not applied to the client.")
			return
		var standalone_flag := FileAccess.open(directory.path_join("standalone_levels.flag"), FileAccess.WRITE)
		standalone_flag.close()
		while Time.get_ticks_msec() < deadline:
			if world.building_edits.merges[0].result.tags.get("building:levels") == "4":
				break
			await process_frame
		if world.building_edits.merges[0].result.tags.get("building:levels") != "4" or absf(float(world.get_node("OSMMap/Building_1").get_meta("measurement_height")) - 15.6) > 0.01 or world.get_node("OSMMap/Building_1").get_child_count() != 8:
			_fail("Live server level edit was not applied to the client.")
			return
		var levels_flag := FileAccess.open(directory.path_join("levels.flag"), FileAccess.WRITE)
		levels_flag.close()
		while Time.get_ticks_msec() < deadline:
			if world.building_edits.merges[0].sources.size() == 3:
				break
			await process_frame
		if world.building_edits.merges[0].sources.size() != 3 or world.get_node_or_null("OSMMap/Building_3") != null or not world.building_edits.level_edits.is_empty() or world.building_edits.merges[0].result.tags.get("building:levels") != "4" or world.get_node("OSMMap/Building_1").get_child_count() != 8:
			_fail("Live server edit did not rebuild the client map.")
			return
		var done := FileAccess.open(directory.path_join("done.flag"), FileAccess.WRITE)
		done.close()
		while Time.get_ticks_msec() < deadline:
			if not world.building_edits.merges[0].get("hollow_floors", []).is_empty():
				break
			await process_frame
		var hollow_building: StaticBody3D = world.get_node("OSMMap/Building_1")
		var floors: Array = world.building_edits.merges[0].get("hollow_floors", [])
		if floors.size() != 1 or int(floors[0].floor) != 2 or not is_equal_approx(float(floors[0].wall_thickness), 0.3) or not hollow_building.has_node("FloorPreview_2") or world._commit_building_hollow(hollow_building.get_meta("measurement_way"), 1) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("The hollow floor was not synchronized or a client was allowed to edit.")
			return
		var hollow_flag := FileAccess.open(directory.path_join("hollow.flag"), FileAccess.WRITE)
		hollow_flag.close()
		while Time.get_ticks_msec() < deadline:
			if not world.building_edits.merges[0].hollow_floors[0].get("walls", []).is_empty():
				break
			await process_frame
		hollow_building = world.get_node("OSMMap/Building_1")
		var walls: Array = world.building_edits.merges[0].hollow_floors[0].get("walls", [])
		if walls.size() != 1 or not hollow_building.has_node("InteriorWall_2_1") or world._commit_building_wall(hollow_building.get_meta("measurement_way"), 2, Vector2.ZERO, 0.3) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("The interior wall was not synchronized or a client was allowed to edit.")
			return
		var wall_flag := FileAccess.open(directory.path_join("wall.flag"), FileAccess.WRITE)
		wall_flag.close()
		while Time.get_ticks_msec() < deadline:
			if is_equal_approx(float(world.building_edits.merges[0].hollow_floors[0].walls[0].thickness), 0.5):
				break
			await process_frame
		hollow_building = world.get_node("OSMMap/Building_1")
		if not is_equal_approx(float(world.building_edits.merges[0].hollow_floors[0].walls[0].thickness), 0.5) or world._commit_building_wall_change(hollow_building.get_meta("measurement_way"), 2, false, 0, 0.0, 0.4) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("The changed wall was not synchronized or a client was allowed to edit.")
			return
		var wall_changed := FileAccess.open(directory.path_join("wall_changed.flag"), FileAccess.WRITE)
		wall_changed.close()
		while Time.get_ticks_msec() < deadline:
			if world.building_edits.merges[0].hollow_floors[0].has("outline"):
				break
			await process_frame
		var edited_floor: Dictionary = world.building_edits.merges[0].hollow_floors[0]
		if not edited_floor.has("outline") or not is_equal_approx(float(edited_floor.wall_thickness), 0.4) or not world.get_node("OSMMap/Building_1/FloorPreview_2").has_meta("local_outline"):
			_fail("The changed exterior wall was not synchronized.")
			return
		var outer_changed := FileAccess.open(directory.path_join("outer_changed.flag"), FileAccess.WRITE)
		outer_changed.close()
		while Time.get_ticks_msec() < deadline:
			if world.building_edits.merges[0].hollow_floors[0].walls[0].has("cuts"):
				break
			await process_frame
		edited_floor = world.building_edits.merges[0].hollow_floors[0]
		hollow_building = world.get_node("OSMMap/Building_1")
		if edited_floor.walls[0].get("cuts", []).size() != 1 or world._commit_building_wall_split(hollow_building.get_meta("measurement_way"), 2, false, 0, 0) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("Interior split was not synchronized or the client was allowed to split.")
			return
		var split_flag := FileAccess.open(directory.path_join("split.flag"), FileAccess.WRITE)
		split_flag.close()
		while Time.get_ticks_msec() < deadline:
			if absf(float(world.building_edits.merges[0].hollow_floors[0].walls[0].offsets[1])) > 0.4:
				break
			await process_frame
		if absf(float(world.building_edits.merges[0].hollow_floors[0].walls[0].offsets[1])) < 0.4:
			_fail("The moved interior piece was not synchronized.")
			return
		var piece_flag := FileAccess.open(directory.path_join("piece_moved.flag"), FileAccess.WRITE)
		piece_flag.close()
		hollow_building = world.get_node("OSMMap/Building_1")
		if world._commit_building_wall_merge(hollow_building.get_meta("measurement_way"), 2, false, 0, 0, 1) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("A client was allowed to merge wall pieces.")
			return
		while Time.get_ticks_msec() < deadline:
			if not world.building_edits.merges[0].hollow_floors[0].walls[0].has("cuts"):
				break
			await process_frame
		if world.building_edits.merges[0].hollow_floors[0].walls[0].has("cuts"):
			_fail("The merged interior wall was not synchronized.")
			return
		var joined_flag := FileAccess.open(directory.path_join("wall_joined.flag"), FileAccess.WRITE)
		joined_flag.close()
		while Time.get_ticks_msec() < deadline:
			if not world.building_edits.merges[0].hollow_floors[0].get("outer_splits", []).is_empty():
				break
			await process_frame
		if world.building_edits.merges[0].hollow_floors[0].get("outer_splits", []).is_empty():
			_fail("The exterior split was not synchronized.")
			return
		var outer_split_flag := FileAccess.open(directory.path_join("outer_split.flag"), FileAccess.WRITE)
		outer_split_flag.close()
		while Time.get_ticks_msec() < deadline:
			if absf(float(world.building_edits.merges[0].hollow_floors[0].outer_splits[0].offsets[0])) > 0.2:
				break
			await process_frame
		if absf(float(world.building_edits.merges[0].hollow_floors[0].outer_splits[0].offsets[0])) < 0.2:
			_fail("The moved exterior piece was not synchronized.")
			return
		var outer_piece_flag := FileAccess.open(directory.path_join("outer_piece_moved.flag"), FileAccess.WRITE)
		outer_piece_flag.close()
		while Time.get_ticks_msec() < deadline:
			if world.building_edits.merges[0].hollow_floors[0].outer_splits[0].cuts.is_empty():
				break
			await process_frame
		var joined_outer: Dictionary = world.building_edits.merges[0].hollow_floors[0].outer_splits[0]
		if not joined_outer.cuts.is_empty() or absf(float(joined_outer.offsets[0]) + 0.3) > 0.01:
			_fail("The merged exterior wall was not synchronized.")
			return
		var outer_joined_flag := FileAccess.open(directory.path_join("outer_joined.flag"), FileAccess.WRITE)
		outer_joined_flag.close()
		hollow_building = world.get_node("OSMMap/Building_1")
		if world._commit_building_reset_floor(hollow_building.get_meta("measurement_way"), 2) != "Nur der Server-Host kann Gebäude bearbeiten." or world._commit_building_reset(hollow_building.get_meta("measurement_way")) != "Nur der Server-Host kann Gebäude bearbeiten.":
			_fail("A client was allowed to reset a floor or building.")
			return
		while not world.building_edits.merges[0].hollow_floors.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if not world.building_edits.merges[0].hollow_floors.is_empty() or world.get_node("OSMMap/Building_1").has_node("FloorPreview_2"):
			_fail("The floor reset was not synchronized.")
			return
		var floor_reset_flag := FileAccess.open(directory.path_join("floor_reset.flag"), FileAccess.WRITE)
		floor_reset_flag.close()
		while world.building_edits.blocked_merges.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if world.building_edits.blocked_merges.is_empty() or world.get_node_or_null("OSMMap/Building_2") == null or world.get_node_or_null("OSMMap/Building_3") == null:
			_fail("A conflict known only to the server did not restore the client's original buildings.")
			return
		var conflict := FileAccess.open(directory.path_join("conflict.flag"), FileAccess.WRITE)
		conflict.close()
		while not world.building_edits.merges.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if not world.building_edits.merges.is_empty() or not world.building_edits.blocked_merges.is_empty() or world.get_node_or_null("OSMMap/Building_1") == null or world.get_node_or_null("OSMMap/Building_2") == null or world.get_node_or_null("OSMMap/Building_3") == null:
			_fail("The conflicted building reset was not synchronized.")
			return
		var building_reset_flag := FileAccess.open(directory.path_join("building_reset.flag"), FileAccess.WRITE)
		building_reset_flag.close()
	print("Building edit network test passed: " + role)
	peer.close()
	world.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error(role + ": " + reason)
	quit(1)
