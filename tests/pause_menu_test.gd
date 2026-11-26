extends SceneTree

const MainScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.05, true).timeout
	var release := InputEventKey.new()
	release.keycode = KEY_ESCAPE
	release.pressed = false
	Input.parse_input_event(release)
	await create_timer(0.05, true).timeout


func _test() -> void:
	var world := MainScene.instantiate()
	root.add_child(world)
	current_scene = world
	for i in range(10):
		await physics_frame
	var player: CharacterBody3D = world.get_node("Player")
	await _escape()
	if not paused or not world.menu_open:
		_fail("Escape did not open the paused menu.")
		return
	var menu: Control = world.get_node("PauseMenu/Menu")
	if not menu.get_node("Panel/Options/Resume").visible or not menu.get_node("Panel/Options/ResetToMap").visible or not menu.get_node("Panel/Options/Quit").visible:
		_fail("Pause menu options are missing.")
		return
	var health: int = player.health
	player.global_position = Vector3(100, 50, 100)
	menu.get_node("Panel/Options/ResetToMap").pressed.emit()
	await process_frame
	if player.global_position.distance_to(player.spawn_position) > 1.0 or player.health != health:
		_fail("The on-foot reset did not return the player safely without changing health.")
		return
	var start := player.position
	Input.action_press("move_forward")
	for i in range(10):
		await process_frame
	if player.position != start:
		_fail("The single-player world moved while paused.")
		return
	Input.action_release("move_forward")
	menu.get_node("Panel/Options/Resume").pressed.emit()
	await process_frame
	if paused or world.menu_open or world.has_node("PauseMenu"):
		_fail("Resume did not close the pause menu.")
		return
	Input.action_press("move_forward")
	for i in range(20):
		await physics_frame
	Input.action_release("move_forward")
	if player.position.z >= start.z - 1.0:
		_fail("The player did not resume moving.")
		return
	world._enter_car()
	world.active_car.global_position = Vector3(100, 50, 100)
	await _escape()
	menu = world.get_node("PauseMenu/Menu")
	menu.get_node("Panel/Options/ResetToMap").pressed.emit()
	if not world.in_car or world.active_car.global_position.distance_to(Vector3(0, 0.5, -5)) > 2.0:
		_fail("The vehicle reset did not return the driven car to its map spawn: %s (%s)" % [world.active_car.global_position, world.status.text])
		return
	menu.get_node("Panel/Options/Resume").pressed.emit()
	await process_frame
	if paused or world.menu_open:
		_fail("Resume after resetting the vehicle did not close the pause menu.")
		return
	await _escape()
	await _escape()
	if paused or world.menu_open:
		_fail("Escape did not close the pause menu.")
		return
	await _escape()
	world.get_node("PauseMenu/Menu/Panel/Options/ReturnToMenu").pressed.emit()
	await process_frame
	if paused or current_scene.name != "Menu":
		_fail("Returning to the main menu failed.")
		return
	if not current_scene.get_node("Panel/Options/Quit").visible:
		_fail("The main menu has no quit button.")
		return
	print("Pause menu, resume and return passed; testing quit button")
	current_scene.get_node("Panel/Options/Quit").pressed.emit()
	await create_timer(1.0, true).timeout
	_fail("The quit button did not exit the game.")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
