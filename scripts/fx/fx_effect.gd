class_name FxEffect
extends Node3D
## One reusable effect node for every Super Mak 64 particle effect.
## Each scene in res://scenes/fx/ is this script with a preset name (see FxPresets).
##
## Usage from gameplay code:
##   var fx := preload("res://scenes/fx/DustPuff.tscn").instantiate()
##   get_tree().current_scene.add_child(fx)
##   fx.global_position = pos
##   fx.play()                       # or emit(); one-shots free themselves when done
## Or the helper:  FxEffect.spawn(self, "res://scenes/fx/CollectPop.tscn", pos)
## Continuous presets (RunDust, Sparkle, ambient) loop until set_active(false) or stop().

signal finished

@export var preset: String = "dust_puff"
@export var autoplay: bool = true
## Scales particle counts and sizes (for example a bigger slam).
@export var intensity: float = 1.0
## One-shots normally remove themselves when done. The VFX lab turns this off to re-trigger.
@export var free_when_done: bool = true
## Optional tint multiplied into every layer (for example green for a gummy, pink for frosting).
@export var tint: Color = Color(1, 1, 1, 1)
## Uniform size multiplier applied as node scale (works after the effect is built; the player sets it).
@export var fx_scale: float = 1.0:
	set(v):
		fx_scale = v
		scale = Vector3.ONE * maxf(v, 0.001)
		# World-space GPU particles ignore the node scale, so particle size, emission shape and speed are scaled
		# explicitly (rings, arcs and shock meshes follow the node scale).
		if _built:
			_apply_particle_scale(maxf(v, 0.001))
## Ambient drop-ins: overrides the emission box half-extents of box-emitting layers (metres) and scales their
## particle count with the area so density stays constant. Zero keeps the preset's own box.
@export var area: Vector3 = Vector3.ZERO

## Set by the Juice pool: when done, hide and emit `finished` instead of freeing.
var pooled := false
## Set by Juice for effects that must keep animating while the tree is paused (truffle celebration).
var pause_proof := false
## Juice fix r2 (screen-area budget): a "lite" play skips the flash sprites, billboard rings and lights of this effect.
var lite := false

var _built := false
var _particles: Array = [] # GPUParticles3D on desktop; supported CPU adapters on web.
## Per particle layer: true for single big flash sprites (skipped on a lite play).
var _flash_layer: Array[bool] = []
var _applied_k := -1.0
var _delays: Array[float] = []
var _rings: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _arcs: Array[Dictionary] = []
var _shocks: Array[Dictionary] = []
var _one_shot := true
var _duration := 1.0
var _last_play_frame := -1
var _play_id := 0
## Juice fix r4 (perf critic r2: the object count crept +2/s from one SceneTreeTimer per play and per delayed layer):
## delayed layers and the done countdown tick in _process instead ([seconds_left, layer_index] pairs).
var _pending: Array = []
var _done_left := -1.0

## Effect lights alive right now (all effects). Juice stacks of heavy events used to wash the ground flat yellow:
## at most MAX_LIGHTS light at once, energy shared by 1/sqrt(n), and a light is hidden when its flash ends.
static var live_lights := 0
const MAX_LIGHTS := 3
## Juice turns effect lights off per world (W3 perf: lights on its terrain tripled GPU time in combat bursts).
static var lights_enabled := true


static func spawn(context: Node, scene_path: String, world_pos: Vector3, parent: Node = null) -> FxEffect:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("[Fx] missing effect scene " + scene_path)
		return null
	var fx := packed.instantiate() as FxEffect
	var host: Node = parent if parent != null else context.get_tree().current_scene
	fx.autoplay = false
	host.add_child(fx)
	fx.global_position = world_pos
	fx.play()
	return fx


func _ready() -> void:
	_build()
	if autoplay:
		play()


func is_one_shot() -> bool:
	_build()
	return _one_shot


func emit() -> void:
	play()


