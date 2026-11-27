extends RefCounted

const PlaceStore = preload("res://scripts/place_store.gd")
const MapBlockGrid = preload("res://scripts/map_block_grid.gd")
const ORIGIN_LAT := 47.7748417
const ORIGIN_LON := 10.6034933
const BUILDING_HEIGHT := 10.0
const LEVEL_HEIGHT := 3.0
const SCALE_SETTING := "opencrime/osm/scale"
const PEDESTRIAN_WAYS := ["footway", "path", "pedestrian", "steps", "cycleway"]
const ROAD_HEIGHT := 0.04
const PATH_HEIGHT := 0.02
const WAY_THICKNESS := 0.02
const JOINT_SEGMENTS := 24
const BUILDING_PICK_LAYER := 1 << 19


static func populate(world: Node3D, place: Dictionary = {}) -> bool:
	var setting: Variant = ProjectSettings.get_setting(SCALE_SETTING)
	if (typeof(setting) != TYPE_FLOAT and typeof(setting) != TYPE_INT) or not is_finite(float(setting)) or float(setting) <= 0.0:
		push_error("Der OSM-Kartenfaktor muss eine endliche Zahl größer als 0 sein: " + str(setting))
		return false
	var map_scale := float(setting)
	if place.is_empty():
		place = PlaceStore.find_by_id("thalhofen")
	if not PlaceStore.is_valid(place):
		push_error("OSM-Kartendaten sind ungültig.")
		return false

	for node_name in ["Road", "Building1", "Building2", "MapBoundary"]:
		var old_node := world.get_node_or_null(node_name)
		if old_node != null:
			old_node.free()
	var old_map := world.get_node_or_null("OSMMap")
	if old_map != null:
		old_map.free()
	var old_credit := world.get_node_or_null("HUD/OSMCredit")
	if old_credit != null:
		old_credit.free()

	var ground_mesh: MeshInstance3D = world.get_node("Ground/MeshInstance3D")
	var ground_shape: CollisionShape3D = world.get_node("Ground/CollisionShape3D")
	ground_mesh.mesh = ground_mesh.mesh.duplicate()
	ground_shape.shape = ground_shape.shape.duplicate()
	ground_mesh.mesh.size = Vector3(MapBlockGrid.BLOCK_SIZE * map_scale, 1, MapBlockGrid.BLOCK_SIZE * map_scale)
	ground_shape.shape.size = Vector3(MapBlockGrid.BLOCK_SIZE * map_scale, 1, MapBlockGrid.BLOCK_SIZE * map_scale)
	var base_block := MapBlockGrid.block_at_origin(place.origin)
	var base_offset := MapBlockGrid.block_local_center(place.origin, base_block) * map_scale
	ground_mesh.position = Vector3(base_offset.x, 0.0, base_offset.y)
	ground_shape.position = ground_mesh.position
	_add_map_boundary(world, 3.0 * MapBlockGrid.BLOCK_SIZE * map_scale)
	world.get_node("MapBoundary").position = Vector3(base_offset.x, 0.0, base_offset.y)

	var map := Node3D.new()
	map.name = "OSMMap"
	map.set_meta("place", place)
	world.set_meta("place", place)
	world.add_child(map)
	_populate_geometry(map, place, map_scale)

	var credit := Label.new()
	credit.name = "OSMCredit"
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 20.0
	credit.offset_top = -30.0
	credit.offset_right = 650.0
	credit.offset_bottom = -5.0
	credit.text = "© OpenStreetMap-Mitwirkende | https://www.openstreetmap.org/copyright"
	world.get_node("HUD").add_child(credit)
	return true


static func create_block(place: Dictionary, map_scale: float) -> Node3D:
	if not PlaceStore.is_valid(place) or not is_finite(map_scale) or map_scale <= 0.0:
		return null
	var map := Node3D.new()
	map.name = "Block"
	_populate_geometry(map, place, map_scale)
	return map


