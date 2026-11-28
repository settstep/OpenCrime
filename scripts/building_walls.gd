extends RefCounted

const EPSILON := 0.001
const MAX_SNAP_DISTANCE := 1.0
const MAX_WALLS := 1000


static func floor_outline(original: PackedVector2Array, edit: Dictionary) -> Dictionary:
	if not edit.has("outline") and not edit.has("outer_splits"):
		var unchanged := expand_outline(original, [])
		return {"outline": original, "base": original, "edges": unchanged.edges}
	var outline := PackedVector2Array()
	if edit.has("outline"):
		var value: Variant = edit.outline
		if not value is Array or value.size() != original.size():
			return {"error": "Der bearbeitete Etagengrundriss ist ungültig."}
		for coordinate in value:
			if not coordinate is Array or coordinate.size() != 2 or not (coordinate[0] is int or coordinate[0] is float) or not (coordinate[1] is int or coordinate[1] is float):
				return {"error": "Der bearbeitete Etagengrundriss enthält ungültige Koordinaten."}
			var point := Vector2(float(coordinate[0]), float(coordinate[1]))
			if not point.is_finite():
				return {"error": "Der bearbeitete Etagengrundriss enthält ungültige Koordinaten."}
			outline.append(point)
		if _outline_mapping(original, outline).is_empty():
			return {"error": "Der bearbeitete Etagengrundriss ist ungültig."}
	else:
		outline = original
	var expanded := expand_outline(outline, edit.get("outer_splits", []))
	if expanded.has("error"):
		return expanded
	var effective: PackedVector2Array = expanded.outline
	if Geometry2D.triangulate_polygon(effective).is_empty() or Geometry2D.is_polygon_clockwise(original) != Geometry2D.is_polygon_clockwise(effective):
		return {"error": "Der bearbeitete Etagengrundriss ist ungültig."}
	for a in effective.size():
		for b in range(a + 1, effective.size()):
			if b == a + 1 or (a == 0 and b == effective.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(effective[a], effective[(a + 1) % effective.size()], effective[b], effective[(b + 1) % effective.size()]) != null:
				return {"error": "Der bearbeitete Etagengrundriss überschneidet sich."}
	return {"outline": effective, "base": outline, "edges": expanded.edges}


static func expand_outline(outline: PackedVector2Array, splits: Variant) -> Dictionary:
	if not splits is Array or splits.size() > outline.size():
		return {"error": "Die Außenwandteilstücke sind ungültig."}
	if splits.is_empty():
		var unchanged_edges := []
		for index in outline.size():
			unchanged_edges.append({"edge": index, "segment": -1, "connector": false})
		return {"outline": outline, "edges": unchanged_edges}
	var configs := {}
	for item in splits:
		if not item is Dictionary or not (item.get("edge") is int or item.get("edge") is float) or not is_finite(float(item.edge)) or float(item.edge) != floorf(float(item.edge)) or int(item.edge) < 0 or int(item.edge) >= outline.size() or configs.has(int(item.edge)):
			return {"error": "Die Außenwandteilstücke sind ungültig."}
		var cuts: Variant = item.get("cuts")
		var offsets: Variant = item.get("offsets")
		if not cuts is Array or not offsets is Array or cuts.is_empty() or cuts.size() > MAX_WALLS or offsets.size() != cuts.size() + 1:
			return {"error": "Die Außenwandteilstücke sind ungültig."}
		var previous := 0.0
		for cut in cuts:
			if not (cut is int or cut is float) or not is_finite(float(cut)) or float(cut) <= previous or float(cut) >= 1.0:
				return {"error": "Die Teilungspunkte der Außenwand sind ungültig."}
			previous = float(cut)
		for offset in offsets:
			if not (offset is int or offset is float) or not is_finite(float(offset)):
				return {"error": "Die Position eines Außenwandteilstücks ist ungültig."}
		configs[int(item.edge)] = item
	var starts := []
	var ends := []
	var directions := []
	var normals := []
	for index in outline.size():
		var direction := outline[(index + 1) % outline.size()] - outline[index]
		if direction.length() <= EPSILON:
			return {"error": "Der Gebäudegrundriss enthält eine zu kurze Wand."}
		directions.append(direction.normalized())
		normals.append(Vector2(-direction.y, direction.x).normalized())
		var offsets: Array = configs[index].offsets if configs.has(index) else [0.0]
		starts.append(outline[index] + normals[index] * float(offsets[0]))
		ends.append(outline[(index + 1) % outline.size()] + normals[index] * float(offsets[-1]))
	for index in outline.size():
		var previous := (index + outline.size() - 1) % outline.size()
		if absf(directions[previous].cross(directions[index])) <= EPSILON:
			continue
		var intersection: Variant = Geometry2D.line_intersects_line(ends[previous], directions[previous], starts[index], directions[index])
		if intersection == null:
			return {"error": "Die Außenwände können nicht verbunden werden."}
		ends[previous] = intersection
		starts[index] = intersection
	var points := PackedVector2Array()
	var edges := []
	for index in outline.size():
		var cuts: Array = configs[index].cuts if configs.has(index) else []
		var offsets: Array = configs[index].offsets if configs.has(index) else [0.0]
		var piece_start: Vector2 = starts[index]
		for part in cuts.size() + 1:
			var piece_end: Vector2 = ends[index] if part == cuts.size() else outline[index].lerp(outline[(index + 1) % outline.size()], float(cuts[part])) + normals[index] * float(offsets[part])
			if (piece_end - piece_start).dot(directions[index]) <= EPSILON:
				return {"error": "Ein Außenwandteilstück würde über eine Endwand hinausgehen."}
			points.append(piece_start)
			edges.append({"edge": index, "segment": part if not cuts.is_empty() else -1, "connector": false})
			if part < cuts.size():
				var next_start: Vector2 = outline[index].lerp(outline[(index + 1) % outline.size()], float(cuts[part])) + normals[index] * float(offsets[part + 1])
				if piece_end.distance_to(next_start) > EPSILON:
					points.append(piece_end)
					edges.append({"edge": index, "segment": -1, "connector": true})
				piece_start = next_start
		var next := (index + 1) % outline.size()
		if ends[index].distance_to(starts[next]) > EPSILON:
			points.append(ends[index])
			edges.append({"edge": index, "segment": -1, "connector": true})
	return {"outline": points, "edges": edges}


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
		if not wall.get("junction", false) is bool:
			return {"error": "Die Wandverbindung ist ungültig."}
		var cursor := Vector2(float(coords[0]), float(coords[1]))
		var hint := []
		if wall.get("junction", false):
			var source_direction: Variant = wall.get("source_direction")
			if not source_direction is Array or source_direction.size() != 2 or not (source_direction[0] is int or source_direction[0] is float) or not (source_direction[1] is int or source_direction[1] is float):
				return {"error": "Die Richtung der Wandverbindung ist ungültig."}
			var direction := Vector2(float(source_direction[0]), float(source_direction[1]))
			if not direction.is_finite() or direction.length() < EPSILON:
				return {"error": "Die Richtung der Wandverbindung ist ungültig."}
			hint = [cursor, cursor + direction.normalized()]
		var plan := plan_wall(regions, cursor, float(thickness), wall, wall.get("junction", false), hint)
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
		return {"outside": outside, "direction": (interior[(outside + 1) % interior.size()] - interior[outside]).normalized()}
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
		var index := _mapped_outside(anchor, interior, mapping, point)
		if index < 0:
			return []
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


static func _mapped_outside(anchor: Dictionary, interior: PackedVector2Array, mapping: Array, point: Vector2) -> int:
	var mapped: int = mapping[anchor.outside]
	if mapped >= 0:
		return mapped
	var best := -1
	var distance := INF
	for index in interior.size():
		var a := interior[index]
		var b := interior[(index + 1) % interior.size()]
		if (b - a).normalized().dot(anchor.direction) < 0.999:
			continue
		var candidate := point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, a, b))
		if candidate < distance:
			best = index
			distance = candidate
	return best


