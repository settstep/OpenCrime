extends SceneTree

const MainScene = preload("res://scenes/main.tscn")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")


func _initialize() -> void:
	call_deferred("_test")


func _square(offset: float) -> Array:
	return [[offset, 0.0], [offset, 0.0001], [offset + 0.0001, 0.0001], [offset + 0.0001, 0.0], [offset, 0.0]]


func _test() -> void:
	var original: Variant = ProjectSettings.get_setting(OSMMap.SCALE_SETTING)
	var place := {
		"id": "features", "name": "Features", "origin": [0.0, 0.0],
		"bounds": [-0.001, -0.001, 0.001, 0.001],
		"ways": [
			{"id": 1, "tags": {"highway": "residential", "width": "7.5 m", "lanes": "3"}, "geometry": [[0.0, 0.0], [0.0001, 0.0]]},
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
		for expected in [[5, 12.0], [6, 6.0], [7, 3.0], [13, 9.0]]:
			var building: StaticBody3D = map.get_node("Building_%d" % expected[0])
			var mesh: MeshInstance3D = building.get_child(0)
			var collision: CollisionShape3D = building.get_child(1)
			var faces: PackedVector3Array = collision.shape.get_faces()
			var max_y := 0.0
			for point in faces:
				max_y = maxf(max_y, point.y)
			if not is_equal_approx(mesh.mesh.get_aabb().size.y, expected[1] * factor) or not is_equal_approx(max_y, expected[1] * factor):
				_fail("Building height or collision is incorrect for way %s." % expected[0])
				return
		var parking: MeshInstance3D = map.get_node_or_null("Parking_8")
		var pedestrian: MeshInstance3D = map.get_node_or_null("Pedestrian_9")
		if parking == null or pedestrian == null or map.has_node("Parking_10") or map.has_node("Parking_11"):
			_fail("Area filtering or rendering is incorrect.")
			return
		if absf(parking.mesh.get_aabb().size.x - 11.132 * factor) > 0.01:
			_fail("Parking area does not scale with the map.")
			return
		var normals: PackedVector3Array = parking.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if normals.is_empty() or normals[0].y < 0.99:
			_fail("Parking surface faces away from the light.")
			return
		world.free()
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


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
