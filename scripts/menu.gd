extends Control

signal resume_requested
signal return_to_menu_requested
signal save_requested
signal save_as_requested
signal quit_requested

const MainScene = preload("res://scenes/main.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const SaveStore = preload("res://scripts/save_store.gd")
const MAX_CLIENTS := 8
const DEFAULT_PORT := 7777

var in_game := false
var host_selection := false
var can_save := false

@onready var address: LineEdit = $Panel/Options/Address
@onready var port: LineEdit = $Panel/Options/Port
@onready var message: Label = $Panel/Options/Message


func _ready() -> void:
	$Panel/Options/Version.text = "Version " + ProjectSettings.get_setting("application/config/version")
	if in_game:
		$Backdrop.show()
		$Panel/Options/Resume.show()
		$Panel/Options/ReturnToMenu.show()
		$Panel/Options/SaveGame.visible = can_save
		$Panel/Options/SaveGameAs.visible = can_save
		for node_name in ["SinglePlayer", "LoadGame", "AddressLabel", "Address", "PortLabel", "Port", "Host", "Join"]:
			$Panel/Options.get_node(node_name).hide()
		$Panel/Options/Resume.grab_focus()
		return

	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		var server_port := DEFAULT_PORT
		var place_id := "thalhofen"
		for arg in args:
			if arg.begins_with("--port="):
				var port_text := arg.trim_prefix("--port=")
				if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
					push_error("Ungültiger Server-Port: " + port_text)
					get_tree().quit(1)
					return
				server_port = int(port_text)
			elif arg.begins_with("--place="):
				place_id = arg.trim_prefix("--place=")
		var place := PlaceStore.find_by_id(place_id)
		if place.is_empty():
			push_error("Gespeicherter Server-Ort nicht gefunden: " + place_id)
			get_tree().quit(1)
			return
		_start_server.call_deferred(server_port, true, place)


func _input(event: InputEvent) -> void:
	if in_game and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if $ChangelogPanel.visible:
			_on_changelog_back_pressed()
		else:
			resume_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_return_to_menu_pressed() -> void:
	return_to_menu_requested.emit()


func _on_quit_pressed() -> void:
	if in_game:
		quit_requested.emit()
	else:
		get_tree().quit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_save_as_pressed() -> void:
	save_as_requested.emit()


func _on_changelog_pressed() -> void:
	var file := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
	if file == null:
		message.text = "Änderungsprotokoll konnte nicht geöffnet werden."
		push_error("Änderungsprotokoll konnte nicht geöffnet werden.")
		return
	$ChangelogPanel/Layout/Content.text = file.get_as_text()
	$Panel.hide()
	$ChangelogPanel.show()
	$ChangelogPanel/Layout/Back.grab_focus()


func _on_changelog_back_pressed() -> void:
	$ChangelogPanel.hide()
	$Panel.show()
	$Panel/Options/Changelog.grab_focus()


func _on_single_pressed() -> void:
	_open_place_selection(false)


func _on_load_pressed() -> void:
	var selection_scene: PackedScene = load("res://scenes/save_selection.tscn")
	var selection := selection_scene.instantiate()
	selection.name = "SaveSelection"
	selection.save_chosen.connect(_on_save_chosen)
	selection.cancelled.connect(_on_save_selection_cancelled)
	$Panel.hide()
	add_child(selection)


func _on_save_selection_cancelled() -> void:
	$SaveSelection.queue_free()
	$Panel.show()


func _on_save_chosen(data: Dictionary) -> void:
	_open_game(false, false, data.place, data)


func _on_host_pressed() -> void:
	var selected_port := _selected_port()
	if selected_port > 0:
		_open_place_selection(true)


func _on_join_pressed() -> void:
	var selected_port := _selected_port()
	var host := address.text.strip_edges()
	if selected_port == 0:
		return
	if host.is_empty():
		message.text = "Bitte eine Serveradresse eingeben."
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, selected_port)
	if error != OK:
		message.text = "Verbindung konnte nicht gestartet werden (Fehler %d)." % error
		return
	multiplayer.multiplayer_peer = peer
	_open_game(true, false, {})


func _open_place_selection(for_host: bool) -> void:
	host_selection = for_host
	var selection_scene: PackedScene = load("res://scenes/place_selection.tscn")
	var selection := selection_scene.instantiate()
	selection.name = "PlaceSelection"
	selection.place_chosen.connect(_on_place_chosen)
	selection.cancelled.connect(_on_place_selection_cancelled)
	$Panel.hide()
	add_child(selection)


func _on_place_selection_cancelled() -> void:
	$PlaceSelection.queue_free()
	$Panel.show()


func _on_place_chosen(place: Dictionary) -> void:
	if host_selection:
		var selected_port := _selected_port()
		if selected_port > 0:
			_start_server(selected_port, false, place)
	else:
		_open_game(false, false, place)


func _selected_port() -> int:
	if not port.text.is_valid_int() or int(port.text) < 1 or int(port.text) > 65535:
		message.text = "Bitte einen Port zwischen 1 und 65535 eingeben."
		return 0
	return int(port.text)


func _start_server(server_port: int, is_dedicated: bool, place: Dictionary) -> void:
	var raw := JSON.stringify(place).to_utf8_buffer()
	if raw.size() > NetworkGame.MAX_PLACE_BYTES or raw.compress(FileAccess.COMPRESSION_GZIP).size() > NetworkGame.MAX_COMPRESSED_BYTES:
		var error_message := "Der Ort ist für die Multiplayer-Übertragung zu groß."
		if is_dedicated:
			push_error(error_message)
			get_tree().quit(1)
		else:
			message.text = error_message
			if has_node("PlaceSelection"):
				_on_place_selection_cancelled()
		return
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(server_port, MAX_CLIENTS)
	if error != OK:
		var error_message := "Server konnte nicht gestartet werden (Port %d, Fehler %d)." % [server_port, error]
		if is_dedicated:
			push_error(error_message)
			get_tree().quit(1)
		else:
			message.text = error_message
			if has_node("PlaceSelection"):
				_on_place_selection_cancelled()
		return
	multiplayer.multiplayer_peer = peer
	print("Server gestartet auf UDP-Port ", server_port)
	_open_game(true, is_dedicated, place)


func _open_game(networked: bool, is_dedicated: bool, place: Dictionary, save_data: Dictionary = {}) -> void:
	var world := MainScene.instantiate()
	var waiting_for_server := networked and not multiplayer.is_server()
	if not waiting_for_server and not OSMMap.populate(world, place):
		world.free()
		if networked:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		if is_dedicated:
			get_tree().quit(1)
		else:
			message.text = "Kartendaten oder Kartenfaktor sind ungültig. Details stehen in der Konsole."
			if has_node("PlaceSelection"):
				_on_place_selection_cancelled()
			elif has_node("SaveSelection"):
				$SaveSelection.info.text = message.text
		return
	if networked:
		world.set_script(NetworkGame)
		world.dedicated = is_dedicated
		world.place_data = place
		world.client_waiting_for_map = waiting_for_server
	else:
		world.save_id = save_data.get("id", "")
		if world.save_id.is_empty():
			world.save_id = SaveStore.new_id()
		if world.save_id.is_empty():
			world.free()
			message.text = "Ein Spielstand konnte nicht angelegt werden."
			if has_node("PlaceSelection"):
				_on_place_selection_cancelled()
			return
		world.restore_data = save_data
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not networked and save_data.is_empty():
		world.save_game()
	queue_free()