static func _same_anchor(old: Dictionary, current: Dictionary, mapping: Array, interior: PackedVector2Array, point: Vector2) -> bool:
	if old.has("outside"):
		return current.has("outside") and int(current.outside) == _mapped_outside(old, interior, mapping, point)
	return old.has("wall") and current.has("wall") and int(old.wall) == int(current.wall) and old.direction.dot(current.direction) > 0.999


static func adjust_walls(old_interior: PackedVector2Array, new_interior: PackedVector2Array, walls: Array, moved_wall := -1, distance := 0.0, thickness := -1.0, moved_segment := -1) -> Dictionary:
	var previous := build(old_interior, walls)
	if previous.has("error"):
		return previous
	if walls.is_empty() and moved_wall == -1:
		return {"walls": [], "regions": [new_interior], "polygons": []}
	var mapping := _outline_mapping(old_interior, new_interior)
	if mapping.is_empty() and not old_interior.is_empty() and not new_interior.is_empty():
		mapping.resize(old_interior.size())
		mapping.fill(-1)
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
			if moved_segment >= 0:
				var offsets: Variant = result[index].get("offsets", [])
				if not offsets is Array or moved_segment >= offsets.size():
					return {"error": "Das Wandteilstück ist nicht mehr verfügbar."}
				offsets[moved_segment] = float(offsets[moved_segment]) + distance
				if thickness > 0.0:
					var widths: Array = result[index].get("thicknesses", []).duplicate()
					if widths.is_empty():
						widths.resize(offsets.size())
						widths.fill(float(result[index].thickness))
					widths[moved_segment] = thickness
					result[index]["thicknesses"] = widths
			else:
				desired += (original.source[1] - original.source[0]).normalized() * distance
				if thickness > 0.0:
					result[index].thickness = thickness
					if result[index].has("thicknesses"):
						result[index].thicknesses.fill(thickness)
		var projected: Vector2 = new_edge[0] + direction * (desired - new_edge[0]).dot(direction)
		var inward: Vector2 = (original.end - original.start).normalized()
		var cursor := projected + inward * EPSILON * 2.0
		var plan := plan_wall(regions, cursor, float(result[index].thickness), result[index], false, new_edge)
		if plan.has("error"):
			plan = plan_wall(regions, cursor, float(result[index].thickness), result[index], true, new_edge)
			if plan.has("error"):
				return plan
			result[index]["junction"] = true
			var hint_direction: Vector2 = (new_edge[1] - new_edge[0]).normalized()
			result[index]["source_direction"] = [hint_direction.x, hint_direction.y]
		var new_source := _anchor(plan.start, plan.source, new_interior, new_built)
		var new_target := _anchor(plan.end, plan.target, new_interior, new_built)
		if not _same_anchor(source, new_source, mapping, new_interior, original.start) or not _same_anchor(target, new_target, mapping, new_interior, original.end):
			return {"error": "Die Verschiebung würde eine Wandverbindung lösen oder verändern."}
		result[index].cursor = [cursor.x, cursor.y]
		regions = plan.regions
		old_built.append(original.polygon)
		new_built.append(plan.polygon)
	var checked := build(new_interior, result)
	if checked.has("error") or checked.walls != new_built:
		return {"error": "Die Wandverbindungen können nicht zuverlässig wiederhergestellt werden."}
	return {"walls": result, "regions": regions, "polygons": new_built}