func play() -> void:
	_build()
	# autoplay plus an explicit play() in the same frame must not double-fire.
	var f := Engine.get_process_frames()
	if f == _last_play_frame:
		return
	_last_play_frame = f
	visible = true
	_play_id += 1
	_pending.clear()
	_done_left = -1.0
	for i in _particles.size():
		var p: Variant = _particles[i]
		if lite and _flash_layer[i]:
			p.emitting = false
			continue
		# Web warm-up copies are recycled after three frames, often sooner than
		# an authored delayed layer would start (and the loading tree is paused).
		# Emit those layers for preparation only; live effect timing is unchanged.
		if _delays[i] > 0.0 and not (OS.has_feature("web") and has_meta("prewarm")):
			p.emitting = false
			_pending.append([_delays[i], i])
		else:
			p.restart()
	for r in _rings:
		_play_ring(r)
	for a in _arcs:
		_play_ring(a)
	for sh in _shocks:
		if lite and bool(sh["def"].get("billboard", false)):
			continue
		_play_ring(sh)
	for l in _lights:
		if lite or not lights_enabled:
			continue
		_play_light(l)
	if _one_shot:
		_done_left = _duration + 0.15
	if _one_shot or not _pending.is_empty():
		set_process(true)


func _restart_layer(i: int, id: int) -> void:
	if id == _play_id and i < _particles.size():
		_particles[i].restart()


func _done_if_current(id: int) -> void:
	if id == _play_id:
		_on_done()


## Ends this play now (Juice: budget recycling and prewarm copies): particles stop and vanish, rings and lights end,
## and a pooled copy returns to its pool.
func recycle() -> void:
	_play_id += 1
	_pending.clear()
	_done_left = -1.0
	for p in _particles:
		p.emitting = false
	for list in [_rings, _arcs, _shocks]:
		for r in list:
			r["active"] = false
			(r["node"] as Node3D).visible = false
	for l in _lights:
		_end_light(l)
	visible = false
	_on_done()


func set_active(on: bool) -> void:
	_build()
	for p in _particles:
		p.emitting = on


func stop() -> void:
	set_active(false)


func _process(delta: float) -> void:
	_update_rings(delta)
	_update_arcs(delta)
	_update_shocks(delta)
	if not _pending.is_empty():
		var i := 0
		while i < _pending.size():
			_pending[i][0] = float(_pending[i][0]) - delta
			if float(_pending[i][0]) <= 0.0:
				var li := int(_pending[i][1])
				_pending.remove_at(i)
				if li < _particles.size():
					_particles[li].restart()
			else:
				i += 1
	if _done_left > 0.0:
		_done_left -= delta
		if _done_left <= 0.0:
			_done_left = -1.0
			_on_done()
	if not _is_busy():
		set_process(false)


func _is_busy() -> bool:
	if _done_left > 0.0 or not _pending.is_empty():
		return true
	for list in [_rings, _arcs, _shocks]:
		for r in list:
			if r.get("active", false):
				return true
	return false


func _on_done() -> void:
	finished.emit()
	if pooled:
		visible = false
		return
	if free_when_done and is_inside_tree():
		queue_free()


func _build() -> void:
	if _built:
		return
	_built = true
	_build_layers()
	if not is_equal_approx(fx_scale, 1.0):
		_apply_particle_scale(maxf(fx_scale, 0.001))