static func replace_block(map: Node3D, place: Dictionary, map_scale: float) -> bool:
	if map == null or not PlaceStore.is_valid(place) or not is_finite(map_scale) or map_scale <= 0.0:
		return false
	for child in map.get_children():
		child.free()
	map.set_meta("place", place)
	_populate_geometry(map, place, map_scale)
	return true


static func clear_block(map: Node3D) -> void:
	for child in map.get_children():
		child.free()


static func _populate_geometry(map: Node3D, place: Dictionary, map_scale: float) -> void:
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color(0.27, 0.28, 0.30)
	var building_material := StandardMaterial3D.new()
	building_material.albedo_color = Color(0.73, 0.62, 0.48)
	building_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pedestrian_material := StandardMaterial3D.new()
	pedestrian_material.albedo_color = Color(0.57, 0.57, 0.54)
	pedestrian_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var parking_material := StandardMaterial3D.new()
	parking_material.albedo_color = Color(0.37, 0.38, 0.39)
	parking_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var road_joints: Array[Transform3D] = []
	var path_joints: Array[Transform3D] = []
	for way in place.ways:
		if way.tags.has("building"):
			_add_building(map, way, building_material, map_scale, place.origin)
		elif way.tags.get("amenity", "") == "parking" and way.tags.get("parking", "") in ["", "surface"]:
			_add_area(map, way, parking_material, map_scale, place.origin, "Parking", 0.015)
		elif way.tags.get("area", "") == "yes" and way.tags.get("highway", "") in PEDESTRIAN_WAYS:
			_add_area(map, way, pedestrian_material, map_scale, place.origin, "Pedestrian", PATH_HEIGHT)
		elif way.tags.has("highway") and way.tags.get("area", "") != "yes":
			var is_path: bool = way.tags.highway in PEDESTRIAN_WAYS
			var material := pedestrian_material if is_path else road_material
			_add_road(map, way, material, map_scale, place.origin, PATH_HEIGHT if is_path else ROAD_HEIGHT, path_joints if is_path else road_joints)

	_add_joints(map, "RoadJoints", road_joints, road_material)
	_add_joints(map, "PathJoints", path_joints, pedestrian_material)
	_add_point_features(map, place, map_scale)


static func _add_point_features(map: Node3D, place: Dictionary, map_scale: float) -> void:
	var points := _point_feature_positions(place, map_scale)
	var posts: Array = []
	for kind in ["Signal", "Stop", "GiveWay", "Sign", "Defibrillator"]:
		posts.append_array(points[kind])
	_add_point_mesh(map, "FeaturePosts", posts, Vector3(0.12, 2.1, 0.12), 1.05, Color(0.35, 0.35, 0.35), map_scale, 8)
	_add_point_mesh(map, "Signal", points.Signal, Vector3(0.75, 0.7, 0.35), 2.45, Color(0.12, 0.12, 0.12), map_scale)
	_add_point_mesh(map, "SignalRed", points.Signal, Vector3(0.16, 0.05, 0.16), 2.83, Color(0.9, 0.08, 0.08), map_scale, 12, -0.23)
	_add_point_mesh(map, "SignalYellow", points.Signal, Vector3(0.16, 0.05, 0.16), 2.83, Color(0.95, 0.75, 0.05), map_scale, 12)
	_add_point_mesh(map, "SignalGreen", points.Signal, Vector3(0.16, 0.05, 0.16), 2.83, Color(0.08, 0.7, 0.2), map_scale, 12, 0.23)
	_add_point_mesh(map, "Stop", points.Stop, Vector3(0.8, 0.12, 0.8), 2.1, Color(0.8, 0.04, 0.04), map_scale, 8)
	_add_point_mesh(map, "StopCenter", points.Stop, Vector3(0.52, 0.04, 0.52), 2.18, Color(1.0, 1.0, 1.0), map_scale, 8)
	_add_point_mesh(map, "GiveWay", points.GiveWay, Vector3(0.9, 0.12, 0.9), 2.1, Color(0.8, 0.04, 0.04), map_scale, 3)
	_add_point_mesh(map, "GiveWayCenter", points.GiveWay, Vector3(0.55, 0.04, 0.55), 2.18, Color(1.0, 1.0, 1.0), map_scale, 3)
	_add_point_mesh(map, "Sign", points.Sign, Vector3(0.7, 0.12, 0.7), 2.1, Color(0.8, 0.8, 0.8), map_scale)
	_add_point_mesh(map, "Crossing", points.Crossing, Vector3(0.8, 0.06, 0.8), 0.09, Color(0.95, 0.8, 0.1), map_scale)
	_add_point_mesh(map, "Hydrant", points.Hydrant, Vector3(0.45, 0.85, 0.45), 0.425, Color(0.8, 0.08, 0.05), map_scale, 12)
	_add_point_mesh(map, "UndergroundHydrant", points.UndergroundHydrant, Vector3(0.65, 0.06, 0.65), 0.09, Color(0.45, 0.45, 0.45), map_scale, 12)
	_add_point_mesh(map, "Defibrillator", points.Defibrillator, Vector3(0.65, 0.55, 0.65), 1.4, Color(0.05, 0.55, 0.2), map_scale)
	_add_point_mesh(map, "DefibrillatorCrossA", points.Defibrillator, Vector3(0.4, 0.04, 0.12), 1.7, Color.WHITE, map_scale)
	_add_point_mesh(map, "DefibrillatorCrossB", points.Defibrillator, Vector3(0.12, 0.04, 0.4), 1.7, Color.WHITE, map_scale)


