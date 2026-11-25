extends Node3D
## MoveLab: Mr. Mak's movement test course (night 01, player workstream).
## Geometry is built at load time from exact numbers so every distance is calibrated; the four
## story cameras StoryCam_A..D are fixed nodes in MoveLab.tscn (A = side profile of the jump track).
## Layout (metres, Y up, forward -Z, spawn at the origin):
##   run track x -2..2 (z 0..-40)        reversal strip x 5..9
##   jump-gap ladder z 8..12, 1 m high platforms, gaps 2..9 m along +X
##   step/ledge blocks 0.3..4.5 m at z -6..-10, x 12..41.5    stairs x 12..16 (0.25 m risers)
##   slopes 15/30/50 deg at x 20..38 rising toward -Z           chimneys 2.5 m and 3.5 m at x -22..-7.5
##   narrow beam x -26 (0.3 m), tunnels with 2.0 m and 1.0 m clearance at x -6..-3
##   moving, lifting and rotating platforms x 44..66; vine pole (48, 0, 4); bounce pad (56, 0, 6)
##   wind zone (64, 0, 4); hot plate hazard (14, 0, 2); punching dummies (-6, 0, 3) and (-8, 0, 3)
##   sniff targets at (-28, 0, 26) and (66, 0, 26); kill plane at kill_y.
## Dev argument --render-fps=<n> caps the render loop (used by the consistency test).

@export var kill_y := -25.0
@export var world_id := "TEST"
@export var display_name := "MoveLab"

const GRID_SHADER := preload("res://scenes/tests/lab_grid.gdshader")

var _geo: Node3D
var _mats := {}
var _hud_label: Label
var _player: Node3D


class Mover:
	extends AnimatableBody3D
	var mode := "line"
	var axis := Vector3.RIGHT
	var amplitude := 4.0
	var period := 6.0
	var spin_deg := 30.0
	var _origin := Vector3.ZERO
	var _t := 0.0

	func _ready() -> void:
		sync_to_physics = true
		_origin = position

	func _physics_process(delta: float) -> void:
		_t += delta
		if mode == "line":
			position = _origin + axis * amplitude * sin(_t * TAU / period)
		else:
			rotation.y = wrapf(rotation.y + deg_to_rad(spin_deg) * delta, -PI, PI)


class Pole:
	extends Area3D
	var pole_radius := 0.14
	var height := 9.0

	func _ready() -> void:
		add_to_group("climbable")

	func get_climb_axis() -> Vector3:
		return global_basis.y.normalized()

	func get_climb_bottom() -> Vector3:
		return global_position

	func get_climb_top() -> Vector3:
		return global_position + global_basis.y.normalized() * height


class Wind:
	extends Area3D
	var wind := Vector3(0.0, 0.0, -5.0)

	func _ready() -> void:
		add_to_group("wind_zone")

	func get_wind(_pos: Vector3) -> Vector3:
		return wind


class Dummy:
	extends StaticBody3D
	var hits := 0
	var _wobble := 0.0
	var _wobble_v := 0.0
	var vis: Node3D
	var label: Label3D
	var _label_t := 0.0

	func hit_by_player(kind: String, from_position: Vector3) -> bool:
		hits += 1
		var away := global_position - from_position
		away.y = 0.0
		var dir := 1.0 if away.dot(Vector3.BACK) >= 0.0 else -1.0
		_wobble_v += 7.0 * dir
		if label != null:
			label.text = kind.to_upper() + "!"
			_label_t = 0.8
		print("[MoveLab] dummy %s hit by %s (#%d)" % [name, kind, hits])
		return true

	func _process(delta: float) -> void:
		var a := -110.0 * _wobble - 5.0 * _wobble_v
		_wobble_v += a * delta
		_wobble += _wobble_v * delta
		if vis != null:
			vis.rotation.x = clampf(_wobble * 0.6, -0.8, 0.8)
		_label_t -= delta
		if label != null:
			label.visible = _label_t > 0.0
			label.position.y = 2.1 + (0.8 - _label_t) * 0.6


