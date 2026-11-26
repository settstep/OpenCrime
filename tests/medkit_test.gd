extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const PlayerScript = preload("res://scripts/player.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _press_h(world: Node) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	key.pressed = true
	world._unhandled_input(key)


func _test() -> void:
	SaveStore.directory = "user://medkit_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
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
	var pickup := Vector2(world.player.global_position.x, world.player.global_position.z)
	world._set_medkit_state({"point": pickup, "available": true, "healing": PlayerScript.MEDKIT_HEALING})
	if not world._try_pickup_medkit(world.player, true) or world.player.medkits != 1 or world.medkit_state.available or world.game_map.has_medkit:
		_fail("The nearby first-aid kit was not picked up exactly once.")
		return
	world.player.medkits = 0
	world.medkit_state.available = true
	world.in_car = true
	if world._try_pickup_medkit(world.player, not world.in_car) or not world.medkit_state.available:
		_fail("A player inside a vehicle picked up the kit.")
		return
	world.in_car = false
	world.player.medkits = PlayerScript.MAX_MEDKITS
	world.medkit_state.available = true
	if world._try_pickup_medkit(world.player, true) or world.player.medkits != PlayerScript.MAX_MEDKITS:
		_fail("A player with a full inventory picked up another kit.")
		return
	world.player.medkits = 1
	world.player.health = PlayerScript.MAX_HEALTH
	world._use_medkit(world.player, false)
	if world.player.medkits != 1 or world.player.health != PlayerScript.MAX_HEALTH:
		_fail("A kit was consumed at full health.")
		return
	world.player.health = 60
	world.in_car = true
	_press_h(world)
	world.in_car = false
	if world.player.medkits != 1 or world.player.health != 60:
		_fail("A kit was consumed while inside a vehicle.")
		return
	world.player.health = 0
	_press_h(world)
	if world.player.medkits != 1 or world.player.health != 0:
		_fail("A kit was consumed while incapacitated.")
		return
	world.player.health = 60
	_press_h(world)
	if world.player.medkits != 0 or world.player.health != PlayerScript.MAX_HEALTH:
		_fail("Using a kit did not heal up to the health limit.")
		return
	world.player.health = 20
	world.player.medkits = 1
	_press_h(world)
	if world.player.medkits != 0 or world.player.health != 70:
		_fail("Using a kit did not apply the configured healing amount.")
		return
	world.player.medkits = 2
	world.medkit_state.available = false
	world.medkit_state.point = Vector2(12.5, -4.0)
	if not world.save_game():
		_fail("Could not save inventory state.")
		return
	var id: String = world.save_id
	var saved := SaveStore.read_slot(id)
	if saved.error != OK or saved.data.inventory.medkits != 2 or saved.data.inventory.pickup_available or saved.data.inventory.pickup_position != [12.5, -4.0]:
		_fail("The save did not preserve the inventory and pickup state.")
		return
	var legacy: Dictionary = saved.data.duplicate(true)
	legacy.erase("inventory")
	if not SaveStore.is_valid(legacy):
		_fail("A legacy save without inventory was rejected.")
		return
	var invalid: Dictionary = saved.data.duplicate(true)
	invalid.inventory.medkits = PlayerScript.MAX_MEDKITS + 1
	if SaveStore.is_valid(invalid):
		_fail("An inventory above capacity was accepted.")
		return
	world._return_to_main_menu()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	menu.get_node("SaveSelection")._on_load_pressed()
	await process_frame
	world = current_scene
	if world.player.medkits != 2 or world.medkit_state.available or world.medkit_state.point != Vector2(12.5, -4.0) or world.medkit_marker.visible:
		_fail("Loading did not restore the inventory or hidden pickup.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(directory)) != OK:
		_fail("Could not clean up medkit test files.")
		return
	print("Medkit pickup, use constraints and save/load passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
