extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const Grid = preload("res://scripts/map_block_grid.gd")


func _initialize() -> void:
	ProjectSettings.set_setting("opencrime/osm/download_blocks", false)
	call_deferred("_test")


func _square(offset: float) -> Array:
	return [[offset, 0.0], [offset, 0.0001], [offset + 0.0001, 0.0001], [offset + 0.0001, 0.0], [offset, 0.0]]


func _joint_covers(transforms: Array[Transform3D], mesh: Mesh, center: Vector2, radius: float) -> bool:
	var faces := mesh.get_faces()
	for transform in transforms:
		if Vector2(transform.origin.x, transform.origin.z).distance_to(center) > 0.001:
			continue
		for sample in 96:
			var angle := TAU * float(sample) / 96.0
			var point := center + Vector2(cos(angle), sin(angle)) * radius * 0.999
			var covered := false
			for index in range(0, faces.size(), 3):
				var triangle := PackedVector2Array()
				for vertex in range(3):
					var position: Vector3 = transform * faces[index + vertex]
					triangle.append(Vector2(position.x, position.z))
				if Geometry2D.is_point_in_polygon(point, triangle):
					covered = true
					break
			if not covered:
				return false
		return true
	return false


func _test() -> void:
	var original: Variant = ProjectSettings.get_setting(OSMMap.SCALE_SETTING)
	var place := {
		"id": "features", "name": "Features", "origin": [0.0, 0.0],
		"bounds": [-0.001, -0.001, 0.001, 0.001],
		"ways": [
			{"id": 1, "tags": {"highway": "residential", "width": "7.5 m", "lanes": "3"}, "geometry": [[0.0, 0.0], [0.0001, 0.0], [0.0001, 0.0001]]},
			{"id": 2, "tags": {"highway": "residential", "lanes": "3"}, "geometry": [[0.0, 0.0001], [0.0001, 0.0001]]},
			{"id": 3, "tags": {"highway": "footway", "width": "12ft"}, "geometry": [[0.0, 0.0002], [0.0001, 0.0002]]},
			{"id": 4, "tags": {"highway": "service"}, "geometry": [[0.0, 0.0003], [0.0001, 0.0003]]},
			{"id": 5, "tags": {"building": "yes", "height": "12 m", "building:levels": "2"}, "geometry": _square(0.0001)},
			{"id": 6, "tags": {"building": "yes", "building:levels": "2"}, "geometry": _square(0.0003)},
			{"id": 7, "tags": {"building": "garage"}, "geometry": _square(0.0005)},
			{"id": 8, "tags": {"amenity": "parking", "parking": "surface"}, "geometry": _square(-0.0004)},
			{"id": 9, "tags": {"highway": "pedestrian", "area": "yes"}, "geometry": _square(-0.0002)},
			{"id": 10, "tags": {"amenity": "parking", "parking": "underground"}, "geometry": _square(-0.0006)},
			{"id": 11, "tags": {"amenity": "parking"}, "geometry": [[0.0, 0.0], [0.0001, 0.0], [0.0001, 0.0001]]},
			{"id": 12, "tags": {"highway": "residential", "width": "unknown", "lanes": "2"}, "geometry": [[0.0, 0.0004], [0.0001, 0.0004]]},
			{"id": 13, "tags": {"building": "yes", "height": "-1", "building:levels": "3"}, "geometry": _square(0.0007)},
			{"id": 14, "tags": {"highway": "service"}, "geometry": [[0.0001, 0.0], [0.0002, -0.0001]]},
			{"id": 15, "tags": {"highway": "footway"}, "geometry": [[0.0001, -0.0001], [0.0001, 0.0001]]},
			{"id": 16, "tags": {"highway": "service"}, "geometry": [[0.0, 0.001], [0.0000001, 0.001], [0.0000001, 0.001], [0.0001, 0.001]]},
			{"id": 17, "tags": {"building": "yes", "building:levels": "2.5"}, "geometry": _square(0.0009)},
		],
	}
	for factor in [1.0, 2.0]:
		ProjectSettings.set_setting(OSMMap.SCALE_SETTING, factor)
		var world: Node3D = MainScene.instantiate()
		if not OSMMap.populate(world, place):
			_fail("Synthetic map did not load.")
			return
		var map: Node3D = world.get_node("OSMMap")
		for expected in [[1, 7.5], [2, 9.0], [3, 3.6576], [4, 4.0], [12, 6.0]]:
			var road: MeshInstance3D = map.get_node("Road_%d_0" % expected[0])
			if not is_equal_approx(road.mesh.size.x, expected[1] * factor):
				_fail("Road width or scaling is incorrect for way %s." % expected[0])
				return
		if map.get_node("Road_1_0").mesh.material == map.get_node("Road_3_0").mesh.material:
			_fail("Separately mapped footways are not visually distinct.")
			return
		var road: MeshInstance3D = map.get_node("Road_1_0")
		var path: MeshInstance3D = map.get_node("Road_15_0")
		var path_area: MeshInstance3D = map.get_node("Pedestrian_9")
		if road.position.y + road.mesh.size.y / 2.0 <= path.position.y + path.mesh.size.y / 2.0 or road.position.y + road.mesh.size.y / 2.0 <= path_area.position.y:
			_fail("Roads do not cover overlapping paths and pedestrian areas.")
			return
		var center: Vector2 = OSMMap._project([0.0001, 0.0], place.origin) * factor
		var road_joints: MultiMeshInstance3D = map.get_node("RoadJoints")
		var path_joints: MultiMeshInstance3D = map.get_node("PathJoints")
		var road_transforms: Array[Transform3D] = []
		var branch_transforms: Array[Transform3D] = []
		var path_transforms: Array[Transform3D] = []
		var test_map := Node3D.new()
		OSMMap._add_road(test_map, place.ways[0], road.mesh.material, factor, place.origin, OSMMap.ROAD_HEIGHT, road_transforms)
		OSMMap._add_road(test_map, place.ways[13], road.mesh.material, factor, place.origin, OSMMap.ROAD_HEIGHT, branch_transforms)
		OSMMap._add_road(test_map, place.ways[14], path.mesh.material, factor, place.origin, OSMMap.PATH_HEIGHT, path_transforms)
		test_map.free()
		if road_joints.multimesh.instance_count < road_transforms.size() + branch_transforms.size() or not map.has_node("Road_1_1") or not _joint_covers(road_transforms, road_joints.multimesh.mesh, center, 7.5 * factor / 2.0) or not _joint_covers(branch_transforms, road_joints.multimesh.mesh, center, 2.0 * factor):
			_fail("The road bend and shared intersection are not filled across their full width.")
			return
		if not map.has_node("Road_16_0") or map.has_node("Road_16_1") or not map.has_node("Road_16_2"):
			_fail("A short segment was dropped or a duplicate point produced a segment.")
			return
		var path_end: Vector2 = OSMMap._project([0.0001, 0.0001], place.origin) * factor
		if path_joints.multimesh.instance_count < path_transforms.size() or not _joint_covers(path_transforms, path_joints.multimesh.mesh, path_end, factor):
			_fail("The path end is not rounded across its full width.")
			return
		for expected in [[5, 12.0, 1], [6, 6.0, 2], [7, 3.0, 1], [13, 9.0, 3], [17, 10.0, 1]]:
			var building: StaticBody3D = map.get_node("Building_%d" % expected[0])
			if building.get_child_count() != expected[2] * 2:
				_fail("Incorrect number of building segments for way %s." % expected[0])
				return
			var max_y := 0.0
			for index in expected[2]:
				var mesh: MeshInstance3D = building.get_child(index * 2)
				var collision: CollisionShape3D = building.get_child(index * 2 + 1)
				if not is_equal_approx(mesh.mesh.get_aabb().size.y, expected[1] * factor / expected[2]):
					_fail("Building segment height is incorrect for way %s." % expected[0])
					return
				for point in collision.shape.get_faces():
					max_y = maxf(max_y, point.y + collision.position.y)
			if not is_equal_approx(max_y, expected[1] * factor):
				_fail("Building height or collision is incorrect for way %s." % expected[0])
				return
		var parking: MeshInstance3D = map.get_node_or_null("Parking_8")
		var pedestrian: MeshInstance3D = map.get_node_or_null("Pedestrian_9")
		if parking == null or pedestrian == null or map.has_node("Parking_10") or map.has_node("Parking_11"):
			_fail("Area filtering or rendering is incorrect.")
			return
		var parking_points := PackedVector2Array()
		for coordinate in place.ways[7].geometry:
			parking_points.append(OSMMap._project(coordinate, place.origin) * factor)
		var parking_bounds := Rect2(parking_points[0], Vector2.ZERO)
		for point in parking_points:
			parking_bounds = parking_bounds.expand(point)
		if absf(parking.mesh.get_aabb().size.x - parking_bounds.size.x) > 0.01:
			_fail("Parking area does not scale with the map.")
			return
		var normals: PackedVector3Array = parking.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if normals.is_empty() or normals[0].y < 0.99:
			_fail("Parking surface faces away from the light.")
			return
		world.free()
	var large_map := Node3D.new()
	var tall_way: Dictionary = place.ways[5].duplicate(true)
	tall_way.tags["building:levels"] = "1000"
	OSMMap._add_building(large_map, tall_way, StandardMaterial3D.new(), 1.0, place.origin)
	var tall_building := large_map.get_node("Building_6") as StaticBody3D
	var top_floor := tall_building.get_node("Segment_1000") as MeshInstance3D
	if tall_building.get_child_count() != 2000 or not is_equal_approx(top_floor.position.y, 2997.0) or not is_equal_approx(top_floor.mesh.get_aabb().size.y, 3.0):
		_fail("The maximum supported floor count did not produce 1000 stacked floors.")
		return
	large_map.free()
	if not _test_point_features():
		return
	var thalhofen := PlaceStore.find_by_id("thalhofen")
	if not thalhofen.ways.any(func(way): return way.tags.get("amenity") == "parking"):
		_fail("Bundled Thalhofen has no parking data.")
		return
	var thalhofen_world: Node3D = MainScene.instantiate()
	if not OSMMap.populate(thalhofen_world, thalhofen):
		_fail("Bundled Thalhofen could not be loaded.")
		return
	if not thalhofen_world.get_node("OSMMap").has_node("Parking_60096824") or not thalhofen_world.get_node("OSMMap").has_node("Parking_503649128"):
		_fail("Bundled parking areas were not rendered.")
		return
	thalhofen_world.free()
	ProjectSettings.set_setting(OSMMap.SCALE_SETTING, original)
	print("OSM widths, heights, collisions, paths, parking and scaling passed")
	quit(0)


