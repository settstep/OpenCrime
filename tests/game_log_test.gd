extends SceneTree

const GameLog = preload("res://scripts/game_log.gd")

var original_path := ""
var test_path := ""


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	original_path = GameLog.path
	test_path = "user://game_log_test_%d.log" % Time.get_ticks_usec()
	GameLog.path = test_path
	GameLog.info("test", "first line")
	GameLog.error("test", "second line\nwith another line")
	var file := FileAccess.open(test_path, FileAccess.READ)
	if file == null:
		_fail("The game log file was not created.")
		return
	var contents := file.get_as_text()
	file.close()
	GameLog.path = original_path
	if not contents.contains("[INFO] [test] first line") or not contents.contains("[ERROR] [test] second line with another line"):
		_fail("The game log did not append timestamped, single-line entries.")
		return
	var seed_file := FileAccess.open(test_path, FileAccess.WRITE)
	if seed_file == null:
		_fail("A large test log could not be created.")
		return
	seed_file.store_string("x".repeat(GameLog.MAX_FILE_BYTES - 20))
	seed_file.close()
	GameLog.path = test_path
	GameLog.info("test", "rotate")
	GameLog.path = original_path
	var archive_path := test_path + GameLog.ARCHIVE_SUFFIX
	var archived := FileAccess.open(archive_path, FileAccess.READ)
	if archived == null or archived.get_length() != GameLog.MAX_FILE_BYTES - 20:
		_fail("The log did not rotate before the next entry exceeded 1 MiB.")
		return
	archived.close()
	var current := FileAccess.open(test_path, FileAccess.READ)
	if current == null or not current.get_as_text().contains("[INFO] [test] rotate"):
		_fail("The rotated log did not contain the new entry.")
		return
	current.close()
	for temporary_path in [test_path, archive_path]:
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		if remove_error != OK:
			_fail("A temporary game log file could not be removed.")
			return
	print("Game log append and line sanitization passed")
	quit(0)


func _fail(reason: String) -> void:
	GameLog.path = original_path
	for temporary_path in [test_path, test_path + GameLog.ARCHIVE_SUFFIX]:
		if not temporary_path.is_empty() and FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	push_error(reason)
	quit(1)