func _ready() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev != null and bool(dev.call("has_arg", "render-fps")):
		Engine.max_fps = int(str(dev.call("arg", "render-fps", "0")))
	_player = get_node_or_null("Player") as Node3D
	if dev != null and bool(dev.call("has_arg", "lab-no-ledge-grab")):
		# Movement test "ledge_opt_out": every lab body opts out of ledge grabs (group no_ledge_grab).
		call_deferred("_opt_out_ledges", self)
	if dev != null and bool(dev.call("has_arg", "lab-cocoa")):
		# Movement test "cocoa_splash": a hot-chocolate HazardVolume (objects track) across the run track.
		var hp := "res://scenes/objects/HazardVolume.tscn"
		if ResourceLoader.exists(hp):
			var hv := (load(hp) as PackedScene).instantiate() as Node3D
			hv.set("look", 1)   # HazardVolume.Look.HOT_CHOCOLATE
			hv.set("size", Vector3(2.0, 1.0, 3.0))
			hv.position = Vector3(-12.0, 0.0, 20.0)
			add_child(hv)
	_build_environment()
	_geo = Node3D.new()
	_geo.name = "Geometry"
	add_child(_geo)
	_build_course()
	_build_hud()


func _process(_delta: float) -> void:
	if _hud_label == null or _player == null:
		return
	var v: Vector3 = _player.get("velocity")
	var st: Variant = _player.get("state")
	_hud_label.text = "MoveLab  |  %s  |  %.2f m/s  |  height %.2f m" % [str(st), Vector2(v.x, v.z).length(), _player.global_position.y]


# ------------------------------------------------------------------ building

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.47, 0.88)
	sky_mat.sky_horizon_color = Color(0.72, 0.83, 0.95)
	sky_mat.ground_bottom_color = Color(0.32, 0.36, 0.3)
	sky_mat.ground_horizon_color = Color(0.8, 0.86, 0.9)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.95)
	env.fog_density = 0.0007
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


func _mat(key: String, c: Color, grid := true) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if grid:
		var sm := ShaderMaterial.new()
		sm.shader = GRID_SHADER
		sm.set_shader_parameter("base_color", c)
		m = sm
	else:
		var st := StandardMaterial3D.new()
		st.albedo_color = c
		st.roughness = 0.85
		m = st
	_mats[key] = m
	return m


func _box(n: String, size: Vector3, center: Vector3, mat: Material, rot_deg := Vector3.ZERO, collide := true) -> Node3D:
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		holder = body
	else:
		holder = Node3D.new()
	holder.name = n
	holder.position = center
	holder.rotation_degrees = rot_deg
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	holder.add_child(mi)
	_geo.add_child(holder)
	return holder


func _label(text: String, pos: Vector3, rot_deg := Vector3.ZERO, size := 72, color := Color(1, 1, 1)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot_deg
	l.font_size = size
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.12, 0.1, 0.12, 0.9)
	_geo.add_child(l)
	return l


func _ground_label(text: String, pos: Vector3, size := 72) -> void:
	_label(text, Vector3(pos.x, 0.02, pos.z), Vector3(-90.0, 0.0, 0.0), size)


func _ramp(n: String, angle_deg: float, rise: float, x0: float, x1: float, z0: float, mat: Material) -> float:
	var th := 0.6
	var a := deg_to_rad(angle_deg)
	var run := rise / tan(a)
	var slope_len := sqrt(run * run + rise * rise)
	var ext := 0.8
	var hyp := slope_len + ext
	var normal := Vector3(0.0, cos(a), sin(a))
	var along := Vector3(0.0, sin(a), -cos(a))
	var surf_center := Vector3((x0 + x1) * 0.5, rise * 0.5, z0 - run * 0.5) - along * ext * 0.5
	var center := surf_center - normal * th * 0.5
	_box(n, Vector3(x1 - x0, th, hyp), center, mat, Vector3(angle_deg, 0.0, 0.0))
	return run