static func _point_feature_positions(place: Dictionary, map_scale: float) -> Dictionary:
	var points := {
		"Signal": [], "Stop": [], "GiveWay": [], "Crossing": [],
		"Sign": [], "Hydrant": [], "UndergroundHydrant": [], "Defibrillator": [],
	}
	var block := MapBlockGrid.block_at_origin(place.origin)
	for node in place.get("nodes", []):
		if MapBlockGrid.block_for_coordinate(node.location, place.origin) != block:
			continue
		var offset := _project(node.location, place.origin) * map_scale
		var position := Vector3(offset.x, 0.0, offset.y)
		var tags: Dictionary = node.tags
		match tags.get("highway", ""):
			"traffic_signals":
				points.Signal.append(position)
			"stop":
				points.Stop.append(position)
			"give_way":
				points.GiveWay.append(position)
			"crossing":
				points.Crossing.append(position)
			_:
				if tags.has("traffic_sign"):
					points.Sign.append(position)
		match tags.get("emergency", ""):
			"fire_hydrant":
				if tags.get("fire_hydrant:type", "") == "underground":
					points.UndergroundHydrant.append(position)
				else:
					points.Hydrant.append(position)
			"defibrillator":
				points.Defibrillator.append(position)
	return points


static func _add_point_mesh(map: Node3D, node_name: String, positions: Array, dimensions: Vector3, height: float, color: Color, map_scale: float, radial_segments: int = 0, offset_x: float = 0.0) -> void:
	if positions.is_empty():
		return
	var mesh: PrimitiveMesh
	if radial_segments > 0:
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = radial_segments
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.0
		mesh = cylinder
	else:
		mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = positions.size()
	for index in positions.size():
		var position: Vector3 = positions[index]
		instances.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(dimensions * map_scale), position + Vector3(offset_x, height, 0.0) * map_scale))
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = instances
	map.add_child(visual)


static func _add_map_boundary(world: Node3D, extent: float) -> void:
	var boundary := StaticBody3D.new()
	boundary.name = "MapBoundary"
	var thickness := 2.0
	var height := 8.0
	var half_extent := extent / 2.0
	var wall_specs := [
		[Vector3(thickness, height, extent + thickness), Vector3(half_extent - thickness / 2.0, height / 2.0, 0)],
		[Vector3(thickness, height, extent + thickness), Vector3(-half_extent + thickness / 2.0, height / 2.0, 0)],
		[Vector3(extent + thickness, height, thickness), Vector3(0, height / 2.0, half_extent - thickness / 2.0)],
		[Vector3(extent + thickness, height, thickness), Vector3(0, height / 2.0, -half_extent + thickness / 2.0)],
	]
	for spec in wall_specs:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[0]
		collision.shape = shape
		collision.position = spec[1]
		boundary.add_child(collision)
	world.add_child(boundary)


