extends RefCounted

const EPSILON := 0.001
const MAX_SNAP_DISTANCE := 1.0
const MAX_WALLS := 1000


static func floor_outline(original: PackedVector2Array, edit: Dictionary) -> Dictionary:
	if not edit.has("outline"):
		return {"outline": original}
	var value: Variant = edit.outline
	if not value is Array or value.size() != original.size():
		return {"error": "Der bearbeitete Etagengrundriss ist ungültig."}
	var outline := PackedVector2Array()
	for coordinate in value:
		if not coordinate is Array or coordinate.size() != 2 or not (coordinate[0] is int or coordinate[0] is float) or not (coordinate[1] is int or coordinate[1] is float):
			return {"error": "Der bearbeitete Etagengrundriss enthält ungültige Koordinaten."}
		var point := Vector2(float(coordinate[0]), float(coordinate[1]))
		if not point.is_finite():
			return {"error": "Der bearbeitete Etagengrundriss enthält ungültige Koordinaten."}
		outline.append(point)
	if _outline_mapping(original, outline).is_empty() or Geometry2D.triangulate_polygon(outline).is_empty() or Geometry2D.is_polygon_clockwise(original) != Geometry2D.is_polygon_clockwise(outline):
		return {"error": "Der bearbeitete Etagengrundriss ist ungültig."}
	for a in outline.size():
		for b in range(a + 1, outline.size()):
			if b == a + 1 or (a == 0 and b == outline.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(outline[a], outline[(a + 1) % outline.size()], outline[b], outline[(b + 1) % outline.size()]) != null:
				return {"error": "Der bearbeitete Etagengrundriss überschneidet sich."}
	return {"outline": outline}


static func move_outline_edge(outline: PackedVector2Array, index: int, distance: float) -> Dictionary:
	if outline.size() < 3 or index < 0 or index >= outline.size() or not is_finite(distance):
		return {"error": "Die Außenwand oder ihre Position ist ungültig."}
	if is_zero_approx(distance):
		return {"outline": outline.duplicate()}
	var size := outline.size()
	var edge := outline[(index + 1) % size] - outline[index]
	if edge.length() <= EPSILON:
		return {"error": "Der Gebäudegrundriss enthält eine zu kurze Wand."}
	var tangent := edge.normalized()
	var first := index
	var last := index
	while true:
		var previous := (first + size - 1) % size
		if previous == last or (outline[first] - outline[previous]).normalized().dot(tangent) < 0.999999:
			break
		first = previous
	while true:
		var following := (last + 1) % size
		if following == first or (outline[(following + 1) % size] - outline[following]).normalized().dot(tangent) < 0.999999:
			break
		last = following
	var before := (first + size - 1) % size
	var after := (last + 1) % size
	var next := (after + 1) % size
	var first_edge := outline[(first + 1) % size] - outline[first]
	var last_edge := outline[after] - outline[last]
	var previous_edge := outline[first] - outline[before]
	var next_edge := outline[next] - outline[after]
	if edge.length() <= EPSILON or previous_edge.length() <= EPSILON or next_edge.length() <= EPSILON:
		return {"error": "Der Gebäudegrundriss enthält eine zu kurze Wand."}
	var shift := Vector2(-tangent.y, tangent.x) * distance
	var moved_start: Variant = Geometry2D.line_intersects_line(outline[before], previous_edge, outline[first] + shift, first_edge)
	var moved_end: Variant = Geometry2D.line_intersects_line(outline[after] + shift, last_edge, outline[after], next_edge)
	if moved_start == null or moved_end == null:
		return {"error": "Die benachbarten Wände können nicht eindeutig verbunden werden."}
	if (moved_start - outline[before]).dot(previous_edge) <= EPSILON or (outline[next] - moved_end).dot(next_edge) <= EPSILON or (moved_end - moved_start).dot(tangent) <= EPSILON:
		return {"error": "Die Wand kann nicht über das Ende einer benachbarten Wand verschoben werden."}
	var moved := outline.duplicate()
	var current := first
	while current != after:
		moved[current] = outline[current] + shift
		current = (current + 1) % size
	moved[first] = moved_start
	moved[after] = moved_end
	if Geometry2D.triangulate_polygon(moved).is_empty() or Geometry2D.is_polygon_clockwise(moved) != Geometry2D.is_polygon_clockwise(outline):
		return {"error": "Die Verschiebung würde einen ungültigen Gebäudegrundriss erzeugen."}
	for a in moved.size():
		for b in range(a + 1, moved.size()):
			if b == a + 1 or (a == 0 and b == moved.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(moved[a], moved[(a + 1) % moved.size()], moved[b], moved[(b + 1) % moved.size()]) != null:
				return {"error": "Die Verschiebung würde Außenwände überschneiden."}
	return {"outline": moved}


static func build(interior: PackedVector2Array, walls: Array) -> Dictionary:
	if walls.size() > MAX_WALLS or interior.size() < 3 or Geometry2D.triangulate_polygon(interior).is_empty():
		return {"error": "Die Innenwände sind ungültig."}
	var regions: Array[PackedVector2Array] = [interior]
	var built := []
	var plans := []
	for wall in walls:
		if not wall is Dictionary or not wall.get("cursor") is Array or wall.cursor.size() != 2:
			return {"error": "Eine Innenwand enthält ungültige Koordinaten."}
		var coords: Array = wall.cursor
		if not (coords[0] is int or coords[0] is float) or not (coords[1] is int or coords[1] is float) or not is_finite(float(coords[0])) or not is_finite(float(coords[1])):
			return {"error": "Eine Innenwand enthält ungültige Koordinaten."}
		var thickness: Variant = wall.get("thickness")
		if not (thickness is int or thickness is float) or not is_finite(float(thickness)) or float(thickness) <= 0.0 or float(thickness) > 1000.0:
			return {"error": "Eine Innenwand enthält eine ungültige Wanddicke."}
		var plan := plan_wall(regions, Vector2(float(coords[0]), float(coords[1])), float(thickness))
		if plan.has("error"):
			return plan
		regions = plan.regions
		built.append(plan.polygon)
		var details := plan.duplicate()
		details.erase("regions")
		plans.append(details)
	return {"regions": regions, "walls": built, "plans": plans}


static func _matching_edge(point: Vector2, edge: Array, polygon: PackedVector2Array) -> int:
	var direction: Vector2 = (edge[1] - edge[0]).normalized()
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if absf((b - a).normalized().cross(direction)) < 0.001 and point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < 0.02:
			return index
	return -1


static func _anchor(point: Vector2, edge: Array, interior: PackedVector2Array, built: Array) -> Dictionary:
	for index in built.size():
		var polygon: PackedVector2Array = built[index]
		var match_index := _matching_edge(point, edge, polygon)
		if match_index >= 0:
			var direction := (polygon[(match_index + 1) % polygon.size()] - polygon[match_index]).normalized()
			return {"wall": index, "direction": direction}
	var outside := _matching_edge(point, edge, interior)
	if outside >= 0:
		return {"outside": outside}
	return {}


static func _outline_mapping(old: PackedVector2Array, new_outline: PackedVector2Array) -> Array:
	if old.size() != new_outline.size():
		return []
	var best := []
	var best_cost := INF
	for rotation in old.size():
		var candidate := []
		var cost := 0.0
		for index in old.size():
			var mapped := (index + rotation) % old.size()
			var old_dir := (old[(index + 1) % old.size()] - old[index]).normalized()
			var new_dir := (new_outline[(mapped + 1) % old.size()] - new_outline[mapped]).normalized()
			if old_dir.dot(new_dir) < 0.999:
				candidate.clear()
				break
			candidate.append(mapped)
			cost += old[index].distance_squared_to(new_outline[mapped])
		if not candidate.is_empty() and cost < best_cost:
			best = candidate
			best_cost = cost
	return best


static func _anchor_edge(anchor: Dictionary, interior: PackedVector2Array, built: Array, mapping: Array, point: Vector2) -> Array:
	if anchor.has("outside"):
		var index: int = mapping[anchor.outside]
		return [interior[index], interior[(index + 1) % interior.size()]]
	if not anchor.has("wall") or int(anchor.wall) >= built.size():
		return []
	var polygon: PackedVector2Array = built[anchor.wall]
	var best := []
	var distance := INF
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if (b - a).normalized().dot(anchor.direction) < 0.999:
			continue
		var candidate := point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, a, b))
		if candidate < distance:
			distance = candidate
			best = [a, b]
	return best