func _build_course() -> void:
	var m_ground := _mat("ground", Color(0.42, 0.64, 0.30))
	var m_sand := _mat("sand", Color(0.93, 0.84, 0.62), false)
	var m_plat := _mat("plat", Color(0.9, 0.56, 0.42))
	var m_block := _mat("block", Color(0.56, 0.72, 0.93))
	var m_wood := _mat("wood", Color(0.78, 0.6, 0.4))
	var m_ramp := _mat("ramp", Color(0.72, 0.63, 0.88))
	var m_brick := _mat("brick", Color(0.8, 0.47, 0.36))
	var m_stone := _mat("stone", Color(0.72, 0.72, 0.75))
	var m_gold := _mat("gold", Color(0.97, 0.8, 0.36))

	# Ground slab: x -32..72, z -62..32, top at y = 0.
	_box("Ground", Vector3(104.0, 1.0, 94.0), Vector3(20.0, -0.5, -15.0), m_ground)

	# Run track and reversal strip (visual only) with distance numbers every 5 m.
	_box("RunTrack", Vector3(4.0, 0.02, 40.0), Vector3(0.0, 0.006, -20.0), m_sand, Vector3.ZERO, false)
	_box("ReversalStrip", Vector3(4.0, 0.02, 30.0), Vector3(7.0, 0.006, -15.0), m_sand, Vector3.ZERO, false)
	for d in range(0, 45, 5):
		_ground_label("%d m" % d, Vector3(-2.9, 0.0, -float(d)), 56)
	_ground_label("RUN", Vector3(0.0, 0.0, 1.2), 90)
	_ground_label("REVERSE", Vector3(7.0, 0.0, 1.2), 72)

	# Jump-gap ladder along +X, 1 m high platforms, gaps 2..9 m.
	var x := -25.0
	for i in 4:
		_box("LadderStep%d" % i, Vector3(1.0, 0.25 * (i + 1), 4.0), Vector3(-28.5 + i, 0.125 * (i + 1), 10.0), m_wood)
	_box("Gap_P0", Vector3(3.0, 1.0, 4.0), Vector3(x + 1.5, 0.5, 10.0), m_plat)
	x += 3.0
	for g in range(2, 10):
		_label("%d m" % g, Vector3(x + g * 0.5, 2.6, 10.0), Vector3.ZERO, 96, Color(1.0, 0.95, 0.75))
		x += g
		_box("Gap_P%d" % (g - 1), Vector3(3.0, 1.0, 4.0), Vector3(x + 1.5, 0.5, 10.0), m_plat)
		x += 3.0

	# Steps and ledges 0.3..4.5 m.
	var heights := [0.3, 0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]
	for i in heights.size():
		var h: float = heights[i]
		var bx := 12.0 + i * 3.0 + 1.25
		_box("Ledge_%.1f" % h, Vector3(2.5, h, 4.0), Vector3(bx, h * 0.5, -8.0), m_block if i % 2 == 0 else m_stone)
		_ground_label("%.1f m" % h, Vector3(bx, 0.0, -5.2), 60)
	# A 2 m ledge with blocked headroom (slab 0.8 m above its top).
	_box("Ledge_blocked", Vector3(2.5, 2.0, 4.0), Vector3(44.0, 1.0, -8.0), m_stone)
	_box("Ledge_blocked_roof", Vector3(2.5, 0.3, 4.0), Vector3(44.0, 2.95, -8.6), m_brick)
	_ground_label("blocked", Vector3(44.0, 0.0, -5.2), 56)

	# Stairs: 10 risers of 0.25 m, 0.5 m treads, then a landing.
	for i in 10:
		var top := 0.25 * (i + 1)
		_box("Stair%d" % i, Vector3(4.0, top, 0.5), Vector3(14.0, top * 0.5, -14.25 - 0.5 * i), m_wood)
	_box("StairLanding", Vector3(4.0, 2.5, 4.0), Vector3(14.0, 1.25, -21.0), m_wood)
	_ground_label("STAIRS", Vector3(14.0, 0.0, -12.6), 64)

	# Slopes rising 3 m toward -Z.
	var ramps := [[15.0, 20.0, 24.0], [30.0, 27.0, 31.0], [50.0, 34.0, 38.0]]
	for r in ramps:
		var ang: float = r[0]
		var x0: float = r[1]
		var x1: float = r[2]
		var run := _ramp("Ramp%d" % int(ang), ang, 3.0, x0, x1, -14.0, m_ramp)
		_box("RampTop%d" % int(ang), Vector3(x1 - x0, 3.0, 3.0), Vector3((x0 + x1) * 0.5, 1.5, -14.0 - run - 1.5), m_ramp)
		_ground_label("%d°" % int(ang), Vector3((x0 + x1) * 0.5, 0.0, -12.4), 80)

	# Chimneys for wall kicks: inner gaps 2.5 m and 3.5 m, 14 m tall.
	_box("ChimneyA1", Vector3(1.0, 14.0, 4.0), Vector3(-21.5, 7.0, -12.0), m_brick)
	_box("ChimneyA2", Vector3(1.0, 14.0, 4.0), Vector3(-18.0, 7.0, -12.0), m_brick)
	_box("ChimneyB1", Vector3(1.0, 14.0, 4.0), Vector3(-12.5, 7.0, -12.0), m_brick)
	_box("ChimneyB2", Vector3(1.0, 14.0, 4.0), Vector3(-8.0, 7.0, -12.0), m_brick)
	# Camera-hint zones (group camera_zone): a side-on, pulled-back view of each chimney climb.
	_camera_zone("CamZoneA", Vector3(-19.75, 7.0, -12.0), Vector3(2.5, 14.0, 4.0), 0.0, 4.0, 8.0)
	_camera_zone("CamZoneB", Vector3(-10.25, 7.0, -12.0), Vector3(3.5, 14.0, 4.0), 0.0, 4.0, 8.5)
	_ground_label("2.5 m", Vector3(-19.75, 0.0, -8.6), 64)
	_ground_label("3.5 m", Vector3(-10.25, 0.0, -8.6), 64)

	# Narrow beam 0.3 m wide, 1 m high, 10 m long.
	_box("BeamStart", Vector3(2.0, 1.0, 2.0), Vector3(-26.0, 0.5, -19.0), m_wood)
	_box("Beam", Vector3(0.3, 1.0, 10.0), Vector3(-26.0, 0.5, -25.0), m_wood)
	_box("BeamEnd", Vector3(2.0, 1.0, 2.0), Vector3(-26.0, 0.5, -31.0), m_wood)
	_ground_label("BEAM 0.3 m", Vector3(-26.0, 0.0, -16.8), 56)

	# Tunnels: 2.0 m clearance (jump bonk) then 1.0 m clearance (crouch).
	_box("TunnelWallW", Vector3(0.5, 2.4, 8.0), Vector3(-6.25, 1.2, -10.0), m_stone)
	_box("TunnelWallE", Vector3(0.5, 2.4, 8.0), Vector3(-2.75, 1.2, -10.0), m_stone)
	_box("TunnelRoofHigh", Vector3(4.0, 0.4, 4.0), Vector3(-4.5, 2.2, -8.0), m_stone)
	_box("TunnelRoofLow", Vector3(4.0, 1.4, 4.0), Vector3(-4.5, 1.7, -12.0), m_stone)
	_ground_label("2.0 m", Vector3(-4.5, 0.0, -5.4), 52)

	# Moving platforms.
	_box("MoverStart", Vector3(2.0, 1.75, 3.0), Vector3(45.0, 0.875, -8.0), m_stone)
	var mv := _mover("MoverX", Vector3(3.0, 0.5, 3.0), Vector3(53.0, 1.5, -8.0), m_gold)
	mv.axis = Vector3.RIGHT
	mv.amplitude = 5.0
	mv.period = 6.0
	var lift := _mover("Elevator", Vector3(3.0, 0.5, 3.0), Vector3(60.0, 3.25, -16.0), m_gold)
	lift.axis = Vector3.UP
	lift.amplitude = 3.0
	lift.period = 8.0
	_box("ElevatorTop", Vector3(4.0, 0.5, 4.0), Vector3(64.0, 5.75, -16.0), m_stone)
	var disc := _mover("SpinDisc", Vector3.ZERO, Vector3(52.0, 0.75, -21.0), m_gold, 3.5)
	disc.mode = "spin"
	disc.spin_deg = 35.0

	# Vine pole with a perch.
	_pole(Vector3(48.0, 0.0, 4.0), 9.0)
	_box("PolePerch", Vector3(3.0, 0.4, 3.0), Vector3(50.2, 8.3, 4.0), m_wood)

	# Bounce pad stand-in and a high shelf.
	var pad := _cylinder_body("BouncePad", 1.0, 0.3, Vector3(56.0, 0.15, 6.0), _mat("pad", Color(0.95, 0.42, 0.55), false))
	pad.add_to_group("bouncy")
	pad.set_meta("bounce_velocity", 17.0)
	_box("BounceShelf", Vector3(3.0, 0.5, 3.0), Vector3(56.0, 4.5, 10.0), m_stone)
	_ground_label("BOUNCE", Vector3(56.0, 0.0, 8.2), 56)

	# Wind zone stand-in.
	var wind := Wind.new()
	wind.name = "WindZone"
	wind.collision_layer = 128
	wind.collision_mask = 0
	wind.position = Vector3(64.0, 2.5, 4.0)
	var wcs := CollisionShape3D.new()
	var wsh := BoxShape3D.new()
	wsh.size = Vector3(6.0, 5.0, 10.0)
	wcs.shape = wsh
	wind.add_child(wcs)
	var wmi := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = wsh.size
	wmi.mesh = wbm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.7, 0.85, 1.0, 0.16)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmi.material_override = wmat
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wind.add_child(wmi)
	_geo.add_child(wind)
	_ground_label("WIND", Vector3(64.0, 0.0, 9.6), 56)

	# Hot plate hazard.
	var hz := Area3D.new()
	hz.name = "HotPlate"
	hz.collision_layer = 16
	hz.collision_mask = 0
	hz.position = Vector3(14.0, 0.0, 2.0)
	hz.add_to_group("hazard")
	hz.set_meta("damage", 1)
	hz.set_meta("knockback_up", 7.5)
	var hcs := CollisionShape3D.new()
	var hsh := BoxShape3D.new()
	hsh.size = Vector3(2.0, 0.6, 2.0)
	hcs.shape = hsh
	hcs.position = Vector3(0.0, 0.3, 0.0)
	hz.add_child(hcs)
	var hmi := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(2.0, 0.04, 2.0)
	hmi.mesh = hbm
	hmi.position = Vector3(0.0, 0.02, 0.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.32, 0.12)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.3, 0.05)
	hmat.emission_energy_multiplier = 1.4
	hmi.material_override = hmat
	hz.add_child(hmi)
	_geo.add_child(hz)
	_ground_label("HOT", Vector3(14.0, 0.0, 3.6), 52)

	# Punching dummies.
	_dummy("DummyA", Vector3(-6.0, 0.0, 3.0))
	_dummy("DummyB", Vector3(-8.0, 0.0, 3.0))

	# Bonk wall (hero pass 2): a long jump from the run-up at (-14, 0, 13) heading +Z hits it above 8.9 m/s.
	_box("BonkWall", Vector3(4.0, 4.0, 1.0), Vector3(-14.0, 2.0, 27.0), m_plat)
	_ground_label("BONK", Vector3(-14.0, 0.0, 14.5), 52)

	# Sniff targets (golden truffle stand-ins), half hidden behind bushes.
	_truffle(Vector3(-28.0, 0.0, 26.0))
	_truffle(Vector3(66.0, 0.0, 26.0))


