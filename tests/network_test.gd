extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")
const OSMMap = preload("res://scripts/osm_map.gd")

var world: NetworkGame
var role := ""
var expected_players := 3


func _initialize() -> void:
	call_deferred("_test")


func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _wait_for(predicate: Callable, frames := 600) -> bool:
	for i in range(frames):
		if predicate.call():
			return true
		await physics_frame
	return false


func _interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(3)
	event.pressed = false
	Input.parse_input_event(event)


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(3)
	event.pressed = false
	Input.parse_input_event(event)


func _test() -> void:
	var server_port := 17777
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.trim_prefix("--role=")
		elif arg.begins_with("--port="):
			server_port = int(arg.trim_prefix("--port="))
		elif arg == "--dedicated":
			expected_players = 2
		elif arg.begins_with("--scale="):
			ProjectSettings.set_setting(OSMMap.SCALE_SETTING, float(arg.trim_prefix("--scale=")))
	if role not in ["host", "driver", "observer"]:
		_fail("Expected --role=host, driver or observer.")
		return

	if role == "observer":
		var menu := MenuScene.instantiate()
		root.add_child(menu)
		current_scene = menu
		await process_frame
		menu.get_node("Panel/Options/Port").text = str(server_port)
		menu.get_node("Panel/Options/Join").pressed.emit()
		await process_frame
		if not current_scene is NetworkGame:
			_fail("Joining from the menu did not open the network game.")
			return
		world = current_scene
	else:
		var peer := ENetMultiplayerPeer.new()
		var error: Error
		if role == "host":
			error = peer.create_server(server_port, 8)
		else:
			error = peer.create_client("127.0.0.1", server_port)
		if error != OK:
			_fail("Could not start ENet: %d" % error)
			return
		root.multiplayer.multiplayer_peer = peer
		var instance := MainScene.instantiate()
		if not OSMMap.populate(instance):
			_fail("The OSM map could not be loaded.")
			return
		instance.set_script(NetworkGame)
		world = instance
		root.add_child(world)
		current_scene = world

	if not await _wait_for(func(): return world.connected and world.players.size() == expected_players, 3600):
		_fail("Players did not connect.")
		return

	if role == "driver":
		Input.action_press("move_forward")
		await _frames(45)
		Input.action_release("move_forward")
		await _interact()
		if not await _wait_for(func(): return world.driver_id == root.multiplayer.get_unique_id(), 180):
			_fail("Driver could not enter the car.")
			return
		await _frames(180)
		Input.action_press("move_right")
		await _frames(55)
		Input.action_release("move_right")
		await _frames(5)
		await _interact()
		if not await _wait_for(func(): return world.driver_id == 0 and world.players[root.multiplayer.get_unique_id()].visible, 180):
			_fail("Driver could not exit the car.")
			return
		await _frames(30)
		await _interact()
		if not await _wait_for(func(): return world.driver_id == root.multiplayer.get_unique_id(), 180):
			_fail("Driver could not re-enter the car.")
			return
		await _frames(60)
	elif role == "observer":
		var initial_positions := {}
		for peer_id in world.players:
			initial_positions[peer_id] = world.players[peer_id].position
		if not await _wait_for(func(): return world.driver_id != 0, 300):
			_fail("Observer did not see the driver enter.")
			return
		var driver: CharacterBody3D = world.players[world.driver_id]
		if driver.visible or driver.position.distance_to(initial_positions[world.driver_id]) < 1.0:
			_fail("Driver movement or visibility was not synchronized.")
			return
		Input.action_press("move_forward")
		await _frames(45)
		Input.action_release("move_forward")
		await _interact()
		if not await _wait_for(func(): return world.status.text == "Das Auto ist bereits besetzt.", 180):
			_fail("Second player could not see that the car is occupied.")
			return
		await _escape()
		if not world.menu_open or paused:
			_fail("Multiplayer menu did not open without pausing the server.")
			return
		await _frames(20)
		var own_player: CharacterBody3D = world.players[root.multiplayer.get_unique_id()]
		var own_position := own_player.position
		Input.action_press("move_right")
		await _frames(30)
		Input.action_release("move_right")
		if own_player.position.distance_to(own_position) > 0.1:
			_fail("The local player moved while the menu was open.")
			return
		if not await _wait_for(func(): return world.car.position.x > 3.0, 300):
			_fail("The server did not continue while the menu was open.")
			return
		await _escape()
		if world.menu_open:
			_fail("Escape did not close the multiplayer menu.")
			return
		if not await _wait_for(func(): return world.car.position.x > 3.0, 300):
			_fail("Observer did not see the car move.")
			return
		if not await _wait_for(func(): return world.driver_id == 0 and driver.visible, 300):
			_fail("Observer did not see the driver exit.")
			return
		if not await _wait_for(func(): return world.driver_id != 0 and not driver.visible, 180):
			_fail("Observer did not see the driver re-enter.")
			return
		if not await _wait_for(func(): return world.driver_id == 0 and world.players.size() == expected_players - 1, 300):
			_fail("Driver disconnect was not synchronized.")
			return
		await _escape()
		world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
		await process_frame
		if current_scene.name != "Menu":
			_fail("Returning to the main menu failed for the client.")
			return
	else:
		var host_player: CharacterBody3D = world.players[1]
		var host_start := host_player.position
		Input.action_press("move_left")
		await _frames(15)
		Input.action_release("move_left")
		if host_player.position.x >= host_start.x - 0.5:
			_fail("The host could not move.")
			return
		await _escape()
		if not world.menu_open or paused:
			_fail("The host menu should not pause the server.")
			return
		await _frames(10)
		var paused_position := host_player.position
		Input.action_press("move_left")
		await _frames(20)
		Input.action_release("move_left")
		if host_player.position.distance_to(paused_position) > 0.1:
			_fail("The host moved while the menu was open.")
			return
		await _escape()
		if not await _wait_for(func(): return world.driver_id != 0, 300):
			_fail("Host did not see the driver enter.")
			return
		if not await _wait_for(func(): return world.car.position.x > 3.0, 400):
			_fail("Host did not see the car move.")
			return
		if not await _wait_for(func(): return world.driver_id == 0 and world.players.size() == 2, 300):
			_fail("Host did not release the disconnected driver's car.")
			return
		if not await _wait_for(func(): return world.players.size() == 1, 300):
			_fail("Host did not remove the observer after disconnect.")
			return
		host_player.position = world.car.position + Vector3(0, 0.4, 2.4)
		host_player.velocity = Vector3.ZERO
		await _frames(3)
		await _interact()
		if world.driver_id != 1 or host_player.visible:
			_fail("Host could not enter the car.")
			return
		var host_car_start := world.car.position.x
		Input.action_press("move_right")
		await _frames(15)
		Input.action_release("move_right")
		if world.car.position.x <= host_car_start + 1.0:
			_fail("Host could not drive the car.")
			return
		await _interact()
		if world.driver_id != 0 or not host_player.visible:
			_fail("Host could not exit the car.")
			return

	print("Network test passed: ", role)
	quit(0)


func _fail(reason: String) -> void:
	push_error(role + ": " + reason)
	quit(1)
