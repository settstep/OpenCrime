extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var reservation := PacketPeerUDP.new()
	if reservation.bind(0, "127.0.0.1") != OK:
		_fail("Could not reserve a test port.")
		return
	var port := reservation.get_local_port()
	reservation.close()

	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.get_node("Panel/Options/Port").text = str(port)
	menu.get_node("Panel/Options/Join").pressed.emit()
	await process_frame
	if not current_scene is NetworkGame:
		_fail("The join menu did not open the network game.")
		return
	var world: NetworkGame = current_scene
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		if world.status.text.begins_with("Verbindung fehlgeschlagen"):
			if world.connected:
				_fail("Failed connection was still marked connected.")
				return
			print("Connection failure was reported")
			quit(0)
			return
		await process_frame
	_fail("No connection failure was reported.")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