static func split_wall(interior: PackedVector2Array, walls: Array, wall_index: int, segment_index: int) -> Dictionary:
	var current := build(interior, walls)
	if current.has("error"):
		return current
	if wall_index < 0 or wall_index >= walls.size():
		return {"error": "Die Wand ist nicht mehr verfügbar."}
	var plan: Dictionary = current.plans[wall_index]
	if segment_index < 0 or segment_index >= plan.segments.size():
		return {"error": "Das Wandteilstück ist nicht mehr verfügbar."}
	var segment: Array = plan.segments[segment_index]
	var segment_widths: Array = walls[wall_index].get("thicknesses", [])
	var width: float = float(segment_widths[segment_index]) if not segment_widths.is_empty() else float(walls[wall_index].thickness)
	var length: float = segment[0].distance_to(segment[1])
	if length <= EPSILON * 10.0:
		return {"error": "Die Wand ist zu kurz zum Aufteilen."}
	var positions := []
	for other_index in current.plans.size():
		if other_index == wall_index:
			continue
		var other: Dictionary = current.plans[other_index]
		for point in [other.start, other.end]:
			var projected := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
			if point.distance_to(projected) > width * 0.5 + EPSILON * 10.0:
				continue
			var fraction: float = (projected - segment[0]).dot((segment[1] - segment[0]).normalized()) / length
			if fraction > EPSILON * 10.0 / length and fraction < 1.0 - EPSILON * 10.0 / length:
				var duplicate := false
				for existing in positions:
					if absf(float(existing) - fraction) * length <= EPSILON * 10.0:
						duplicate = true
				if not duplicate:
					positions.append(fraction)
	if positions.is_empty():
		positions.append(0.5)
	positions.sort()
	var result := walls.duplicate(true)
	var cuts: Array = result[wall_index].get("cuts", []).duplicate()
	var offsets: Array = result[wall_index].get("offsets", []).duplicate()
	if offsets.is_empty():
		offsets = [0.0]
	var widths: Array = result[wall_index].get("thicknesses", []).duplicate()
	if widths.is_empty():
		widths.resize(offsets.size())
		widths.fill(float(result[wall_index].thickness))
	var low := 0.0 if segment_index == 0 else float(cuts[segment_index - 1])
	var high := 1.0 if segment_index == cuts.size() else float(cuts[segment_index])
	for index in positions.size():
		cuts.insert(segment_index + index, lerpf(low, high, float(positions[index])))
		offsets.insert(segment_index + index + 1, offsets[segment_index])
		widths.insert(segment_index + index + 1, widths[segment_index])
	result[wall_index]["cuts"] = cuts
	result[wall_index]["offsets"] = offsets
	result[wall_index]["thicknesses"] = widths
	var rebuilt := build(interior, result)
	if rebuilt.has("error"):
		return rebuilt
	return {"walls": result, "plans": rebuilt.plans, "polygons": rebuilt.walls, "regions": rebuilt.regions, "pieces": positions.size() + 1}


