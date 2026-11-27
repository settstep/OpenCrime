extends RefCounted

const EPSILON := 0.001
const MAX_SNAP_DISTANCE := 1.0
const MAX_WALLS := 1000


static func build(interior: PackedVector2Array, walls: Array) -> Dictionary:
	if walls.size() > MAX_WALLS or interior.size() < 3 or Geometry2D.triangulate_polygon(interior).is_empty():
		return {"error": "Die Innenwände sind ungültig."}
	var regions: Array[PackedVector2Array] = [interior]
	var built := []
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
	return {"regions": regions, "walls": built}


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
	return {"regions": next_regions, "polygon": clipped[0], "source": [start_a, start_b], "start": nearest, "end": end}