func _test_point_features() -> bool:
	var reference := [47.7748417, 10.6034933]
	var block := Grid.block_at_origin(reference)
	var origin := Grid.block_origin(reference, block)
	var projected := Grid.project(origin, Grid.zone_for_origin(origin), true)
	var tags_list := [
		{"highway": "traffic_signals"}, {"highway": "stop", "traffic_sign": "DE:206"}, {"highway": "give_way"},
		{"highway": "crossing"}, {"traffic_sign": "DE:274-30"},
		{"emergency": "fire_hydrant"}, {"emergency": "fire_hydrant", "fire_hydrant:type": "underground"},
		{"emergency": "defibrillator"}, {"amenity": "bench"},
	]
	var nodes: Array = []
	for index in tags_list.size():
		nodes.append({
			"id": index + 1,
			"tags": tags_list[index],
			"location": Grid.unproject([projected[0] + float(index) * 5.0, projected[1]], Grid.zone_for_origin(origin), true),
		})
	nodes.append({
		"id": 100, "tags": {"emergency": "fire_hydrant"},
		"location": Grid.block_origin(reference, block + Vector2i.RIGHT),
	})
	var place := {
		"id": "point_test", "name": "Points", "origin": origin,
		"bounds": Grid.block_bounds(reference, block), "ways": [], "nodes": nodes,
	}
	var map := OSMMap.create_block(place, 2.0)
	if map == null:
		_fail("A block containing OSM point features did not load.")
		return false
	for name in ["Signal", "Stop", "GiveWay", "Crossing", "Sign", "Hydrant", "UndergroundHydrant", "Defibrillator"]:
		var visual := map.get_node_or_null(name) as MultiMeshInstance3D
		if visual == null or visual.multimesh.instance_count != 1:
			_fail("Missing or duplicated point-feature model: " + name)
			map.free()
			return false
	for child in map.get_children():
		if child is CollisionObject3D:
			_fail("Decorative point features must not create collision obstacles.")
			map.free()
			return false
	var positions := OSMMap._point_feature_positions(place, 2.0)
	var actual: Vector3 = positions.Sign[0]
	var expected := OSMMap._project(nodes[4].location, origin) * 2.0
	if Vector2(actual.x, actual.z).distance_to(expected) > 0.01:
		_fail("Point feature position or scaling is incorrect: actual=%s expected=%s" % [actual, expected])
		map.free()
		return false
	var legacy: Dictionary = place.duplicate(true)
	legacy.erase("nodes")
	if not OSMMap.replace_block(map, legacy, 1.0) or map.has_node("Signal") or map.has_node("Hydrant"):
		_fail("Replacing a block with legacy data left stale point features.")
		map.free()
		return false
	map.free()
	return true


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
