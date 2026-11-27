extends RefCounted

const DataPaths = preload("res://scripts/data_paths.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const BLOCK_DATA_VERSION := 2
const BUILTIN_PLACES := [
	{"id": "thalhofen", "name": "Thalhofen – Waldmünchener Straße", "path": "res://data/thalhofen.json", "origin": [47.7748417, 10.6034933]},
	{"id": "gendarmenmarkt", "name": "Berlin – Gendarmenmarkt", "path": "res://data/gendarmenmarkt.json", "origin": [52.5130, 13.3912]},
]

static var DIRECTORY := DataPaths.path("places")
static var BLOCK_CACHE_DIRECTORY := DataPaths.path("map_blocks")


static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Ort konnte nicht geöffnet werden: " + path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("Ortsdatei ist ungültig: " + path)
		return {}
	return json.data


static func is_valid(place: Dictionary) -> bool:
	if not place.has_all(["id", "name", "origin", "bounds", "ways"]):
		return false
	if not place.id is String or place.id.is_empty() or not place.name is String or place.name.is_empty():
		return false
	if not place.origin is Array or place.origin.size() != 2 or not place.bounds is Array or place.bounds.size() != 4 or not place.ways is Array or not place.get("nodes", []) is Array:
		return false
	if place.has("block_data_version"):
		var version: Variant = place.block_data_version
		if (typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT) or not is_finite(float(version)) or float(version) < 1.0 or float(version) != floorf(float(version)):
			return false
	for value in place.origin + place.bounds:
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
			return false
	var south := float(place.bounds[0])
	var west := float(place.bounds[1])
	var north := float(place.bounds[2])
	var east := float(place.bounds[3])
	if south < -85.0 or north > 85.0 or west < -180.0 or east > 180.0 or south >= north or west >= east:
		return false
	if float(place.origin[0]) < south or float(place.origin[0]) > north or float(place.origin[1]) < west or float(place.origin[1]) > east:
		return false
	for way in place.ways:
		if not way is Dictionary or not way.has_all(["id", "tags", "geometry"]) or not way.tags is Dictionary or not way.geometry is Array:
			return false
		if (typeof(way.id) != TYPE_INT and typeof(way.id) != TYPE_FLOAT) or float(way.id) <= 0.0 or not is_finite(float(way.id)):
			return false
		for point in way.geometry:
			if not point is Array or point.size() != 2:
				return false
			for value in point:
				if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
					return false
			if absf(float(point[0])) > 90.0 or absf(float(point[1])) > 180.0:
				return false
	for node in place.get("nodes", []):
		if not node is Dictionary or not node.has_all(["id", "tags", "location"]) or not node.tags is Dictionary or not node.location is Array or node.location.size() != 2:
			return false
		if (typeof(node.id) != TYPE_INT and typeof(node.id) != TYPE_FLOAT) or float(node.id) <= 0.0 or not is_finite(float(node.id)):
			return false
		for value in node.location:
			if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)):
				return false
		if absf(float(node.location[0])) > 90.0 or absf(float(node.location[1])) > 180.0:
			return false
	return true


static func block_needs_refresh(block_data: Dictionary) -> bool:
	return block_data.get("block_data_version", 0) != BLOCK_DATA_VERSION


static func block_query(bounds: Array) -> String:
	if bounds.size() != 4:
		return ""
	var bbox := "%.7f,%.7f,%.7f,%.7f" % bounds
	return '[out:json][timeout:60];(way["highway"](%s);way["building"](%s);way["amenity"="parking"](%s);node["highway"~"^(traffic_signals|stop|give_way|crossing)$"](%s);node["traffic_sign"](%s);way["traffic_sign"](%s);node["emergency"~"^(fire_hydrant|defibrillator)$"](%s);way["emergency"~"^(fire_hydrant|defibrillator)$"](%s););out body geom;' % [bbox, bbox, bbox, bbox, bbox, bbox, bbox, bbox]


