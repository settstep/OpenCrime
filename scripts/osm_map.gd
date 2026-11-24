extends RefCounted

const DATA_PATH := "res://data/gendarmenmarkt.json"
const ORIGIN_LAT := 52.5130
const ORIGIN_LON := 13.3912
const METERS_PER_DEGREE := 111320.0
const BUILDING_HEIGHT := 10.0


static func populate(world: Node3D) -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("OSM-Kartendaten konnten nicht geöffnet werden: " + DATA_PATH)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary or not json.data.has("ways"):
		push_error("OSM-Kartendaten sind ungültig: " + DATA_PATH)
		return false

	for node_name in ["Road", "Building1", "Building2"]:
		world.get_node(node_name).free()

	var ground_mesh: MeshInstance3D = world.get_node("Ground/MeshInstance3D")
	var ground_shape: CollisionShape3D = world.get_node("Ground/CollisionShape3D")
	ground_mesh.mesh = ground_mesh.mesh.duplicate()
	ground_shape.shape = ground_shape.shape.duplicate()
	ground_mesh.mesh.size = Vector3(450, 1, 450)
	ground_shape.shape.size = Vector3(450, 1, 450)

	var map := Node3D.new()
	map.name = "OSMMap"
	world.add_child(map)
	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color(0.27, 0.28, 0.30)
	var building_material := StandardMaterial3D.new()
	building_material.albedo_color = Color(0.73, 0.62, 0.48)
	building_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	for way in json.data.ways:
		if way.tags.has("building"):
			_add_building(map, way, building_material)
		elif way.tags.has("highway") and way.tags.get("area", "") != "yes":
			_add_road(map, way, road_material)

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


static func _project(point: Array) -> Vector2:
	var x := (float(point[1]) - ORIGIN_LON) * METERS_PER_DEGREE * cos(deg_to_rad(ORIGIN_LAT))
	var z := (ORIGIN_LAT - float(point[0])) * METERS_PER_DEGREE
	return Vector2(x, z)


static func _add_road(map: Node3D, way: Dictionary, material: Material) -> void:
	var width := 6.0
	if way.tags.highway in ["footway", "path", "pedestrian", "steps", "cycleway"]:
		width = 2.0
	for index in range(way.geometry.size() - 1):
		var start := _project(way.geometry[index])
		var end := _project(way.geometry[index + 1])
		var direction := end - start
		if direction.length() < 0.05:
			continue
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(width, 0.02, direction.length())
		road_mesh.material = material
		var segment := MeshInstance3D.new()
		segment.mesh = road_mesh
		segment.position = Vector3((start.x + end.x) / 2.0, 0.02, (start.y + end.y) / 2.0)
		segment.rotation.y = atan2(direction.x, direction.y)
		map.add_child(segment)


static func _add_building(map: Node3D, way: Dictionary, material: Material) -> void:
	var points := PackedVector2Array()
	for coordinate in way.geometry:
		var point := _project(coordinate)
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
	for index in triangles:
		surface.add_vertex(Vector3(points[index].x, BUILDING_HEIGHT, points[index].y))
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var a_bottom := Vector3(a.x, 0, a.y)
		var b_bottom := Vector3(b.x, 0, b.y)
		var a_top := a_bottom + Vector3.UP * BUILDING_HEIGHT
		var b_top := b_bottom + Vector3.UP * BUILDING_HEIGHT
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
