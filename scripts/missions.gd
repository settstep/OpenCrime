extends RefCounted

signal changed(peer_id: int)
signal notification(peer_id: int, text: String)

const OSMMap = preload("res://scripts/osm_map.gd")
const CATALOG := "res://data/missions.json"
const MIN_DISTANCE := 25.0
const INTERACTION_RADIUS := 2.5

var definitions: Array[Dictionary] = []
var candidates: Array[Dictionary] = []
var missions := {}
var players := {}
var error := ""
var rng := RandomNumberGenerator.new()
var minimum_distance := MIN_DISTANCE


func setup(place: Dictionary, scale_factor: float) -> bool:
	var file := FileAccess.open(CATALOG, FileAccess.READ)
	if file == null:
		error = "Auftragsdatei konnte nicht geöffnet werden."
		push_error(error)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary or not json.data.get("missions") is Array:
		error = "Auftragsdatei ist ungültig."
		push_error(error)
		return false
	var ids := {}
	var types := {}
	for item in json.data.missions:
		if not item is Dictionary or not item.has_all(["id", "type", "title", "sms", "reward"]) or not item.id is String or item.id.is_empty() or ids.has(item.id) or item.type not in ["story", "recurring"] or not item.title is String or item.title.is_empty() or not item.sms is String or item.sms.is_empty() or not _integer(item.reward) or item.reward <= 0 or item.reward > 1000000:
			error = "Ungültige Auftragsdefinition in " + CATALOG
			push_error(error)
			return false
		definitions.append(item)
		ids[item.id] = true
		types[item.type] = true
	if not types.has("story") or not types.has("recurring"):
		error = "Auftragsdatei benötigt Haupt- und wiederkehrende Aufträge."
		push_error(error)
		return false
	rng.randomize()
	minimum_distance = maxf(MIN_DISTANCE * scale_factor, INTERACTION_RADIUS * 2.0 + 1.0)
	candidates = _candidate_points(place, scale_factor)
	if candidates.size() < 2:
		error = "Für diesen Ort wurden keine geeigneten Auftragsziele gefunden."
		push_warning(error)
		return false
	return true


static func _integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floorf(float(value))


static func _candidate_points(place: Dictionary, scale_factor: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var buildings: Array[Dictionary] = []
	for way in place.ways:
		if way.tags.has("building") and way.geometry.size() >= 3:
			var polygon := PackedVector2Array()
			for point in way.geometry:
				polygon.append(OSMMap._project(point, place.origin))
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				bounds = bounds.expand(point)
			buildings.append({"polygon": polygon, "bounds": bounds.grow(2.0 / scale_factor)})
	var half := 225.0 - 4.0 / scale_factor
	for way in place.ways:
		if not way.tags.has("highway") or way.tags.get("area", "") == "yes" or way.tags.get("bridge", "") not in ["", "no"] or way.tags.get("tunnel", "") not in ["", "no"]:
			continue
		for index in range(way.geometry.size() - 1):
			var a := OSMMap._project(way.geometry[index], place.origin)
			var b := OSMMap._project(way.geometry[index + 1], place.origin)
			if a.distance_to(b) < 3.0:
				continue
			for fraction in [0.25, 0.5, 0.75]:
				var point := a.lerp(b, fraction)
				if absf(point.x) > half or absf(point.y) > half:
					continue
				var clear := true
				for building in buildings:
					if not building.bounds.has_point(point):
						continue
					var polygon: PackedVector2Array = building.polygon
					if Geometry2D.is_point_in_polygon(point, polygon):
						clear = false
						break
					for edge in polygon.size():
						if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()])) < 2.0 / scale_factor:
							clear = false
							break
					if not clear:
						break
				if clear:
					var name := str(way.tags.get("name", "")).strip_edges()
					if name.is_empty():
						name = "Unbenannter Weg"
					result.append({"point": point * scale_factor, "label": "%s (%+.0f m Ost, %+.0f m Süd)" % [name, point.x, point.y]})
	return result


func add_player(peer_id: int, restored: Dictionary = {}) -> bool:
	if players.has(peer_id):
		error = "Spieler ist bereits für Aufträge registriert."
		push_error(error)
		return false
	if not restored.is_empty():
		if not valid_save(restored):
			error = "Gespeicherte Auftragsdaten sind ungültig."
			push_error(error)
			return false
		players[peer_id] = restored.player.duplicate(true)
		missions = restored.missions.duplicate(true)
		players[peer_id].money = int(players[peer_id].money)
		for id in missions:
			missions[id].owner = int(missions[id].owner)
			missions[id].stage = int(missions[id].stage)
			missions[id].reward = int(missions[id].reward)
			for index in missions[id].participants.size():
				missions[id].participants[index] = int(missions[id].participants[index])
	else:
		players[peer_id] = {"money": 0, "completed": [], "active": "", "offers": [], "deferred": []}
		if not _offer_next(peer_id):
			return false
	changed.emit(peer_id)
	return true