static func available_places() -> Array[Dictionary]:
	var places: Array[Dictionary] = []
	for item in BUILTIN_PLACES:
		var place := read_file(item.path)
		place["id"] = item.id
		place["name"] = item.name
		place["origin"] = item.origin
		if is_valid(place):
			places.append(place)
		else:
			push_error("Mitgelieferter Ort ist ungültig: " + item.path)
	var directory := DirAccess.open(DIRECTORY)
	if directory != null:
		var files := directory.get_files()
		files.sort()
		for filename in files:
			if not filename.begins_with("place_") or not filename.ends_with(".json"):
				continue
			var path := DIRECTORY.path_join(filename)
			var place := read_file(path)
			if is_valid(place):
				places.append(place)
			else:
				push_error("Gespeicherter Ort ist ungültig: " + path)
	return places


static func find_by_id(id: String) -> Dictionary:
	for place in available_places():
		if place.id == id:
			return place
	return {}


static func find_containing(places: Array[Dictionary], latitude: float, longitude: float) -> Dictionary:
	for place in places:
		var bounds: Array = place.bounds
		if latitude >= float(bounds[0]) and latitude <= float(bounds[2]) and longitude >= float(bounds[1]) and longitude <= float(bounds[3]):
			return place
	return {}


static func from_overpass(response: Dictionary, latitude: float, longitude: float, bounds: Array, place_name: String) -> Dictionary:
	if response.has("remark") or not response.has("elements") or not response.elements is Array:
		return {}
	if response.has("osm3s") and not response.osm3s is Dictionary:
		return {}
	var ways: Array = []
	var nodes: Array = []
	var seen_elements := {}
	var closest := Vector2.ZERO
	var closest_distance := INF
	var longitude_scale := 111320.0 * cos(deg_to_rad(latitude))
	for element in response.elements:
		if not element is Dictionary or not element.has_all(["id", "tags"]) or not element.tags is Dictionary:
			return {}
		var element_key := str(element.get("type", "")) + ":" + str(element.id)
		if seen_elements.has(element_key):
			continue
		seen_elements[element_key] = true
		if element.get("type") == "node":
			if not element.has_all(["lat", "lon"]):
				return {}
			if (typeof(element.lat) != TYPE_INT and typeof(element.lat) != TYPE_FLOAT) or (typeof(element.lon) != TYPE_INT and typeof(element.lon) != TYPE_FLOAT):
				return {}
			if not is_finite(float(element.lat)) or not is_finite(float(element.lon)) or absf(float(element.lat)) > 90.0 or absf(float(element.lon)) > 180.0:
				return {}
			nodes.append({"id": element.id, "tags": element.tags, "location": [element.lat, element.lon]})
			continue
		if element.get("type") != "way" or not element.has("geometry"):
			return {}
		var geometry: Array = []
		if not element.geometry is Array:
			return {}
		for point in element.geometry:
			if not point is Dictionary or not point.has_all(["lat", "lon"]):
				return {}
			if (typeof(point.lat) != TYPE_INT and typeof(point.lat) != TYPE_FLOAT) or (typeof(point.lon) != TYPE_INT and typeof(point.lon) != TYPE_FLOAT):
				return {}
			if not is_finite(float(point.lat)) or not is_finite(float(point.lon)) or absf(float(point.lat)) > 90.0 or absf(float(point.lon)) > 180.0:
				return {}
			geometry.append([point.lat, point.lon])
		if element.tags.has("highway") and element.tags.get("area", "") != "yes":
			for index in range(geometry.size() - 1):
				var a := Vector2((float(geometry[index][1]) - longitude) * longitude_scale, (latitude - float(geometry[index][0])) * 111320.0)
				var b := Vector2((float(geometry[index + 1][1]) - longitude) * longitude_scale, (latitude - float(geometry[index + 1][0])) * 111320.0)
				var candidate := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b)
				if candidate.length() < closest_distance:
					closest = candidate
					closest_distance = candidate.length()
		var way := {"id": element.id, "tags": element.tags, "geometry": geometry}
		if element.has("nodes"):
			way["nodes"] = element.nodes
		ways.append(way)
	if closest_distance > 100.0:
		return {}
	var scale: Variant = ProjectSettings.get_setting("opencrime/osm/scale")
	if (typeof(scale) != TYPE_INT and typeof(scale) != TYPE_FLOAT) or not is_finite(float(scale)) or float(scale) <= 0.0:
		return {}
	var spawn_points: Array[Vector2] = [closest, closest + Vector2(0, -5.0 / float(scale))]
	for slot in range(9):
		spawn_points.append(closest + Vector2(float(slot % 3 - 1) * 1.5, 2.0 + float(slot / 3) * 1.5) / float(scale))
	for way in ways:
		if not way.tags.has("building") or way.geometry.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point in way.geometry:
			polygon.append(Vector2((float(point[1]) - longitude) * longitude_scale, (latitude - float(point[0])) * 111320.0))
		for index in spawn_points.size():
			var radius := (2.0 if index == 1 else 0.6) / float(scale)
			if Geometry2D.is_point_in_polygon(spawn_points[index], polygon):
				return {}
			for edge in polygon.size():
				if spawn_points[index].distance_to(Geometry2D.get_closest_point_to_segment(spawn_points[index], polygon[edge], polygon[(edge + 1) % polygon.size()])) < radius:
					return {}
	var id := "place_" + ("%0.6f,%0.6f" % [latitude, longitude]).sha256_text().substr(0, 16)
	var place := {
		"id": id,
		"name": place_name,
		"origin": [latitude - closest.y / 111320.0, longitude + closest.x / longitude_scale],
		"bounds": bounds,
		"ways": ways,
		"nodes": nodes,
		"source": ProjectSettings.get_setting("opencrime/osm/overpass_url"),
		"osm_timestamp": response.get("osm3s", {}).get("timestamp_osm_base", ""),
	}
	return place if is_valid(place) and not ways.is_empty() else {}


