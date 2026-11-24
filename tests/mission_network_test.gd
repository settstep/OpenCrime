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
		await process_frame
	return false


func _test() -> void:
	var host := OS.get_cmdline_user_args().has("--host")
	var port := 17785
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
	if not await _wait_for(func(): return world.connected and world.map_ready and world.players.size() == 2 and not world.mission_ui.state.is_empty()):
		_fail("Mission players were not initialized.")
		return
	if host:
		var guest := 0
		for peer in world.players:
			if peer != 1:
				guest = peer
		var id: String = world.mission_manager.players[1].offers[0]
		world.mission_ui.get_node("Panel/Layout/Buttons/Accept").pressed.emit()
		var peer_index: int = world.mission_ui.peers.get_item_index(guest)
		if peer_index < 0:
			_fail("The guest was not selectable for forwarding.")
			return
		world.mission_ui.peers.select(peer_index)
		world.mission_ui.get_node("Panel/Layout/Invite/Send").pressed.emit()
		if not await _wait_for(func(): return world.mission_manager.missions[id].participants.has(guest)):
			_fail("Client did not accept the invitation.")
			return
		var mission: Dictionary = world.mission_manager.missions[id]
		world.players[guest].global_position = Vector3(mission.pickup[0], 0.9, mission.pickup[1])
		if not await _wait_for(func(): return mission.stage == 1):
			_fail("Client did not pick up the package on the server.")
			return
		await create_timer(0.5).timeout
		world.players[1].global_position = Vector3(mission.destination[0], 0.9, mission.destination[1])
		if not await _wait_for(func(): return world.mission_manager.players[1].money == 50 and world.mission_manager.players[guest].money == 50):
			_fail("The server did not split the reward.")
			return
		await create_timer(1.0).timeout
		print("Server shared mission and reward passed")
	else:
		var own_id := root.multiplayer.get_unique_id()
		if not await _wait_for(func():
			for offer in world.mission_ui.state.player.offers:
				if world.mission_ui.state.missions[offer].owner == 1:
					return true
			return false):
			_fail("Client did not receive the forwarded SMS.")
			return
		var invitation := ""
		for offer in world.mission_ui.state.player.offers:
			if world.mission_ui.state.missions[offer].owner == 1:
				invitation = offer
		for index in world.mission_ui.list.item_count:
			if world.mission_ui.list.get_item_metadata(index) == invitation:
				world.mission_ui.list.select(index)
				break
		world.mission_ui.get_node("Panel/Layout/Buttons/Accept").pressed.emit()
		if not await _wait_for(func(): return world.mission_ui.state.player.active == invitation):
			_fail("Client could not accept the shared mission.")
			return
		if not await _wait_for(func(): return world.mission_ui.state.missions.has(invitation) and world.mission_ui.state.missions[invitation].stage == 1):
			_fail("Client did not receive shared pickup progress.")
			return
		if not await _wait_for(func(): return world.mission_ui.state.player.money == 50 and world.mission_ui.state.player.active.is_empty()):
			_fail("Client did not receive the shared reward.")
			return
		if not world.mission_ui.state.player.completed.has("first_delivery") or own_id == 1:
			_fail("Client story completion was not synchronized.")
			return
		print("Client invitation, progress and reward passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
