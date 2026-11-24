extends SceneTree

const MenuScene = preload("res://scenes/menu.tscn")
const SaveStore = preload("res://scripts/save_store.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const MainScene = preload("res://scenes/main.tscn")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	if not await _check_place("gendarmenmarkt"):
		return
	if not await _check_place("thalhofen"):
		return
	SaveStore.directory = "user://multicar_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu._on_single_pressed()
	await process_frame
	menu.get_node("PlaceSelection")._on_start_pressed()
	await process_frame
	var world = current_scene
	var id: String = world.save_id
	if world.cars.size() != 3:
		_fail("The saved place did not create three cars.")
		return
	for index in range(world.cars.size()):
		for other in range(index):
			if world.cars[index].global_position.distance_to(world.cars[other].global_position) < 6.0:
				_fail("Spawned cars overlap.")
				return
		world.cars[index].global_rotation.y = index * 0.2
	world.player.global_position = world.cars[1].global_position + Vector3(0, 0.4, 2.4)
	world.interact_requested = true
	world._physics_process(0.0)
	if not world.in_car or world.active_car != world.cars[1] or not world.cars[1].occupied or world.car.occupied:
		_fail("Interaction did not enter the nearest car.")
		return
	world._process(0.0)
	if Vector2(world.camera.global_position.x, world.camera.global_position.z).distance_to(Vector2(world.cars[1].global_position.x, world.cars[1].global_position.z)) > 0.01 or world.game_map.player_position.distance_to(Vector2(world.cars[1].global_position.x, world.cars[1].global_position.z)) > 0.01:
		_fail("Camera or map did not follow the selected car.")
		return
	var health: int = world.player.health
	world.car.impact.emit(18.0)
	if world.player.health != health:
		_fail("A different car damaged the player.")
		return
	world.cars[1].impact.emit(18.0)
	if world.player.health >= health:
		_fail("The occupied car did not damage the player.")
		return
	world._update_car_map()
	if world.game_map.car_positions.size() != 3:
		_fail("The map did not receive all cars.")
		return
	if not world.save_game():
		_fail("Could not save multiple cars.")
		return
	var saved: Dictionary = SaveStore.read_slot(id).data
	if saved.vehicles.size() != 3 or saved.active_vehicle != 1:
		_fail("The save did not record all cars and the active car.")
		return
	var invalid: Dictionary = saved.duplicate(true)
	invalid.active_vehicle = 3
	if SaveStore.is_valid(invalid):
		_fail("An invalid occupied car index was accepted.")
		return
	invalid = saved.duplicate(true)
	invalid.vehicles[1].position = [1, 2]
	if SaveStore.is_valid(invalid):
		_fail("An invalid car position was accepted.")
		return
	world._return_to_main_menu()
	await process_frame
	menu = current_scene
	menu._on_save_chosen(SaveStore.read_slot(id).data)
	await process_frame
	world = current_scene
	if world.cars.size() != 3 or not world.in_car or world.active_car != world.cars[1] or not world.cars[1].occupied:
		_fail("Loading did not restore the occupied second car.")
		return
	for index in world.cars.size():
		var point: Array = saved.vehicles[index].position
		var expected := Vector3(float(point[0]), float(point[1]), float(point[2]))
		if world.cars[index].global_position.distance_to(expected) > 0.1 or absf(world.cars[index].global_rotation.y - float(saved.vehicles[index].rotation)) > 0.01:
			_fail("Loading did not restore car %d: position %s, rotation %s" % [index, world.cars[index].global_position, world.cars[index].global_rotation.y])
			return
	world.queue_free()
	await process_frame
	saved.erase("vehicles")
	saved.erase("active_vehicle")
	if SaveStore.write_slot(saved) != OK:
		_fail("Could not create an old single-car save.")
		return
	menu = MenuScene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu._on_save_chosen(SaveStore.read_slot(id).data)
	await process_frame
	world = current_scene
	var old_position := Vector3(float(saved.car_position[0]), float(saved.car_position[1]), float(saved.car_position[2]))
	if not world.in_car or world.active_car != world.car or not world.car.occupied or world.cars.size() != 3 or world.car.global_position.distance_to(old_position) > 0.1:
		_fail("An old single-car save was not migrated.")
		return
	world.queue_free()
	await process_frame
	if SaveStore.delete_slot(id) != OK or DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.directory)) != OK:
		_fail("Could not clean up isolated saves.")
		return
	print("Multiple cars, independent damage, map, save and legacy migration passed")
	quit(0)


func _check_place(id: String) -> bool:
	var place := PlaceStore.find_by_id(id)
	var world := MainScene.instantiate()
	if not OSMMap.populate(world, place):
		_fail("The bundled place could not be loaded: " + id)
		return false
	root.add_child(world)
	await physics_frame
	await physics_frame
	if world.cars.size() != 3:
		_fail("The bundled place did not create three cars: " + id)
		return false
	for index in range(1, world.cars.size()):
		var vehicle: CharacterBody3D = world.cars[index]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = vehicle.get_node("CollisionShape3D").shape
		query.transform = vehicle.global_transform.translated(Vector3.UP * 0.05)
		query.collision_mask = vehicle.collision_mask
		query.exclude = [vehicle.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			_fail("An additional car spawned inside an obstacle: " + id)
			return false
	world.queue_free()
	await process_frame
	return true


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
