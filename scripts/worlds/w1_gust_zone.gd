extends WindZone
## W1 fix round 2 (feel critic r1: "the B3 gust leaks through the chimney wall"): a WindZone that never blows inside the
## listed world-space boxes. B3 swivels, so clipping its box would leave the plateau short at one end of the sweep;
## excluding the flue volume is exact at every angle. Built by w1_level.gd (W1-owned subclass, objects code unchanged).

var exclude_aabbs: Array[AABB] = []


func get_wind(at: Vector3) -> Vector3:
	for b in exclude_aabbs:
		if b.has_point(at):
			return Vector3.ZERO
	return super.get_wind(at)
