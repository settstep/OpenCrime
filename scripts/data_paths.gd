extends RefCounted

const DATA_DIRECTORY_NAME := "OpenCrimeData"
const LEGACY_DIRECTORY_PAIRS := [
	["user://saves", "saves"],
	["user://places", "places"],
	["user://tile_cache", "tile_cache"],
	["user://logs", "logs"],
]

static var root_override := ""
static var _resolved_root := ""
static var _migration_complete := false


static func root() -> String:
	if not root_override.is_empty():
		return ProjectSettings.globalize_path(root_override)
	if not _resolved_root.is_empty():
		return _resolved_root

	var project_run := OS.has_feature("editor") or OS.get_cmdline_args().has("--path")
	var project_root := ProjectSettings.globalize_path("res://").path_join(DATA_DIRECTORY_NAME)
	var executable_root := OS.get_executable_path().get_base_dir().path_join(DATA_DIRECTORY_NAME)
	var preferred_root := project_root if project_run else executable_root
	var directory_error := DirAccess.make_dir_recursive_absolute(preferred_root)
	if directory_error == OK:
		_resolved_root = preferred_root
		return _resolved_root

	var alternate_root := executable_root if project_run else project_root
	directory_error = DirAccess.make_dir_recursive_absolute(alternate_root)
	if directory_error == OK:
		push_warning("Spieleordner ist nicht beschreibbar; Datenspeicherung erfolgt unter: " + alternate_root)
		_resolved_root = alternate_root
		return _resolved_root

	var fallback_root := ProjectSettings.globalize_path("user://OpenCrimeData")
	directory_error = DirAccess.make_dir_recursive_absolute(fallback_root)
	if directory_error == OK:
		push_warning("Spieleordner ist nicht beschreibbar; Datenspeicherung erfolgt im Godot-Benutzerordner: " + fallback_root)
		_resolved_root = fallback_root
		return _resolved_root

	push_error("Kein beschreibbarer OpenCrimeData-Ordner konnte erstellt werden (Fehler %d)." % directory_error)
	_resolved_root = fallback_root
	return _resolved_root


static func path(relative_path: String) -> String:
	return root().path_join(relative_path)


static func migrate_legacy_data() -> Error:
	if _migration_complete:
		return OK
	for pair in LEGACY_DIRECTORY_PAIRS:
		var error := _copy_directory(pair[0], path(pair[1]))
		if error != OK:
			return error
	var old_config := "user://first_aid.json"
	var new_config := path("config/first_aid.json")
	if FileAccess.file_exists(old_config) and not FileAccess.file_exists(new_config):
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(new_config.get_base_dir()))
		if directory_error != OK:
			push_error("Konfigurationsordner konnte nicht migriert werden (Fehler %d)." % directory_error)
			return directory_error
		var copy_error := _copy_file(old_config, new_config)
		if copy_error != OK:
			return copy_error
	_migration_complete = true
	return OK


static func _copy_directory(source: String, destination: String) -> Error:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(source)):
		return OK
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	if error != OK:
		push_error("Datenordner konnte nicht migriert werden: " + destination)
		return error
	var source_directory := DirAccess.open(source)
	if source_directory == null:
		error = DirAccess.get_open_error()
		push_error("Bisheriger Datenordner konnte nicht gelesen werden: " + source)
		return error
	for filename in source_directory.get_files():
		var copy_error := _copy_file(source.path_join(filename), destination.path_join(filename))
		if copy_error != OK:
			return copy_error
	for directory_name in source_directory.get_directories():
		var copy_error := _copy_directory(source.path_join(directory_name), destination.path_join(directory_name))
		if copy_error != OK:
			return copy_error
	return OK


static func _copy_file(source: String, destination: String) -> Error:
	if FileAccess.file_exists(destination):
		return OK
	var source_file := FileAccess.open(source, FileAccess.READ)
	if source_file == null:
		var error := FileAccess.get_open_error()
		push_error("Bisherige Datendatei konnte nicht gelesen werden: " + source)
		return error
	var expected_size := source_file.get_length()
	var contents := source_file.get_buffer(expected_size)
	source_file.close()
	if contents.size() != expected_size:
		push_error("Bisherige Datendatei konnte nicht vollständig gelesen werden: " + source)
		return ERR_FILE_EOF
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	if directory_error != OK:
		push_error("Zielordner konnte nicht erstellt werden: " + destination.get_base_dir())
		return directory_error
	var temporary := destination + "." + Crypto.new().generate_random_bytes(8).hex_encode() + ".tmp"
	var destination_file := FileAccess.open(temporary, FileAccess.WRITE)
	if destination_file == null:
		var error := FileAccess.get_open_error()
		push_error("Bisherige Datendatei konnte nicht kopiert werden: " + destination)
		return error
	destination_file.store_buffer(contents)
	destination_file.flush()
	var error := destination_file.get_error()
	destination_file.close()
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
	if error != OK and FileAccess.file_exists(temporary):
		var cleanup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if cleanup_error != OK:
			push_error("Temporäre Migrationsdatei konnte nicht entfernt werden: " + temporary)
	if error != OK:
		push_error("Bisherige Datendatei konnte nicht kopiert werden: " + destination)
	return error
