extends RefCounted

const PlaceStore = preload("res://scripts/place_store.gd")
const Missions = preload("res://scripts/missions.gd")
const PlayerScript = preload("res://scripts/player.gd")
const DataPaths = preload("res://scripts/data_paths.gd")
const FORMAT_VERSION := 2
const MAX_FILE_BYTES := 16 * 1024 * 1024
const LEGACY_GRID_SIZE := 45
const MAX_EXPLORED_CELLS := 250000
const MAX_VEHICLES := 64

static var directory := DataPaths.path("saves")


static func _valid_id(id: String) -> bool:
	return id.length() == 32 and id.is_valid_hex_number(false) and id == id.to_lower()


static func _path(id: String) -> String:
	return directory.path_join(id + ".json")


static func new_id() -> String:
	var crypto := Crypto.new()
	for attempt in range(4):
		var id := crypto.generate_random_bytes(16).hex_encode()
		if _valid_id(id) and not FileAccess.file_exists(_path(id)):
			return id
	push_error("Ein eindeutiger Spielstand konnte nicht angelegt werden.")
	return ""


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for number in value:
		if not _number(number) or absf(float(number)) > 1000000.0:
			return false
	return true


static func is_valid(data: Dictionary) -> bool:
	if not data.has_all(["format", "id", "created_at", "saved_at", "place", "scale", "player_position", "car_position", "car_rotation", "in_car", "explored"]):
		return false
	if not _integer(data.format):
		return false
	var format := int(data.format)
	if format not in [1, FORMAT_VERSION] or not data.id is String or not _valid_id(data.id):
		return false
	if not data.created_at is String or data.created_at.is_empty() or not data.saved_at is String or data.saved_at.is_empty():
		return false
	if not data.place is Dictionary or not PlaceStore.is_valid(data.place):
		return false
	if not _number(data.scale) or float(data.scale) <= 0.0:
		return false
	if not _vector(data.player_position) or not _vector(data.car_position) or not _number(data.car_rotation) or not data.in_car is bool:
		return false
	if data.has("health") and (not _number(data.health) or float(data.health) != floorf(float(data.health)) or data.health < 0 or data.health > PlayerScript.MAX_HEALTH or (data.health == 0 and data.in_car)):
		return false
	if data.has("inventory"):
		var inventory: Variant = data.inventory
		if not inventory is Dictionary or not inventory.has_all(["medkits", "pickup_available", "pickup_position"]) or not _number(inventory.medkits) or float(inventory.medkits) != floorf(float(inventory.medkits)) or inventory.medkits < 0 or inventory.medkits > PlayerScript.MAX_MEDKITS or not inventory.pickup_available is bool or not inventory.pickup_position is Array or inventory.pickup_position.size() != 2:
			return false
		for coordinate in inventory.pickup_position:
			if not _number(coordinate) or absf(float(coordinate)) > 1000000.0:
				return false
	if data.has("vehicles") != data.has("active_vehicle"):
		return false
	if data.has("vehicles"):
		if not data.vehicles is Array or data.vehicles.is_empty() or data.vehicles.size() > MAX_VEHICLES:
			return false
		for vehicle in data.vehicles:
			if not vehicle is Dictionary or not vehicle.has_all(["position", "rotation"]) or not _vector(vehicle.position) or not _number(vehicle.rotation):
				return false
		if data.vehicles[0].position != data.car_position or data.vehicles[0].rotation != data.car_rotation:
			return false
		if not _number(data.active_vehicle) or float(data.active_vehicle) != floorf(float(data.active_vehicle)):
			return false
		var active := int(data.active_vehicle)
		if (data.in_car and (active < 0 or active >= data.vehicles.size())) or (not data.in_car and active != -1):
			return false
	if not data.explored is Array or data.explored.size() > MAX_EXPLORED_CELLS or (format == 1 and data.explored.size() > LEGACY_GRID_SIZE * LEGACY_GRID_SIZE):
		return false
	for cell in data.explored:
		if not cell is Array or cell.size() != 2:
			return false
		for value in cell:
			if not _number(value) or float(value) != floorf(float(value)):
				return false
			if format == 1 and (float(value) < 0.0 or float(value) >= LEGACY_GRID_SIZE):
				return false
			if format == FORMAT_VERSION and absf(float(value)) > 100000.0:
				return false
	if data.has("mission") and (not data.mission is Dictionary or not Missions.valid_save(data.mission)):
		return false
	return true


static func read_slot(id: String) -> Dictionary:
	if not _valid_id(id):
		return {"error": ERR_INVALID_PARAMETER}
	var file := FileAccess.open(_path(id), FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error()}
	if file.get_length() > MAX_FILE_BYTES:
		return {"error": ERR_INVALID_DATA}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"error": ERR_INVALID_DATA}
	var data: Dictionary = json.data
	if _integer(data.get("format")) and int(data.format) == 1:
		if not is_valid(data):
			return {"error": ERR_INVALID_DATA}
		data = _migrate_format_one(data)
	if not is_valid(data) or data.id != id:
		return {"error": ERR_INVALID_DATA}
	return {"error": OK, "data": data}


static func _migrate_format_one(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	migrated.format = FORMAT_VERSION
	var explored: Array = []
	for cell in data.explored:
		explored.append([int(cell[0]) - 23, int(cell[1]) - 23])
	migrated.explored = explored
	return migrated


static func list_slots() -> Dictionary:
	var slots: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		if FileAccess.file_exists(directory):
			return {"error": ERR_CANT_OPEN, "slots": slots}
		return {"error": OK, "slots": slots}
	var dir := DirAccess.open(directory)
	if dir == null:
		return {"error": DirAccess.get_open_error(), "slots": slots}
	for filename in dir.get_files():
		if not filename.ends_with(".json"):
			continue
		var id := filename.trim_suffix(".json")
		if not _valid_id(id):
			continue
		var result := read_slot(id)
		var metadata := {}
		if result.error == OK:
			metadata = {"place": {"name": result.data.place.name}, "created_at": result.data.created_at, "saved_at": result.data.saved_at}
		slots.append({"id": id, "error": result.error, "data": metadata, "modified": FileAccess.get_modified_time(_path(id))})
	slots.sort_custom(func(a: Dictionary, b: Dictionary): return a.modified > b.modified)
	return {"error": OK, "slots": slots}


static func write_slot(data: Dictionary) -> Error:
	if not is_valid(data) or int(data.format) != FORMAT_VERSION:
		return ERR_INVALID_DATA
	var json := JSON.stringify(data)
	if json.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return ERR_INVALID_DATA
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return error
	var temporary := directory.path_join(data.id + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(json)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(_path(data.id)))
	if error != OK and FileAccess.file_exists(temporary):
		var cleanup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if cleanup_error != OK:
			push_error("Temporäre Spielstandsdatei konnte nicht entfernt werden: " + temporary)
	return error


static func delete_slot(id: String) -> Error:
	if not _valid_id(id):
		return ERR_INVALID_PARAMETER
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(id)))