static func _same_anchor(old: Dictionary, current: Dictionary, mapping: Array) -> bool:
	if old.has("outside"):
		return current.has("outside") and int(current.outside) == int(mapping[old.outside])
	return old.has("wall") and current.has("wall") and int(old.wall) == int(current.wall) and old.direction.dot(current.direction) > 0.999


static func adjust_walls(old_interior: PackedVector2Array, new_interior: PackedVector2Array, walls: Array, moved_wall := -1, distance := 0.0, thickness := -1.0) -> Dictionary:
	var previous := build(old_interior, walls)
	if previous.has("error"):
		return previous
	if walls.is_empty() and moved_wall == -1:
		return {"walls": [], "regions": [new_interior], "polygons": []}
	var mapping := _outline_mapping(old_interior, new_interior)
	if mapping.is_empty() or moved_wall < -1 or moved_wall >= walls.size() or not is_finite(distance):
		return {"error": "Die Wandverbindungen können für diesen Grundriss nicht eindeutig erhalten werden."}
	var result := walls.duplicate(true)
	var regions: Array[PackedVector2Array] = [new_interior]
	var old_built := []
	var new_built := []
	for index in walls.size():
		var original: Dictionary = previous.plans[index]
		var source := _anchor(original.start, original.source, old_interior, old_built)
		var target := _anchor(original.end, original.target, old_interior, old_built)
		if source.is_empty() or target.is_empty():
			return {"error": "Eine bestehende Wandverbindung konnte nicht zugeordnet werden."}
		var new_edge := _anchor_edge(source, new_interior, new_built, mapping, original.start)
		if new_edge.is_empty():
			return {"error": "Eine verbundene Wand ist nicht mehr verfügbar."}
		var direction: Vector2 = (new_edge[1] - new_edge[0]).normalized()
		var desired: Vector2 = original.start
		if index == moved_wall:
			desired += (original.source[1] - original.source[0]).normalized() * distance
			if thickness > 0.0:
				result[index].thickness = thickness
		var projected: Vector2 = new_edge[0] + direction * (desired - new_edge[0]).dot(direction)
		var inward: Vector2 = (original.end - original.start).normalized()
		var cursor := projected + inward * EPSILON * 2.0
		var plan := plan_wall(regions, cursor, float(result[index].thickness))
		if plan.has("error"):
			return plan
		var new_source := _anchor(plan.start, plan.source, new_interior, new_built)
		var new_target := _anchor(plan.end, plan.target, new_interior, new_built)
		if not _same_anchor(source, new_source, mapping) or not _same_anchor(target, new_target, mapping):
			return {"error": "Die Verschiebung würde eine Wandverbindung lösen oder verändern."}
		result[index].cursor = [cursor.x, cursor.y]
		regions = plan.regions
		old_built.append(original.polygon)
		new_built.append(plan.polygon)
	return {"walls": result, "regions": regions, "polygons": new_built}


