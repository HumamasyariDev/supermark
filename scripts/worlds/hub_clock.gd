class_name HubTruffleClock
extends StaticBody3D
## The brass Truffle Clock (HUB A22): a walnut drum plinth, a stout column, an orrery ring turning 6 deg/s with
## 26 sockets (24 world truffles, HUB-1 and BOSS-1) that fill with gold as truffles are won, and a glass dome
## holding a giant golden truffle. The drum top (y 1.0) is walkable.

const SOCKET_IDS := ["W1-1", "W1-2", "W1-3", "W1-4", "W1-5", "W1-6", "W1-7", "W1-8",
	"W2-1", "W2-2", "W2-3", "W2-4", "W2-5", "W2-6", "W2-7", "W2-8",
	"W3-1", "W3-2", "W3-3", "W3-4", "W3-5", "W3-6", "W3-7", "W3-8", "HUB-1", "BOSS-1", "W1-100", "W2-100", "W3-100"]
## r1 QA: the integration owner's bonus truffles (100 acorns per world) get their own smaller brass sockets.
const BONUS_IDS := ["W1-100", "W2-100", "W3-100"]
const TRUFFLE_GLB := "res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb"

var _ring: Node3D
var _gears: Array[Node3D] = []
var _sockets: Dictionary = {}  # id -> Node3D (gold fill)
var _count_label: Label3D
var _big: Node3D
var _t := 0.0
var _inner: Node3D
var _spin := 0.0  # extra deg/s after the Grand Bong
var _frozen := false  # R3.3: EV_huff_7 stops the orrery until the Grand Bong
## True once the hub has played its return flights (or when the scene is not the hub) so refresh() shows everything.
var _all_seen_ok := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()
	refresh()
	var game := get_node_or_null("/root/Game")
	if game and game.has_signal("truffle_collected"):
		game.truffle_collected.connect(func(_id: String) -> void: refresh())


