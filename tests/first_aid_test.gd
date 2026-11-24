extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const FirstAid = preload("res://scripts/first_aid.gd")


func _initialize() -> void:
	call_deferred("_test")


func _press_f(world: Node) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	world._unhandled_input(key)


func _test() -> void:
	var suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	SaveStore.directory = "user://first_aid_saves_" + suffix
	FirstAid.config_path = "user://first_aid_" + suffix + ".json"
	var candidates: Array[Dictionary] = [{"point": Vector2(10, 0)}, {"point": Vector2(3, 0)}]
	var defaults := FirstAid.setup(candidates, Vector2.ZERO)
	if defaults.has("error") or defaults.point != Vector2(3, 0) or not FileAccess.file_exists(FirstAid.config_path):
		_fail("The default settings or nearest station were not created.")
		return
	var file := FileAccess.open(FirstAid.config_path, FileAccess.WRITE)
	file.store_string('{"price": 0, "healing": 50}')
	file.close()
	if not FirstAid.setup(candidates, Vector2.ZERO).has("error"):
		_fail("An invalid price was accepted.")
		return
	file = FileAccess.open(FirstAid.config_path, FileAccess.WRITE)
	file.store_string('{"price": 13, "healing": 27}')
	file.close()
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.get_node("Panel/Options/SinglePlayer").pressed.emit()
	await process_frame
	menu.get_node("PlaceSelection")._on_start_pressed()
	await process_frame
	var world = current_scene
	var id: String = world.save_id
	if world.first_aid.price != 13 or world.first_aid.healing != 27 or not world.first_aid_marker.visible or not world.game_map.has_first_aid:
		_fail("Custom station settings or markers were not applied.")
		return
	file = FileAccess.open(FirstAid.config_path, FileAccess.WRITE)
	file.store_string('{"price": 13, "healing": 101}')
	file.close()
	world._setup_first_aid()
	if world.first_aid_marker.visible or world.game_map.has_first_aid or world.first_aid_prompt.text.is_empty() or not world.mission_ready:
		_fail("Invalid settings were not displayed or incorrectly disabled missions.")
		return
	file = FileAccess.open(FirstAid.config_path, FileAccess.WRITE)
	file.store_string('{"price": 13, "healing": 27}')
	file.close()
	world._setup_first_aid()
	var point: Vector2 = world.first_aid.point
	world.player.health = 20
	world.player.global_position = Vector3(point.x + 10, 0.9, point.y)
	_press_f(world)
	if not world.status.text.contains("näher") or world.player.health != 20:
		_fail("Healing was possible away from the station.")
		return
	world.player.global_position = Vector3(point.x, 0.9, point.y)
	world._process(0.0)
	if not world.first_aid_prompt.text.contains("13") or not world.first_aid_prompt.text.contains("27"):
		_fail("The station prompt does not display its configured treatment.")
		return
	_press_f(world)
	if not world.status.text.contains("Nicht genug Geld") or world.player.health != 20:
		_fail("A player without enough money was treated.")
		return
	var mission_id: String = world.mission_manager.players[1].offers[0]
	if not world.mission_manager.accept(1, mission_id).is_empty():
		_fail("Could not accept the delivery mission.")
		return
	var mission: Dictionary = world.mission_manager.missions[mission_id]
	world.mission_manager.visit(1, Vector3(mission.pickup[0], 0, mission.pickup[1]), true)
	world.mission_manager.visit(1, Vector3(mission.destination[0], 0, mission.destination[1]), true)
	if world.mission_manager.players[1].money != 100:
		_fail("The delivery did not pay the player.")
		return
	_press_f(world)
	if world.player.health != 47 or world.mission_manager.players[1].money != 87 or not world.mission_ui.summary.text.contains("87"):
		_fail("Treatment did not update health, money and HUD using the custom values.")
		return
	world.player.health = 95
	_press_f(world)
	if world.player.health != 100 or world.mission_manager.players[1].money != 74:
		_fail("Treatment did not cap health at 100.")
		return
	_press_f(world)
	if world.mission_manager.players[1].money != 74 or not world.status.text.contains("bereits voll"):
		_fail("Full health was charged.")
		return
	world.player.health = 30
	world.in_car = true
	_press_f(world)
	world.in_car = false
	if world.player.health != 30 or world.mission_manager.players[1].money != 74 or not world.status.text.contains("aussteigen"):
		_fail("A player in a vehicle was treated.")
		return
	world.mission_manager.players[1].money = 12
	_press_f(world)
	if world.player.health != 30 or world.mission_manager.players[1].money != 12:
		_fail("An unaffordable treatment changed health or money.")
		return
	world.mission_manager.players[1].money = 74
	_press_f(world)
	if world.player.health != 57 or world.mission_manager.players[1].money != 61:
		_fail("The final treatment failed.")
		return
	if not world.save_game():
		_fail("Could not save treatment state.")
		return
	world._return_to_main_menu()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	menu.get_node("SaveSelection")._on_load_pressed()
	await process_frame
	world = current_scene
	if world.player.health != 57 or world.mission_manager.players[1].money != 61 or world.first_aid.point != point:
		_fail("Reloading lost health, money or station position.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(FirstAid.config_path)) != OK:
		_fail("Could not clean up isolated test files.")
		return
	print("First-aid configuration, treatment, constraints and save/load passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