func _camera_zone(n: String, center: Vector3, size: Vector3, yaw_deg: float, pitch_deg: float, dist: float) -> void:
	var a := Area3D.new()
	a.name = n
	a.collision_layer = 128      # layer 8, trigger
	a.collision_mask = 0
	a.monitoring = false
	a.add_to_group("camera_zone")
	a.set_meta("camera_yaw_deg", yaw_deg)
	a.set_meta("camera_pitch_deg", pitch_deg)
	a.set_meta("camera_distance", dist)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	_geo.add_child(a)
	a.position = center


func _mover(n: String, size: Vector3, pos: Vector3, mat: Material, radius := 0.0) -> Mover:
	var mv := Mover.new()
	mv.name = n
	mv.collision_layer = 1
	mv.collision_mask = 0
	mv.position = pos
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	if radius > 0.0:
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 0.5
		cs.shape = cyl
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.5
		cm.radial_segments = 40
		mi.mesh = cm
	else:
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	mi.material_override = mat
	mv.add_child(cs)
	mv.add_child(mi)
	_geo.add_child(mv)
	return mv


func _cylinder_body(n: String, r: float, h: float, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	body.collision_layer = 1
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 36
	mi.mesh = cm
	mi.material_override = mat
	body.add_child(mi)
	_geo.add_child(body)
	return body


func _pole(base: Vector3, height: float) -> void:
	var pole := Pole.new()
	pole.name = "VinePole"
	pole.height = height
	pole.collision_layer = 128
	pole.collision_mask = 0
	pole.position = base
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.55
	sh.height = height
	cs.shape = sh
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	pole.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = Vector3(0.0, height * 0.5, 0.0)
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.36, 0.62, 0.26)
	vm.roughness = 0.8
	mi.material_override = vm
	pole.add_child(mi)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.45, 0.75, 0.3)
	for i in 6:
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.14
		lm.mesh = sm
		lm.material_override = leaf
		var ang := i * 2.1
		lm.position = Vector3(cos(ang) * 0.24, 1.2 + i * 1.3, sin(ang) * 0.24)
		lm.rotation_degrees = Vector3(20.0, rad_to_deg(ang), 0.0)
		pole.add_child(lm)
	_geo.add_child(pole)


