extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _test() -> void:
	var origin := [47.7748417, 10.6034933]
	var zone := Grid.zone_for_origin(origin)
	var projected := Grid.project(origin, zone, true)
	var points: Array = []
	for offset in [Vector2(0, 0), Vector2(10, 0), Vector2(10, 20), Vector2(10, 20), Vector2(0, 20), Vector2(0, 0)]:
		points.append(Grid.unproject([projected[0] + offset.x, projected[1] + offset.y], zone, true))
	var world: Node3D = MainScene.instantiate()
	root.add_child(world)
	world.set_process(false)
	var block := Node3D.new()
	block.position = Vector3(3, 0, -2)
	world.add_child(block)
	OSMMap._add_building(block, {"id": 123, "tags": {"building": "yes", "height": "5"}, "geometry": points}, StandardMaterial3D.new(), 1.3, origin)
	var building: StaticBody3D = block.get_node("Building_123")
	var measurement: Control = world.get_node("HUD/BuildingMeasurement")
	var camera: Camera3D = world.get_node("Camera3D")
	camera.global_position = block.position + Vector3(6.5, 50, -13)
	await physics_frame
	await physics_frame
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F4
	toggle.pressed = true
	root.push_input(toggle, true)
	if not measurement.active:
		_fail("F4 did not activate measurement.")
		return
	await process_frame
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(block.to_global(Vector3(6.5, 6.5, -13)))
	root.push_input(click, true)
	if not measurement.pending_click:
		_fail("Viewport did not deliver the building click: position=%s panel=%s" % [click.position, measurement.panel.visible])
		return
	await physics_frame
	await physics_frame
	if measurement.selected_building != building:
		_fail("Click did not select the transformed building: event=%s stored=%s camera=%s active=%s pending=%s" % [click.position, measurement.click_position, camera.global_position, measurement.active, measurement.pending_click])
		return
	var side_text: String = measurement.sides.text
	if not side_text.contains("Seite 1: 10.00 m (OSM) | 13.00 Spieleinheiten") or not side_text.contains("Seite 2: 20.00 m (OSM) | 26.00 Spieleinheiten") or not side_text.contains("Seite 4: 20.00 m (OSM) | 26.00 Spieleinheiten") or side_text.contains("Seite 5:"):
		_fail("Incorrect side lengths, scaling, duplicate handling or closing edge: " + side_text)
		return
	if building.collision_layer & 1 == 0:
		_fail("Building lost its original collision layer.")
		return
	camera.global_position.x += 50
	root.push_input(click, true)
	await physics_frame
	await physics_frame
	if measurement.selected_building != null or not measurement.sides.text.is_empty():
		_fail("A click outside the building did not clear the selection.")
		return
	camera.global_position.x -= 50
	root.push_input(click, true)
	await physics_frame
	await physics_frame
	if measurement.selected_building != building:
		_fail("Building could not be selected again.")
		return
	world.map_open = true
	measurement._unhandled_input(toggle)
	if not measurement.active or measurement._can_interact():
		_fail("Measurement must not accept input while the map is open.")
		return
	paused = true
	await process_frame
	await process_frame
	if measurement.panel.visible:
		_fail("Measurement panel remained visible while the game was paused.")
		return
	paused = false
	world.map_open = false
	block.free()
	await process_frame
	if measurement.selected_building != null or not measurement.sides.text.is_empty():
		_fail("Removing a streamed block did not clear the selected building.")
		return
	measurement._unhandled_input(toggle)
	if measurement.active:
		_fail("F4 did not deactivate measurement.")
		return
	world.free()
	var network: Node3D = MainScene.instantiate()
	network.set_script(NetworkGame)
	root.add_child(network)
	var network_measurement: Control = network.get_node("HUD/BuildingMeasurement")
	if not network_measurement._can_interact():
		_fail("A connected multiplayer host cannot use measurement.")
		return
	network.connected = false
	if network_measurement._can_interact():
		_fail("A disconnected client can use measurement.")
		return
	network.connected = true
	network.map_ready = false
	if network_measurement._can_interact():
		_fail("A client without map data can use measurement.")
		return
	network.map_ready = true
	network.dedicated = true
	if network_measurement._can_interact():
		_fail("A dedicated server can use the local measurement interface.")
		return
	network.free()
	print("Building selection, dimensions, scaling, input gating and block removal passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
