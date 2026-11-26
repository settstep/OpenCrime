extends RefCounted

const BLOCK_SIZE := 1000.0
const WINDOW_RADIUS := 1
const UTM_SEMI_MAJOR_AXIS := 6378137.0
const UTM_FLATTENING := 1.0 / 298.257223563
const UTM_ECCENTRICITY_SQUARED := UTM_FLATTENING * (2.0 - UTM_FLATTENING)
const UTM_SECOND_ECCENTRICITY_SQUARED := UTM_ECCENTRICITY_SQUARED / (1.0 - UTM_ECCENTRICITY_SQUARED)
const UTM_SCALE := 0.9996
const UTM_FALSE_EASTING := 500000.0
const UTM_FALSE_NORTHING := 10000000.0


static func zone_for_origin(origin: Array) -> int:
	var longitude := clampf(float(origin[1]), -180.0, 180.0)
	if longitude >= 180.0:
		return 60
	return clampi(floori((longitude + 180.0) / 6.0) + 1, 1, 60)


static func is_northern_hemisphere(origin: Array) -> bool:
	return float(origin[0]) >= 0.0


static func project(coordinate: Array, zone: int, northern_hemisphere: bool) -> Array:
	# Keep projected coordinates as 64-bit floats; Vector2 loses meter-scale precision at UTM northings.
	if coordinate.size() != 2 or zone < 1 or zone > 60:
		return []
	var latitude := deg_to_rad(float(coordinate[0]))
	var longitude := deg_to_rad(float(coordinate[1]))
	var central_meridian := deg_to_rad(float(zone - 1) * 6.0 - 180.0 + 3.0)
	var longitude_delta := wrapf(longitude - central_meridian, -PI, PI)
	var sin_latitude := sin(latitude)
	var cos_latitude := cos(latitude)
	var tan_latitude := tan(latitude)
	var n := UTM_SEMI_MAJOR_AXIS / sqrt(1.0 - UTM_ECCENTRICITY_SQUARED * sin_latitude * sin_latitude)
	var t := tan_latitude * tan_latitude
	var c := UTM_SECOND_ECCENTRICITY_SQUARED * cos_latitude * cos_latitude
	var a := cos_latitude * longitude_delta
	var e2 := UTM_ECCENTRICITY_SQUARED
	var meridian := UTM_SEMI_MAJOR_AXIS * (
		(1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0) * latitude
		- (3.0 * e2 / 8.0 + 3.0 * e2 * e2 / 32.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(2.0 * latitude)
		+ (15.0 * e2 * e2 / 256.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(4.0 * latitude)
		- (35.0 * e2 * e2 * e2 / 3072.0) * sin(6.0 * latitude)
	)
	var easting := UTM_FALSE_EASTING + UTM_SCALE * n * (
		a
		+ (1.0 - t + c) * pow(a, 3.0) / 6.0
		+ (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * UTM_SECOND_ECCENTRICITY_SQUARED) * pow(a, 5.0) / 120.0
		+ (61.0 - 479.0 * t + 179.0 * t * t - t * t * t) * pow(a, 7.0) / 5040.0
	)
	var northing := UTM_SCALE * (
		meridian
		+ n * tan_latitude * (
			a * a / 2.0
			+ (5.0 - t + 9.0 * c + 4.0 * c * c) * pow(a, 4.0) / 24.0
			+ (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * UTM_SECOND_ECCENTRICITY_SQUARED) * pow(a, 6.0) / 720.0
			+ (1385.0 - 3111.0 * t + 543.0 * t * t - t * t * t) * pow(a, 8.0) / 40320.0
		)
	)
	if not northern_hemisphere:
		northing += UTM_FALSE_NORTHING
	return [easting, northing]


static func unproject(position: Array, zone: int, northern_hemisphere: bool) -> Array:
	if position.size() != 2 or zone < 1 or zone > 60:
		return []
	var easting := float(position[0]) - UTM_FALSE_EASTING
	var northing := float(position[1]) if northern_hemisphere else float(position[1]) - UTM_FALSE_NORTHING
	var e2 := UTM_ECCENTRICITY_SQUARED
	var e1 := (1.0 - sqrt(1.0 - e2)) / (1.0 + sqrt(1.0 - e2))
	var meridian := northing / UTM_SCALE
	var mu := meridian / (UTM_SEMI_MAJOR_AXIS * (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0))
	var phi1 := (
		mu
		+ (3.0 * e1 / 2.0 - 27.0 * pow(e1, 3.0) / 32.0) * sin(2.0 * mu)
		+ (21.0 * e1 * e1 / 16.0 - 55.0 * pow(e1, 4.0) / 32.0) * sin(4.0 * mu)
		+ (151.0 * pow(e1, 3.0) / 96.0) * sin(6.0 * mu)
		+ (1097.0 * pow(e1, 4.0) / 512.0) * sin(8.0 * mu)
	)
	var sin_phi1 := sin(phi1)
	var cos_phi1 := cos(phi1)
	var tan_phi1 := tan(phi1)
	var n1 := UTM_SEMI_MAJOR_AXIS / sqrt(1.0 - e2 * sin_phi1 * sin_phi1)
	var r1 := UTM_SEMI_MAJOR_AXIS * (1.0 - e2) / pow(1.0 - e2 * sin_phi1 * sin_phi1, 1.5)
	var t1 := tan_phi1 * tan_phi1
	var c1 := UTM_SECOND_ECCENTRICITY_SQUARED * cos_phi1 * cos_phi1
	var d := easting / (n1 * UTM_SCALE)
	var latitude := phi1 - n1 * tan_phi1 / r1 * (
		d * d / 2.0
		- (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * UTM_SECOND_ECCENTRICITY_SQUARED) * pow(d, 4.0) / 24.0
		+ (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * UTM_SECOND_ECCENTRICITY_SQUARED - 3.0 * c1 * c1) * pow(d, 6.0) / 720.0
		- (1385.0 + 3633.0 * t1 + 4095.0 * t1 * t1 + 1575.0 * t1 * t1 * t1) * pow(d, 8.0) / 40320.0
	)
	var longitude := deg_to_rad(float(zone - 1) * 6.0 - 180.0 + 3.0) + (
		d
		- (1.0 + 2.0 * t1 + c1) * pow(d, 3.0) / 6.0
		+ (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * UTM_SECOND_ECCENTRICITY_SQUARED + 24.0 * t1 * t1) * pow(d, 5.0) / 120.0
		- (61.0 + 662.0 * t1 + 1320.0 * t1 * t1 + 720.0 * t1 * t1 * t1) * pow(d, 7.0) / 5040.0
	) / cos_phi1
	return [rad_to_deg(latitude), rad_to_deg(longitude)]


static func block_for_position(position: Vector2, map_scale: float = 1.0, origin: Array = [0.0, 0.0]) -> Vector2i:
	if not position.is_finite() or not is_finite(map_scale) or map_scale <= 0.0 or origin.size() != 2:
		return Vector2i.ZERO
	var projected_origin := project(origin, zone_for_origin(origin), is_northern_hemisphere(origin))
	if projected_origin.size() != 2:
		return Vector2i.ZERO
	return Vector2i(
		floori((projected_origin[0] + position.x / map_scale) / BLOCK_SIZE),
		floori((projected_origin[1] - position.y / map_scale) / BLOCK_SIZE)
	)


static func block_for_coordinate(coordinate: Array, origin: Array) -> Vector2i:
	if coordinate.size() != 2 or origin.size() != 2:
		return Vector2i.ZERO
	var position := project(coordinate, zone_for_origin(origin), is_northern_hemisphere(origin))
	if position.size() != 2:
		return Vector2i.ZERO
	return Vector2i(floori(position[0] / BLOCK_SIZE), floori(position[1] / BLOCK_SIZE))


static func block_at_origin(origin: Array) -> Vector2i:
	return block_for_coordinate(origin, origin)


static func block_local_center(origin: Array, block: Vector2i) -> Vector2:
	var zone := zone_for_origin(origin)
	var projected_origin := project(origin, zone, is_northern_hemisphere(origin))
	var center := [(float(block.x) + 0.5) * BLOCK_SIZE, (float(block.y) + 0.5) * BLOCK_SIZE]
	if projected_origin.size() != 2:
		return Vector2.ZERO
	return Vector2(center[0] - projected_origin[0], projected_origin[1] - center[1])


static func block_origin(origin: Array, block: Vector2i) -> Array:
	var zone := zone_for_origin(origin)
	return unproject(
		[(float(block.x) + 0.5) * BLOCK_SIZE, (float(block.y) + 0.5) * BLOCK_SIZE],
		zone,
		is_northern_hemisphere(origin)
	)


static func block_bounds(origin: Array, block: Vector2i) -> Array:
	var zone := zone_for_origin(origin)
	var southwest := unproject([float(block.x) * BLOCK_SIZE, float(block.y) * BLOCK_SIZE], zone, is_northern_hemisphere(origin))
	var southeast := unproject([float(block.x + 1) * BLOCK_SIZE, float(block.y) * BLOCK_SIZE], zone, is_northern_hemisphere(origin))
	var northwest := unproject([float(block.x) * BLOCK_SIZE, float(block.y + 1) * BLOCK_SIZE], zone, is_northern_hemisphere(origin))
	var northeast := unproject([float(block.x + 1) * BLOCK_SIZE, float(block.y + 1) * BLOCK_SIZE], zone, is_northern_hemisphere(origin))
	if southwest.is_empty() or southeast.is_empty() or northwest.is_empty() or northeast.is_empty():
		return []
	var latitudes := [southwest[0], southeast[0], northwest[0], northeast[0]]
	var longitudes := [southwest[1], southeast[1], northwest[1], northeast[1]]
	latitudes.sort()
	longitudes.sort()
	return [latitudes[0], longitudes[0], latitudes[latitudes.size() - 1], longitudes[longitudes.size() - 1]]


static func blocks_around(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(center.x - WINDOW_RADIUS, center.x + WINDOW_RADIUS + 1):
		for northing in range(center.y - WINDOW_RADIUS, center.y + WINDOW_RADIUS + 1):
			result.append(Vector2i(x, northing))
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


static func tile_id(block: Vector2i, origin: Array) -> String:
	var northing_index := block.y
	if not is_northern_hemisphere(origin):
		northing_index -= int(UTM_FALSE_NORTHING / BLOCK_SIZE)
	return "utm%d_%d_%d" % [zone_for_origin(origin), block.x, northing_index]


static func key(block: Vector2i) -> String:
	return "%d_%d" % [block.x, block.y]
