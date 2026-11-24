extends RefCounted

const DEFAULT_CONFIG := "res://data/first_aid.json"
const INTERACTION_RADIUS := 2.5

static var config_path := "user://first_aid.json"


static func setup(candidates: Array[Dictionary], start: Vector2) -> Dictionary:
	var path := config_path
	var source := path if FileAccess.file_exists(path) else DEFAULT_CONFIG
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return _error("Erste-Hilfe-Einstellungen konnten nicht gelesen werden: " + source)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return _error("Erste-Hilfe-Einstellungen sind ungültig: " + source)
	var config: Dictionary = json.data
	if not config.has_all(["price", "healing"]) or not _integer_in_range(config.price, 1, 1000000000) or not _integer_in_range(config.healing, 1, 100):
		return _error("Erste-Hilfe-Einstellungen benötigen einen Preis ab 1 und Heilung von 1 bis 100: " + source)
	if source != path:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return _error("Erste-Hilfe-Einstellungen konnten nicht angelegt werden: " + path)
		file.store_string(text)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK:
			return _error("Erste-Hilfe-Einstellungen konnten nicht gespeichert werden: " + path)
	if candidates.is_empty():
		return _error("Für die Erste-Hilfe-Station wurde kein geeigneter Ort gefunden.")
	var nearest: Vector2 = candidates[0].point
	for candidate in candidates:
		var point: Vector2 = candidate.point
		if point.distance_squared_to(start) < nearest.distance_squared_to(start):
			nearest = point
	return {"point": nearest, "price": int(config.price), "healing": int(config.healing)}


static func valid_state(state: Dictionary) -> bool:
	if state.has("error"):
		return state.error is String and not state.error.is_empty()
	return state.has_all(["point", "price", "healing"]) and state.point is Vector2 and state.point.is_finite() and _integer_in_range(state.price, 1, 1000000000) and _integer_in_range(state.healing, 1, 100)


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


static func _error(message: String) -> Dictionary:
	push_error(message)
	return {"error": message}
