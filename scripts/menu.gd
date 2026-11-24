extends Control

signal resume_requested
signal return_to_menu_requested

const MainScene = preload("res://scenes/main.tscn")
const NetworkGame = preload("res://scripts/network_game.gd")
const OSMMap = preload("res://scripts/osm_map.gd")
const MAX_CLIENTS := 8
const DEFAULT_PORT := 7777

var in_game := false

@onready var address: LineEdit = $Panel/Options/Address
@onready var port: LineEdit = $Panel/Options/Port
@onready var message: Label = $Panel/Options/Message


func _ready() -> void:
	$Panel/Options/Version.text = "Version " + ProjectSettings.get_setting("application/config/version")
	if in_game:
		$Backdrop.show()
		$Panel/Options/Resume.show()
		$Panel/Options/ReturnToMenu.show()
		for node_name in ["SinglePlayer", "AddressLabel", "Address", "PortLabel", "Port", "Host", "Join"]:
			$Panel/Options.get_node(node_name).hide()
		$Panel/Options/Resume.grab_focus()
		return

	var args := OS.get_cmdline_user_args()
	if args.has("--server"):
		var server_port := DEFAULT_PORT
		for arg in args:
			if arg.begins_with("--port="):
				var port_text := arg.trim_prefix("--port=")
				if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535:
					push_error("Ungültiger Server-Port: " + port_text)
					get_tree().quit(1)
					return
				server_port = int(port_text)
		_start_server.call_deferred(server_port, true)


func _input(event: InputEvent) -> void:
	if in_game and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_return_to_menu_pressed() -> void:
	return_to_menu_requested.emit()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_single_pressed() -> void:
	_open_game(false, false)


func _on_host_pressed() -> void:
	var selected_port := _selected_port()
	if selected_port > 0:
		_start_server(selected_port, false)


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
	_open_game(true, false)


func _selected_port() -> int:
	if not port.text.is_valid_int() or int(port.text) < 1 or int(port.text) > 65535:
		message.text = "Bitte einen Port zwischen 1 und 65535 eingeben."
		return 0
	return int(port.text)


func _start_server(server_port: int, is_dedicated: bool) -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(server_port, MAX_CLIENTS)
	if error != OK:
		var error_message := "Server konnte nicht gestartet werden (Port %d, Fehler %d)." % [server_port, error]
		if is_dedicated:
			push_error(error_message)
			get_tree().quit(1)
		else:
			message.text = error_message
		return
	multiplayer.multiplayer_peer = peer
	print("Server gestartet auf UDP-Port ", server_port)
	_open_game(true, is_dedicated)


func _open_game(networked: bool, is_dedicated: bool) -> void:
	var world := MainScene.instantiate()
	if not OSMMap.populate(world):
		world.free()
		if networked:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		if is_dedicated:
			get_tree().quit(1)
		else:
			message.text = "Kartendaten konnten nicht geladen werden. Details stehen in der Konsole."
		return
	if networked:
		world.set_script(NetworkGame)
		world.dedicated = is_dedicated
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	queue_free()
