extends RefCounted

const BLOCK_SIZE := 500.0
const WINDOW_RADIUS := 1
const METERS_PER_DEGREE := 111320.0


static func block_for_position(position: Vector2, map_scale: float = 1.0) -> Vector2i:
	if not position.is_finite() or not is_finite(map_scale) or map_scale <= 0.0:
		return Vector2i.ZERO
	var meters := position / map_scale
	return Vector2i(floori((meters.x + BLOCK_SIZE / 2.0) / BLOCK_SIZE), floori((meters.y + BLOCK_SIZE / 2.0) / BLOCK_SIZE))


static func blocks_around(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(center.x - WINDOW_RADIUS, center.x + WINDOW_RADIUS + 1):
		for z in range(center.y - WINDOW_RADIUS, center.y + WINDOW_RADIUS + 1):
			result.append(Vector2i(x, z))
	return result


static func new_blocks(previous: Array[Vector2i], center: Vector2i) -> Array[Vector2i]:
	var existing := {}
	for block in previous:
		existing[block] = true
	var result: Array[Vector2i] = []
	for block in blocks_around(center):
		if not existing.has(block):
			result.append(block)
	return result


static func block_origin(origin: Array, block: Vector2i) -> Array:
	var latitude := float(origin[0]) - float(block.y) * BLOCK_SIZE / METERS_PER_DEGREE
	var longitude_scale := METERS_PER_DEGREE * cos(deg_to_rad(float(origin[0])))
	var longitude := float(origin[1]) + float(block.x) * BLOCK_SIZE / longitude_scale
	return [latitude, longitude]


static func block_bounds(origin: Array, block: Vector2i) -> Array:
	var center := block_origin(origin, block)
	var latitude_delta := BLOCK_SIZE / (2.0 * METERS_PER_DEGREE)
	var longitude_delta := BLOCK_SIZE / (2.0 * METERS_PER_DEGREE * cos(deg_to_rad(float(origin[0]))))
	return [
		float(center[0]) - latitude_delta,
		float(center[1]) - longitude_delta,
		float(center[0]) + latitude_delta,
		float(center[1]) + longitude_delta,
	]


static func key(block: Vector2i) -> String:
	return "%d_%d" % [block.x, block.y]
