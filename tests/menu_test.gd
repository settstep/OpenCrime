extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var original_version: String = ProjectSettings.get_setting("application/config/version")
	ProjectSettings.set_setting("application/config/version", "9.8.7-test")
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var version: Label = menu.get_node("Panel/Options/Version")
	if not version.visible or version.text != "Version 9.8.7-test":
		_fail("The menu did not display the configured project version.")
		return
	ProjectSettings.set_setting("application/config/version", original_version)
	menu.get_node("Panel/Options/Changelog").pressed.emit()
	if not menu.get_node("ChangelogPanel").visible or not menu.get_node("ChangelogPanel/Layout/Content").text.contains("0.2.0"):
		_fail("The changelog did not open.")
		return
	menu.get_node("ChangelogPanel/Layout/Back").pressed.emit()
	var port: LineEdit = menu.get_node("Panel/Options/Port")
	var message: Label = menu.get_node("Panel/Options/Message")
	port.text = "0"
	menu.get_node("Panel/Options/Host").pressed.emit()
	if message.text.is_empty() or current_scene != menu:
		_fail("Invalid port was not rejected.")
		return
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	var selection = menu.get_node_or_null("PlaceSelection")
	if selection == null or selection.places.size() < 2:
		_fail("Single-player did not open the saved place selection.")
		return
	selection._on_cancel_pressed()
	await process_frame
	if not menu.get_node("Panel").visible:
		_fail("Cancelling place selection did not restore the menu.")
		return
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	selection = menu.get_node("PlaceSelection")
	selection._select_saved(1)
	selection._on_start_pressed()
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
	selection = menu.get_node_or_null("PlaceSelection")
	if selection == null:
		_fail("Hosting did not open the place selection.")
		return
	selection._on_start_pressed()
	await process_frame
	if not current_scene is NetworkGame or not current_scene.connected or not current_scene.players.has(1):
		_fail("Hosting from the menu did not create a local player.")
		return
	print("Menu single-player, validation and hosting passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
