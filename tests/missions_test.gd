extends SceneTree

const Missions = preload("res://scripts/missions.gd")
const PlaceStore = preload("res://scripts/place_store.gd")
const OSMMap = preload("res://scripts/osm_map.gd")


func _safe_target(place: Dictionary, target: Vector2, factor: float) -> bool:
	if absf(target.x) > 225.0 * factor - 4.0 or absf(target.y) > 225.0 * factor - 4.0:
		return false
	for way in place.ways:
		if not way.tags.has("building") or way.geometry.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point in way.geometry:
			polygon.append(OSMMap._project(point, place.origin) * factor)
		if Geometry2D.is_point_in_polygon(target, polygon):
			return false
		for index in polygon.size():
			if target.distance_to(Geometry2D.get_closest_point_to_segment(target, polygon[index], polygon[(index + 1) % polygon.size()])) < 2.0:
				return false
	return true


func _initialize() -> void:
	var manager := Missions.new()
	var place := PlaceStore.find_by_id("thalhofen")
	if not manager.setup(place, 1.1) or not manager.add_player(1):
		_fail("Mission setup failed: " + manager.error)
		return
	var story: String = manager.players[1].offers[0]
	if manager.missions[story].type != "story" or not manager.players[1].active.is_empty():
		_fail("The first story SMS was not offered without starting it.")
		return
	if not manager.defer_offer(1, story).is_empty() or not manager.players[1].deferred.has(story) or manager.missions[manager.players[1].offers[0]].type != "recurring":
		_fail("Declining a story offer did not preserve it and offer a recurring job.")
		return
	if not manager.accept(1, story).is_empty():
		_fail("The deferred story offer could not be accepted.")
		return
	var mission: Dictionary = manager.missions[story]
	if mission.pickup_label.is_empty() or mission.destination_label.is_empty():
		_fail("The SMS does not identify both delivery locations.")
		return
	var pickup := Vector3(float(mission.pickup[0]), 0.9, float(mission.pickup[1]))
	var destination := Vector3(float(mission.destination[0]), 0.9, float(mission.destination[1]))
	if pickup.distance_to(destination) < 27.5 or not _safe_target(place, Vector2(pickup.x, pickup.z), 1.1) or not _safe_target(place, Vector2(destination.x, destination.z), 1.1):
		_fail("The delivery locations are too close.")
		return
	if manager.accept(1, manager.players[1].offers[0]).is_empty():
		_fail("A second mission could be accepted while one was active.")
		return
	manager.visit(1, pickup, false)
	if mission.stage != 0:
		_fail("Driving over a package collected it.")
		return
	manager.visit(1, destination, true)
	if mission.stage != 0:
		_fail("The destination completed the job before pickup.")
		return
	manager.visit(1, pickup, true)
	if mission.stage != 1:
		_fail("Walking to the package did not complete the first stage.")
		return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(manager.save_for(1)))
	if not Missions.valid_save(saved):
		_fail("A mission in progress did not survive JSON serialization.")
		return
	var invalid := saved.duplicate(true)
	invalid.player.offers.append(story)
	if Missions.valid_save(invalid):
		_fail("An inconsistent mission save was accepted.")
		return
	var restored := Missions.new()
	if not restored.setup(PlaceStore.find_by_id("thalhofen"), 1.1) or not restored.add_player(1, saved):
		_fail("A mission in progress could not be restored.")
		return
	restored.visit(1, destination, true)
	if restored.players[1].money != 100 or not restored.players[1].completed.has("first_delivery") or not restored.players[1].active.is_empty():
		_fail("Delivery did not pay once or remember the story completion.")
		return
	restored.visit(1, destination, true)
	if restored.players[1].money != 100 or restored.missions[restored.players[1].offers[0]].type != "recurring":
		_fail("A completed story mission repeated or paid twice.")
		return
	var coop := Missions.new()
	if not coop.setup(PlaceStore.find_by_id("gendarmenmarkt"), 1.0) or not coop.add_player(1) or not coop.add_player(2) or not coop.add_player(3):
		_fail("Multiplayer mission setup failed.")
		return
	var shared: String = coop.players[1].offers[0]
	coop.missions[shared].reward = 101
	if not coop.accept(1, shared).is_empty() or not coop.invite(1, 2).is_empty() or not coop.invite(1, 3).is_empty():
		_fail("Could not accept and forward a mission.")
		return
	if not coop.defer_offer(2, shared).is_empty() or not coop.accept(2, shared).is_empty():
		_fail("A deferred invitation could not be accepted.")
		return
	var shared_mission: Dictionary = coop.missions[shared]
	var shared_pickup := Vector3(float(shared_mission.pickup[0]), 0, float(shared_mission.pickup[1]))
	var shared_destination := Vector3(float(shared_mission.destination[0]), 0, float(shared_mission.destination[1]))
	coop.visit(3, shared_pickup, true)
	if shared_mission.stage != 0:
		_fail("An unaccepted invitation progressed a mission.")
		return
	coop.visit(2, shared_pickup, true)
	coop.visit(1, shared_destination, true)
	if coop.players[1].money != 51 or coop.players[2].money != 50 or coop.players[3].money != 0 or coop.missions.has(shared):
		_fail("Cooperative progress or split reward was incorrect.")
		return
	if not coop.players[2].completed.has("first_delivery") or not coop.players[3].completed.is_empty():
		_fail("Story completion leaked to an unaccepted participant.")
		return
	var reconnect := Missions.new()
	if not reconnect.setup(PlaceStore.find_by_id("thalhofen"), 1.0) or not reconnect.add_player(1) or not reconnect.add_player(2):
		_fail("Disconnect test setup failed.")
		return
	var shared_after_disconnect: String = reconnect.players[1].offers[0]
	reconnect.accept(1, shared_after_disconnect)
	reconnect.invite(1, 2)
	reconnect.accept(2, shared_after_disconnect)
	var remaining: Dictionary = reconnect.missions[shared_after_disconnect]
	reconnect.remove_player(1)
	reconnect.visit(2, Vector3(remaining.pickup[0], 0, remaining.pickup[1]), true)
	reconnect.visit(2, Vector3(remaining.destination[0], 0, remaining.destination[1]), true)
	if reconnect.players[2].money != 100:
		_fail("The remaining participant could not finish after a disconnect.")
		return
	print("Mission offers, stages, persistence and cooperative rewards passed")
	quit(0)


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)