func _build() -> void:
	var walnut := HubArchitecture.toon("bookshelf_wood", Color(0.7, 0.46, 0.32), 0.9)
	var brass := HubArchitecture.brass()
	var b := HubKit.Buf.new()
	# Drum: plinth with a rounded lip, top at y 1.0.
	HubKit.turned(b, PackedVector2Array([Vector2(1.7, 0.0), Vector2(1.7, 0.12), Vector2(1.58, 0.2), Vector2(1.55, 0.8),
		Vector2(1.66, 0.88), Vector2(1.66, 0.97), Vector2(1.6, 1.0)]), 40)
	_mesh(b, walnut, "Drum")
	var bb := HubKit.Buf.new()
	HubKit.lathe(bb, HubKit.round_rect_profile(1.56, 1.62, 0.36, 0.46, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 9.0, true, false)
	HubKit.lathe(bb, HubKit.round_rect_profile(1.56, 1.62, 0.6, 0.66, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 9.0, true, false)
	# Column with collars.
	HubKit.turned(bb, PackedVector2Array([Vector2(0.62, 1.0), Vector2(0.62, 1.1), Vector2(0.4, 1.2), Vector2(0.26, 1.45),
		Vector2(0.22, 2.2), Vector2(0.32, 2.35), Vector2(0.5, 2.45), Vector2(0.5, 2.55), Vector2(0.3, 2.6)]), 28)
	_mesh(bb, brass, "Column")
	HubKit.add_cyl_collision(self, null, 1.62, 1.0, Vector3(0, 0.5, 0), "Drum")
	HubKit.add_cyl_collision(self, null, 0.4, 1.4, Vector3(0, 1.7, 0), "Column")
	# R3.3 / r1 feel: the glass dome needs a top to slam (it had none, so a slam fell to the 0.4 m column cap or the
	# drum and missed the trigger). A 0.6 m cylinder up to the dome crown at y 3.4.
	HubKit.add_cyl_collision(self, null, 0.6, 1.0, Vector3(0, 2.9, 0), "Dome")
	# Orrery ring with 26 sockets.
	_ring = Node3D.new()
	_ring.name = "Ring"
	add_child(_ring)
	var rb := HubKit.Buf.new()
	HubKit.lathe(rb, HubKit.round_rect_profile(1.3, 1.5, 2.72, 2.84, 0.05, 0.05, 0.05, 0.05), 0.0, 360.0, 6.0, true, false)
	for k in 4:
		var th := 45.0 + 90.0 * float(k)
		var p0 := HubKit.polar(0.35, th, 2.6)
		var p1 := HubKit.polar(1.32, th, 2.78)
		var d := p1 - p0
		HubKit.rounded_box(rb, Vector3(d.length(), 0.06, 0.08), 0.03, Transform3D(HubArchitecture.along(d), (p0 + p1) * 0.5))
	# r1 visual: the orrery read as a bowl of fruit. Planet balls on the four arms and a counter-rotating inner
	# ring of moons make it legible as an orrery from the hero cameras (until HUB-M04 lands).
	var planet_cols := [Color("3f7fc4"), Color("c4473f"), Color("5aa04a"), Color("efe2c4")]
	for k in 4:
		var th := 45.0 + 90.0 * float(k)
		var pp := HubKit.polar(0.95, th, 2.86)
		HubKit.rounded_box(rb, Vector3(0.03, 0.12, 0.03), 0.01, Transform3D(Basis(), HubKit.polar(0.95, th, 2.78)))
		var pl := HubArchitecture.mi(_ring, SphereMesh.new(), HubArchitecture.flat_toon(planet_cols[k], 0.55, 0.5), "Planet%d" % k)
		(pl.mesh as SphereMesh).radius = 0.13 if k % 2 == 0 else 0.1
		(pl.mesh as SphereMesh).height = (pl.mesh as SphereMesh).radius * 2.0
		pl.position = pp + Vector3(0, 0.08, 0)
	var ring_mi := HubArchitecture.mi(_ring, rb.commit(), brass, "RingMesh")
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cup := HubKit.turned_mesh(PackedVector2Array([Vector2(0.04, 0.0), Vector2(0.11, 0.05), Vector2(0.13, 0.16), Vector2(0.115, 0.17)]), 12)
	var empty_mat := HubKit.mat(Color("6b4a2a"), 0.5, 0.6, "socket_empty")
	var gold := HubKit.emissive(Color("ffc93c"), 0.9, "socket_gold")
	gold.metallic = 0.9
	gold.roughness = 0.25
	var truffle_scene: PackedScene = HubAssets.scene(TRUFFLE_GLB)
	for i in SOCKET_IDS.size():
		var th := 360.0 * float(i) / float(SOCKET_IDS.size())
		var s := Node3D.new()
		s.position = HubKit.polar(1.4, th, 2.84)
		_ring.add_child(s)
		HubArchitecture.mi(s, cup, brass if i >= 24 else HubKit.mat(Color("b08a3a"), 0.35, 0.95, "socket_cup"), "Cup")
		if BONUS_IDS.has(SOCKET_IDS[i]):
			s.scale = Vector3.ONE * 0.8
			# An acorn-cap collar marks a bonus socket.
			var collar := HubKit.Buf.new()
			HubKit.lathe(collar, HubKit.round_rect_profile(0.1, 0.15, 0.16, 0.2, 0.01, 0.01, 0.01, 0.01), 0.0, 360.0, 20.0, true, false)
			HubArchitecture.mi(s, collar.commit(), HubArchitecture.flat_toon(Color("8a5a2e"), 0.5, 0.2), "AcornCollar")
		var hole := HubArchitecture.mi(s, SphereMesh.new(), empty_mat, "Hole")
		(hole.mesh as SphereMesh).radius = 0.09
		(hole.mesh as SphereMesh).height = 0.07
		hole.position.y = 0.15
		var fill := Node3D.new()
		fill.name = "Fill"
		fill.position.y = 0.2
		s.add_child(fill)
		if truffle_scene:
			var t := truffle_scene.instantiate() as Node3D
			t.scale = Vector3.ONE * 0.55
			fill.add_child(t)
		else:
			var g := HubArchitecture.mi(fill, SphereMesh.new(), gold, "Gold")
			(g.mesh as SphereMesh).radius = 0.1
			(g.mesh as SphereMesh).height = 0.16
		fill.visible = false
		_sockets[SOCKET_IDS[i]] = fill
	_inner = Node3D.new()
	_inner.name = "InnerRing"
	add_child(_inner)
	var ib := HubKit.Buf.new()
	HubKit.lathe(ib, HubKit.round_rect_profile(0.78, 0.86, 2.2, 2.26, 0.02, 0.02, 0.02, 0.02), 0.0, 360.0, 8.0, true, false)
	for k in 3:
		var th := 120.0 * float(k)
		var d := HubKit.polar(0.8, th, 2.23) - HubKit.polar(0.3, th, 2.2)
		HubKit.rounded_box(ib, Vector3(d.length(), 0.03, 0.04), 0.012, Transform3D(HubArchitecture.along(d), (HubKit.polar(0.8, th, 2.23) + HubKit.polar(0.3, th, 2.2)) * 0.5))
		var moon := HubArchitecture.mi(_inner, SphereMesh.new(), HubArchitecture.flat_toon(Color("f4ead6"), 0.6, 0.6), "Moon%d" % k)
		(moon.mesh as SphereMesh).radius = 0.06
		(moon.mesh as SphereMesh).height = 0.12
		moon.position = HubKit.polar(0.82, th + 60.0, 2.32)
	HubArchitecture.mi(_inner, ib.commit(), brass, "InnerRingMesh")
	# Two big gears on the drum face, turning against each other.
	for k in 2:
		var dg := Node3D.new()
		dg.position = HubKit.polar(1.6, 140.0 + 80.0 * float(k), 0.55)
		dg.rotation.y = deg_to_rad(-(140.0 + 80.0 * float(k)) + 180.0)
		add_child(dg)
		var gb2 := HubKit.Buf.new()
		for j in 14:
			var a := TAU * float(j) / 14.0
			HubKit.rounded_box(gb2, Vector3(0.09, 0.09, 0.06), 0.02, Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0) * 0.3))
		var disc2 := CylinderMesh.new()
		disc2.top_radius = 0.29
		disc2.bottom_radius = 0.29
		disc2.height = 0.05
		var dm2 := HubArchitecture.mi(dg, disc2, brass, "Disc")
		dm2.rotation_degrees.x = 90
		HubArchitecture.mi(dg, gb2.commit(), brass, "Teeth")
		_gears.append(dg)
	# Little gears on the column, turning in opposite directions.
	for k in 3:
		var gear := Node3D.new()
		gear.position = HubKit.polar(0.48, 120.0 * float(k) + 30.0, 1.75 + 0.2 * float(k))
		gear.rotation.y = deg_to_rad(-(120.0 * float(k) + 30.0))
		add_child(gear)
		var gbuf := HubKit.Buf.new()
		var teeth := 10
		for j in teeth:
			var a := TAU * float(j) / float(teeth)
			HubKit.rounded_box(gbuf, Vector3(0.07, 0.07, 0.06), 0.015, Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a), sin(a), 0) * 0.2))
		var disc := CylinderMesh.new()
		disc.top_radius = 0.19
		disc.bottom_radius = 0.19
		disc.height = 0.05
		var dm := HubArchitecture.mi(gear, disc, brass, "Disc")
		dm.rotation_degrees.x = 90
		HubArchitecture.mi(gear, gbuf.commit(), brass, "Teeth")
		_gears.append(gear)
	# Glass dome and the giant truffle inside.
	_big = Node3D.new()
	_big.name = "GreatTruffle"
	_big.position = Vector3(0, 2.62, 0)
	add_child(_big)
	if truffle_scene:
		var t2 := truffle_scene.instantiate() as Node3D
		# Fix r2 (visual minor): from spawn the top read as a bunch of gold grapes; 1.3x larger.
		t2.scale = Vector3.ONE * 2.6
		_big.add_child(t2)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.95, 1.0, 0.25)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.rim_enabled = true
	glass.rim = 1.0
	glass.rim_tint = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dome := HubKit.Buf.new()
	var prof := PackedVector2Array()
	for i in 10:
		var a := deg_to_rad(90.0 * float(i) / 9.0)
		prof.append(Vector2(0.58 * cos(a), 2.6 + 0.8 * sin(a)))
	HubKit.lathe(dome, prof, 0.0, 360.0, 12.0, false, false, 80.0)
	var dmi := HubArchitecture.mi(self, dome.commit(), glass, "GlassDome")
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gl := OmniLight3D.new()
	gl.light_color = Color(1.0, 0.8, 0.4)
	gl.light_energy = 1.2
	gl.omni_range = 3.5
	gl.position = Vector3(0, 3.0, 0)
	add_child(gl)
	# Brass plaque with the running count.
	# OPUSLOOK: the plate stands proud of the drum. Flush at z 1.6, the drum's brass band (y 0.6-0.66, r 1.62) ran across
	# the middle of the digits and the count read "C / 29" on both builds.
	_count_label = Label3D.new()
	_count_label.position = Vector3(0, 0.62, 1.755)
	_count_label.font_size = 64
	_count_label.pixel_size = 0.004
	_count_label.modulate = Color("3b2416")
	_count_label.outline_size = 0
	_count_label.double_sided = false
	# Fix r2 (visual minor): the count read "C/29" under nearest filtering; text keeps linear filtering.
	_count_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_count_label.set_meta("retro_skip", true)
	add_child(_count_label)
	var plaque := HubKit.Buf.new()
	HubKit.rounded_box(plaque, Vector3(0.9, 0.3, 0.05), 0.02, Transform3D(Basis(), Vector3(0, 0.62, 1.715)))
	HubArchitecture.mi(self, plaque.commit(), brass, "Plaque")
	# Dark walnut band behind the plate so the count reads (r1 visual).
	var band := HubKit.Buf.new()
	HubKit.rounded_box(band, Vector3(1.1, 0.42, 0.12), 0.03, Transform3D(Basis(), Vector3(0, 0.62, 1.64)))
	HubArchitecture.mi(self, band.commit(), HubArchitecture.flat_toon(Color("3b2416"), 0.3, 0.1), "PlateBand")


