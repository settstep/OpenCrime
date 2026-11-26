extends RefCounted

const DEFAULT_PATH := "user://logs/opencrime.log"
const ARCHIVE_SUFFIX := ".1"
const MAX_FILE_BYTES := 1048576

static var path := DEFAULT_PATH


static func info(category: String, message: String) -> void:
	_write("INFO", category, message)


static func warning(category: String, message: String) -> void:
	_write("WARN", category, message)


static func error(category: String, message: String) -> void:
	_write("ERROR", category, message)


static func _write(level: String, category: String, message: String) -> void:
	var directory := path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if directory_error != OK:
		push_error("Log-Verzeichnis konnte nicht erstellt werden (Fehler %d)." % directory_error)
		return

	var safe_category := category.replace("\r", " ").replace("\n", " ")
	var safe_message := message.replace("\r", " ").replace("\n", " ")
	var line := "%s [%s] [%s] %s" % [Time.get_datetime_string_from_system(), level, safe_category, safe_message]
	var line_size := line.to_utf8_buffer().size() + 1
	var archive_path := path + ARCHIVE_SUFFIX
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing == null:
			push_error("Logdatei konnte nicht geprüft werden (Fehler %d)." % FileAccess.get_open_error())
			return
		var rotate := existing.get_length() + line_size > MAX_FILE_BYTES
		existing.close()
		if rotate:
			var absolute_path := ProjectSettings.globalize_path(path)
			var absolute_archive_path := ProjectSettings.globalize_path(archive_path)
			if FileAccess.file_exists(archive_path):
				var remove_error := DirAccess.remove_absolute(absolute_archive_path)
				if remove_error != OK:
					push_error("Alte Logdatei konnte nicht rotiert werden (Fehler %d)." % remove_error)
					return
			var rename_error := DirAccess.rename_absolute(absolute_path, absolute_archive_path)
			if rename_error != OK:
				push_error("Logdatei konnte nicht rotiert werden (Fehler %d)." % rename_error)
				return

	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file == null:
		push_error("Logdatei konnte nicht geöffnet werden (Fehler %d)." % FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(line)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_error("Logdatei konnte nicht geschrieben werden (Fehler %d)." % write_error)
