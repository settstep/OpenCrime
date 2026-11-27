extends SceneTree

const PlayerScene = preload("res://scenes/player.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const Grid = preload("res://scripts/map_block_grid.gd")

const ORIGIN := [47.7748417, 10.6034933]


func _initialize() -> void:
	call_deferred("_test")


func _frames(count: int) -> void:
	for index in count:
		await physics_frame


func _way(reverse: bool) -> Dictionary:
	var zone := Grid.zone_for_origin(ORIGIN)
	var origin := Grid.project(ORIGIN, zone, true)
	var points := [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]
	if reverse:
		points.reverse()
	points.append(points[0])
	var geometry := []
	for point in points:
		geometry.append(Grid.unproject([origin[0] + point.x, origin[1] + point.y], zone, true))
	return {"id": 1, "tags": {"building": "yes"}, "geometry": geometry}


func _test() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(100, 1, 100)
	ground_collision.shape = ground_shape
	ground.position.y = -0.5
	ground.add_child(ground_collision)
	world.add_child(ground)
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.uses_local_input = false
	world.add_child(player)
	for reverse in [false, true]:
		var map := Node3D.new()
		world.add_child(map)
		OSMMap._add_building(map, _way(reverse), StandardMaterial3D.new(), 1.0, ORIGIN)
		for side in [
			{"start": Vector3(-2, 0.9, -5), "inward": Vector2.RIGHT, "tangent": Vector2.DOWN},
			{"start": Vector3(12, 0.9, -5), "inward": Vector2.LEFT, "tangent": Vector2.UP},
			{"start": Vector3(5, 0.9, 2), "inward": Vector2.UP, "tangent": Vector2.RIGHT},
			{"start": Vector3(5, 0.9, -12), "inward": Vector2.DOWN, "tangent": Vector2.LEFT},
		]:
			player.global_position = side.start
			player.velocity = Vector3.ZERO
			player.movement_input = side.inward
			await _frames(40)
			var at_wall := player.global_position
			var travelled := Vector2(at_wall.x - side.start.x, at_wall.z - side.start.z).dot(side.inward)
			if travelled < 1.4 or travelled > 1.65:
				_fail("Player crossed or did not reach wall (reverse=%s): %s" % [reverse, at_wall])
				return
			player.movement_input = -side.inward
			await _frames(20)
			var away := player.global_position
			if Vector2(away.x - at_wall.x, away.z - at_wall.z).dot(-side.inward) < 1.0:
				_fail("Player could not reverse directly at wall (reverse=%s): %s -> %s" % [reverse, at_wall, away])
				return
			player.movement_input = side.inward
			await _frames(30)
			at_wall = player.global_position
			player.movement_input = (side.inward + side.tangent).normalized()
			await _frames(20)
			var sliding := player.global_position
			var slide_delta := Vector2(sliding.x - at_wall.x, sliding.z - at_wall.z)
			if slide_delta.dot(side.tangent) < 0.8 or slide_delta.dot(side.inward) > 0.05:
				_fail("Player did not slide along wall (reverse=%s): %s -> %s" % [reverse, at_wall, sliding])
				return
			player.movement_input = -side.inward
			await _frames(20)
			var departure := Vector2(player.global_position.x - sliding.x, player.global_position.z - sliding.z)
			if departure.dot(-side.inward) < 1.0:
				_fail("Player could not move away from wall (reverse=%s): %s -> %s" % [reverse, sliding, player.global_position])
				return
		player.movement_input = Vector2.ZERO
		map.free()
	world.free()
	print("Player building collision and wall sliding passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