static func from_overpass_block(response: Dictionary, origin: Array, bounds: Array, block_id: String) -> Dictionary:
	if response.has("remark") or not response.has("elements") or not response.elements is Array or origin.size() != 2 or bounds.size() != 4 or block_id.is_empty():
		return {}
	if response.has("osm3s") and not response.osm3s is Dictionary:
		return {}
	var ways: Array = []
	var nodes: Array = []
	var seen_elements := {}
	for element in response.elements:
		if not element is Dictionary or not element.has_all(["id", "tags"]) or not element.tags is Dictionary:
			return {}
		var element_key := str(element.get("type", "")) + ":" + str(element.id)
		if seen_elements.has(element_key):
			continue
		seen_elements[element_key] = true
		if element.get("type") == "node":
			if not element.has_all(["lat", "lon"]):
				return {}
			if (typeof(element.lat) != TYPE_INT and typeof(element.lat) != TYPE_FLOAT) or (typeof(element.lon) != TYPE_INT and typeof(element.lon) != TYPE_FLOAT):
				return {}
			if not is_finite(float(element.lat)) or not is_finite(float(element.lon)) or absf(float(element.lat)) > 90.0 or absf(float(element.lon)) > 180.0:
				return {}
			nodes.append({"id": element.id, "tags": element.tags, "location": [element.lat, element.lon]})
			continue
		if element.get("type") != "way" or not element.has("geometry") or not element.geometry is Array:
			return {}
		var geometry: Array = []
		for point in element.geometry:
			if not point is Dictionary or not point.has_all(["lat", "lon"]):
				return {}
			if (typeof(point.lat) != TYPE_INT and typeof(point.lat) != TYPE_FLOAT) or (typeof(point.lon) != TYPE_INT and typeof(point.lon) != TYPE_FLOAT):
				return {}
			if not is_finite(float(point.lat)) or not is_finite(float(point.lon)) or absf(float(point.lat)) > 90.0 or absf(float(point.lon)) > 180.0:
				return {}
			geometry.append([point.lat, point.lon])
		var way := {"id": element.id, "tags": element.tags, "geometry": geometry}
		if element.has("nodes"):
			way["nodes"] = element.nodes
		ways.append(way)
	var place := {
		"id": block_id,
		"name": "Kartenblock " + block_id,
		"origin": origin,
		"bounds": bounds,
		"ways": ways,
		"nodes": nodes,
		"block_data_version": BLOCK_DATA_VERSION,
		"source": ProjectSettings.get_setting("opencrime/osm/overpass_url"),
		"osm_timestamp": response.get("osm3s", {}).get("timestamp_osm_base", ""),
	}
	return place if is_valid(place) else {}