func _dummy(n: String, pos: Vector3) -> void:
	var d := Dummy.new()
	d.name = n
	d.collision_layer = 4
	d.collision_mask = 0
	d.position = pos
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35
	sh.height = 1.5
	cs.shape = sh
	cs.position = Vector3(0.0, 0.75, 0.0)
	d.add_child(cs)
	var hurt := Area3D.new()
	hurt.name = "Hurtbox"
	hurt.collision_layer = 64
	hurt.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hsh := CylinderShape3D.new()
	hsh.radius = 0.5
	hsh.height = 1.7
	hcs.shape = hsh
	hcs.position = Vector3(0.0, 0.85, 0.0)
	hurt.add_child(hcs)
	d.add_child(hurt)
	var vis := Node3D.new()
	d.add_child(vis)
	d.vis = vis
	var sack := StandardMaterial3D.new()
	sack.albedo_color = Color(0.86, 0.74, 0.5)
	sack.roughness = 1.0
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.5, 0.33, 0.2)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.36
	cap.height = 1.3
	body.mesh = cap
	body.position = Vector3(0.0, 0.85, 0.0)
	body.material_override = sack
	vis.add_child(body)
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.4
	bm.bottom_radius = 0.45
	bm.height = 0.16
	base.mesh = bm
	base.position = Vector3(0.0, 0.08, 0.0)
	base.material_override = post
	d.add_child(base)
	var face := Label3D.new()
	face.text = "x  x\n  o"
	face.font_size = 48
	face.pixel_size = 0.008
	face.modulate = Color(0.25, 0.15, 0.1)
	face.outline_size = 0
	face.position = Vector3(0.0, 1.15, 0.37)
	vis.add_child(face)
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64
	l.pixel_size = 0.01
	l.outline_size = 14
	l.modulate = Color(1.0, 0.85, 0.3)
	l.visible = false
	d.add_child(l)
	d.label = l
	_geo.add_child(d)


