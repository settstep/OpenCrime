extends RefCounted

const PlaceStore = preload("res://scripts/place_store.gd")
const ORIGIN_LAT := 47.7748417
const ORIGIN_LON := 10.6034933
const METERS_PER_DEGREE := 111320.0
const BUILDING_HEIGHT := 10.0
const LEVEL_HEIGHT := 3.0
const SCALE_SETTING := "opencrime/osm/scale"
const PEDESTRIAN_WAYS := ["footway", "path", "pedestrian", "steps", "cycleway"]
const ROAD_HEIGHT := 0.04
const PATH_HEIGHT := 0.02
const WAY_THICKNESS := 0.02
const JOINT_SEGMENTS := 24


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
	ground_mesh.mesh.size = Vector3(500 * map_scale, 1, 500 * map_scale)
	ground_shape.shape.size = Vector3(500 * map_scale, 1, 500 * map_scale)
	_add_map_boundary(world, 1500.0 * map_scale)

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
	var x := (float(point[1]) - float(origin[1])) * METERS_PER_DEGREE * cos(deg_to_rad(float(origin[0])))
	var z := (float(origin[0]) - float(point[0])) * METERS_PER_DEGREE
	return Vector2(x, z)


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
		var levels := str(tags["building:levels"]).strip_edges()
		if levels.is_valid_int() and int(levels) > 0 and int(levels) <= 1000:
			return float(levels.to_int()) * LEVEL_HEIGHT
		push_warning("Ungültige OSM-Etagenzahl: " + str(tags["building:levels"]))
	if tags.get("building", "") in ["garage", "garages"]:
		return 3.0
	return BUILDING_HEIGHT


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
	var points := PackedVector2Array()
	for coordinate in way.geometry:
		var point := _project(coordinate, origin)
		if points.is_empty() or point.distance_to(points[points.size() - 1]) > 0.01:
			points.append(point)
	if points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < 0.01:
		points.remove_at(points.size() - 1)
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		push_warning("OSM-Gebäude %d konnte nicht trianguliert werden." % int(way.id))
		return

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var height := _building_height(way.tags) * map_scale
	for index in triangles:
		surface.add_vertex(Vector3(points[index].x * map_scale, height, points[index].y * map_scale))
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var a_bottom := Vector3(a.x * map_scale, 0, a.y * map_scale)
		var b_bottom := Vector3(b.x * map_scale, 0, b.y * map_scale)
		var a_top := a_bottom + Vector3.UP * height
		var b_top := b_bottom + Vector3.UP * height
		for vertex in [a_bottom, a_top, b_top, a_bottom, b_top, b_bottom]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	var body := StaticBody3D.new()
	body.name = "Building_%d" % int(way.id)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.shape = mesh.create_trimesh_shape()
	body.add_child(collider)
	map.add_child(body)