static func split_exterior(outline: PackedVector2Array, splits: Array, plans: Array, wall_thickness: float, edge_index: int, segment_index: int) -> Dictionary:
	var expanded := expand_outline(outline, splits)
	if expanded.has("error"):
		return expanded
	var current_segment := maxi(0, segment_index)
	var segment := []
	for index in expanded.edges.size():
		var edge: Dictionary = expanded.edges[index]
		if int(edge.edge) == edge_index and not edge.connector and maxi(0, int(edge.segment)) == current_segment:
			segment = [expanded.outline[index], expanded.outline[(index + 1) % expanded.outline.size()]]
			break
	if segment.is_empty():
		return {"error": "Das Außenwandteilstück ist nicht mehr verfügbar."}
	var length: float = segment[0].distance_to(segment[1])
	if length <= EPSILON * 10.0:
		return {"error": "Die Wand ist zu kurz zum Aufteilen."}
	var direction: Vector2 = (segment[1] - segment[0]).normalized()
	var positions := []
	for plan in plans:
		for candidate in [[plan.start, plan.source], [plan.end, plan.target]]:
			var source_direction: Vector2 = (candidate[1][1] - candidate[1][0]).normalized()
			if absf(source_direction.cross(direction)) > 0.001:
				continue
			var projected := Geometry2D.get_closest_point_to_segment(candidate[0], segment[0], segment[1])
			if candidate[0].distance_to(projected) > wall_thickness + EPSILON * 10.0:
				continue
			var fraction: float = (projected - segment[0]).dot(direction) / length
			if fraction > EPSILON * 10.0 / length and fraction < 1.0 - EPSILON * 10.0 / length:
				var duplicate := false
				for existing in positions:
					if absf(float(existing) - fraction) * length <= EPSILON * 10.0:
						duplicate = true
				if not duplicate:
					positions.append(fraction)
	if positions.is_empty():
		positions.append(0.5)
	positions.sort()
	var result := splits.duplicate(true)
	var config := {}
	for item in result:
		if int(item.edge) == edge_index:
			config = item
			break
	if config.is_empty():
		config = {"edge": edge_index, "cuts": [], "offsets": [0.0]}
		result.append(config)
	var cuts: Array = config.cuts
	var offsets: Array = config.offsets
	var base_direction := (outline[(edge_index + 1) % outline.size()] - outline[edge_index]).normalized()
	var base_length := outline[edge_index].distance_to(outline[(edge_index + 1) % outline.size()])
	for index in positions.size():
		var point: Vector2 = segment[0].lerp(segment[1], float(positions[index]))
		var fraction: float = (point - outline[edge_index]).dot(base_direction) / base_length
		if fraction <= 0.0 or fraction >= 1.0:
			return {"error": "Dieser Teilungspunkt liegt außerhalb der ursprünglichen Außenwand."}
		cuts.insert(current_segment + index, fraction)
		offsets.insert(current_segment + index + 1, offsets[current_segment])
	var checked := expand_outline(outline, result)
	if checked.has("error"):
		return checked
	return {"splits": result, "outline": checked.outline, "edges": checked.edges, "pieces": positions.size() + 1}


