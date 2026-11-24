extends SceneTree


func _initialize() -> void:
	call_deferred("_test")


func _frames(count: int) -> void:
	for index in count:
		await physics_frame


func _test() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(5)
	scene._enter_car()
	scene.car.impact.emit(7.0)
	if scene.player.health != 100:
		_fail("A low-speed contact caused damage.")
		return
	scene.car.uses_local_input = false
	scene.car.position = Vector3(-16.0, 0.5, -6.0)
	scene.car.rotation = Vector3(0, -PI / 2.0, 0)
	scene.car.velocity = Vector3.ZERO
	await _frames(3)
	scene.car.movement_input = Vector2.RIGHT
	await _frames(35)
	var after_impact: int = scene.player.health
	if after_impact < 55 or after_impact > 57:
		_fail("Driving into a building should cause one impact of damage: %d" % after_impact)
		return
	await _frames(60)
	if scene.player.health != after_impact:
		_fail("Holding the car against a wall caused repeated damage.")
		return
	scene._process(0.0)
	if int(scene.health_bar.value) != after_impact or not scene.health_label.text.contains(str(after_impact)):
		_fail("The health display did not reflect the driver's damage.")
		return
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1, 3, 50)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	scene.add_child(wall)
	wall.position = Vector3(8, 1.5, 0)
	scene.car.position = Vector3(3, 0.5, -12)
	scene.car.rotation.y = -3.0 * PI / 4.0
	scene.car.velocity = Vector3.ZERO
	await _frames(3)
	scene.car.movement_input = Vector2(1, 1).normalized()
	await _frames(25)
	var sliding_health: int = scene.player.health
	if sliding_health >= after_impact or sliding_health <= 0:
		_fail("The diagonal impact did not cause nonfatal damage: %d -> %d, position %s, velocity %s" % [after_impact, sliding_health, scene.car.position, scene.car.get_real_velocity()])
		return
	await _frames(20)
	if scene.player.health != sliding_health:
		_fail("A diagonal collision caused repeated damage while against a wall.")
		return
	wall.queue_free()
	scene.car.movement_input = Vector2.ZERO
	scene.car.position = Vector3(0, 0.5, 0)
	scene.car.velocity = Vector3.ZERO
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(35, 3, 35)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	blocker.position = Vector3(0, 1.5, 0)
	await _frames(3)
	scene.car.impact.emit(40.0)
	if scene.in_car or scene.car.occupied or scene.player.health != 0:
		_fail("Fatal damage did not release the vehicle.")
		return
	await _frames(5)
	if scene.player.health != 0 or scene.player.visible:
		_fail("The player respawned into an obstructed start area.")
		return
	blocker.queue_free()
	await _frames(5)
	if scene.player.health != 25 or not scene.player.visible or scene.player.collision_layer == 0:
		_fail("The player did not respawn with 25 health.")
		return
	if scene.player.global_position.distance_to(scene.player.spawn_position) > 4.0 or scene.player.global_position.distance_to(scene.car.global_position) < 1.0:
		_fail("The player respawned at an unsafe or distant position.")
		return
	print("Collision damage, no repeated wall damage, HUD and safe respawn passed")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
