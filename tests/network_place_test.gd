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
			await create_timer(2.0).timeout
			print("Host selected Berlin")
			quit(0)
			return
		if not host and world.map_ready and world.players.size() == expected_players:
			if world.place_data.id != "gendarmenmarkt" or world.get_node_or_null("OSMMap") == null:
				_fail("Client did not receive the host's Berlin map.")
				return
			print("Client received the host's Berlin map")
			quit(0)
			return
		await process_frame
	_fail("Place synchronization timed out.")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
