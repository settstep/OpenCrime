extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _test() -> void:
	SaveStore.directory = "user://mission_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
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
	if not world.mission_ready or world.mission_ui.state.player.offers.size() != 1:
		_fail("The first SMS was not displayed.")
		return
	var health_hud: Control = world.get_node("HUD/Health")
	var mission_summary: Control = world.mission_ui.get_node("Summary")
	var mission_notice: Control = world.mission_ui.get_node("Notice")
	if mission_summary.get_global_rect().intersects(health_hud.get_global_rect()) or mission_summary.get_global_rect().intersects(mission_notice.get_global_rect()):
		_fail("The mission summary overlaps the health HUD or its notice.")
		return
	if not world.mission_ui.details.text.contains("Hauptauftrag"):
		_fail("The story mission was not identified in the SMS.")
		return
	var key := InputEventAction.new()
	key.action = "show_missions"
	key.pressed = true
	world._unhandled_input(key)
	if not world.missions_open or not paused:
		_fail("Opening SMS did not pause the single-player game.")
		return
	world.mission_ui.get_node("Panel/Layout/Buttons/Accept").pressed.emit()
	var active: String = world.mission_manager.players[1].active
	if active.is_empty() or not world.mission_marker.visible or not world.game_map.has_mission_target:
		_fail("Accepting SMS did not create an active mission and markers.")
		return
	world._close_missions()
	var mission: Dictionary = world.mission_manager.missions[active]
	if not world.mission_ui.details.text.contains(mission.pickup_label) or not world.mission_ui.details.text.contains(mission.destination_label):
		_fail("The mission screen did not show pickup and delivery locations.")
		return
	world.player.global_position = Vector3(mission.pickup[0], 0.9, mission.pickup[1])
	world.in_car = true
	world._physics_process(0)
	if mission.stage != 0:
		_fail("A player in a car collected the package.")
		return
	world.in_car = false
	world._physics_process(0)
	if mission.stage != 1 or not world.mission_ui.details.text.contains("✓"):
		_fail("Pickup did not update mission progress.")
		return
	if not world.save_game():
		_fail("Could not save an active mission.")
		return
	world._return_to_main_menu()
	await process_frame
	menu = current_scene
	menu.get_node("Panel/Options/LoadGame").pressed.emit()
	await process_frame
	menu.get_node("SaveSelection")._on_load_pressed()
	await process_frame
	world = current_scene
	if world.mission_manager.players[1].active != active or world.mission_manager.missions[active].stage != 1 or not world.mission_marker.visible:
		_fail("Loading lost the active mission or marker.")
		return
	mission = world.mission_manager.missions[active]
	world.player.global_position = Vector3(mission.destination[0], 0.9, mission.destination[1])
	world._physics_process(0)
	if world.mission_manager.players[1].money != 100 or not world.mission_manager.players[1].completed.has("first_delivery"):
		_fail("Delivery did not record the payout and story completion.")
		return
	if not world.save_game():
		_fail("Could not save the completed mission.")
		return
	world.queue_free()
	await process_frame
	var saved := SaveStore.read_slot(id)
	if saved.error != OK or saved.data.mission.player.money != 100 or not saved.data.mission.player.completed.has("first_delivery"):
		_fail("Completed mission progress was not persisted.")
		return
	menu = MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu._on_save_chosen(saved.data)
	await process_frame
	world = current_scene
	var offered_id: String = world.mission_manager.players[1].offers[0]
	if world.mission_manager.players[1].money != 100 or world.mission_manager.missions[offered_id].type != "recurring":
		_fail("Reloading a completed story mission did not preserve money or the next offer.")
		return
	world.queue_free()
	await process_frame
	saved.data.erase("mission")
	if SaveStore.write_slot(saved.data) != OK:
		_fail("Could not create a legacy save.")
		return
	menu = MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu._on_save_chosen(SaveStore.read_slot(id).data)
	await process_frame
	world = current_scene
	if not world.mission_ready or world.mission_manager.players[1].offers.is_empty():
		_fail("An older save did not receive an introductory mission.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
		_fail("Could not remove the isolated test save.")
		return
	print("Mission UI, single-player pickup, delivery and save migration passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
