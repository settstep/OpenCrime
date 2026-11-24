extends Control

signal accept_requested(id: String)
signal defer_requested(id: String)
signal invite_requested(peer_id: int)
signal close_requested

@onready var summary: Label = $Summary
@onready var notice: Label = $Notice
@onready var panel: PanelContainer = $Panel
@onready var list: ItemList = $Panel/Layout/Offers
@onready var details: Label = $Panel/Layout/DetailsScroll/Details
@onready var peers: OptionButton = $Panel/Layout/Invite/Peers
@onready var message: Label = $Panel/Layout/Message

var state := {}
var local_id := 1


func _ready() -> void:
	$Panel/Layout/Buttons/Accept.pressed.connect(_accept)
	$Panel/Layout/Buttons/Defer.pressed.connect(_defer)
	$Panel/Layout/Invite/Send.pressed.connect(_invite)
	$Panel/Layout/Close.pressed.connect(func(): close_requested.emit())
	list.item_selected.connect(func(_index: int): _show_details())


func _input(event: InputEvent) -> void:
	if panel.visible and (event.is_action_pressed("show_missions") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_requested.emit()


func update_state(value: Dictionary, peer_id: int) -> void:
	state = value
	local_id = peer_id
	_refresh()


func show_error(text: String) -> void:
	message.text = text
	notice.text = text


func _refresh() -> void:
	if state.is_empty():
		return
	var player: Dictionary = state.player
	var active: String = player.active
	summary.text = "Geld: %d $  |  SMS/Aufträge: J" % int(player.money)
	if not active.is_empty() and state.missions.has(active):
		var mission: Dictionary = state.missions[active]
		summary.text += "\n%s: %s" % [mission.title, "Paket abholen" if mission.stage == 0 else "Paket abgeben"]
	if not player.offers.is_empty():
		summary.text += "\nNeue SMS erhalten."
	var selected := _selected_id()
	list.clear()
	for id in player.offers + player.deferred:
		if not state.missions.has(id):
			continue
		var mission: Dictionary = state.missions[id]
		var label: String = "SMS" if player.offers.has(id) else "Zurückgestellt"
		if mission.owner != local_id:
			label += " / Einladung"
		var category := "Hauptauftrag" if mission.type == "story" else "Wiederkehrend"
		list.add_item("%s / %s: %s" % [label, category, mission.title])
		list.set_item_metadata(list.item_count - 1, id)
		if id == selected:
			list.select(list.item_count - 1)
	if list.get_selected_items().is_empty() and list.item_count > 0:
		list.select(0)
	peers.clear()
	for id in state.peers:
		if int(id) != local_id:
			peers.add_item("Spieler %s" % id, int(id))
	_show_details()


func _selected_id() -> String:
	var selected := list.get_selected_items()
	return str(list.get_item_metadata(selected[0])) if not selected.is_empty() else ""


func _show_details() -> void:
	if state.is_empty():
		return
	var player: Dictionary = state.player
	var lines: Array[String] = []
	if not player.active.is_empty() and state.missions.has(player.active):
		var active: Dictionary = state.missions[player.active]
		var category := "Hauptauftrag" if active.type == "story" else "Wiederkehrender Auftrag"
		lines.append("Aktiv (%s): %s" % [category, active.title])
		lines.append("%s Abholen: %s" % ["✓" if active.stage == 1 else "□", active.pickup_label])
		lines.append("□ Abgeben: " + active.destination_label)
		lines.append("Belohnung: %d $ (bei Teamarbeit geteilt)" % int(active.reward))
	var id := _selected_id()
	if not id.is_empty() and state.missions.has(id):
		var offer: Dictionary = state.missions[id]
		var category := "Hauptauftrag" if offer.type == "story" else "Wiederkehrender Auftrag"
		lines.append("\n%s: %s\n%s\nAbholung: %s\nZiel: %s\nBelohnung: %d $" % [category, offer.title, offer.sms, offer.pickup_label, offer.destination_label, int(offer.reward)])
	if lines.is_empty():
		lines.append("Keine Aufträge vorhanden.")
	details.text = "\n".join(lines)


func _accept() -> void:
	var id := _selected_id()
	if id.is_empty():
		message.text = "Bitte eine SMS auswählen."
	else:
		message.text = ""
		accept_requested.emit(id)


func _defer() -> void:
	var id := _selected_id()
	if id.is_empty():
		message.text = "Bitte eine SMS auswählen."
	else:
		message.text = ""
		defer_requested.emit(id)


func _invite() -> void:
	if peers.item_count == 0:
		message.text = "Kein Mitspieler verfügbar."
		return
	message.text = ""
	invite_requested.emit(peers.get_selected_id())
