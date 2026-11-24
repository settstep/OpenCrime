extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")
const SaveStore = preload("res://scripts/save_store.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	SaveStore.directory = "user://menu_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
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
	if not menu.get_node("ChangelogPanel").visible or not menu.get_node("ChangelogPanel/Layout/Content").text.contains("0.8.0"):
		_fail("The changelog did not open.")
		return
	menu.get_node("ChangelogPanel/Layout/Back").pressed.emit()
	for directory_exists in [false, true]:
		if directory_exists and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
			_fail("Could not create an empty test save directory.")
			return
		menu.get_node("Panel/Options/LoadGame").pressed.emit()
		await process_frame
		var save_selection = menu.get_node("SaveSelection")
		if not save_selection.slots.is_empty() or save_selection.info.text != "Noch keine Spielstände vorhanden.":
			_fail("An empty save list was not displayed correctly.")
			return
		save_selection._on_load_pressed()
		save_selection._on_delete_pressed()
		if not save_selection.info.text.contains("auswählen") or save_selection.confirmation.visible:
			_fail("An empty save list allowed loading or deleting a save.")
			return
		save_selection._on_cancel_pressed()
		await process_frame
		if not menu.get_node("Panel").visible:
			_fail("Cancelling the empty save list did not restore the menu.")
			return
		if directory_exists and DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
			_fail("Could not remove the empty test save directory.")
			return
	var blocker := FileAccess.open(SaveStore.directory, FileAccess.WRITE)
	if blocker == null:
		_fail("Could not create the save directory blocker.")
		return
	blocker.close()
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	var blocked_selection = menu.get_node("SaveSelection")
	if not blocked_selection.slots.is_empty() or not blocked_selection.info.text.contains("nicht gelesen"):
		_fail("An inaccessible save directory was not reported.")
		return
	blocked_selection._on_cancel_pressed()
	await process_frame
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
		_fail("Could not remove the test save directory blocker.")
		return
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
	var save_id: String = current_scene.save_id
	if SaveStore.delete_slot(save_id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
		_fail("The isolated test save could not be removed.")
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