static func plan_wall(regions: Array[PackedVector2Array], cursor: Vector2, thickness: float) -> Dictionary:
	if not cursor.is_finite() or not is_finite(thickness) or thickness <= 0.0 or thickness > 1000.0:
		return {"error": "Ungültige Position oder Wanddicke."}
	var containing := -1
	for index in regions.size():
		if Geometry2D.is_point_in_polygon(cursor, regions[index]):
			containing = index
			break
	var chosen_region := -1
	var chosen_edge := -1
	var nearest := Vector2.ZERO
	var closest_distance := INF
	for region_index in regions.size():
		if containing >= 0 and region_index != containing:
			continue
		var region := regions[region_index]
		for edge_index in region.size():
			var a := region[edge_index]
			var b := region[(edge_index + 1) % region.size()]
			if a.distance_squared_to(b) <= EPSILON * EPSILON:
				continue
			var projected := Geometry2D.get_closest_point_to_segment(cursor, a, b)
			var distance := cursor.distance_squared_to(projected)
			if distance < closest_distance:
				closest_distance = distance
				chosen_region = region_index
				chosen_edge = edge_index
				nearest = projected
	if chosen_region < 0 or (containing < 0 and closest_distance > MAX_SNAP_DISTANCE * MAX_SNAP_DISTANCE):
		return {"error": "Bitte in die Nähe einer Raumwand zeigen."}
	var region := regions[chosen_region]
	var start_a := region[chosen_edge]
	var start_b := region[(chosen_edge + 1) % region.size()]
	if nearest.distance_to(start_a) <= thickness * 0.5 + EPSILON or nearest.distance_to(start_b) <= thickness * 0.5 + EPSILON:
		return {"error": "Bitte etwas Abstand zur Wandecke halten."}
	var tangent := (start_b - start_a).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	var middle := (start_a + start_b) * 0.5
	if not Geometry2D.is_point_in_polygon(middle + normal * EPSILON * 10.0, region):
		normal = -normal
	if not Geometry2D.is_point_in_polygon(nearest + normal * EPSILON * 10.0, region):
		return {"error": "An dieser Stelle kann keine Wand beginnen."}
	var bounds := Rect2(region[0], Vector2.ZERO)
	for point in region:
		bounds = bounds.expand(point)
	var far := nearest + normal * (bounds.size.length() + 1.0)
	var end := Vector2.ZERO
	var target := []
	var nearest_hit := INF
	for edge_index in region.size():
		if edge_index == chosen_edge:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(nearest + normal * EPSILON, far, region[edge_index], region[(edge_index + 1) % region.size()])
		if hit == null:
			continue
		var distance: float = (hit - nearest).dot(normal)
		if distance > EPSILON and distance < nearest_hit:
			nearest_hit = distance
			end = hit
			target = [region[edge_index], region[(edge_index + 1) % region.size()]]
	if not is_finite(nearest_hit) or nearest_hit <= thickness + EPSILON:
		return {"error": "Keine geeignete gegenüberliegende Wand gefunden."}
	var half_width := tangent * thickness * 0.5
	var extension := normal * EPSILON * 4.0
	var rectangle := PackedVector2Array([
		nearest - extension - half_width, nearest - extension + half_width,
		end + extension + half_width, end + extension - half_width,
	])
	var clipped := Geometry2D.intersect_polygons(region, rectangle)
	var remainder := Geometry2D.clip_polygons(region, rectangle)
	if clipped.size() != 1 or remainder.size() != 2 or Geometry2D.triangulate_polygon(clipped[0]).is_empty():
		return {"error": "Die Wand kann diesen Raum an dieser Stelle nicht eindeutig teilen."}
	var next_regions: Array[PackedVector2Array] = regions.duplicate()
	next_regions.remove_at(chosen_region)
	for part in remainder:
		if part.size() < 3 or Geometry2D.triangulate_polygon(part).is_empty():
			return {"error": "Die Wand würde einen ungültigen Raum erzeugen."}
		next_regions.append(part)
	return {"regions": next_regions, "polygon": clipped[0], "source": [start_a, start_b], "target": target, "start": nearest, "end": end}