static func _project(point: Array, origin: Array = [ORIGIN_LAT, ORIGIN_LON]) -> Vector2:
	var zone := MapBlockGrid.zone_for_origin(origin)
	var northern_hemisphere := MapBlockGrid.is_northern_hemisphere(origin)
	var projected_point := MapBlockGrid.project(point, zone, northern_hemisphere)
	var projected_origin := MapBlockGrid.project(origin, zone, northern_hemisphere)
	return Vector2(projected_point[0] - projected_origin[0], projected_origin[1] - projected_point[1])


static func _add_road(map: Node3D, way: Dictionary, material: Material, map_scale: float, origin: Array, height: float, joints: Array[Transform3D]) -> void:
	var width := _road_width(way.tags)
	var joint_indices := {}
	for index in range(way.geometry.size() - 1):
		var start := _project(way.geometry[index], origin)
		var end := _project(way.geometry[index + 1], origin)
		var direction := end - start
		if direction.length_squared() < 0.000000000001:
			continue
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(width * map_scale, WAY_THICKNESS, direction.length() * map_scale)
		road_mesh.material = material
		var segment := MeshInstance3D.new()
		segment.name = "Road_%d_%d" % [int(way.id), index]
		segment.mesh = road_mesh
		segment.position = Vector3((start.x + end.x) * map_scale / 2.0, height, (start.y + end.y) * map_scale / 2.0)
		segment.rotation.y = atan2(direction.x, direction.y)
		map.add_child(segment)
		for endpoint in [index, index + 1]:
			if joint_indices.has(endpoint):
				continue
			joint_indices[endpoint] = true
			var point := start if endpoint == index else end
			# Circumscribe the road width so polygonal round joins leave no gaps.
			var diameter := width * map_scale / cos(PI / JOINT_SEGMENTS)
			joints.append(Transform3D(Basis.IDENTITY.scaled(Vector3(diameter, 1.0, diameter)), Vector3(point.x * map_scale, height, point.y * map_scale)))


