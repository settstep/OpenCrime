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
		while world.building_edits.blocked_merges.is_empty() and Time.get_ticks_msec() < deadline:
			await process_frame
		if world.building_edits.blocked_merges.is_empty() or world.get_node_or_null("OSMMap/Building_2") == null or world.get_node_or_null("OSMMap/Building_3") == null:
			_fail("A conflict known only to the server did not restore the client's original buildings.")
			return
		var conflict := FileAccess.open(directory.path_join("conflict.flag"), FileAccess.WRITE)
		conflict.close()
	print("Building edit network test passed: " + role)
	peer.close()
	world.free()
	quit(0)


func _fail(reason: String) -> void:
	push_error(role + ": " + reason)
	quit(1)
