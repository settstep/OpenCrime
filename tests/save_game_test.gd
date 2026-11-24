extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const OSMMap = preload("res://scripts/osm_map.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	SaveStore.directory = "user://save_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory := SaveStore.directory
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	menu.get_node("PlaceSelection")._on_start_pressed()
	await process_frame
	var world = current_scene
	var first_id: String = world.save_id
	if first_id.is_empty() or SaveStore.read_slot(first_id).error != OK:
		_fail("Starting a game did not create its own save.")
		return
	var snapshot: Dictionary = world.get_node("OSMMap").get_meta("place").duplicate(true)
	snapshot.id = "only_in_save"
	world.get_node("OSMMap").set_meta("place", snapshot)
	world.player.global_position = Vector3(1, 0.9, 0)
	world.car.global_position = Vector3(0, 0.5, -5)
	world.car.global_rotation.y = 0.75
	world._enter_car()
	world.player.health = 63
	world.game_map.update_position(Vector3(100, 0, 100))
	world._process(world.AUTOSAVE_INTERVAL + 1.0)
	var saved := SaveStore.read_slot(first_id)
	if saved.error != OK or not saved.data.in_car or absf(float(saved.data.car_rotation) - 0.75) > 0.001 or saved.data.explored.size() < 50:
		_fail("Autosave lost the car state or exploration.")
		return
	if saved.data.health != 63:
		_fail("Autosave lost the player's health.")
		return
	var legacy: Dictionary = saved.data.duplicate(true)
	legacy.erase("health")
	if not SaveStore.is_valid(legacy):
		_fail("Old saves without health should remain valid.")
		return
	var bad_health: Dictionary = saved.data.duplicate(true)
	for value in [-1, 101, 2.5, 0]:
		bad_health.health = value
		if SaveStore.is_valid(bad_health):
			_fail("Invalid health or an incapacitated driver was accepted.")
			return
	var invalid: Dictionary = saved.data.duplicate(true)
	invalid.in_car = "yes"
	if SaveStore.write_slot(invalid) != ERR_INVALID_DATA or SaveStore.read_slot(first_id).data.in_car != true:
		_fail("An invalid update replaced a valid save.")
		return
	world._open_pause_menu()
	var pause: Control = world.get_node("PauseMenu/Menu")
	if not pause.get_node("Panel/Options/SaveGame").visible:
		_fail("Single-player pause menu has no save button.")
		return
	pause.get_node("Panel/Options/SaveGame").pressed.emit()
	if not pause.get_node("Panel/Options/Message").text.contains("gespeichert"):
		_fail("Manual save did not report success.")
		return
	pause.get_node("Panel/Options/SaveGameAs").pressed.emit()
	var branch_id: String = world.save_id
	if branch_id == first_id or SaveStore.read_slot(branch_id).error != OK or SaveStore.read_slot(first_id).error != OK:
		_fail("Saving as a new slot did not preserve the previous save.")
		return
	world.car.global_position.x = 2.0
	pause.get_node("Panel/Options/SaveGame").pressed.emit()
	if absf(float(SaveStore.read_slot(first_id).data.car_position[0])) > 0.01 or absf(float(SaveStore.read_slot(branch_id).data.car_position[0]) - 2.0) > 0.01:
		_fail("Saving one branch changed a different slot.")
		return
	world.car.global_position.x = 0.0
	if SaveStore.delete_slot(first_id) != OK:
		_fail("Original test branch could not be removed.")
		return
	first_id = branch_id
	var blocker_path := directory.path_join("blocker")
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("block")
	blocker.close()
	SaveStore.directory = blocker_path.path_join("saves")
	pause.get_node("Panel/Options/SaveGameAs").pressed.emit()
	if world.save_id != first_id:
		_fail("A failed save-as changed the active slot.")
		return
	pause.get_node("Panel/Options/ReturnToMenu").pressed.emit()
	if current_scene != world or not paused or not pause.get_node("Panel/Options/Message").text.contains("nicht gespeichert"):
		_fail("A save failure did not prevent leaving the game.")
		return
	SaveStore.directory = directory
	pause.get_node("Panel/Options/ReturnToMenu").pressed.emit()
	await process_frame
	if current_scene.name != "Menu" or paused:
		_fail("Returning to menu after saving failed.")
		return
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	var selection = menu.get_node("SaveSelection")
	var original_scale: Variant = ProjectSettings.get_setting(OSMMap.SCALE_SETTING)
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, 1.0 if float(original_scale) == 2.0 else 2.0)
	selection._on_load_pressed()
	if current_scene != menu or not selection.info.text.contains("Kartenfaktor"):
		_fail("An incompatible map scale was not rejected.")
		return
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, original_scale)
	selection._on_load_pressed()
	await process_frame
	world = current_scene
	if world.save_id != first_id or not world.in_car or not world.car.occupied or world.player.visible or world.player.collision_layer != 0:
		_fail("Loading did not restore the player inside the car.")
		return
	if world.player.health != 63:
		_fail("Loading did not restore the player's health.")
		return
	if world.get_node("OSMMap").get_meta("place").id != "only_in_save":
		_fail("Loading did not restore the embedded place snapshot.")
		return
	if world.car.global_position.distance_to(Vector3(0, 0.5, -5)) > 0.01 or absf(world.car.global_rotation.y - 0.75) > 0.001 or world.game_map.explored.size() < 50:
		_fail("Loading did not restore the car position, rotation or explored map.")
		return
	for i in range(10):
		await physics_frame
	var car_start: Vector3 = world.car.position
	Input.action_press("move_forward")
	for i in range(12):
		await physics_frame
	Input.action_release("move_forward")
	if world.car.position.distance_to(car_start) < 0.5:
		_fail("The restored car could not be driven.")
		return
	world._exit_car()
	if world.in_car or not world.player.visible or world.player.collision_layer == 0:
		_fail("The restored player could not exit the car.")
		return
	world._open_pause_menu()
	world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	menu.get_node("PlaceSelection")._on_start_pressed()
	await process_frame
	world = current_scene
	var second_id: String = world.save_id
	if second_id == first_id or SaveStore.read_slot(first_id).error != OK or SaveStore.read_slot(second_id).error != OK:
		_fail("Starting a second game overwrote the first save.")
		return
	world._open_pause_menu()
	world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	selection = menu.get_node("SaveSelection")
	if selection.slots.size() != 2:
		_fail("The save list does not contain both games.")
		return
	var second_index := 0
	for slot in selection.slots:
		if slot.id == second_id:
			break
		second_index += 1
	selection.list.select(second_index)
	selection._on_delete_pressed()
	if not selection.confirmation.visible or SaveStore.read_slot(second_id).error != OK:
		_fail("Deleting a save did not require confirmation.")
		return
	selection.confirmation.confirmed.emit()
	if SaveStore.read_slot(second_id).error == OK or SaveStore.read_slot(first_id).error != OK or selection.slots.size() != 1:
		_fail("Deleting a save affected the wrong slot.")
		return
	var corrupt_id := SaveStore.new_id()
	var corrupt := FileAccess.open(directory.path_join(corrupt_id + ".json"), FileAccess.WRITE)
	corrupt.store_string("{invalid")
	corrupt.close()
	selection._refresh()
	var corrupt_index := 0
	for slot in selection.slots:
		if slot.id == corrupt_id:
			break
		corrupt_index += 1
	selection.list.select(corrupt_index)
	selection._on_load_pressed()
	if current_scene != menu or not selection.info.text.contains("nicht gelesen"):
		_fail("A corrupt save was not reported.")
		return
	if SaveStore.delete_slot(corrupt_id) != OK:
		_fail("Corrupt test save could not be removed.")
		return
	selection._refresh()
	var index := 0
	for slot in selection.slots:
		if slot.id == first_id:
			break
		index += 1
	selection.list.select(index)
	var old_save: Dictionary = SaveStore.read_slot(first_id).data
	old_save.erase("health")
	if SaveStore.write_slot(old_save) != OK:
		_fail("The old save could not be written for the migration test.")
		return
	selection._on_load_pressed()
	await process_frame
	world = current_scene
	if world.in_car or not world.player.visible or world.player.collision_layer == 0 or world.save_id != first_id:
		_fail("The on-foot state was not restored.")
		return
	if world.player.health != 100:
		_fail("Old saves did not start with full health.")
		return
	if not world._damage_player(world.player, 40.0) or not world.save_game():
		_fail("Saving a player waiting to respawn failed.")
		return
	world._open_pause_menu()
	world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	menu.get_node("SaveSelection")._on_load_pressed()
	await process_frame
	world = current_scene
	for i in range(5):
		await physics_frame
	if world.player.health != 25 or not world.player.visible:
		_fail("Loading an incapacitated player did not complete the respawn.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(first_id) != OK:
		_fail("Test saves could not be removed.")
		return
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker_path)) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(directory)) != OK:
		_fail("Test directory could not be cleaned up.")
		return
	print("Multiple saves, autosave, failures and on-foot/in-car restore passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