static func _add_joints(map: Node3D, node_name: String, transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty():
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = WAY_THICKNESS
	mesh.radial_segments = JOINT_SEGMENTS
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = multimesh
	map.add_child(visual)


static func _measurement(value: Variant, max_value: float) -> float:
	var text := str(value).strip_edges().to_lower()
	var multiplier := 1.0
	if text.ends_with("ft"):
		text = text.trim_suffix("ft").strip_edges()
		multiplier = 0.3048
	elif text.ends_with("m"):
		text = text.trim_suffix("m").strip_edges()
	if not text.is_valid_float():
		return 0.0
	var result := float(text) * multiplier
	return result if is_finite(result) and result > 0.0 and result <= max_value else 0.0


static func _road_width(tags: Dictionary) -> float:
	if tags.has("width"):
		var width := _measurement(tags.width, 1000.0)
		if width > 0.0:
			return width
		push_warning("Ungültige OSM-Straßenbreite: " + str(tags.width))
	if tags.get("highway", "") in PEDESTRIAN_WAYS:
		return 2.0
	if tags.has("lanes"):
		var lanes := str(tags.lanes).strip_edges()
		if lanes.is_valid_int() and int(lanes) > 0 and int(lanes) <= 20:
			return float(lanes.to_int()) * 3.0
		push_warning("Ungültige OSM-Fahrstreifenanzahl: " + str(tags.lanes))
	match tags.get("highway", ""):
		"service":
			return 4.0
		"secondary":
			return 7.0
		_:
			return 6.0


static func _building_height(tags: Dictionary) -> float:
	if tags.has("height"):
		var height := _measurement(tags.height, 10000.0)
		if height > 0.0:
			return height
		push_warning("Ungültige OSM-Gebäudehöhe: " + str(tags.height))
	if tags.has("building:levels"):
		var levels := _building_levels(tags)
		if levels > 0:
			return float(levels) * LEVEL_HEIGHT
		push_warning("Ungültige OSM-Etagenzahl: " + str(tags["building:levels"]))
	if tags.get("building", "") in ["garage", "garages"]:
		return 3.0
	return BUILDING_HEIGHT


static func _building_levels(tags: Dictionary) -> int:
	var levels := str(tags.get("building:levels", "")).strip_edges()
	if levels.is_valid_int() and int(levels) > 0 and int(levels) <= 1000:
		return levels.to_int()
	return 0


static func _floor_count(tags: Dictionary) -> int:
	if tags.has("height") and _measurement(tags.height, 10000.0) > 0.0:
		return 0
	return _building_levels(tags)


static func _building_points(way: Dictionary, origin: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for coordinate in way.geometry:
		var point := _project(coordinate, origin)
		if points.is_empty() or point.distance_to(points[points.size() - 1]) > 0.01:
			points.append(point)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < 0.01:
		points.remove_at(points.size() - 1)
	return points


static func _building_interior(points: PackedVector2Array, thickness: float) -> PackedVector2Array:
	if points.size() < 3 or not is_finite(thickness) or thickness <= 0.0 or Geometry2D.triangulate_polygon(points).is_empty():
		return PackedVector2Array()
	var interiors := Geometry2D.offset_polygon(points, -thickness, Geometry2D.JOIN_MITER)
	if interiors.size() != 1 or interiors[0].size() < 3 or Geometry2D.triangulate_polygon(interiors[0]).is_empty():
		return PackedVector2Array()
	for point in interiors[0]:
		if not Geometry2D.is_point_in_polygon(point, points):
			return PackedVector2Array()
	return interiors[0]


static func _add_area(map: Node3D, way: Dictionary, material: Material, map_scale: float, origin: Array, prefix: String, height: float) -> void:
	if way.tags.get("area", "") == "no" or way.geometry.size() < 4 or way.geometry[0] != way.geometry[-1]:
		return
	var points := PackedVector2Array()
	for coordinate in way.geometry:
		var point := _project(coordinate, origin)
		if points.is_empty() or point.distance_to(points[points.size() - 1]) > 0.01:
			points.append(point)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < 0.01:
		points.remove_at(points.size() - 1)
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		push_warning("OSM-Fläche %d konnte nicht trianguliert werden." % int(way.id))
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for index in range(0, triangles.size(), 3):
		var a := points[triangles[index]]
		var b := points[triangles[index + 1]]
		var c := points[triangles[index + 2]]
		if (b - a).cross(c - a) < 0.0:
			var temporary := b
			b = c
			c = temporary
		for point in [a, b, c]:
			surface.add_vertex(Vector3(point.x * map_scale, height, point.y * map_scale))
	surface.generate_normals()
	var visual := MeshInstance3D.new()
	visual.name = "%s_%d" % [prefix, int(way.id)]
	visual.mesh = surface.commit()
	map.add_child(visual)


static func _add_building(map: Node3D, way: Dictionary, material: Material, map_scale: float, origin: Array) -> void:
	var points := _building_points(way, origin)
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		push_warning("OSM-Gebäude %d konnte nicht trianguliert werden." % int(way.id))
		return

	var height := _building_height(way.tags) * map_scale
	var floor_count := _floor_count(way.tags)
	var segment_count := maxi(1, floor_count)
	var segment_height := height / float(segment_count)
	var mesh := _building_segment_mesh(points, triangles, material, map_scale, segment_height, floor_count > 0)
	var body := StaticBody3D.new()
	body.name = "Building_%d" % int(way.id)
	body.collision_layer |= BUILDING_PICK_LAYER
	body.set_meta("measurement_points", points)
	body.set_meta("measurement_scale", map_scale)
	body.set_meta("measurement_height", height)
	body.set_meta("measurement_osm_id", way.id)
	body.set_meta("measurement_way", way.duplicate(true))
	var shape := mesh.create_trimesh_shape()
	var hollow_floors: Array = way.get("_hollow_floors", [])
	var floor_thickness := {}
	var hollow_meshes := {}
	for edit in hollow_floors:
		floor_thickness[int(edit.floor)] = float(edit.wall_thickness)
	for index in segment_count:
		var floor_mesh := mesh
		var floor_shape := shape
		var preview_mesh: ArrayMesh
		if floor_thickness.has(index + 1):
			var thickness: float = floor_thickness[index + 1]
			if not hollow_meshes.has(thickness):
				var interior := _building_interior(points, thickness)
				if interior.is_empty():
					push_error("Innenraum von Gebäude %s, Etage %d konnte nicht aufgebaut werden." % [str(way.id), index + 1])
				else:
					var hollow_mesh := _building_segment_mesh(points, triangles, material, map_scale, segment_height, true, interior)
					var collision_mesh := _building_segment_mesh(points, triangles, material, map_scale, segment_height, true, interior, false, true)
					hollow_meshes[thickness] = {
						"mesh": hollow_mesh,
						"shape": collision_mesh.create_trimesh_shape(),
						"preview": _building_segment_mesh(points, triangles, material, map_scale, segment_height, true, interior, true),
						"interior": interior,
					}
			if hollow_meshes.has(thickness):
				floor_mesh = hollow_meshes[thickness].mesh
				floor_shape = hollow_meshes[thickness].shape
				preview_mesh = hollow_meshes[thickness].preview
		var visual := MeshInstance3D.new()
		visual.name = "Segment_%d" % (index + 1)
		visual.mesh = floor_mesh
		visual.position.y = float(index) * segment_height
		var collider := CollisionShape3D.new()
		collider.name = "SegmentCollision_%d" % (index + 1)
		collider.shape = floor_shape
		collider.position.y = visual.position.y
		if floor_count > 0:
			visual.set_meta("floor_number", index + 1)
			collider.set_meta("floor_number", index + 1)
		body.add_child(visual)
		body.add_child(collider)
		if preview_mesh != null:
			var preview := MeshInstance3D.new()
			preview.name = "FloorPreview_%d" % (index + 1)
			preview.mesh = preview_mesh
			preview.position.y = visual.position.y
			preview.visible = false
			preview.set_meta("interior_points", hollow_meshes[floor_thickness[index + 1]].interior)
			body.add_child(preview)
	map.add_child(body)


static func _building_segment_mesh(points: PackedVector2Array, triangles: PackedInt32Array, material: Material, map_scale: float, height: float, bottom: bool, interior := PackedVector2Array(), preview := false, collision_caps := false) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	if not preview:
		for index in triangles:
			surface.add_vertex(Vector3(points[index].x * map_scale, height, points[index].y * map_scale))
		if collision_caps and not interior.is_empty():
			for index in range(triangles.size() - 1, -1, -1):
				var point := points[triangles[index]]
				surface.add_vertex(Vector3(point.x * map_scale, height, point.y * map_scale))
	if bottom:
		if interior.is_empty() or collision_caps:
			for index in range(triangles.size() - 1, -1, -1):
				var point := points[triangles[index]]
				surface.add_vertex(Vector3(point.x * map_scale, 0, point.y * map_scale))
		if not interior.is_empty():
			for index in triangles:
				var point := points[index]
				surface.add_vertex(Vector3(point.x * map_scale, 0, point.y * map_scale))
	_add_building_walls(surface, points, map_scale, height, false)
	if not interior.is_empty():
		_add_building_walls(surface, interior, map_scale, height, true)
	surface.generate_normals()
	return surface.commit()


static func _add_building_walls(surface: SurfaceTool, points: PackedVector2Array, map_scale: float, height: float, inward: bool) -> void:
	# Wall collision faces must point outward, or into the room for interior walls.
	var clockwise := Geometry2D.is_polygon_clockwise(points)
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		if clockwise == inward:
			var temporary := a
			a = b
			b = temporary
		var a_bottom := Vector3(a.x * map_scale, 0, a.y * map_scale)
		var b_bottom := Vector3(b.x * map_scale, 0, b.y * map_scale)
		var a_top := a_bottom + Vector3.UP * height
		var b_top := b_bottom + Vector3.UP * height
		for vertex in [a_bottom, a_top, b_top, a_bottom, b_top, b_bottom]:
			surface.add_vertex(vertex)