static func plan_wall(regions: Array[PackedVector2Array], cursor: Vector2, thickness: float, wall: Dictionary = {}, allow_junction := false, source_hint: Array = []) -> Dictionary:
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
			if not source_hint.is_empty():
				var hint_direction: Vector2 = (source_hint[1] - source_hint[0]).normalized()
				if absf((b - a).normalized().cross(hint_direction)) > 0.001 or absf((a - source_hint[0]).cross(hint_direction)) > EPSILON * 10.0:
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
	if not allow_junction and (nearest.distance_to(start_a) <= thickness * 0.5 + EPSILON or nearest.distance_to(start_b) <= thickness * 0.5 + EPSILON):
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
		if allow_junction and distance <= thickness + EPSILON:
			var next := (chosen_edge + 1) % region.size()
			var previous := (chosen_edge + region.size() - 1) % region.size()
			if edge_index == (next + 1) % region.size() and nearest.distance_to(region[next]) <= EPSILON * 10.0 and hit.distance_to(region[(next + 1) % region.size()]) <= EPSILON * 10.0:
				continue
			if edge_index == (previous + region.size() - 1) % region.size() and nearest.distance_to(region[chosen_edge]) <= EPSILON * 10.0 and hit.distance_to(region[previous]) <= EPSILON * 10.0:
				continue
		if distance > EPSILON and distance < nearest_hit:
			nearest_hit = distance
			end = hit
			target = [region[edge_index], region[(edge_index + 1) % region.size()]]
	if not is_finite(nearest_hit) or nearest_hit <= thickness + EPSILON:
		return {"error": "Keine geeignete gegenüberliegende Wand gefunden."}
	var cuts: Variant = wall.get("cuts", [])
	var offsets: Variant = wall.get("offsets", [])
	var widths: Variant = wall.get("thicknesses", [])
	if not cuts is Array or not offsets is Array or not widths is Array or cuts.size() > MAX_WALLS or (not cuts.is_empty() and offsets.size() != cuts.size() + 1) or (cuts.is_empty() and not offsets.is_empty()) or (not widths.is_empty() and widths.size() != offsets.size()):
		return {"error": "Die Wandteilstücke sind ungültig."}
	var last_cut := 0.0
	for cut in cuts:
		if not (cut is int or cut is float) or not is_finite(float(cut)) or float(cut) <= last_cut or float(cut) >= 1.0:
			return {"error": "Die Teilungspunkte der Wand sind ungültig."}
		last_cut = float(cut)
	for offset in offsets:
		if not (offset is int or offset is float) or not is_finite(float(offset)):
			return {"error": "Die Position eines Wandteilstücks ist ungültig."}
	for width in widths:
		if not (width is int or width is float) or not is_finite(float(width)) or float(width) <= 0.0 or float(width) > 1000.0:
			return {"error": "Die Dicke eines Wandteilstücks ist ungültig."}
	var polygon: PackedVector2Array
	var segments := []
	if cuts.is_empty():
		segments.append([nearest, end])
		var half_width := tangent * thickness * 0.5
		var extension := normal * EPSILON * 4.0
		polygon = PackedVector2Array([
			nearest - extension - half_width, nearest - extension + half_width,
			end + extension + half_width, end + extension - half_width,
		])
	else:
		var moved_start := nearest + tangent * float(offsets[0])
		var target_direction: Vector2 = target[1] - target[0]
		var moved_end: Variant = Geometry2D.line_intersects_line(end + tangent * float(offsets[-1]), normal, target[0], target_direction)
		if moved_end == null or moved_start.distance_to(Geometry2D.get_closest_point_to_segment(moved_start, start_a, start_b)) > EPSILON or moved_end.distance_to(Geometry2D.get_closest_point_to_segment(moved_end, target[0], target[1])) > EPSILON:
			return {"error": "Ein Wandteilstück würde seine Endwand verlassen."}
		var first_width := thickness if widths.is_empty() else float(widths[0])
		var last_width := thickness if widths.is_empty() else float(widths[-1])
		if not allow_junction and (moved_start.distance_to(start_a) <= first_width * 0.5 + EPSILON or moved_start.distance_to(start_b) <= first_width * 0.5 + EPSILON or moved_end.distance_to(target[0]) <= last_width * 0.5 + EPSILON or moved_end.distance_to(target[1]) <= last_width * 0.5 + EPSILON):
			return {"error": "Ein Wandteilstück würde über eine Endwand hinausgehen."}
		var path := PackedVector2Array([moved_start - normal * EPSILON * 4.0])
		var piece_start := moved_start
		for index in cuts.size():
			var middle_point: Vector2 = nearest.lerp(end, float(cuts[index]))
			path.append(middle_point + tangent * float(offsets[index]))
			segments.append([piece_start, middle_point + tangent * float(offsets[index])])
			var next_point := middle_point + tangent * float(offsets[index + 1])
			if path[-1].distance_to(next_point) > EPSILON:
				path.append(next_point)
			piece_start = next_point
		path.append(moved_end + normal * EPSILON * 4.0)
		segments.append([piece_start, moved_end])
		for path_index in range(1, path.size() - 2):
			var midpoint := (path[path_index] + path[path_index + 1]) * 0.5
			if not Geometry2D.is_point_in_polygon(midpoint, region):
				return {"error": "Die Wandverbindung würde den Raum verlassen."}
		if widths.is_empty():
			var expanded := Geometry2D.offset_polyline(path, thickness * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_SQUARE)
			if expanded.size() != 1:
				return {"error": "Die Wandteilstücke ergeben keine zusammenhängende Wand."}
			polygon = expanded[0]
		else:
			for index in segments.size():
				var lines := [segments[index]]
				if index > 0 and segments[index - 1][1].distance_to(segments[index][0]) > EPSILON:
					lines.push_front([segments[index - 1][1], segments[index][0]])
				for line_index in lines.size():
					var width: float = widths[index]
					if line_index == 0 and lines.size() == 2:
						width = maxf(width, float(widths[index - 1]))
					var stroke := Geometry2D.offset_polyline(PackedVector2Array(lines[line_index]), width * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_SQUARE)
					if stroke.size() != 1:
						return {"error": "Ein Wandteilstück konnte nicht aufgebaut werden."}
					if polygon.is_empty():
						polygon = stroke[0]
					else:
						var joined := Geometry2D.merge_polygons(polygon, stroke[0])
						if joined.size() != 1:
							return {"error": "Die Wandteilstücke ergeben keine zusammenhängende Wand."}
						polygon = joined[0]
	var clipped := Geometry2D.intersect_polygons(region, polygon)
	var remainder := Geometry2D.clip_polygons(region, polygon)
	if clipped.size() != 1 or remainder.size() != 2 or Geometry2D.triangulate_polygon(clipped[0]).is_empty():
		return {"error": "Die Wand kann diesen Raum an dieser Stelle nicht eindeutig teilen."}
	var next_regions: Array[PackedVector2Array] = regions.duplicate()
	next_regions.remove_at(chosen_region)
	for part in remainder:
		if part.size() < 3 or Geometry2D.triangulate_polygon(part).is_empty():
			return {"error": "Die Wand würde einen ungültigen Raum erzeugen."}
		next_regions.append(part)
	return {"regions": next_regions, "polygon": clipped[0], "source": [start_a, start_b], "target": target, "start": nearest, "end": end, "segments": segments}
