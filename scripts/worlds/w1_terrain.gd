class_name W1Terrain
extends RefCounted
## W1 heightfield access (data baked by game/assets/environment/w1/tools/w1_terrain.py).
## height(x, z) is a bilinear sample of the 0.5 m grid, identical to the rendered and collision mesh.

const BIN_PATH := "res://assets/environment/w1/w1_terrain.bin"
const LEVEL_PATH := "res://assets/environment/w1/w1_level.json"

static var _n := 0
static var _x0 := -60.0
static var _z0 := -60.0
static var _step := 0.5
static var _h := PackedFloat32Array()
static var _m := PackedByteArray()
static var _level: Dictionary = {}


static func ensure_loaded() -> bool:
	if _n > 0:
		return true
	var f := FileAccess.open(BIN_PATH, FileAccess.READ)
	if f == null:
		push_error("[W1Terrain] missing " + BIN_PATH)
		return false
	var magic := f.get_buffer(4).get_string_from_ascii()
	if magic != "W1T1":
		push_error("[W1Terrain] bad magic")
		return false
	_n = f.get_32()
	_x0 = f.get_float()
	_z0 = f.get_float()
	_step = f.get_float()
	_h = f.get_buffer(_n * _n * 4).to_float32_array()
	_m = f.get_buffer(_n * _n * 4)
	return true


static func level() -> Dictionary:
	if _level.is_empty():
		var txt := FileAccess.get_file_as_string(LEVEL_PATH)
		var d: Variant = JSON.parse_string(txt)
		if d is Dictionary:
			_level = d
	return _level


static func grid_n() -> int:
	ensure_loaded()
	return _n


static func grid_step() -> float:
	return _step


static func grid_origin() -> Vector2:
	return Vector2(_x0, _z0)


static func h_at(ix: int, iz: int) -> float:
	ix = clampi(ix, 0, _n - 1)
	iz = clampi(iz, 0, _n - 1)
	return _h[iz * _n + ix]


static func mask_at(ix: int, iz: int) -> Color:
	ix = clampi(ix, 0, _n - 1)
	iz = clampi(iz, 0, _n - 1)
	var i := (iz * _n + ix) * 4
	return Color(_m[i] / 255.0, _m[i + 1] / 255.0, _m[i + 2] / 255.0, _m[i + 3] / 255.0)


## Ground height, matching the triangulation used by the mesh (two triangles per cell, split along the
## diagonal from (i, j) to (i+1, j+1)).
static func height(x: float, z: float) -> float:
	if not ensure_loaded():
		return 0.0
	var fx := (x - _x0) / _step
	var fz := (z - _z0) / _step
	var ix := clampi(int(floor(fx)), 0, _n - 2)
	var iz := clampi(int(floor(fz)), 0, _n - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var h00 := h_at(ix, iz)
	var h10 := h_at(ix + 1, iz)
	var h01 := h_at(ix, iz + 1)
	var h11 := h_at(ix + 1, iz + 1)
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


static func mask(x: float, z: float) -> Color:
	if not ensure_loaded():
		return Color(0, 0, 0, 0)
	var ix := clampi(int(round((x - _x0) / _step)), 0, _n - 1)
	var iz := clampi(int(round((z - _z0) / _step)), 0, _n - 1)
	return mask_at(ix, iz)


static func normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height(x + e, z) - height(x - e, z)
	var dz := height(x, z + e) - height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


## Distance to the stream centreline and the downstream tangent at the nearest point.
static func stream_info(x: float, z: float) -> Dictionary:
	var s: Array = level().get("_derived", {}).get("stream_samples", [])
	var best := 1e9
	var tan := Vector3.RIGHT
	for i in range(s.size() - 1):
		var a := Vector2(s[i][0], s[i][1])
		var b := Vector2(s[i + 1][0], s[i + 1][1])
		var ab := b - a
		var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := Vector2(x, z).distance_to(a + ab * t)
		if d < best:
			best = d
			var tn := ab.normalized()
			tan = Vector3(tn.x, 0, tn.y)
	return {"distance": best, "tangent": tan}


## Minimum distance from (x, z) to any lane centreline.
static func path_distance(x: float, z: float) -> float:
	var paths: Dictionary = level().get("_derived", {}).get("path_samples", {})
	var best := 1e9
	for k in paths:
		var s: Array = paths[k]
		for i in range(s.size() - 1):
			var a := Vector2(s[i][0], s[i][2])
			var b := Vector2(s[i + 1][0], s[i + 1][2])
			var ab := b - a
			var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			best = minf(best, Vector2(x, z).distance_to(a + ab * t))
	return best
