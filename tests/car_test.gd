extends SceneTree


func _initialize() -> void:
	call_deferred("_test")


func _advance_frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func _interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await _advance_frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await _advance_frames(2)


func _test() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	var car: CharacterBody3D = scene.get_node("Car")
	var camera: Camera3D = scene.get_node("Camera3D")
	var status: Label = scene.get_node("HUD/Status")
	await _advance_frames(10)

	await _interact()
	if not player.visible or status.text.is_empty():
		_fail("Entering from too far away should not work.")
		return

	Input.action_press("move_forward")
	await _advance_frames(20)
	Input.action_release("move_forward")
	await _interact()
	if player.visible or player.collision_layer != 0:
		_fail("Entering the nearby car failed.")
		return

	var start_x := car.position.x
	Input.action_press("move_right")
	await _advance_frames(30)
	Input.action_release("move_right")
	await _advance_frames(3)
	if car.position.x <= start_x + 2.0 or absf(car.position.z + 5.0) > 0.1:
		_fail("Driving right did not move in the expected world direction.")
		return
	var diagonal_start := car.position
	Input.action_press("move_right")
	Input.action_press("move_forward")
	await _advance_frames(15)
	if car.position.x <= diagonal_start.x + 1.0 or car.position.z >= diagonal_start.z - 1.0 or not is_equal_approx(Vector2(car.velocity.x, car.velocity.z).length(), 10.0):
		_fail("Diagonal driving failed.")
		return
	Input.action_release("move_right")
	Input.action_release("move_forward")
	await _advance_frames(3)
	await process_frame
	if absf(camera.global_position.x - car.global_position.x) > 0.1:
		_fail("The camera did not follow the car.")
		return

	await _interact()
	if not player.visible or player.collision_layer == 0:
		_fail("Exiting the car failed.")
		return
	var player_start := player.position
	Input.action_press("move_right")
	await _advance_frames(20)
	Input.action_release("move_right")
	if player.position.x <= player_start.x + 0.5:
		_fail("The player cannot move after exiting.")
		return

	player.position = car.position + Vector3(2, 0.4, 0)
	player.velocity = Vector3.ZERO
	await _advance_frames(3)
	await _interact()
	if player.visible:
		_fail("Re-entering the car failed.")
		return

	car.position = Vector3(-14.0, 0.5, -6.0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	await _advance_frames(3)
	Input.action_press("move_right")
	await _advance_frames(50)
	Input.action_release("move_right")
	await _advance_frames(3)
	if car.position.x < -12.3 or car.position.x > -12.05:
		_fail("The car did not stop at the building: " + str(car.position))
		return
	await _interact()
	if not player.visible:
		_fail("Exiting beside a building should use a free position.")
		return

	await _interact()
	if player.visible:
		_fail("Re-entering beside a building failed.")
		return
	car.position = Vector3(-11.5, 0.5, -6.0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	await _advance_frames(3)
	Input.action_press("move_right")
	await _advance_frames(20)
	Input.action_release("move_right")
	if absf(car.rotation.y) > 0.01 or car.position.x > -11.45:
		_fail("The car turned into the building.")
		return

	car.position = Vector3(0, 0.5, 0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	var blockers: Array[StaticBody3D] = []
	for offset in [Vector3(1.7, 1, 0), Vector3(-1.7, 1, 0), Vector3(0, 1, 2.4), Vector3(0, 1, -2.4)]:
		var blocker := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1, 2, 1)
		shape.shape = box
		blocker.add_child(shape)
		scene.add_child(blocker)
		blocker.position = offset
		blockers.append(blocker)
	await _advance_frames(5)
	await _interact()
	if player.visible or status.text.is_empty():
		_fail("Exiting into an obstruction should be rejected.")
		return
	for blocker in blockers:
		blocker.queue_free()
	await _advance_frames(3)

	car.position = Vector3(24.5, 0.5, 0)
	car.velocity = Vector3.ZERO
	await _advance_frames(3)
	await _interact()
	if not player.visible or player.position.x >= 25.0:
		_fail("Exiting should avoid positions outside the ground.")
		return

	print("Car entry, driving, collisions, camera and exit passed")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