## EV_grand_bong: the orrery whirls up and settles over a few seconds.
func spin_up() -> void:
	_frozen = false
	_spin = 220.0


## EV_huff_7 (R3.3): the orrery ring freezes; return flights still fill sockets.
func freeze() -> void:
	_frozen = true
	_spin = 0.0


func is_frozen() -> bool:
	return _frozen


## EV_dome_bong: a plain bong for any dome slam that is not the Grand Bong.
func bong() -> void:
	_spin = maxf(_spin, 90.0) if not _frozen else 0.0
	if _big:
		var tw := create_tween()
		tw.tween_property(_big, "scale", Vector3.ONE * 1.25, 0.08)
		tw.tween_property(_big, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var a := get_node_or_null("/root/Audio")
	if a and a.has_method("play_sfx"):
		a.call("play_sfx", "chime", global_position + Vector3(0, 3.4, 0))
	ObjSvc.burst(self, global_position + Vector3(0, 3.6, 0), Color(1.0, 0.85, 0.4), 18, 3.0, 0.16, -3.0, 0.8)


func _mesh(b: HubKit.Buf, m: Material, n: String) -> void:
	HubArchitecture.mi(self, b.commit(), m, n)


func refresh() -> void:
	var game := get_node_or_null("/root/Game")
	var n := 0
	for id in _sockets.keys():
		var has := false
		if game and game.has_method("has_truffle"):
			has = bool(game.call("has_truffle", id))
			# A truffle that has not flown into the clock yet (HubEvents return flight) stays empty for now.
			if has and not HubKit.flag(self, "hub_seen_" + String(id)) and not _all_seen_ok:
				has = false
		(_sockets[id] as Node3D).visible = has
		if has:
			n += 1
	if _count_label:
		_count_label.text = "%d / %d" % [n, SOCKET_IDS.size()]


func _process(delta: float) -> void:
	_t += delta
	_spin = move_toward(_spin, 0.0, 45.0 * delta)
	var run := 0.0 if _frozen else 1.0
	if _ring:
		_ring.rotation.y += deg_to_rad(6.0 * run + _spin) * delta
	if _inner:
		_inner.rotation.y -= deg_to_rad(14.0 * run + _spin * 1.4) * delta
	for i in _gears.size():
		_gears[i].rotate_object_local(Vector3.BACK, delta * run * (1.2 if i % 2 == 0 else -1.6))
	if _big:
		_big.rotation.y += delta * 0.6
		_big.position.y = 2.62 + sin(_t * 1.4) * 0.03
