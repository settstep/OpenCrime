extends Control

signal place_chosen(place: Dictionary)
signal cancelled

const PlaceStore = preload("res://scripts/place_store.gd")
const Grid = preload("res://scripts/map_block_grid.gd")
const USER_AGENT := "OpenCrime/0.27.0 (+https://github.com/settstep/OpenCrime)"
const PLACE_EXTENT_METERS := 165.0
const MAX_RESPONSE_BYTES := 8 * 1024 * 1024

@onready var map = $Margin/Layout/Map
@onready var list: ItemList = $Margin/Layout/Bottom/Saved/Places
@onready var name_field: LineEdit = $Margin/Layout/Bottom/Details/Name
@onready var info: Label = $Margin/Layout/Bottom/Details/Info
@onready var start_button: Button = $Margin/Layout/Bottom/Details/Start
@onready var refresh_button: Button = $Margin/Layout/Bottom/Details/Refresh

var places: Array[Dictionary] = []
var selected_place: Dictionary = {}
var selected_latitude := 47.7748417
var selected_longitude := 10.6034933
var request: HTTPRequest
var pending_block := Vector2i.ZERO
var pending_block_id := ""
var pending_bounds: Array = []
var pending_place_bounds: Array = []
var pending_refresh_only := false


func _ready() -> void:
	places = PlaceStore.available_places()
	if places.is_empty():
		info.text = "Keine gespeicherten Orte verfügbar. Wähle einen Punkt auf der Karte."
	else:
		for place in places:
			list.add_item(place.name)
		list.select(0)
		_select_saved(0)
	map.point_selected.connect(_on_map_selected)
	map.map_error.connect(_on_map_error)
	map.set_places(places)
	request = HTTPRequest.new()
	request.timeout = 90.0
	request.body_size_limit = MAX_RESPONSE_BYTES
	add_child(request)
	request.request_completed.connect(_on_download_completed)


func _select_saved(index: int) -> void:
	if index < 0 or index >= places.size():
		return
	selected_place = places[index]
	selected_latitude = float(selected_place.origin[0])
	selected_longitude = float(selected_place.origin[1])
	name_field.text = selected_place.name
	name_field.editable = false
	name_field.placeholder_text = "Name des Ortes"
	refresh_button.visible = true
	info.text = "Gespeicherter Ort – vorhandene Startdaten werden genutzt; fehlende 1-km-Blöcke lädt das Spiel nach dem Start."
	start_button.text = "Ort starten"
	map.select_place(selected_place)


func _on_map_selected(latitude: float, longitude: float) -> void:
	selected_latitude = latitude
	selected_longitude = longitude
	var origin := [latitude, longitude]
	var cached_block := PlaceStore.read_block_cache(Grid.block_at_origin(origin), origin)
	if not cached_block.is_empty():
		selected_place = {}
		list.deselect_all()
		name_field.clear()
		name_field.editable = false
		name_field.placeholder_text = "Für einen Cache-Start wird kein Ort gespeichert."
		refresh_button.visible = true
		if PlaceStore.block_needs_refresh(cached_block):
			info.text = "Gecachter 1 × 1 km-UTM-Block; Verkehrs- und Notfallobjekte fehlen noch. Der Block kann manuell aktualisiert werden."
		else:
			info.text = "Gecachter 1 × 1 km-UTM-Block. Start nahe dem angeklickten Punkt; ein erneuter Download ist manuell möglich."
		start_button.text = "Hier starten"
		return
	selected_place = PlaceStore.find_containing(places, latitude, longitude)
	if not selected_place.is_empty():
		var index := places.find(selected_place)
		list.select(index)
		name_field.text = selected_place.name
		name_field.editable = false
		name_field.placeholder_text = "Name des Ortes"
		refresh_button.visible = true
		info.text = "Gespeicherter Ausschnitt: %s. Vorhandene Startdaten werden genutzt; fehlende 1-km-Blöcke lädt das Spiel nach dem Start." % selected_place.name
		start_button.text = "Ort starten"
	else:
		list.deselect_all()
		name_field.editable = true
		name_field.placeholder_text = "Name des Ortes"
		name_field.text = "Ort %.5f, %.5f" % [latitude, longitude]
		refresh_button.hide()
		info.text = "Neuer 1 × 1 km-UTM-Block; wird aus dem Cache geladen oder vor Spielstart heruntergeladen."
		start_button.text = "Ort laden und starten"


func _on_map_error(message: String) -> void:
	info.text = message + " Gespeicherte Orte können trotzdem gestartet werden."


func _on_start_pressed() -> void:
	if not selected_place.is_empty():
		place_chosen.emit(selected_place)
		return
	if not _prepare_pending_block():
		return
	var selected_origin := [selected_latitude, selected_longitude]
	var cached_block := PlaceStore.read_block_cache(pending_block, selected_origin)
	if not cached_block.is_empty():
		var start_name := "Startpunkt %.5f, %.5f" % [selected_latitude, selected_longitude]
		var cached_place := PlaceStore.from_cached_block(cached_block, selected_latitude, selected_longitude, pending_place_bounds, start_name)
		if cached_place.is_empty():
			info.text = "Im gespeicherten 1-km-Block wurde kein sicherer Startpunkt nahe einer Straße gefunden."
			return
		_finish_place(cached_place, false)
		return
	var name := name_field.text.strip_edges()
	if name.is_empty():
		info.text = "Bitte einen Namen für den Ort eingeben."
		return
	pending_refresh_only = false
	_request_block_download()