func _build_layers() -> void:
	var def: Dictionary = FxPresets.get_preset(preset)
	if def.is_empty():
		push_warning("[Fx] unknown preset " + preset)
		return
	_one_shot = def.get("one_shot", true)
	set_process(false)
	_duration = 0.0
	for layer in def.get("layers", []):
		var kind: String = layer.get("kind", "particles")
		match kind:
			"particles":
				var lay: Dictionary = layer
				if area != Vector3.ZERO and lay.get("emit", "") == "box":
					lay = layer.duplicate()
					var base: Vector3 = layer.get("extents", Vector3.ONE)
					var ratio := (area.x * area.z) / maxf(base.x * base.z, 0.01)
					lay["extents"] = area
					lay["amount"] = clampi(int(round(float(layer.get("amount", 8)) * ratio)), 1, 400)
					var vis_size := area + Vector3(4, 6, 4)
					lay["aabb"] = AABB(-vis_size, vis_size * 2.0)
				var p: Variant = FxPresets.make_particles(lay, intensity, tint, _one_shot)
				add_child(p)
				_particles.append(p)
				var sz: Vector2 = lay.get("size", Vector2(0.3, 0.5))
				_flash_layer.append(int(lay.get("amount", 8)) == 1 and lay.get("add", false) and String(lay.get("tex", "")) == "soft_dot" and sz.y >= 0.9)
				var delay: float = layer.get("delay", 0.0)
				_delays.append(delay)
				_duration = maxf(_duration, delay + p.lifetime * (1.0 if p.explosiveness > 0.5 else 2.0))
			"ring":
				var r := FxPresets.make_ring(layer, intensity, tint)
				add_child(r)
				r.visible = false
				_rings.append({"node": r, "def": layer})
				_duration = maxf(_duration, layer.get("time", 0.4) + layer.get("delay", 0.0))
			"arc":
				var arc := FxPresets.make_arc(layer, intensity, tint)
				add_child(arc)
				arc.visible = false
				_arcs.append({"node": arc, "def": layer})
				_duration = maxf(_duration, layer.get("time", 0.25) + layer.get("delay", 0.0))
			"shock":
				var sh := FxPresets.make_shock(layer, intensity, tint)
				add_child(sh)
				sh.visible = false
				_shocks.append({"node": sh, "def": layer})
				_duration = maxf(_duration, layer.get("time", 0.5) + layer.get("delay", 0.0))
			"light":
				var l := OmniLight3D.new()
				l.light_color = layer.get("color", Color(1, 0.9, 0.72))
				l.omni_range = layer.get("range", 3.0) * intensity
				l.light_energy = 0.0
				l.shadow_enabled = false
				# Hidden while idle so a finished flash never sits in the light clusters.
				l.visible = false
				l.position = layer.get("offset", Vector3(0, 0.5, 0))
				add_child(l)
				_lights.append({"node": l, "def": layer})
				_duration = maxf(_duration, layer.get("time", 0.3))


func _apply_particle_scale(k: float) -> void:
	# Juice fix r2 (perf): quantised and cached, so a pooled copy re-played at the same size writes nothing.
	if k >= 0.1:
		k = snappedf(k, 0.02)
	if is_equal_approx(k, _applied_k):
		return
	_applied_k = k
	for p in _particles:
		var pm := p.process_material as ParticleProcessMaterial
		if pm == null or p.local_coords:
			continue
		if not p.has_meta("fx_base"):
			p.set_meta("fx_base", {"smin": pm.scale_min, "smax": pm.scale_max, "vmin": pm.initial_velocity_min, "vmax": pm.initial_velocity_max,
				"sph": pm.emission_sphere_radius, "rr": pm.emission_ring_radius, "rir": pm.emission_ring_inner_radius, "box": pm.emission_box_extents,
				"grav": pm.gravity, "radmin": pm.radial_velocity_min, "radmax": pm.radial_velocity_max, "dmin": pm.damping_min, "dmax": pm.damping_max})
		var b: Dictionary = p.get_meta("fx_base")
		pm.scale_min = b["smin"] * k
		pm.scale_max = b["smax"] * k
		pm.initial_velocity_min = b["vmin"] * k
		pm.initial_velocity_max = b["vmax"] * k
		pm.emission_sphere_radius = b["sph"] * k
		pm.emission_ring_radius = b["rr"] * k
		pm.emission_ring_inner_radius = b["rir"] * k
		pm.emission_box_extents = b["box"] * k
		pm.gravity = b["grav"] * k
		pm.radial_velocity_min = b["radmin"] * k
		pm.radial_velocity_max = b["radmax"] * k
		pm.damping_min = b["dmin"] * k
		pm.damping_max = b["dmax"] * k
		if OS.has_feature("web") and p.has_method("sync_scale"):
			p.sync_scale()


func _play_ring(r: Dictionary) -> void:
	r["t"] = 0.0 if OS.has_feature("web") and has_meta("prewarm") else -float(r["def"].get("delay", 0.0))
	r["active"] = true
	set_process(true)