func _truffle(pos: Vector3) -> void:
	var t := Node3D.new()
	t.name = "SniffTarget"
	t.position = pos + Vector3(0.0, 0.25, 0.0)
	t.add_to_group("sniff_target")
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.42
	mi.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.95, 0.75, 0.25)
	gm.metallic = 0.6
	gm.roughness = 0.3
	gm.emission_enabled = true
	gm.emission = Color(0.6, 0.4, 0.05)
	mi.material_override = gm
	t.add_child(mi)
	_geo.add_child(t)
	var bush := StandardMaterial3D.new()
	bush.albedo_color = Color(0.3, 0.55, 0.25)
	for i in 3:
		var b := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.8 - i * 0.12
		bs.height = 1.2 - i * 0.2
		b.mesh = bs
		b.material_override = bush
		b.position = pos + Vector3(-0.6 + i * 0.7, 0.45, -1.0 + i * 0.25)
		_geo.add_child(b)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LabHUD"
	layer.add_to_group("hud")
	add_child(layer)
	var lab := Label.new()
	lab.position = Vector2(24.0, 18.0)
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12))
	lab.add_theme_constant_override("outline_size", 8)
	layer.add_child(lab)
	_hud_label = lab


func _opt_out_ledges(n: Node) -> void:
	if n is StaticBody3D or n is AnimatableBody3D:
		n.add_to_group("no_ledge_grab")
	for c in n.get_children():
		_opt_out_ledges(c)
