extends SceneTree

const BuildingWalls = preload("res://scripts/building_walls.gd")


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var room := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var moved_outer := BuildingWalls.move_outline_edge(room, 0, 2.0)
	if moved_outer.has("error") or moved_outer.outline[0].distance_to(Vector2(0, 2)) > 0.01 or moved_outer.outline[1].distance_to(Vector2(10, 2)) > 0.01:
		_fail("The exterior wall did not move along its adjoining walls: %s" % moved_outer)
		return
	if not BuildingWalls.move_outline_edge(room, 0, 10.1).has("error") or room[0] != Vector2.ZERO:
		_fail("A move past adjoining walls was accepted or modified the original outline.")
		return
	var split_outline := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0.0001), Vector2(10, 10), Vector2(0, 10)])
	var moved_split := BuildingWalls.move_outline_edge(split_outline, 1, 1.0)
	if moved_split.has("error") or absf(moved_split.outline[0].y - 1.0) > 0.01 or absf(moved_split.outline[1].y - 1.0) > 0.01 or absf(moved_split.outline[2].y - 1.0) > 0.01:
		_fail("A straight exterior wall split into OSM segments did not move together: %s" % moved_split)
		return
	var regions: Array[PackedVector2Array] = [room]
	var first := BuildingWalls.plan_wall(regions, Vector2(3, 0.5), 0.3)
	if first.has("error") or first.start.distance_to(Vector2(3, 0)) > 0.01 or first.end.distance_to(Vector2(3, 10)) > 0.01:
		_fail("The first wall did not span the room perpendicularly: %s" % first)
		return
	var second := BuildingWalls.plan_wall(first.regions, Vector2(0.5, 5), 0.3)
	if second.has("error") or second.start.distance_to(Vector2(0, 5)) > 0.01 or second.end.distance_to(Vector2(2.85, 5)) > 0.02:
		_fail("The second wall did not stop at the nearer interior wall: %s" % second)
		return
	var saved := [
		{"cursor": [3.0, 0.5], "thickness": 0.3},
		{"cursor": [0.5, 5.0], "thickness": 0.3},
	]
	var rebuilt := BuildingWalls.build(room, saved)
	if rebuilt.has("error") or rebuilt.regions.size() != 3 or rebuilt.walls.size() != 2 or rebuilt.walls[1] != second.polygon:
		_fail("Saved walls did not reconstruct the same rooms: %s" % rebuilt)
		return
	var moved := BuildingWalls.adjust_walls(room, room, saved, 0, 2.0, 0.6)
	if moved.has("error"):
		_fail("Moving a partition with an attached wall failed: %s" % moved)
		return
	var replay := BuildingWalls.build(room, moved.walls)
	if replay.has("error") or replay.plans[0].start.distance_to(Vector2(5, 0)) > 0.02 or replay.plans[1].end.distance_to(Vector2(4.7, 5)) > 0.03:
		_fail("The attached wall did not follow the relocated and widened partition: %s" % replay)
		return
	if not BuildingWalls.adjust_walls(room, room, saved, 0, 8.0).has("error"):
		_fail("An interior wall moved beyond its supporting walls.")
		return
	if not BuildingWalls.plan_wall(regions, Vector2(0.01, 0.01), 0.3).has("error") or not BuildingWalls.plan_wall(regions, Vector2(30, 30), 0.3).has("error") or not BuildingWalls.plan_wall(regions, Vector2(3, 0.5), 20.0).has("error"):
		_fail("A corner, distant cursor or oversized wall was accepted.")
		return
	var invalid := [{"cursor": [3.0, 0.5], "thickness": -1.0}]
	if not BuildingWalls.build(room, invalid).has("error"):
		_fail("Invalid saved walls were accepted.")
		return
	var from_interior := BuildingWalls.plan_wall(first.regions, Vector2(2.6, 5), 0.3)
	if from_interior.has("error") or from_interior.start.distance_to(Vector2(2.85, 5)) > 0.02 or from_interior.end.distance_to(Vector2(0, 5)) > 0.02:
		_fail("A new wall did not start perpendicularly from an existing interior wall: %s" % from_interior)
		return
	var source_attached := [saved[0], {"cursor": [2.6, 5.0], "thickness": 0.3}]
	var moved_source := BuildingWalls.adjust_walls(room, room, source_attached, 0, 2.0, 0.3)
	if moved_source.has("error"):
		_fail("Moving a source wall with an attached partition failed: %s" % moved_source)
		return
	var attached_replay := BuildingWalls.build(room, moved_source.walls)
	if attached_replay.has("error") or attached_replay.plans[1].start.distance_to(Vector2(4.85, 5)) > 0.03 or attached_replay.plans[1].end.distance_to(Vector2(0, 5)) > 0.03:
		_fail("A partition did not remain attached when its source moved: %s" % attached_replay)
		return
	var short_support := saved.duplicate(true)
	short_support.append({"cursor": [1.5, 4.7], "thickness": 0.3})
	if BuildingWalls.build(room, short_support).has("error") or not BuildingWalls.adjust_walls(room, room, short_support, 2, -2.0).has("error"):
		_fail("A wall was allowed to move beyond its shorter supporting wall.")
		return
	var rotated := PackedVector2Array()
	for point in room:
		rotated.append(point.rotated(0.6))
	var rotated_wall := BuildingWalls.plan_wall([rotated], Vector2(3, 0.5).rotated(0.6), 0.3)
	if rotated_wall.has("error") or rotated_wall.start.distance_to(Vector2(3, 0).rotated(0.6)) > 0.02 or rotated_wall.end.distance_to(Vector2(3, 10).rotated(0.6)) > 0.02:
		_fail("A wall did not snap correctly in a rotated room: %s" % rotated_wall)
		return
	var rotated_cursor := Vector2(3, 0.5).rotated(0.6)
	var rotated_saved := [{"cursor": [rotated_cursor.x, rotated_cursor.y], "thickness": 0.3}]
	var rotated_move := BuildingWalls.adjust_walls(rotated, rotated, rotated_saved, 0, 1.0, 0.3)
	if rotated_move.has("error") or BuildingWalls.build(rotated, rotated_move.walls).plans[0].start.distance_to(Vector2(4, 0).rotated(0.6)) > 0.03:
		_fail("A partition in a rotated room did not move sideways: %s" % rotated_move)
		return
	var concave := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 3), Vector2(4, 3), Vector2(4, 8), Vector2(0, 8)])
	var concave_wall := BuildingWalls.plan_wall([concave], Vector2(2, 0.5), 0.3)
	if concave_wall.has("error") or concave_wall.end.distance_to(Vector2(2, 8)) > 0.02:
		_fail("A wall did not stop correctly in a concave room: %s" % concave_wall)
		return
	room.reverse()
	if BuildingWalls.plan_wall([room], Vector2(3, 0.5), 0.3).has("error"):
		_fail("Reversing the room outline prevented wall creation.")
		return
	print("Interior wall snapping, splitting, replay and validation passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