func _update_rings(delta: float) -> void:
	for r in _rings:
		if not r.get("active", false):
			continue
		var node: MeshInstance3D = r["node"]
		var d: Dictionary = r["def"]
		r["t"] = float(r["t"]) + delta
		var t: float = r["t"]
		if t < 0.0:
			continue
		var dur: float = d.get("time", 0.4)
		var k := clampf(t / dur, 0.0, 1.0)
		if k >= 1.0:
			node.visible = false
			r["active"] = false
			continue
		node.visible = true
		var size: float = d.get("size", 2.0) * intensity
		var start: float = d.get("start", 0.15)
		var e := 1.0 - pow(1.0 - k, 3.0)
		node.scale = Vector3.ONE * size * lerpf(start, 1.0, e)
		var col: Color = d.get("color", Color.WHITE) * tint
		col.a *= 1.0 - k * k
		(node.material_override as StandardMaterial3D).albedo_color = col


func _update_arcs(delta: float) -> void:
	for a in _arcs:
		if not a.get("active", false):
			continue
		var node: MeshInstance3D = a["node"]
		var d: Dictionary = a["def"]
		a["t"] = float(a["t"]) + delta
		var t: float = a["t"]
		if t < 0.0:
			continue
		var dur: float = d.get("time", 0.25)
		var k := clampf(t / dur, 0.0, 1.0)
		if k >= 1.0:
			node.visible = false
			a["active"] = false
			continue
		node.visible = true
		# Smear timing: draw the full arc fast, HOLD it (hold seconds, default 3 frames), then wipe it from the
		# tail to the tip (the shader's `wipe`). Reads at gameplay distance instead of flashing past in 4 frames.
		var hold: float = d.get("hold", 0.05)
		var draw_t: float = d.get("draw", dur * 0.35)
		var wipe_t: float = maxf(dur - draw_t - hold, 0.01)
		var mat := node.material_override as ShaderMaterial
		if t < draw_t:
			var e := 1.0 - pow(1.0 - t / draw_t, 2.2)
			mat.set_shader_parameter("progress", e)
			mat.set_shader_parameter("wipe", 0.0)
		else:
			mat.set_shader_parameter("progress", 1.0)
			mat.set_shader_parameter("wipe", clampf((t - draw_t - hold) / wipe_t, 0.0, 1.0))


func _update_shocks(delta: float) -> void:
	for sh in _shocks:
		if not sh.get("active", false):
			continue
		var node: MeshInstance3D = sh["node"]
		var d: Dictionary = sh["def"]
		sh["t"] = float(sh["t"]) + delta
		var t: float = sh["t"]
		if t < 0.0:
			continue
		var dur: float = d.get("time", 0.5)
		var k := clampf(t / dur, 0.0, 1.0)
		if k >= 1.0:
			node.visible = false
			sh["active"] = false
			continue
		node.visible = true
		(node.material_override as ShaderMaterial).set_shader_parameter("progress", k)


func _play_light(l: Dictionary) -> void:
	var node: OmniLight3D = l["node"]
	_end_light(l)
	if has_meta("prewarm"):
		if OS.has_feature("web"):
			# Compile the local-light draw variant with negligible illumination.
			# Warm copies run one at a time and recycle this light with the effect.
			node.light_energy = 0.001
			node.visible = true
		return
	if live_lights >= MAX_LIGHTS:
		return
	var d: Dictionary = l["def"]
	live_lights += 1
	l["live"] = true
	node.visible = true
	# Short peak (2 frames), then a quick decay; overlapping flashes share the energy.
	var peak: float = d.get("energy", 2.0) * intensity / sqrt(float(live_lights))
	node.light_energy = peak
	var tw := create_tween()
	l["tween"] = tw
	tw.tween_interval(0.033)
	tw.tween_property(node, "light_energy", 0.0, maxf(float(d.get("time", 0.2)), 0.08)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_end_light.bind(l))


func _end_light(l: Dictionary) -> void:
	var tw: Variant = l.get("tween")
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	l.erase("tween")
	if l.get("live", false):
		l["live"] = false
		live_lights = maxi(live_lights - 1, 0)
	var node: OmniLight3D = l["node"]
	if is_instance_valid(node):
		node.light_energy = 0.0
		node.visible = false


func _exit_tree() -> void:
	for l in _lights:
		if l.get("live", false):
			l["live"] = false
			live_lights = maxi(live_lights - 1, 0)
