extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _wait_for(check: Callable, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await physics_frame
	return false


func _test() -> void:
	var host := OS.get_cmdline_user_args().has("--host")
	var port := 17787
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.port.text = str(port)
	if host:
		menu._on_host_pressed()
		await process_frame
		menu.get_node("PlaceSelection")._on_start_pressed()
	else:
		menu._on_join_pressed()
	await process_frame
	if not current_scene is NetworkGame:
		_fail("Network game did not start.")
		return
	var world: NetworkGame = current_scene
	if not await _wait_for(func(): return world.connected and world.map_ready and world.players.size() == 2 and world.cars.size() == 3):
		_fail("Players or cars did not synchronize.")
		return
	if host:
		var guest := 0
		for peer_id in world.players:
			if peer_id != 1:
				guest = peer_id
		var floor_body := StaticBody3D.new()
		var floor_collision := CollisionShape3D.new()
		var floor_shape := BoxShape3D.new()
		floor_shape.size = Vector3(100, 1, 100)
		floor_collision.shape = floor_shape
		floor_body.add_child(floor_collision)
		world.add_child(floor_body)
		floor_body.position = Vector3(500, -0.5, 0)
		world.cars[0].position = Vector3(490, 0.5, 0)
		world.cars[1].position = Vector3(510, 0.5, 0)
		world.players[1].position = world.cars[0].position + Vector3(0, 0.4, 2.4)
		world.players[guest].position = world.cars[1].position + Vector3(0, 0.4, 2.4)
		await physics_frame
		world._interact(1)
		world._interact(guest)
		if world.cars[0].driver_id != 1 or world.cars[1].driver_id != guest:
			_fail("Two players could not enter separate cars.")
			return
		Input.action_press("move_right")
		for index in range(30):
			await physics_frame
		Input.action_release("move_right")
		if not await _wait_for(func(): return world.cars[0].position.x > 491 and world.cars[1].position.z < -1):
			_fail("Both cars did not move independently.")
			return
		world.cars[1].impact.emit(18.0)
		if world.players[guest].health >= 100 or world.players[1].health != 100:
			_fail("Damage affected the wrong driver.")
			return
		world.cars[1].impact.emit(40.0)
		if not await _wait_for(func(): return world.players[guest].health == 25 and world.cars[1].driver_id == 0):
			_fail("The second driver did not respawn.")
			return
		if world.cars[0].driver_id != 1 or not world.cars[0].occupied:
			_fail("Respawning one driver released the other car.")
			return
		await create_timer(0.5).timeout
		world.players[guest].position = world.cars[1].position + Vector3(0, 0.4, 2.4)
		world._interact(guest)
		if world.cars[1].driver_id != guest:
			_fail("The guest could not re-enter the second car.")
			return
		if not await _wait_for(func(): return world.players.size() == 1):
			_fail("Client did not disconnect.")
			return
		if world.cars[0].driver_id != 1 or not world.cars[0].occupied or world.cars[1].driver_id != 0 or world.cars[1].occupied:
			_fail("A client disconnect released the wrong car or left the guest car occupied.")
			return
		print("Server synchronized independent cars, damage and disconnect")
	else:
		var own_id := root.multiplayer.get_unique_id()
		if not await _wait_for(func(): return world.cars[0].driver_id == 1 and world.cars[1].driver_id == own_id):
			_fail("The client did not see both drivers.")
			return
		Input.action_press("move_forward")
		for index in range(30):
			await physics_frame
		Input.action_release("move_forward")
		if not await _wait_for(func(): return world.players[own_id].health == 25 and world.cars[1].driver_id == 0):
			_fail("The client did not see damage and respawn.")
			return
		if world.cars[0].driver_id != 1:
			_fail("The client lost the other driver's state.")
			return
		if not await _wait_for(func(): return world.cars[1].driver_id == own_id):
			_fail("The client did not see re-entry before disconnect.")
			return
		print("Client saw independent cars and respawn")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
