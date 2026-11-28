extends RefCounted

const DataPaths = preload("res://scripts/data_paths.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const BuildingWalls = preload("res://scripts/building_walls.gd")
const FORMAT := 1
const MAX_BYTES := 3 * 1024 * 1024
const DEFAULT_CONFIG := "res://data/building_editor.json"

var path := DataPaths.path("map_edits/buildings.json")
var merges: Array = []
var level_edits: Array = []
var error := ""
var load_failed := false
var conflicts: Array[int] = []
var blocked_merges := {}


func load_file() -> bool:
	merges = []
	level_edits = []
	error = ""
	load_failed = false
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Gebäudeänderungen konnten nicht gelesen werden (Fehler %d)." % FileAccess.get_open_error()
		load_failed = true
		return false
	if file.get_length() > MAX_BYTES:
		error = "Die Datei mit Gebäudeänderungen ist zu groß."
		load_failed = true
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not set_data(json.data):
		error = "Die Datei mit Gebäudeänderungen ist ungültig; sie wurde nicht verändert."
		load_failed = true
		return false
	return true


func data() -> Dictionary:
	return {"format": FORMAT, "merges": merges.duplicate(true), "level_edits": level_edits.duplicate(true)}


func set_data(value: Variant) -> bool:
	if not value is Dictionary or value.get("format") != FORMAT or not value.get("merges") is Array or not value.get("level_edits", []) is Array:
		return false
	var seen := {}
	for merge in value.merges:
		if not merge is Dictionary or not merge.get("sources") is Array or merge.sources.size() < 2 or not _valid_way(merge.get("result")):
			return false
		if not _valid_floor_edits(merge.get("hollow_floors", []), merge.result, OSMMap._floor_count(merge.result.tags)):
			return false
		var contains_result := false
		for source in merge.sources:
			if not _valid_way(source) or seen.has(int(source.id)):
				return false
			seen[int(source.id)] = true
			contains_result = contains_result or int(source.id) == int(merge.result.id)
		if not contains_result:
			return false
	for edit in value.get("level_edits", []):
		if not edit is Dictionary or not _valid_way(edit.get("source"), false) or not _valid_levels(edit.get("levels")) or seen.has(int(edit.source.id)):
			return false
		if not _valid_floor_edits(edit.get("hollow_floors", []), edit.source, int(edit.levels)):
			return false
		seen[int(edit.source.id)] = true
	merges = value.merges.duplicate(true)
	level_edits = value.get("level_edits", []).duplicate(true)
	error = ""
	return true


func set_blocked(value: Variant) -> bool:
	if not value is Array:
		return false
	var allowed := {}
	for merge in merges:
		allowed[int(merge.result.id)] = true
	for edit in level_edits:
		allowed[int(edit.source.id)] = true
	var blocked := {}
	for id in value:
		if not (id is int or id is float) or not is_finite(float(id)) or float(id) != floorf(float(id)) or not allowed.has(int(id)):
			return false
		blocked[int(id)] = true
	blocked_merges = blocked
	return true


static func _valid_way(way: Variant, require_closed := true) -> bool:
	if not way is Dictionary or not way.has_all(["id", "tags", "geometry"]) or not way.tags is Dictionary or not way.tags.has("building") or not way.geometry is Array:
		return false
	if not (way.id is int or way.id is float) or not is_finite(float(way.id)) or float(way.id) <= 0 or float(way.id) != floorf(float(way.id)):
		return false
	if way.geometry.size() < (4 if require_closed else 3) or way.geometry.size() > 10000:
		return false
	for point in way.geometry:
		if not point is Array or point.size() != 2:
			return false
		for number in point:
			if not (number is int or number is float) or not is_finite(float(number)):
				return false
		if absf(float(point[0])) > 85.0 or absf(float(point[1])) > 180.0:
			return false
	return not require_closed or way.geometry[0] == way.geometry[-1]


static func _valid_levels(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 1.0 and float(value) <= 1000.0


static func _valid_floor_edits(edits: Variant, way: Dictionary, levels: int) -> bool:
	if not edits is Array or edits.size() > levels:
		return false
	var seen := {}
	var points := OSMMap._building_points(way, way.geometry[0])
	for edit in edits:
		if not edit is Dictionary or not _valid_levels(edit.get("floor")) or int(edit.floor) > levels or seen.has(int(edit.floor)):
			return false
		var thickness: Variant = edit.get("wall_thickness")
		if not (thickness is int or thickness is float) or not is_finite(float(thickness)) or float(thickness) <= 0.0 or float(thickness) > 1000.0:
			return false
		var footprint := BuildingWalls.floor_outline(points, edit)
		if footprint.has("error"):
			return false
		var interior := OSMMap._building_interior(footprint.outline, float(thickness))
		if interior.is_empty():
			return false
		var walls: Variant = edit.get("walls", [])
		if not walls is Array:
			return false
		if not walls.is_empty():
			if BuildingWalls.build(interior, walls).has("error"):
				return false
		seen[int(edit.floor)] = true
	return true


func apply(place: Dictionary) -> Dictionary:
	var result := place.duplicate(true)
	conflicts.clear()
	for merge in merges:
		var sources := {}
		for source in merge.sources:
			sources[int(source.id)] = source
		var found := false
		var conflict := false
		for way in result.ways:
			if sources.has(int(way.id)):
				found = true
				if not way.tags.has("building") or not _same_geometry(way.geometry, sources[int(way.id)].geometry):
					conflict = true
		if not found:
			continue
		if conflict or blocked_merges.has(int(merge.result.id)):
			conflicts.append(int(merge.result.id))
			continue
		var ways := []
		for way in result.ways:
			if not sources.has(int(way.id)):
				ways.append(way)
		var merged: Dictionary = merge.result.duplicate(true)
		merged["_edit_sources"] = merge.sources.duplicate(true)
		merged["_hollow_floors"] = merge.get("hollow_floors", []).duplicate(true)
		ways.append(merged)
		result.ways = ways
	for edit in level_edits:
		for index in result.ways.size():
			var way: Dictionary = result.ways[index]
			if int(way.id) != int(edit.source.id):
				continue
			if blocked_merges.has(int(way.id)) or not way.tags.has("building") or not _same_geometry(way.geometry, edit.source.geometry):
				conflicts.append(int(way.id))
				continue
			var changed: Dictionary = way.duplicate(true)
			_set_levels(changed, int(edit.levels))
			changed["_edit_sources"] = [edit.source.duplicate(true)]
			changed["_hollow_floors"] = edit.get("hollow_floors", []).duplicate(true)
			result.ways[index] = changed
	return result


func scan_conflicts(places: Array) -> bool:
	var blocked := {}
	var sources := {}
	for merge in merges:
		for source in merge.sources:
			sources[int(source.id)] = {"way": source, "merge_id": int(merge.result.id)}
	for edit in level_edits:
		sources[int(edit.source.id)] = {"way": edit.source, "merge_id": int(edit.source.id)}
	for place in places:
		for way in place.ways:
			if sources.has(int(way.id)):
				var source: Dictionary = sources[int(way.id)]
				if not way.tags.has("building") or not _same_geometry(way.geometry, source.way.geometry):
					blocked[source.merge_id] = true
	var changed := blocked != blocked_merges
	blocked_merges = blocked
	return changed


static func _same_geometry(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if absf(float(a[index][0]) - float(b[index][0])) > 0.0000000001 or absf(float(a[index][1]) - float(b[index][1])) > 0.0000000001:
			return false
	return true


static func _set_levels(way: Dictionary, levels: int) -> void:
	way.tags.erase("height")
	way.tags["building:levels"] = str(levels)


func prepare_levels(way: Dictionary, levels: int) -> Dictionary:
	if not _valid_way(way, false) or not _valid_levels(levels):
		return {"error": "Bitte ein gültiges Gebäude und eine Etagenzahl von 1 bis 1000 wählen."}
	var id := int(way.id)
	if blocked_merges.has(id):
		return {"error": "Diese Gebäudeänderung hat einen OSM-Konflikt und kann nicht bearbeitet werden."}
	var next := data()
	for merge in next.merges:
		for source in merge.sources:
			if int(source.id) != id:
				continue
			if int(merge.result.id) != id or not way.has("_edit_sources") or blocked_merges.has(int(merge.result.id)):
				return {"error": "Dieses Gebäude gehört zu einer bestehenden Zusammenfassung mit OSM-Konflikt."}
			for floor_edit in merge.get("hollow_floors", []):
				if int(floor_edit.floor) > levels:
					return {"error": "Die Etagenzahl kann nicht unter eine bereits bearbeitete Etage reduziert werden."}
			_set_levels(merge.result, levels)
			return {"data": next}
	var original: Dictionary = way.duplicate(true)
	if way.has("_edit_sources"):
		if not way._edit_sources is Array or way._edit_sources.size() != 1 or not _valid_way(way._edit_sources[0], false) or int(way._edit_sources[0].id) != id:
			return {"error": "Die ursprünglichen OSM-Daten des Gebäudes sind ungültig."}
		original = way._edit_sources[0].duplicate(true)
	original.erase("_edit_sources")
	original.erase("_hollow_floors")
	var retained := []
	var hollow_floors := []
	for edit in next.level_edits:
		if int(edit.source.id) != id:
			retained.append(edit)
		else:
			hollow_floors = edit.get("hollow_floors", []).duplicate(true)
			for floor_edit in hollow_floors:
				if int(floor_edit.floor) > levels:
					return {"error": "Die Etagenzahl kann nicht unter eine bereits bearbeitete Etage reduziert werden."}
	retained.append({"source": original, "levels": levels, "hollow_floors": hollow_floors})
	next.level_edits = retained
	return {"data": next}


func prepare_hollow(way: Dictionary, floor_number: int, thickness: float) -> Dictionary:
	if not _valid_way(way, false):
		return {"error": "Bitte ein gültiges Gebäude auswählen."}
	var levels := OSMMap._floor_count(way.tags)
	if floor_number < 1 or floor_number > levels:
		return {"error": "Bitte zuerst eine gültige Etagenzahl festlegen und eine Etage auswählen."}
	if not is_finite(thickness) or thickness <= 0.0 or thickness > 1000.0:
		return {"error": "Die Wanddicke muss größer als 0 und höchstens 1000 Meter sein."}
	if OSMMap._building_interior(OSMMap._building_points(way, way.geometry[0]), thickness).is_empty():
		return {"error": "Dieser Grundriss ergibt mit der Wanddicke keinen zusammenhängenden Innenraum."}
	var prepared := prepare_levels(way, levels)
	if prepared.has("error"):
		return prepared
	var target: Dictionary = {}
	for merge in prepared.data.merges:
		if int(merge.result.id) == int(way.id):
			target = merge
			break
	if target.is_empty():
		for edit in prepared.data.level_edits:
			if int(edit.source.id) == int(way.id):
				target = edit
				break
	if target.is_empty():
		return {"error": "Die Etage konnte nicht zugeordnet werden."}
	var floors: Array = target.get("hollow_floors", [])
	for edit in floors:
		if int(edit.floor) == floor_number:
			return {"error": "Diese Etage ist bereits ausgehöhlt."}
	floors.append({"floor": floor_number, "wall_thickness": thickness})
	target["hollow_floors"] = floors
	return prepared


func prepare_wall(way: Dictionary, floor_number: int, cursor: Vector2, thickness: float) -> Dictionary:
	if not _valid_way(way, false):
		return {"error": "Bitte ein gültiges Gebäude auswählen."}
	var levels := OSMMap._floor_count(way.tags)
	if floor_number < 1 or floor_number > levels:
		return {"error": "Bitte eine gültige Etage auswählen."}
	var prepared := prepare_levels(way, levels)
	if prepared.has("error"):
		return prepared
	var target: Dictionary = {}
	var original: Dictionary = {}
	for merge in prepared.data.merges:
		if int(merge.result.id) == int(way.id):
			target = merge
			original = merge.result
			break
	if target.is_empty():
		for edit in prepared.data.level_edits:
			if int(edit.source.id) == int(way.id):
				target = edit
				original = edit.source
				break
	if target.is_empty():
		return {"error": "Die Etage konnte nicht zugeordnet werden."}
	for floor_edit in target.get("hollow_floors", []):
		if int(floor_edit.floor) != floor_number:
			continue
		var walls: Array = floor_edit.get("walls", [])
		if walls.size() >= BuildingWalls.MAX_WALLS:
			return {"error": "Auf dieser Etage können keine weiteren Wände gespeichert werden."}
		var points := OSMMap._building_points(original, original.geometry[0])
		var footprint := BuildingWalls.floor_outline(points, floor_edit)
		if footprint.has("error"):
			return footprint
		var interior := OSMMap._building_interior(footprint.outline, float(floor_edit.wall_thickness))
		var existing := BuildingWalls.build(interior, walls)
		if existing.has("error"):
			return existing
		var plan := BuildingWalls.plan_wall(existing.regions, cursor, thickness)
		if plan.has("error"):
			return plan
		walls.append({"cursor": [cursor.x, cursor.y], "thickness": thickness})
		floor_edit["walls"] = walls
		return prepared
	return {"error": "Bitte die Etage zuerst aushöhlen."}


func prepare_wall_change(way: Dictionary, floor_number: int, outside: bool, wall_index: int, distance: float, thickness: float, segment_index := -1) -> Dictionary:
	if not _valid_way(way, false) or not is_finite(distance) or not is_finite(thickness) or thickness <= 0.0 or thickness > 1000.0:
		return {"error": "Ungültige Wandposition oder Wanddicke."}
	var levels := OSMMap._floor_count(way.tags)
	if floor_number < 1 or floor_number > levels:
		return {"error": "Bitte eine gültige Etage auswählen."}
	var prepared := prepare_levels(way, levels)
	if prepared.has("error"):
		return prepared
	var target: Dictionary = {}
	var original: Dictionary = {}
	for merge in prepared.data.merges:
		if int(merge.result.id) == int(way.id):
			target = merge
			original = merge.result
			break
	if target.is_empty():
		for edit in prepared.data.level_edits:
			if int(edit.source.id) == int(way.id):
				target = edit
				original = edit.source
				break
	if target.is_empty():
		return {"error": "Die Etage konnte nicht zugeordnet werden."}
	for floor_edit in target.get("hollow_floors", []):
		if int(floor_edit.floor) != floor_number:
			continue
		var points := OSMMap._building_points(original, original.geometry[0])
		var footprint := BuildingWalls.floor_outline(points, floor_edit)
		if footprint.has("error"):
			return footprint
		var old_interior := OSMMap._building_interior(footprint.outline, float(floor_edit.wall_thickness))
		if outside:
			if segment_index >= 0:
				var matched := false
				for split in floor_edit.get("outer_splits", []):
					if int(split.edge) == wall_index and segment_index < split.offsets.size():
						split.offsets[segment_index] = float(split.offsets[segment_index]) + distance
						matched = true
						break
				if not matched:
					return {"error": "Das Außenwandteilstück ist nicht mehr verfügbar."}
			else:
				var shifted := BuildingWalls.move_outline_edge(footprint.base, wall_index, distance)
				if shifted.has("error"):
					return shifted
				var encoded := []
				for point in shifted.outline:
					encoded.append([point.x, point.y])
				floor_edit["outline"] = encoded
			floor_edit.wall_thickness = thickness
		var next_footprint := BuildingWalls.floor_outline(points, floor_edit)
		if next_footprint.has("error"):
			return next_footprint
		var new_interior := OSMMap._building_interior(next_footprint.outline, float(floor_edit.wall_thickness))
		if new_interior.is_empty():
			return {"error": "Die Änderung würde einen ungültigen Innenraum erzeugen."}
		var walls: Array = floor_edit.get("walls", [])
		var updated := BuildingWalls.adjust_walls(old_interior, new_interior, walls, -1 if outside else wall_index, 0.0 if outside else distance, -1.0 if outside else thickness, -1 if outside else segment_index)
		if updated.has("error"):
			return updated
		floor_edit["walls"] = updated.walls
		return prepared
	return {"error": "Bitte die Etage zuerst aushöhlen."}


func prepare_wall_split(way: Dictionary, floor_number: int, outside: bool, wall_index: int, segment_index: int) -> Dictionary:
	if not _valid_way(way, false):
		return {"error": "Bitte ein gültiges Gebäude auswählen."}
	var levels := OSMMap._floor_count(way.tags)
	if floor_number < 1 or floor_number > levels:
		return {"error": "Bitte eine gültige Etage auswählen."}
	var prepared := prepare_levels(way, levels)
	if prepared.has("error"):
		return prepared
	var target: Dictionary = {}
	var original: Dictionary = {}
	for merge in prepared.data.merges:
		if int(merge.result.id) == int(way.id):
			target = merge
			original = merge.result
			break
	if target.is_empty():
		for edit in prepared.data.level_edits:
			if int(edit.source.id) == int(way.id):
				target = edit
				original = edit.source
				break
	if target.is_empty():
		return {"error": "Die Etage konnte nicht zugeordnet werden."}
	for floor_edit in target.get("hollow_floors", []):
		if int(floor_edit.floor) != floor_number:
			continue
		var points := OSMMap._building_points(original, original.geometry[0])
		var footprint := BuildingWalls.floor_outline(points, floor_edit)
		if footprint.has("error"):
			return footprint
		var interior := OSMMap._building_interior(footprint.outline, float(floor_edit.wall_thickness))
		var walls: Array = floor_edit.get("walls", [])
		var current := BuildingWalls.build(interior, walls)
		if current.has("error"):
			return current
		var preview := []
		var first := maxi(segment_index, 0)
		if outside:
			var result := BuildingWalls.split_exterior(footprint.base, floor_edit.get("outer_splits", []), current.plans, float(floor_edit.wall_thickness), wall_index, segment_index)
			if result.has("error"):
				return result
			floor_edit["outer_splits"] = result.splits
			for index in result.edges.size():
				var edge: Dictionary = result.edges[index]
				if not edge.connector and int(edge.edge) == wall_index and int(edge.segment) >= first and int(edge.segment) < first + result.pieces:
					preview.append([result.outline[index], result.outline[(index + 1) % result.outline.size()]])
		else:
			var result := BuildingWalls.split_wall(interior, walls, wall_index, first)
			if result.has("error"):
				return result
			floor_edit["walls"] = result.walls
			var segments: Array = result.plans[wall_index].segments
			for index in range(first, first + int(result.pieces)):
				preview.append(segments[index])
		if preview.size() < 2:
			return {"error": "Die Wandteilung konnte nicht dargestellt werden."}
		prepared["preview"] = preview
		return prepared
	return {"error": "Bitte die Etage zuerst aushöhlen."}


static func load_wall_thickness() -> Dictionary:
	var path := DataPaths.path("config/building_editor.json")
	var source := path if FileAccess.file_exists(path) else DEFAULT_CONFIG
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return {"error": "Gebäudeeditor-Einstellungen konnten nicht gelesen werden: " + source}
	if file.get_length() > 4096:
		return {"error": "Gebäudeeditor-Einstellungen sind zu groß: " + source}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"error": "Gebäudeeditor-Einstellungen sind ungültig: " + source}
	var thickness: Variant = json.data.get("wall_thickness_m")
	if not (thickness is int or thickness is float) or not is_finite(float(thickness)) or float(thickness) <= 0.0 or float(thickness) > 1000.0:
		return {"error": "Wanddicke muss eine Zahl größer als 0 und höchstens 1000 Meter sein: " + source}
	if source != path:
		var code := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if code != OK:
			return {"error": "Konfigurationsordner konnte nicht angelegt werden (Fehler %d)." % code}
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"error": "Gebäudeeditor-Einstellungen konnten nicht angelegt werden: " + path}
		file.store_string(text)
		file.flush()
		code = file.get_error()
		file.close()
		if code != OK:
			return {"error": "Gebäudeeditor-Einstellungen konnten nicht gespeichert werden (Fehler %d)." % code}
	return {"thickness": float(thickness)}


func prepare(selected: Array) -> Dictionary:
	if selected.size() < 2:
		return {"error": "Bitte mindestens zwei Gebäude auswählen."}
	var sources := []
	var ids := {}
	var polygons: Array[PackedVector2Array] = []
	var origin: Array = selected[0].geometry[0]
	for way in selected:
		if not _valid_way(way):
			return {"error": "Ein ausgewählter Gebäudegrundriss ist ungültig."}
		if not way.get("_hollow_floors", []).is_empty():
			return {"error": "Gebäude mit bearbeiteten Etagen können noch nicht zusammengefasst werden."}
		var way_sources: Array = way.get("_edit_sources", [way])
		for source in way_sources:
			if ids.has(int(source.id)):
				return {"error": "Ein Gebäude wurde mehrfach ausgewählt."}
			ids[int(source.id)] = true
			var original: Dictionary = source.duplicate(true)
			original.erase("_edit_sources")
			sources.append(original)
		var polygon := PackedVector2Array()
		for coordinate in way.geometry:
			var point := OSMMap._project(coordinate, origin)
			if polygon.is_empty() or point.distance_to(polygon[-1]) > 0.01:
				polygon.append(point)
		if polygon.size() > 1 and polygon[0].distance_to(polygon[-1]) < 0.01:
			polygon.remove_at(polygon.size() - 1)
		if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty():
			return {"error": "Ein Gebäudegrundriss kann nicht verarbeitet werden."}
		polygons.append(polygon)
	for edit in level_edits:
		if ids.has(int(edit.source.id)) and not edit.get("hollow_floors", []).is_empty():
			return {"error": "Gebäude mit bearbeiteten Etagen können noch nicht zusammengefasst werden."}
	for old in merges:
		if old.get("hollow_floors", []).is_empty():
			continue
		for source in old.sources:
			if ids.has(int(source.id)):
				return {"error": "Gebäude mit bearbeiteten Etagen können noch nicht zusammengefasst werden."}
	while polygons.size() > 1:
		var combined := false
		for first in range(polygons.size()):
			for second in range(first + 1, polygons.size()):
				var union := Geometry2D.merge_polygons(polygons[first], polygons[second])
				if union.size() != 1 or Geometry2D.triangulate_polygon(union[0]).is_empty():
					continue
				polygons[first] = union[0]
				polygons.remove_at(second)
				combined = true
				break
			if combined:
				break
		if not combined:
			return {"error": "Die Grundrisse müssen zusammenhängen und dürfen keine Innenhöfe bilden."}
	var zone := Grid.zone_for_origin(origin)
	var northern := Grid.is_northern_hemisphere(origin)
	var projected := Grid.project(origin, zone, northern)
	var geometry := []
	for point in polygons[0]:
		geometry.append(Grid.unproject([projected[0] + point.x, projected[1] - point.y], zone, northern))
	geometry.append(geometry[0].duplicate())
	var merged: Dictionary = selected[0].duplicate(true)
	merged.erase("_edit_sources")
	merged.erase("_hollow_floors")
	merged.erase("nodes")
	merged.geometry = geometry
	var next := []
	for old in merges:
		var overlaps := false
		var all_selected := true
		for source in old.sources:
			if ids.has(int(source.id)):
				overlaps = true
			else:
				all_selected = false
		if overlaps and (not all_selected or blocked_merges.has(int(old.result.id))):
			return {"error": "Eine bestehende Zusammenfassung hat einen OSM-Konflikt und kann nicht verändert werden."}
		if not overlaps:
			next.append(old)
	next.append({"sources": sources, "result": merged})
	var remaining_levels := []
	for edit in level_edits:
		if not ids.has(int(edit.source.id)):
			remaining_levels.append(edit)
	return {"data": {"format": FORMAT, "merges": next, "level_edits": remaining_levels}}


func save(value: Dictionary) -> bool:
	error = ""
	var validator: Variant = get_script().new()
	if not validator.set_data(value):
		error = "Gebäudeänderungen sind ungültig und wurden nicht gespeichert."
		return false
	var text := JSON.stringify(value, "", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		error = "Die Gebäudeänderungen sind zu groß zum Speichern."
		return false
	var code := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if code != OK:
		error = "Ordner für Gebäudeänderungen konnte nicht erstellt werden (Fehler %d)." % code
		return false
	var temporary := path + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "Gebäudeänderungen konnten nicht gespeichert werden (Fehler %d)." % FileAccess.get_open_error()
		return false
	file.store_string(text)
	file.flush()
	code = file.get_error()
	file.close()
	if code == OK:
		code = DirAccess.rename_absolute(temporary, path)
	if code != OK:
		if FileAccess.file_exists(temporary):
			var cleanup := DirAccess.remove_absolute(temporary)
			if cleanup != OK:
				push_error("Temporäre Datei konnte nicht entfernt werden: " + temporary)
		error = "Gebäudeänderungen konnten nicht gespeichert werden (Fehler %d)." % code
		return false
	return set_data(value)
