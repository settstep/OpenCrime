extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var host := OS.get_cmdline_user_args().has("--host")
	var dedicated := OS.get_cmdline_user_args().has("--dedicated")
	var expected_players := 1 if dedicated else 2
	var port := 17781 if dedicated else 17780
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.get_node("Panel/Options/Port").text = str(port)
	if host:
		menu.get_node("Panel/Options/Host").pressed.emit()
		await process_frame
		menu.get_node("PlaceSelection")._select_saved(1)
		menu.get_node("PlaceSelection")._on_start_pressed()
	else:
		menu.get_node("Panel/Options/Join").pressed.emit()
	await process_frame
	if not current_scene is NetworkGame:
		_fail("Network game did not start.")
		return
	var world: NetworkGame = current_scene
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if host and world.players.size() == 2:
			world.players[1].position = Vector3(100, 0.9, 100)
			await process_frame
			await process_frame
			if world.game_map.player_position.distance_to(Vector2(100, 100)) > 1.0:
				_fail("The host's map did not follow its player.")
				return
			await create_timer(2.0).timeout
			print("Host selected Berlin")
			quit(0)
			return
		if not host and world.map_ready and world.players.size() == expected_players and (dedicated or world.players.has(1) and world.players[1].position.x > 90.0):
			if world.place_data.id != "gendarmenmarkt" or world.get_node_or_null("OSMMap") == null:
				_fail("Client did not receive the host's Berlin map.")
				return
			await process_frame
			var map = world.game_map
			var cell := floori((100.0 + map.WORLD_SIZE * map.map_scale / 2.0) / (map.CELL_SIZE * map.map_scale))
			if not map.configured or not map.title.text.contains("Gendarmenmarkt") or not map.has_position or map.explored.has(Vector2i(cell, cell)):
				_fail("Client map used the wrong place or another player's exploration.")
				return
			var open := InputEventAction.new()
			open.action = "show_map"
			open.pressed = true
			world._unhandled_input(open)
			Input.action_press("move_forward")
			if not world.map_open or paused or world._local_movement_input() != Vector2.ZERO:
				_fail("Opening the multiplayer map paused the world or failed to block movement.")
				return
			Input.action_release("move_forward")
			world._close_map()
			if world.map_open or paused:
				_fail("Closing the multiplayer map failed.")
				return
			print("Client received the host's Berlin map")
			quit(0)
			return
		await process_frame
	_fail("Place synchronization timed out.")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