static func from_cached_block(block_data: Dictionary, latitude: float, longitude: float, bounds: Array, place_name: String) -> Dictionary:
	if not is_valid(block_data):
		return {}
	var elements: Array = []
	for way in block_data.ways:
		var geometry: Array = []
		for point in way.geometry:
			geometry.append({"lat": point[0], "lon": point[1]})
		var element := {"type": "way", "id": way.id, "tags": way.tags, "geometry": geometry}
		if way.has("nodes"):
			element["nodes"] = way.nodes
		elements.append(element)
	for node in block_data.get("nodes", []):
		elements.append({
			"type": "node",
			"id": node.id,
			"tags": node.tags,
			"lat": node.location[0],
			"lon": node.location[1],
		})
	var response := {
		"elements": elements,
		"osm3s": {"timestamp_osm_base": block_data.get("osm_timestamp", "")},
	}
	return from_overpass(response, latitude, longitude, bounds, place_name)


static func block_cache_path(block_id: String, directory: String = "") -> String:
	var cache_directory := BLOCK_CACHE_DIRECTORY if directory.is_empty() else directory
	return cache_directory.path_join(block_id + ".json")


static func read_block_cache(block: Vector2i, reference_origin: Array, directory: String = "") -> Dictionary:
	if reference_origin.size() != 2:
		return {}
	var block_id := "block_" + Grid.tile_id(block, reference_origin)
	var path := block_cache_path(block_id, directory)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Kartenblock-Cache konnte nicht gelesen werden: " + path)
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary or not is_valid(json.data) or json.data.id != block_id:
		push_warning("Ungültiger Kartenblock-Cache wird erneut geladen: " + path)
		return {}
	var expected_origin := Grid.block_origin(reference_origin, block)
	var expected_bounds := Grid.block_bounds(reference_origin, block)
	if expected_origin.size() != 2 or expected_bounds.size() != 4:
		push_warning("Kartenblock-Cache kann nicht dem UTM-Raster zugeordnet werden: " + path)
		return {}
	for index in 2:
		if not is_equal_approx(float(json.data.origin[index]), float(expected_origin[index])):
			push_warning("Kartenblock-Cache hat einen abweichenden Ursprung: " + path)
			return {}
	for index in 4:
		if not is_equal_approx(float(json.data.bounds[index]), float(expected_bounds[index])):
			push_warning("Kartenblock-Cache hat abweichende Grenzen: " + path)
			return {}
	return json.data


static func write_block_cache(block_id: String, place: Dictionary, directory: String = "") -> Error:
	if not block_id.begins_with("block_utm") or block_id.contains("/") or block_id.contains("\\") or place.get("id", "") != block_id or not is_valid(place):
		return ERR_INVALID_DATA
	var path := block_cache_path(block_id, directory)
	var cache_directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
	if error != OK:
		push_error("Kartenblock-Cache konnte nicht erstellt werden (Fehler %d)." % error)
		return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		push_error("Kartenblock-Cache konnte nicht geöffnet werden (Fehler %d): %s" % [error, path])
		return error
	file.store_string(JSON.stringify(place))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		push_error("Kartenblock-Cache konnte nicht geschrieben werden (Fehler %d): %s" % [error, path])
	return error


static func save_place(place: Dictionary) -> Error:
	if not is_valid(place) or not place.id.begins_with("place_") or place.id.length() != 22 or not place.id.substr(6).is_valid_hex_number(false):
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if error != OK:
		return error
	var path := DIRECTORY.path_join(place.id + ".json")
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(place))
	error = file.get_error()
	file.close()
	if error != OK:
		var cleanup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if cleanup_error != OK:
			push_error("Unvollständige Ortsdatei konnte nicht entfernt werden: " + path)
	return error
