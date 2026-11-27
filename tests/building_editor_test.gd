extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const DataPaths = preload("res://scripts/data_paths.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _way(id: int, left: float, origin: Array) -> Dictionary:
	var zone := Grid.zone_for_origin(origin)
	var projected := Grid.project(origin, zone, true)
	var geometry := []
	for point in [Vector2(left, 0), Vector2(left + 10, 0), Vector2(left + 10, 10), Vector2(left, 10), Vector2(left, 0)]:
		geometry.append(Grid.unproject([projected[0] + point.x, projected[1] + point.y], zone, true))
	return {"id": id, "tags": {"building": "yes", "height": "5"}, "geometry": geometry}


func _test() -> void:
	var directory := ProjectSettings.globalize_path("user://building_editor_test_" + Crypto.new().generate_random_bytes(8).hex_encode())
	DataPaths.root_override = directory
	var origin := [47.7748417, 10.6034933]
	var a := _way(1, 0, origin)
	var b := _way(2, 10, origin)
	var place := {"id": "test", "name": "Test", "origin": origin, "bounds": [47.77, 10.60, 47.78, 10.61], "ways": [a, b]}
	var world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(world, place):
		_fail("Test map could not be built.")
		return
	root.add_child(world)
	world.set_process(false)
	world.map_block_stream.set_process(false)
	var camera: Camera3D = world.get_node("Camera3D")
	camera.size = 50
	camera.global_position = Vector3(13, 50, -6.5)
	await physics_frame
	await physics_frame
	var editor: Control = world.get_node("HUD/BuildingEditor")
	var measurement: Control = world.get_node("HUD/BuildingMeasurement")
	var key := InputEventKey.new()
	key.keycode = KEY_F5
	key.pressed = true
	root.push_input(key, true)
	await process_frame
	await process_frame
	if not editor.active or not editor.panel.visible:
		_fail("F5 did not open the building editor.")
		return
	for center in [Vector3(6.5, 6.5, -6.5), Vector3(19.5, 6.5, -6.5)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = camera.unproject_position(center)
		root.push_input(click, true)
		await physics_frame
		await physics_frame
	if editor.selected.size() != 2 or editor.merge_button.disabled:
		_fail("Clicking two buildings did not select both.")
		return
	editor.merge_button.pressed.emit()
	await physics_frame
	await physics_frame
	if not editor.selected.is_empty() or world.get_node_or_null("OSMMap/Building_2") != null or not FileAccess.file_exists(world.building_edits.path):
		_fail("Merge did not update the map, clear the selection and persist the diff.")
		return
	key.keycode = KEY_F4
	root.push_input(key, true)
	await process_frame
	await process_frame
	if editor.active or not measurement.active:
		_fail("Switching from the editor to measurement failed.")
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(13, 6.5, -6.5))
	root.push_input(click, true)
	await physics_frame
	await physics_frame
	if measurement.selected_building == null or not measurement.sides.text.contains("20.00 m (OSM) | 26.00 Spieleinheiten"):
		_fail("Merged building could not be measured.")
		return
	var changed: Dictionary = place.duplicate(true)
	changed.ways[1].geometry[0][0] += 0.00001
	changed.ways[1].geometry[-1][0] += 0.00001
	var other_block: Vector2i = world.map_block_stream.base_block + Vector2i.RIGHT
	world.map_block_stream.desired_blocks[other_block] = true
	world.map_block_stream._activate_block(other_block, changed)
	await process_frame
	await process_frame
	if world.get_node_or_null("OSMMap/Building_2") == null:
		_fail("A conflict in another loaded block did not restore original buildings.")
		return
	world.map_block_stream._reconcile({world.map_block_stream.base_block: true})
	await process_frame
	await process_frame
	if world.get_node_or_null("OSMMap/Building_2") != null:
		_fail("Unloading a conflicting block did not restore the merge.")
		return
	var path: String = world.building_edits.path
	world.free()
	var reloaded: Node3D = MainScene.instantiate()
	if not OSMMap.populate(reloaded, place):
		_fail("Original test map could not be rebuilt.")
		return
	root.add_child(reloaded)
	if reloaded.get_node_or_null("OSMMap/Building_1") == null or reloaded.get_node_or_null("OSMMap/Building_2") != null:
		_fail("Saved merge was not reapplied when the map was reopened.")
		return
	reloaded.free()
	if DirAccess.remove_absolute(path) != OK or DirAccess.remove_absolute(path.get_base_dir()) != OK or DirAccess.remove_absolute(directory) != OK:
		_fail("Could not clean up editor test files.")
		return
	print("Building editor input, saved merge and measurement passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
