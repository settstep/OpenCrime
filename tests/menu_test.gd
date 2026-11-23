extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var port: LineEdit = menu.get_node("Panel/Options/Port")
	var message: Label = menu.get_node("Panel/Options/Message")
	port.text = "0"
	menu.get_node("Panel/Options/Host").pressed.emit()
	if message.text.is_empty() or current_scene != menu:
		_fail("Invalid port was not rejected.")
		return
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	if current_scene.name != "Main" or current_scene is NetworkGame:
		_fail("Single-player menu did not open the original game.")
		return
	current_scene.queue_free()
	await process_frame

	menu = MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	port = menu.get_node("Panel/Options/Port")
	var reservation := PacketPeerUDP.new()
	if reservation.bind(0, "127.0.0.1") != OK:
		_fail("Could not reserve a test port.")
		return
	port.text = str(reservation.get_local_port())
	reservation.close()
	menu.get_node("Panel/Options/Host").pressed.emit()
	await process_frame
	if not current_scene is NetworkGame or not current_scene.connected or not current_scene.players.has(1):
		_fail("Hosting from the menu did not create a local player.")
		return
	print("Menu single-player, validation and hosting passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
