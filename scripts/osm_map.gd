extends RefCounted

const PlaceStore = preload("res://scripts/place_store.gd")
const ORIGIN_LAT := 47.7748417
const ORIGIN_LON := 10.6034933
const METERS_PER_DEGREE := 111320.0
const BUILDING_HEIGHT := 10.0
const SCALE_SETTING := "opencrime/osm/scale"


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

	for node_name in ["Road", "Building1", "Building2"]:
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
	ground_mesh.mesh.size = Vector3(450 * map_scale, 1, 450 * map_scale)
	ground_shape.shape.size = Vector3(450 * map_scale, 1, 450 * map_scale)

	var map := Node3D.new()
	map.name = "OSMMap"
	world.add_child(map)
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color(0.27, 0.28, 0.30)
	var building_material := StandardMaterial3D.new()
	building_material.albedo_color = Color(0.73, 0.62, 0.48)
	building_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	for way in place.ways:
		if way.tags.has("building"):
			_add_building(map, way, building_material, map_scale, place.origin)
		elif way.tags.has("highway") and way.tags.get("area", "") != "yes":
			_add_road(map, way, road_material, map_scale, place.origin)

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


static func _project(point: Array, origin: Array = [ORIGIN_LAT, ORIGIN_LON]) -> Vector2:
	var x := (float(point[1]) - float(origin[1])) * METERS_PER_DEGREE * cos(deg_to_rad(float(origin[0])))
	var z := (float(origin[0]) - float(point[0])) * METERS_PER_DEGREE
	return Vector2(x, z)


static func _add_road(map: Node3D, way: Dictionary, material: Material, map_scale: float, origin: Array) -> void:
	var width := 6.0
	if way.tags.highway in ["footway", "path", "pedestrian", "steps", "cycleway"]:
		width = 2.0
	for index in range(way.geometry.size() - 1):
		var start := _project(way.geometry[index], origin)
		var end := _project(way.geometry[index + 1], origin)
		var direction := end - start
		if direction.length() < 0.05:
			continue
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(width * map_scale, 0.02, direction.length() * map_scale)
		road_mesh.material = material
		var segment := MeshInstance3D.new()
		segment.mesh = road_mesh
		segment.position = Vector3((start.x + end.x) * map_scale / 2.0, 0.02, (start.y + end.y) * map_scale / 2.0)
		segment.rotation.y = atan2(direction.x, direction.y)
		map.add_child(segment)


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
	var height := BUILDING_HEIGHT * map_scale
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