func _prepare_pending_block() -> bool:
	if absf(selected_latitude) > 80.0 or absf(selected_longitude) > 180.0:
		info.text = "Dieser Ort liegt außerhalb des unterstützten Bereichs."
		return false
	var latitude_delta := PLACE_EXTENT_METERS / 111320.0
	var longitude_delta := PLACE_EXTENT_METERS / (111320.0 * cos(deg_to_rad(selected_latitude)))
	if absf(selected_latitude) + latitude_delta > 80.0 or absf(selected_longitude) + longitude_delta > 180.0:
		info.text = "Der gewünschte Startbereich liegt außerhalb des unterstützten Bereichs."
		return false
	var selected_origin := [selected_latitude, selected_longitude]
	pending_block = Grid.block_at_origin(selected_origin)
	pending_block_id = "block_" + Grid.tile_id(pending_block, selected_origin)
	pending_bounds = Grid.block_bounds(selected_origin, pending_block)
	pending_place_bounds = [
		selected_latitude - latitude_delta,
		selected_longitude - longitude_delta,
		selected_latitude + latitude_delta,
		selected_longitude + longitude_delta,
	]
	if pending_bounds.size() != 4:
		info.text = "Der UTM-Kartenblock für diesen Ort konnte nicht bestimmt werden."
		return false
	return true


func _on_refresh_pressed() -> void:
	if not _prepare_pending_block():
		return
	pending_refresh_only = true
	_request_block_download()


func _request_block_download() -> void:
	var query := PlaceStore.block_query(pending_bounds)
	if query.is_empty():
		info.text = "Die OSM-Abfrage für diesen Kartenblock konnte nicht erstellt werden."
		return
	var endpoint: String = ProjectSettings.get_setting("opencrime/osm/overpass_url")
	var error := request.request(endpoint + "?data=" + query.uri_encode(), PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"]))
	if error != OK:
		info.text = "OSM-Anfrage konnte nicht gestartet werden (Fehler %d)." % error
		pending_refresh_only = false
		return
	start_button.disabled = true
	refresh_button.disabled = true
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_field.editable = false
	info.text = "Lade Verkehrs- und Notfallobjekte für den 1 × 1 km-UTM-Block aus OpenStreetMap …"


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var refresh_only := pending_refresh_only
	pending_refresh_only = false
	start_button.disabled = false
	refresh_button.disabled = false
	list.mouse_filter = Control.MOUSE_FILTER_STOP
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	name_field.editable = not refresh_only and selected_place.is_empty()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		info.text = "OSM-Download fehlgeschlagen (HTTP %d, Fehler %d). Bitte erneut versuchen." % [code, result]
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		info.text = "OSM-Dienst lieferte ungültige Daten."
		return
	var selected_origin := [selected_latitude, selected_longitude]
	var block_data := PlaceStore.from_overpass_block(
		json.data,
		Grid.block_origin(selected_origin, pending_block),
		pending_bounds,
		pending_block_id
	)
	if block_data.is_empty():
		info.text = "OSM-Dienst lieferte für den 1-km-Block ungültige Daten."
		return
	var has_road := false
	for way in block_data.ways:
		if way.tags.has("highway") and way.tags.get("area", "") != "yes" and way.geometry.size() >= 2:
			has_road = true
			break
	if not has_road:
		info.text = "OSM-Dienst lieferte für diesen Block keine nutzbaren Straßen; der vorhandene Cache bleibt erhalten."
		return
	var cache_error := PlaceStore.write_block_cache(pending_block_id, block_data)
	if cache_error != OK:
		info.text = "1-km-Kartenblock konnte nicht zwischengespeichert werden (Fehler %d)." % cache_error
		return
	refresh_button.show()
	if refresh_only:
		var refreshed_block := PlaceStore.read_block_cache(pending_block, selected_origin)
		if refreshed_block.is_empty() or PlaceStore.block_needs_refresh(refreshed_block):
			info.text = "Der erneuerte Kartenblock konnte nicht verifiziert werden."
			return
		info.text = "Kartenblock aktualisiert. Verkehrs- und Notfallobjekte sind jetzt im Cache."
		return
	var place := PlaceStore.from_overpass(json.data, selected_latitude, selected_longitude, pending_place_bounds, name_field.text.strip_edges())
	if place.is_empty():
		info.text = "Kein sicherer Startpunkt im 1-km-Block gefunden. Bitte einen anderen Punkt wählen."
		return
	_finish_place(place)


func _finish_place(place: Dictionary, persist: bool = true) -> void:
	if Grid.block_at_origin(place.origin) != pending_block:
		info.text = "Der sichere Startpunkt liegt in einem anderen 1-km-Block. Bitte einen Punkt weiter innerhalb des Blocks wählen."
		return
	if persist:
		var error := PlaceStore.save_place(place)
		if error != OK:
			info.text = "Ort konnte nicht gespeichert werden (Fehler %d)." % error
			return
	place_chosen.emit(place)


func _on_cancel_pressed() -> void:
	cancelled.emit()
