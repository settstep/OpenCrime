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
	var exterior_parts := BuildingWalls.floor_outline(room, {"outer_splits": [{"edge": 0, "cuts": [0.5], "offsets": [0.0, -1.0]}]})
	if exterior_parts.has("error") or exterior_parts.outline.size() != 6 or exterior_parts.edges.size() != 6 or exterior_parts.outline[1].distance_to(Vector2(5, 0)) > 0.01 or exterior_parts.outline[2].distance_to(Vector2(5, -1)) > 0.01 or exterior_parts.outline[3].distance_to(Vector2(10, -1)) > 0.01:
		_fail("A split exterior wall did not produce a connected stepped outline: %s" % exterior_parts)
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
	var corner_error := BuildingWalls.plan_wall([room], Vector2(0.05, 0.05), 0.3)
	if corner_error.get("error", "") != "Bitte etwas Abstand zur Wandecke halten." or corner_error.get("error_points", PackedVector2Array()).size() != 1 or corner_error.error_points[0].distance_to(Vector2.ZERO) > 0.001:
		_fail("A corner clearance error did not identify the actual corner: %s" % corner_error)
		return
	var irregular := PackedVector2Array()
	for point in [Vector2(0, 0), Vector2(9, -0.02), Vector2(20, 0.02), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20)]:
		irregular.append(point.rotated(1.25456857681274))
	var nested_walls := [
		{"cursor": [-13.9793672561646, 10.4174308776855], "thickness": 0.3},
		{"cursor": [-10.6502370834351, 24.9536247253418], "thickness": 0.3},
		{"cursor": [1.19478273391724, 17.5766506195068], "thickness": 0.3},
		{"cursor": [0.391252994537354, 8.08173561096191], "thickness": 0.3},
	]
	var nested_split := BuildingWalls.split_wall(irregular, nested_walls, 1, 0)
	if nested_split.has("error") and (nested_split.error != "Bitte etwas Abstand zur Wandecke halten." or nested_split.get("error_points", PackedVector2Array()).size() != 1 or nested_split.error_points[0].distance_to(Vector2(2.325523, 20.55003)) > 0.01):
		_fail("A rejected split did not retain the actual corner from rebuilding nested walls: %s" % nested_split)
		return
	var exterior_split := BuildingWalls.split_exterior(room, [], rebuilt.plans, 0.3, 0, -1)
	if exterior_split.has("error") or exterior_split.pieces != 2 or absf(float(exterior_split.splits[0].cuts[0]) - 0.3) > 0.01:
		_fail("The exterior wall was not split where the partition touches it: %s" % exterior_split)
		return
	var exterior_midpoint := BuildingWalls.split_exterior(room, [], [], 0.3, 0, -1)
	if exterior_midpoint.has("error") or absf(float(exterior_midpoint.splits[0].cuts[0]) - 0.5) > 0.01:
		_fail("An exterior wall without contacts was not split in the middle: %s" % exterior_midpoint)
		return
	var split_at_connection := BuildingWalls.split_wall(room, saved, 0, 0)
	if split_at_connection.has("error") or split_at_connection.pieces != 2 or absf(float(split_at_connection.walls[0].cuts[0]) - 0.5) > 0.01:
		_fail("A wall was not split at the attached partition: %s" % split_at_connection)
		return
	var multiple_contacts := [
		saved[0],
		{"cursor": [0.5, 2.0], "thickness": 0.3},
		{"cursor": [0.5, 7.0], "thickness": 0.3},
		{"cursor": [9.5, 2.0], "thickness": 0.3},
	]
	var split_multiple := BuildingWalls.split_wall(room, multiple_contacts, 0, 0)
	if split_multiple.has("error") or split_multiple.pieces != 3 or absf(float(split_multiple.walls[0].cuts[0]) - 0.2) > 0.01 or absf(float(split_multiple.walls[0].cuts[1]) - 0.7) > 0.01:
		_fail("Multiple contacts on both sides did not produce three distinct pieces: %s" % split_multiple)
		return
	var resplit := BuildingWalls.split_wall(room, split_multiple.walls, 0, 1)
	if resplit.has("error") or resplit.walls[0].cuts.size() != 3 or absf(float(resplit.walls[0].cuts[1]) - 0.45) > 0.01:
		_fail("Splitting an existing piece did not split that piece in its middle: %s" % resplit)
		return
	var multiple_plans := BuildingWalls.build(room, multiple_contacts)
	var split_outer_multiple := BuildingWalls.split_exterior(room, [], multiple_plans.plans, 0.3, 3, -1)
	if split_outer_multiple.has("error") or split_outer_multiple.pieces != 3 or split_outer_multiple.splits[0].cuts.size() != 2:
		_fail("Multiple exterior wall contacts did not produce three pieces: %s" % split_outer_multiple)
		return
	var split_at_midpoint := BuildingWalls.split_wall(room, saved, 1, 0)
	if split_at_midpoint.has("error") or split_at_midpoint.pieces != 2 or absf(float(split_at_midpoint.walls[1].cuts[0]) - 0.5) > 0.01:
		_fail("A wall without additional contacts was not split in the middle: %s" % split_at_midpoint)
		return
	var stepped := BuildingWalls.build(room, [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 1.0]}])
	if stepped.has("error"):
		_fail("A split wall with a connecting section could not be built: %s" % stepped)
		return
	if not Geometry2D.is_point_in_polygon(Vector2(3.0, 2.0), stepped.walls[0]) or not Geometry2D.is_point_in_polygon(Vector2(4.0, 8.0), stepped.walls[0]) or not Geometry2D.is_point_in_polygon(Vector2(3.5, 5.0), stepped.walls[0]) or Geometry2D.is_point_in_polygon(Vector2(3.0, 8.0), stepped.walls[0]):
		_fail("The moved segment or its connecting wall has incorrect geometry: %s" % stepped)
		return
	if not BuildingWalls.build(room, [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 8.0]}]).has("error"):
		_fail("A split segment was allowed to leave its supporting wall.")
		return
	var split_saved := [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 0.0]}]
	var split_move := BuildingWalls.adjust_walls(room, room, split_saved, 0, 1.0, 0.3, 1)
	if split_move.has("error") or not is_equal_approx(float(split_move.walls[0].offsets[1]), 1.0) or not Geometry2D.is_point_in_polygon(Vector2(3.5, 5), split_move.polygons[0]):
		_fail("Moving a selected wall segment did not add its connecting wall: %s" % split_move)
		return
	var split_attached := split_saved.duplicate(true)
	split_attached.append(saved[1])
	var attached_move := BuildingWalls.adjust_walls(room, room, split_attached, 0, 1.0, 0.3, 1)
	if attached_move.has("error"):
		_fail("Moving a split wall segment lost its connected partition: %s" % attached_move)
		return
	var merge_source := [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.5], "offsets": [0.0, 1.0], "thicknesses": [0.3, 0.6]}]
	var merged := BuildingWalls.merge_wall(room, merge_source, 0, 1, 0)
	if merged.has("error") or merged.segment != -1 or merged.walls[0].has("cuts") or absf(float(merged.walls[0].thickness) - 0.6) > 0.001:
		_fail("Merging two interior pieces did not retain the first piece's thickness: %s" % merged)
		return
	var merged_build := BuildingWalls.build(room, merged.walls)
	if merged_build.has("error") or merged_build.plans[0].start.distance_to(Vector2(4, 0)) > 0.02 or merged_build.plans[0].end.distance_to(Vector2(4, 10)) > 0.02:
		_fail("Merging did not retain the first interior piece's position: %s" % merged_build)
		return
	var merge_three := [{"cursor": [3.0, 0.5], "thickness": 0.3, "cuts": [0.25, 0.75], "offsets": [0.0, 1.0, 0.0]}]
	var partial_merge := BuildingWalls.merge_wall(room, merge_three, 0, 0, 1)
	if partial_merge.has("error") or partial_merge.walls[0].cuts.size() != 1 or partial_merge.segment != 0 or float(partial_merge.walls[0].offsets[0]) != 0.0:
		_fail("Merging neighboring pieces did not preserve the remaining split: %s" % partial_merge)
		return
	if not BuildingWalls.merge_wall(room, merge_three, 0, 0, 2).has("error"):
		_fail("Nonadjacent pieces were merged.")
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
	var rotated_contacts := []
	for wall in multiple_contacts:
		var point := Vector2(wall.cursor[0], wall.cursor[1]).rotated(0.6)
		rotated_contacts.append({"cursor": [point.x, point.y], "thickness": 0.3})
	var rotated_split := BuildingWalls.split_wall(rotated, rotated_contacts, 0, 0)
	if rotated_split.has("error") or rotated_split.pieces != 3:
		_fail("Wall splitting did not work in a rotated room: %s" % rotated_split)
		return
	rotated.reverse()
	var reversed_split := BuildingWalls.split_wall(rotated, rotated_contacts, 0, 0)
	if reversed_split.has("error") or reversed_split.pieces != 3:
		_fail("Reversing the room outline changed the wall split: %s" % reversed_split)
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
