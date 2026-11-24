extends Control

signal save_chosen(data: Dictionary)
signal cancelled

const SaveStore = preload("res://scripts/save_store.gd")
const OSMMap = preload("res://scripts/osm_map.gd")

@onready var list: ItemList = $Margin/Layout/Saves
@onready var info: Label = $Margin/Layout/Info
@onready var confirmation: ConfirmationDialog = $Confirmation

var slots: Array[Dictionary] = []


func _ready() -> void:
	_refresh()


func _refresh() -> void:
	list.clear()
	var result := SaveStore.list_slots()
	slots = result.slots
	if result.error != OK:
		info.text = "Spielstände konnten nicht gelesen werden (Fehler %d)." % result.error
		return
	if slots.is_empty():
		info.text = "Noch keine Spielstände vorhanden."
		return
	for slot in slots:
		if slot.error == OK:
			list.add_item("%s – begonnen %s – gespeichert %s [%s]" % [slot.data.place.name, slot.data.created_at, slot.data.saved_at, slot.id.substr(0, 8)])
		else:
			list.add_item("Ungültiger Spielstand (%s, Fehler %d)" % [slot.id, slot.error])
	list.select(0)
	info.text = "Spielstand auswählen. Gespeicherte Ortsdaten werden ohne Download geladen."


func _selected_id() -> String:
	var selected := list.get_selected_items()
	if selected.is_empty():
		info.text = "Bitte einen Spielstand auswählen."
		return ""
	return slots[selected[0]].id


func _on_load_pressed() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	var result := SaveStore.read_slot(id)
	if result.error != OK:
		info.text = "Spielstand konnte nicht gelesen werden (Fehler %d)." % result.error
		return
	var setting: Variant = ProjectSettings.get_setting(OSMMap.SCALE_SETTING)
	if (typeof(setting) != TYPE_INT and typeof(setting) != TYPE_FLOAT) or not is_finite(float(setting)) or float(setting) != float(result.data.scale):
		info.text = "Kartenfaktor stimmt nicht: Spielstand %s, aktuell %s. Bitte den ursprünglichen Faktor einstellen." % [result.data.scale, setting]
		return
	save_chosen.emit(result.data)


func _on_delete_pressed() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	confirmation.set_meta("save_id", id)
	confirmation.dialog_text = "Diesen Spielstand dauerhaft löschen?"
	confirmation.popup_centered()


func _on_delete_confirmed() -> void:
	var error := SaveStore.delete_slot(confirmation.get_meta("save_id"))
	if error != OK:
		info.text = "Spielstand konnte nicht gelöscht werden (Fehler %d)." % error
		return
	_refresh()


func _on_cancel_pressed() -> void:
	cancelled.emit()
