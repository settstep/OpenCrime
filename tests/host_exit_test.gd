extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _test() -> void:
	var args := OS.get_cmdline_user_args()
	var is_host := args.has("--host")
	var port := 17778
	for arg in args:
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1) if is_host else peer.create_client("127.0.0.1", port)
	if error != OK:
		_fail("Unable to create the network peer.")
		return
	root.multiplayer.multiplayer_peer = peer
	var world := MainScene.instantiate()
	world.set_script(NetworkGame)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if world.connected and world.players.size() == 2:
			break
		await process_frame
	if not world.connected or world.players.size() != 2:
		_fail("Players did not connect.")
		return
	if is_host:
		await create_timer(0.5).timeout
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		world._unhandled_input(escape)
		world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
		await process_frame
		if current_scene.name != "Menu":
			_fail("Host could not return to the menu.")
			return
	else:
		while Time.get_ticks_msec() < deadline and world.connected:
			await process_frame
		if world.connected or not world.status.text.begins_with("Serververbindung verloren"):
			_fail("The client was not notified of the host leaving.")
			return
	print("Host return and client disconnect passed: ", "host" if is_host else "client")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
