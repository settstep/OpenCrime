extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
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
	var port := 17786
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
	if not await _wait_for(func(): return world.connected and world.map_ready and world.players.size() == 2):
		_fail("Players did not connect.")
		return
	if host:
		var guest := 0
		for peer_id in world.players:
			if peer_id != 1:
				guest = peer_id
		_add_box(world, Vector3(500, -0.5, 0), Vector3(50, 1, 50))
		_add_box(world, Vector3(490, 1.5, -6), Vector3(1, 3, 6))
		world.car.position = Vector3(484, 0.5, -6)
		world.car.rotation.y = -PI / 2.0
		world.car.velocity = Vector3.ZERO
		world.players[guest].position = world.car.position + Vector3(0, 0.4, 3)
		await physics_frame
		world._interact(guest)
		if world.driver_id != guest:
			_fail("Guest could not enter the test car.")
			return
		if not await _wait_for(func(): return world.players[guest].health < 100):
			_fail("The server did not calculate collision damage.")
			return
		await create_timer(1.0).timeout
		if world.players[guest].health < 55 or world.players[guest].health > 57:
			_fail("The server applied unexpected or repeated collision damage.")
			return
		world.pending_interactions.append_array([guest, guest])
		world.car.impact.emit(40.0)
		if world.pending_interactions.has(guest):
			_fail("Queued interactions were not cleared on death.")
			return
		if not await _wait_for(func(): return world.players[guest].health == 25 and world.players[guest].visible and world.driver_id == 0):
			_fail("The server did not respawn the guest.")
			return
		await create_timer(2.0).timeout
		print("Server-authoritative damage and respawn passed")
	else:
		var own_id := root.multiplayer.get_unique_id()
		if not await _wait_for(func(): return world.driver_id == own_id):
			_fail("Client did not see car entry.")
			return
		Input.action_press("move_right")
		if not await _wait_for(func(): return world.players[own_id].health < 100):
			_fail("Client did not receive collision damage.")
			return
		Input.action_release("move_right")
		await process_frame
		if int(world.health_bar.value) != world.players[own_id].health:
			_fail("Client HUD did not show the server health.")
			return
		if not await _wait_for(func(): return world.players[own_id].health == 25 and world.players[own_id].visible and world.driver_id == 0):
			_fail("Client did not receive respawn state.")
			return
		await process_frame
		if int(world.health_bar.value) != 25:
			_fail("Client HUD did not show respawn health.")
			return
		print("Client health HUD and respawn synchronization passed")
	quit(0)


func _add_box(world: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = position


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
