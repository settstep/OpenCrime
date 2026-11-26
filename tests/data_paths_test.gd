extends SceneTree

const DataPaths = preload("res://scripts/data_paths.gd")

var source_directory := ""
var destination_directory := ""


func _initialize() -> void:
	call_deferred("_test")


func _test() -> void:
	var root := DataPaths.root()
	if not root.ends_with(DataPaths.DATA_DIRECTORY_NAME):
		_fail("The portable data root has an unexpected name.")
		return
	if OS.get_cmdline_args().has("--path") and not root.begins_with(ProjectSettings.globalize_path("res://")):
		_fail("A project run did not use a data folder inside the project.")
		return

	var suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	source_directory = "user://data_paths_test_" + suffix + "/legacy"
	destination_directory = "user://data_paths_test_" + suffix + "/portable"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_directory)) != OK:
		_fail("A temporary source folder could not be created.")
		return
	var source_path := source_directory.path_join("save.json")
	var source_file := FileAccess.open(source_path, FileAccess.WRITE)
	if source_file == null:
		_fail("A temporary legacy file could not be created.")
		return
	source_file.store_string("legacy")
	source_file.close()
	if DataPaths._copy_directory(source_directory, destination_directory) != OK:
		_fail("Legacy files could not be copied to the portable folder.")
		return
	var destination_path := destination_directory.path_join("save.json")
	var copied := FileAccess.get_file_as_string(destination_path)
	if copied != "legacy":
		_fail("The copied file did not preserve its contents.")
		return
	source_file = FileAccess.open(source_path, FileAccess.WRITE)
	source_file.store_string("changed")
	source_file.close()
	if DataPaths._copy_directory(source_directory, destination_directory) != OK or FileAccess.get_file_as_string(destination_path) != "legacy":
		_fail("Existing portable files were overwritten during migration.")
		return
	_cleanup()
	print("Portable data location and non-destructive migration passed")
	quit(0)


func _cleanup() -> void:
	for path in [destination_directory.path_join("save.json"), source_directory.path_join("save.json")]:
		if FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if error != OK:
				push_error("A temporary migration test file could not be removed: " + path)
	for path in [destination_directory, source_directory]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if error != OK:
				push_error("A temporary migration test folder could not be removed: " + path)
	var parent := source_directory.get_base_dir()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(parent))


func _fail(reason: String) -> void:
	_cleanup()
	push_error(reason)
	quit(1)
