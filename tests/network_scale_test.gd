extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const NetworkGame = preload("res://scripts/network_game.gd")

var saw_connection := false
var saw_disconnect := false


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var is_host := OS.get_cmdline_user_args().has("--host")
	var port := 17779
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, 1.5 if is_host else 1.0)
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.get_node("Panel/Options/Port").text = str(port)
	if is_host:
		menu.get_node("Panel/Options/Host").pressed.emit()
	else:
		menu.get_node("Panel/Options/Join").pressed.emit()
	await process_frame
	if not current_scene is NetworkGame:
		_fail("The multiplayer game did not start.")
		return
	var world: NetworkGame = current_scene
	if is_host:
		root.multiplayer.peer_connected.connect(func(_id: int): saw_connection = true)
		root.multiplayer.peer_disconnected.connect(func(_id: int): saw_disconnect = true)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if is_host and saw_connection and saw_disconnect and world.players.size() == 1:
			print("Server removed the mismatched client")
			quit(0)
			return
		if not is_host and world.status.text.begins_with("Kartenfaktor stimmt nicht"):
			if world.connected:
				_fail("The mismatched client is still connected.")
				return
			print("Client reported the scale mismatch")
			quit(0)
			return
		await process_frame
	_fail("The scale mismatch was not handled.")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
