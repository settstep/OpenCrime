extends RefCounted

const DataPaths = preload("res://scripts/data_paths.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const FORMAT := 1
const MAX_BYTES := 3 * 1024 * 1024

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
			_set_levels(merge.result, levels)
			return {"data": next}
	var original: Dictionary = way.duplicate(true)
	if way.has("_edit_sources"):
		if not way._edit_sources is Array or way._edit_sources.size() != 1 or not _valid_way(way._edit_sources[0], false) or int(way._edit_sources[0].id) != id:
			return {"error": "Die ursprünglichen OSM-Daten des Gebäudes sind ungültig."}
		original = way._edit_sources[0].duplicate(true)
	original.erase("_edit_sources")
	var retained := []
	for edit in next.level_edits:
		if int(edit.source.id) != id:
			retained.append(edit)
	retained.append({"source": original, "levels": levels})
	next.level_edits = retained
	return {"data": next}


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