func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	players.erase(peer_id)
	for id in missions.keys():
		var mission: Dictionary = missions[id]
		if mission.participants.has(peer_id):
			mission.participants.erase(peer_id)
		mission.invited.erase(peer_id)
		if mission.owner == peer_id and mission.participants.is_empty():
			_remove_mission(id)
	_notify_all()


func _offer_next(peer_id: int) -> bool:
	var player: Dictionary = players[peer_id]
	var selected := {}
	for definition in definitions:
		if definition.type == "story" and not player.completed.has(definition.id) and not _has_story_offer(player, definition.id):
			selected = definition
			break
	if selected.is_empty():
		var recurring: Array[Dictionary] = []
		for definition in definitions:
			if definition.type == "recurring":
				recurring.append(definition)
		selected = recurring[rng.randi_range(0, recurring.size() - 1)]
	var first: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var alternatives: Array[Dictionary] = []
	var bounds := Rect2(candidates[0].point, Vector2.ZERO)
	for candidate in candidates:
		bounds = bounds.expand(candidate.point)
	if bounds.size.length() < minimum_distance:
		error = "Für diesen Ort liegen die möglichen Auftragsziele zu nahe beieinander."
		push_warning(error)
		return false
	var start := rng.randi_range(0, candidates.size() - 1)
	for attempt in candidates.size():
		first = candidates[(start + attempt) % candidates.size()]
		for candidate in candidates:
			if first.point.distance_to(candidate.point) >= minimum_distance:
				alternatives.append(candidate)
		if not alternatives.is_empty():
			break
	if alternatives.is_empty():
		error = "Für diesen Ort liegen die möglichen Auftragsziele zu nahe beieinander."
		push_warning(error)
		return false
	var second: Dictionary = alternatives[rng.randi_range(0, alternatives.size() - 1)]
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	if missions.has(id):
		error = "Ein eindeutiger Auftrag konnte nicht erstellt werden."
		push_error(error)
		return false
	var mission := {
		"id": id, "template": selected.id, "type": selected.type, "title": selected.title,
		"sms": selected.sms, "reward": int(selected.reward), "pickup": [first.point.x, first.point.y],
		"destination": [second.point.x, second.point.y], "pickup_label": first.label,
		"destination_label": second.label, "stage": 0, "owner": peer_id,
		"participants": [], "invited": [],
	}
	missions[id] = mission
	player.offers.append(id)
	return true


func _has_story_offer(player: Dictionary, template: String) -> bool:
	for id in player.offers + player.deferred:
		if missions.has(id) and missions[id].template == template:
			return true
	return false


func accept(peer_id: int, id: String) -> String:
	if not players.has(peer_id) or not missions.has(id):
		return "Dieser Auftrag ist nicht mehr verfügbar."
	var player: Dictionary = players[peer_id]
	var mission: Dictionary = missions[id]
	if not player.active.is_empty():
		return "Bitte zuerst den aktiven Auftrag abschließen."
	if not player.offers.has(id) and not player.deferred.has(id):
		return "Dieser Auftrag wurde nicht angeboten."
	if mission.type == "story" and player.completed.has(mission.template):
		return "Dieser Hauptauftrag wurde bereits abgeschlossen."
	player.offers.erase(id)
	player.deferred.erase(id)
	mission.invited.erase(peer_id)
	if not mission.participants.has(peer_id):
		mission.participants.append(peer_id)
	player.active = id
	_notify_all()
	return ""


func defer_offer(peer_id: int, id: String) -> String:
	if not players.has(peer_id) or not missions.has(id) or not players[peer_id].offers.has(id):
		return "Dieses Angebot ist nicht verfügbar."
	var player: Dictionary = players[peer_id]
	player.offers.erase(id)
	player.deferred.append(id)
	if missions[id].owner == peer_id and player.offers.is_empty() and player.active.is_empty():
		if not _offer_next(peer_id):
			changed.emit(peer_id)
			return error
	changed.emit(peer_id)
	return ""


func invite(peer_id: int, other: int) -> String:
	if not players.has(peer_id) or not players.has(other) or peer_id == other:
		return "Dieser Mitspieler ist nicht verfügbar."
	var id: String = players[peer_id].active
	if id.is_empty() or not missions.has(id):
		return "Zum Weiterleiten muss ein Auftrag aktiv sein."
	var mission: Dictionary = missions[id]
	if mission.participants.has(other) or mission.invited.has(other):
		return "Dieser Mitspieler nimmt bereits teil oder wurde eingeladen."
	if mission.type == "story" and players[other].completed.has(mission.template):
		return "Dieser Mitspieler hat den Hauptauftrag bereits abgeschlossen."
	mission.invited.append(other)
	players[other].offers.append(id)
	_notify_all()
	return ""


