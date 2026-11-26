extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _test() -> void:
	var args := OS.get_cmdline_user_args()
	var directory := ""
	for arg in args:
		if arg.begins_with("--folder="):
			directory = arg.trim_prefix("--folder=")
	if not directory.begins_with("save_restart_test_") or not directory.trim_prefix("save_restart_test_").is_valid_int():
		_fail("Expected an isolated numeric test folder.")
		return
	SaveStore.directory = "user://" + directory
	var prepare := args.has("--prepare")
	if prepare and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SaveStore.directory)):
		_fail("Test directory already exists.")
		return
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	if prepare:
		menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
		await process_frame
		menu.get_node("PlaceSelection")._on_start_pressed()
		await process_frame
		var world = current_scene
		world.player.global_position = Vector3(20, 0.9, 20)
		world.car.global_position = Vector3(5, 0.5, -5)
		world.game_map.update_position(Vector3(90, 0, 90))
		print("Closing the window after changing the game state")
		world._open_pause_menu()
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		await create_timer(2.0).timeout
		_fail("Window close did not exit.")
		return
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	var selection = menu.get_node("SaveSelection")
	if selection.slots.size() != 1:
		_fail("A new process did not find the saved game.")
		return
	var id: String = selection.slots[0].id
	selection._on_load_pressed()
	await process_frame
	var world = current_scene
	if world.name != "Main" or world.player.global_position.distance_to(Vector3(20, 0.9, 20)) > 0.01 or world.car.global_position.distance_to(Vector3(5, 0.5, -5)) > 0.01 or world.game_map.explored.size() < 50:
		_fail("A new process did not restore the saved game.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
		_fail("Restart test data could not be removed.")
		return
	print("Window-close save restored in a new process")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