func visit(peer_id: int, position: Vector3, on_foot: bool) -> void:
	if not on_foot or not players.has(peer_id):
		return
	var id: String = players[peer_id].active
	if id.is_empty() or not missions.has(id):
		return
	var mission: Dictionary = missions[id]
	var target: Array = mission.pickup if mission.stage == 0 else mission.destination
	if Vector2(position.x, position.z).distance_to(Vector2(float(target[0]), float(target[1]))) > INTERACTION_RADIUS:
		return
	if mission.stage == 0:
		mission.stage = 1
		_notify_all()
	else:
		_complete(id)


func _complete(id: String) -> void:
	var mission: Dictionary = missions[id]
	var participants: Array = mission.participants.duplicate()
	participants.sort()
	if participants.is_empty():
		return
	var amount := int(mission.reward) / participants.size()
	var remainder := int(mission.reward) % participants.size()
	var payouts := {}
	var offer_errors := {}
	for index in participants.size():
		var peer_id: int = participants[index]
		if not players.has(peer_id):
			continue
		var player: Dictionary = players[peer_id]
		var payout: int = amount + (1 if index < remainder else 0)
		payouts[peer_id] = payout
		player.money = int(player.money) + payout
		player.active = ""
		if mission.type == "story" and not player.completed.has(mission.template):
			player.completed.append(mission.template)
			for offered in (player.offers + player.deferred).duplicate():
				if missions.has(offered) and missions[offered].template == mission.template:
					if missions[offered].owner == peer_id:
						_remove_mission(offered)
					else:
						player.offers.erase(offered)
						player.deferred.erase(offered)
						missions[offered].invited.erase(peer_id)
	_remove_mission(id)
	for peer_id in participants:
		if players.has(peer_id) and players[peer_id].offers.is_empty():
			if not _offer_next(peer_id):
				offer_errors[peer_id] = error
	_notify_all()
	for peer_id in payouts:
		var notice := "Auftrag abgeschlossen: +%d $." % payouts[peer_id]
		if offer_errors.has(peer_id):
			notice += " " + offer_errors[peer_id]
		notification.emit(peer_id, notice)


func _remove_mission(id: String) -> void:
	for peer_id in players:
		players[peer_id].offers.erase(id)
		players[peer_id].deferred.erase(id)
	missions.erase(id)


func _notify_all() -> void:
	for peer_id in players:
		changed.emit(peer_id)


func view_for(peer_id: int) -> Dictionary:
	var player: Dictionary = players[peer_id]
	var visible := {}
	for id in player.offers + player.deferred + [player.active]:
		if missions.has(id):
			visible[id] = missions[id].duplicate(true)
	return {"player": player.duplicate(true), "missions": visible, "peers": players.keys()}


func save_for(peer_id: int) -> Dictionary:
	var data := view_for(peer_id)
	data.erase("peers")
	return data


static func valid_save(data: Dictionary) -> bool:
	if not data.has_all(["player", "missions"]) or not data.player is Dictionary or not data.missions is Dictionary:
		return false
	var player: Dictionary = data.player
	if not player.has_all(["money", "completed", "active", "offers", "deferred"]) or not _integer(player.money) or player.money < 0 or player.money > 1000000000 or not player.completed is Array or not player.active is String or not player.offers is Array or not player.deferred is Array:
		return false
	for completed in player.completed:
		if not completed is String or completed.is_empty():
			return false
	var referenced := {}
	for id in player.offers + player.deferred + ([player.active] if not player.active.is_empty() else []):
		if not id is String or id.length() != 32 or not id.is_valid_hex_number(false) or id != id.to_lower() or referenced.has(id) or not data.missions.has(id):
			return false
		referenced[id] = true
	if referenced.size() != data.missions.size():
		return false
	for id in data.missions:
		var mission: Variant = data.missions[id]
		if not id is String or not mission is Dictionary or not mission.has_all(["id", "template", "type", "title", "sms", "reward", "pickup", "destination", "pickup_label", "destination_label", "stage", "owner", "participants", "invited"]):
			return false
		if mission.id != id or not mission.template is String or mission.template.is_empty() or mission.type not in ["story", "recurring"] or not mission.title is String or not mission.sms is String or not mission.pickup_label is String or mission.pickup_label.is_empty() or not mission.destination_label is String or mission.destination_label.is_empty() or not _integer(mission.reward) or mission.reward <= 0 or mission.reward > 1000000 or not _integer(mission.stage) or int(mission.stage) not in [0, 1] or not _integer(mission.owner) or int(mission.owner) != 1 or not mission.participants is Array or not mission.invited is Array:
			return false
		if mission.participants.size() > 1 or not mission.invited.is_empty():
			return false
		if not mission.participants.is_empty() and (not _integer(mission.participants[0]) or int(mission.participants[0]) != 1):
			return false
		if mission.stage == 1 and id != player.active:
			return false
		for point in [mission.pickup, mission.destination]:
			if not point is Array or point.size() != 2:
				return false
			for value in point:
				if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or absf(float(value)) > 1000000.0:
					return false
		if (id == player.active) != (not mission.participants.is_empty()):
			return false
	return true
