class_name WolfRecipes
extends RefCounted
## Procedural pose recipes for Sir Reginald (BOSS_amendments R3.11). Each recipe writes targets into a
## WolfRig for time t (seconds in the state). Root offsets are in the boss's local space
## (forward = -Z, so a forward lean is a NEGATIVE root_rot.x; a backward shuffle is +Z).
## Shoulder raise stays at or below about 65 degrees except where the amendment allows it.


static func breathe(r: WolfRig, t: float, amount := 1.0) -> void:
	r.pose("spine_3", Vector3(sin(t * 2.2) * 0.03 * amount, 0, 0))
	r.pose("chest", Vector3(sin(t * 2.2 + 0.4) * 0.02 * amount, 0, 0))
	r.pose("tail", Vector3(0, sin(t * PI) * 0.14, 0))
	r.pose("tail_2", Vector3(0, sin(t * PI - 0.6) * 0.16, 0))
	r.pose("tail_3", Vector3(0, sin(t * PI - 1.2) * 0.18, 0))
	r.pose("ear_l", Vector3(0, 0, sin(t * 0.7) * 0.05))
	r.pose("ear_r", Vector3(0, 0, -sin(t * 0.7 + 0.5) * 0.05))


static func arms_rest(r: WolfRig) -> void:
	# The rig rests in an A-pose; bring the arms in toward the body so he stands like a gentleman.
	r.pose("arm_l", Vector3(0, 0, -0.42))
	r.pose("arm_r", Vector3(0, 0, 0.42))
	r.pose("forearm_l", Vector3(-0.25, 0, 0))
	r.pose("forearm_r", Vector3(-0.25, 0, 0))


static func apply(r: WolfRig, state: String, t: float, p: Dictionary = {}) -> void:
	r.rate = 14.0
	match state:
		"idle", "sip":
			breathe(r, t)
			arms_rest(r)
			var cyc := fmod(t, 3.0)
			var sip := smoothstep(0.0, 0.5, cyc) * (1.0 - smoothstep(1.3, 1.9, cyc))
			r.pose("arm_l", Vector3(-0.55 - 0.25 * sip, 0, 0.1))
			r.pose("forearm_l", Vector3(-1.45 - 0.5 * sip, -0.2, 0))
			r.pose("head", Vector3(0.17 * sip - 0.05, 0, 0))
			r.pose("arm_r", Vector3(-0.15, 0, -0.1))
			r.pose("forearm_r", Vector3(-0.4, 0, 0))
			# Little finger out: the off hand rests on the hip.
		"sneer":
			breathe(r, t)
			arms_rest(r)
			r.pose("head", Vector3(-0.12, sin(t * 1.3) * 0.12, 0.08))
			r.pose("neck", Vector3(-0.08, 0, 0))
			r.pose("arm_l", Vector3(-0.9, 0, 0.1))
			r.pose("forearm_l", Vector3(-1.3, 0, 0))
			r.pose("hand_l", Vector3(0, 0, 0.2))
		"walk", "trot":
			var spd: float = p.get("speed", 3.0)
			var ph: float = p.get("phase", t * 6.0)
			var amp := clampf(spd / 6.0, 0.25, 1.0)
			arms_rest(r)
			r.pose("thigh_l", Vector3(-sin(ph) * 0.55 * amp, 0, 0))
			r.pose("thigh_r", Vector3(sin(ph) * 0.55 * amp, 0, 0))
			r.pose("shin_l", Vector3(maxf(0.0, cos(ph)) * 0.7 * amp, 0, 0))
			r.pose("shin_r", Vector3(maxf(0.0, -cos(ph)) * 0.7 * amp, 0, 0))
			r.pose("arm_l", Vector3(sin(ph) * 0.4 * amp, 0, 0))
			r.pose("arm_r", Vector3(-sin(ph) * 0.4 * amp, 0, 0))
			r.pose("spine", Vector3(0.08 * amp, sin(ph) * 0.06, 0))
			r.pose("tail", Vector3(0, sin(ph) * 0.25, 0))
			r.pose("coat_l", Vector3(0.2 * amp + sin(ph) * 0.1, 0, 0))
			r.pose("coat_r", Vector3(0.2 * amp - sin(ph) * 0.1, 0, 0))
			r.root_pos.y = absf(sin(ph)) * 0.09 * amp
		"inhale":
			var k: float = p.get("k", clampf(t / 1.2, 0.0, 1.0))
			var e := k * k * (3.0 - 2.0 * k)
			breathe(r, t, 0.3)
			r.chest_inflate = e
			r.cheeks_puff = 0.25 * e
			r.pose("spine_2", Vector3(-0.21 * e, 0, 0))
			r.pose("spine_3", Vector3(-0.1 * e, 0, 0))
			r.pose("head", Vector3(-0.26 * e, 0, 0))
			r.pose("arm_l", Vector3(0.1 * e, 0, -0.42 + 0.86 * e))
			r.pose("arm_r", Vector3(0.1 * e, 0, 0.42 - 0.86 * e))
			r.pose("forearm_l", Vector3(-0.3, 0, 0))
			r.pose("forearm_r", Vector3(-0.3, 0, 0))
			r.pose("ear_l", Vector3(-0.3 * e, 0, 0))
			r.pose("ear_r", Vector3(-0.3 * e, 0, 0))
			r.pose("tail", Vector3(-0.4 * e, 0, 0))
			# The chest balloons through bone scale as well as the blend shape.
			var s2 := 1.0 + 0.10 * e
			var s3 := 1.0 + 0.16 * e
			var s4 := 1.0 + 0.06 * e
			r.bscale("spine_2", Vector3.ONE * s2)
			r.bscale("spine_3", Vector3.ONE * s3)
			r.bscale("chest", Vector3.ONE * s4)
			var inv := 1.0 / (s2 * s3 * s4)
			r.bscale("neck", Vector3.ONE * inv * (1.0 + 0.04 * e))
			r.bscale("arm_l", Vector3.ONE * inv)
			r.bscale("arm_r", Vector3.ONE * inv)
			r.root_scale = Vector3(1.0 + 0.04 * e, 1.0 + 0.05 * e, 1.0 + 0.04 * e)
			r.root_pos.z = 0.12 * e
			if bool(p.get("guard", false)):
				# Cane guard tell (r1 animation): the cane is held across the chest during a guarded inhale, so the
				# Pop the Bellows deflect is readable before the player commits.
				r.pose("arm_r", Vector3(-0.95, 0, -0.25))
				r.pose("forearm_r", Vector3(-1.1, 0.5, 0))
				r.pose("hand_r", Vector3(0, 0, 1.3))
				r.pose("arm_l", Vector3(-0.7, 0, 0.3))
				r.pose("forearm_l", Vector3(-1.2, -0.4, 0))
				r.pose("head", Vector3(-0.1, 0.15, 0))
		"huff":
			var hk := clampf(t / 0.3, 0.0, 1.0)
			r.rate = 22.0
			r.chest_inflate = lerpf(1.0, 0.0, clampf(t / maxf(0.2, float(p.get("dur", 1.4))), 0.0, 1.0))
			r.cheeks_puff = 1.0 if t < 0.3 else 0.45
			r.pose("spine", Vector3(0.12 * hk, 0, 0))
			r.pose("spine_2", Vector3(0.14 * hk, 0, 0))
			r.pose("head", Vector3(0.05, float(p.get("yaw", 0.0)), 0))
			r.pose("neck", Vector3(0, float(p.get("yaw", 0.0)) * 0.6, 0))
			r.pose("jaw", Vector3(0.35, 0, 0))
			r.pose("arm_l", Vector3(0.25, 0, 0.35))
			r.pose("arm_r", Vector3(0.25, 0, -0.35))
			r.pose("forearm_l", Vector3(-0.4, 0, 0))
			r.pose("forearm_r", Vector3(-0.4, 0, 0))
			r.pose("coat_l", Vector3(-0.5, 0, 0.2))
			r.pose("coat_r", Vector3(-0.5, 0, -0.2))
			r.pose("ear_l", Vector3(0.5, 0, 0.2))
			r.pose("ear_r", Vector3(0.5, 0, -0.2))
			r.pose("tail", Vector3(0.5, 0, 0))
			r.root_pos.z = 0.15 * (1.0 - clampf((t - 0.2) / 0.6, 0.0, 1.0))
			var bs := 1.0 + 0.12 * r.chest_inflate
			r.bscale("spine_3", Vector3.ONE * bs)
			r.bscale("neck", Vector3.ONE / bs)
			r.bscale("arm_l", Vector3.ONE / bs)
			r.bscale("arm_r", Vector3.ONE / bs)
		"head_turn":
			breathe(r, t)
			arms_rest(r)
			var y: float = p.get("yaw", 0.0)
			var hk := clampf(t / 0.3, 0.0, 1.0)
			r.pose("neck", Vector3(0, y * 0.43 * hk, 0))
			r.pose("head", Vector3(-0.1, y * 0.57 * hk, 0))
			r.pose("arm_r", Vector3(-0.4, 0, 0))
			r.pose("forearm_r", Vector3(-1.2, y * 0.5, 0))
			r.chest_inflate = 0.35
		"hop":
			var k: float = p.get("k", 0.5)
			var air := sin(PI * clampf(k, 0.0, 1.0))
			arms_rest(r)
			r.pose("thigh_l", Vector3(-0.7 * air, 0, 0.1))
			r.pose("thigh_r", Vector3(-0.7 * air, 0, -0.1))
			r.pose("shin_l", Vector3(1.0 * air, 0, 0))
			r.pose("shin_r", Vector3(1.0 * air, 0, 0))
			r.pose("arm_l", Vector3(-0.3 * air, 0, 0.4 * air))
			r.pose("arm_r", Vector3(-0.3 * air, 0, -0.4 * air))
			r.pose("coat_l", Vector3(-0.6 * air, 0, 0))
			r.pose("coat_r", Vector3(-0.6 * air, 0, 0))
			r.pose("tail", Vector3(-0.6 * air, 0, 0))
			r.pose("ear_l", Vector3(-0.4 * air, 0, 0))
			r.pose("ear_r", Vector3(-0.4 * air, 0, 0))
		"pant":
			r.rate = 10.0
			var pt := t * 2.0 * TAU * 0.5
			r.root_pos.y = -0.9
			r.root_pos.z = 0.15
			r.pose("thigh_l", Vector3(-1.4, 0, 0.15))
			r.pose("thigh_r", Vector3(-1.4, 0, -0.15))
			r.pose("shin_l", Vector3(1.9, 0, 0))
			r.pose("shin_r", Vector3(1.9, 0, 0))
			r.pose("foot_l", Vector3(-0.5, 0, 0))
			r.pose("foot_r", Vector3(-0.5, 0, 0))
			r.pose("spine", Vector3(0.3, 0, 0))
			r.pose("spine_2", Vector3(0.22 + sin(pt) * 0.04, 0, 0))
			r.pose("neck", Vector3(-0.15, 0, 0))
			r.pose("head", Vector3(-0.25, sin(t * 0.9) * 0.1, sin(t * 1.3) * 0.06))
			r.pose("jaw", Vector3(0.44 + sin(pt) * 0.08, 0, 0))
			r.pose("arm_l", Vector3(-0.55, 0, -0.1))
			r.pose("arm_r", Vector3(-0.55, 0, 0.1))
			r.pose("forearm_l", Vector3(-0.35, 0, 0))
			r.pose("forearm_r", Vector3(-0.35, 0, 0))
			r.pose("ear_l", Vector3(0.35, 0, 0.2))
			r.pose("ear_r", Vector3(0.35, 0, -0.2))
			r.pose("tail", Vector3(0.6, 0, 0))
			r.chest_inflate = 0.2 + sin(pt) * 0.1
		"hurt":
			# r1 animation major: rebuilt in three beats (was an open-pawed "hooray" held 2 s, shoulders at 109 deg).
			# 1) 0.08 s impact snap; 2) 0.35 s recoil that clutches the hit spot; 3) a grumpy settle.
			var where: String = p.get("where", "head")
			if t < 0.08:
				r.rate = 70.0
				r.pose("head", Vector3(-0.5, 0, 0.1))
				r.pose("neck", Vector3(-0.25, 0, 0))
				r.pose("jaw", Vector3(0.8, 0, 0))
				r.pose("spine_2", Vector3(-0.2, 0, 0))
				r.pose("arm_l", Vector3(0.3, 0, 0.7))
				r.pose("arm_r", Vector3(0.3, 0, -0.7))
				r.pose("ear_l", Vector3(-0.6, 0, 0.3))
				r.pose("ear_r", Vector3(-0.6, 0, -0.3))
				r.pose("tail", Vector3(-1.3, 0, 0))
				r.root_scale = Vector3(1.15, 0.85, 1.15)
				r.cheeks_puff = 1.0
			elif t < 0.43:
				r.rate = 26.0
				var j := sin(t * 40.0) * 0.06
				r.pose("jaw", Vector3(0.55, 0, 0))
				r.pose("ear_l", Vector3(-0.7, 0, 0.35))
				r.pose("ear_r", Vector3(-0.7, 0, -0.35))
				r.cheeks_puff = 0.7
				if where == "tail":
					# Both paws clutch the seat of the trousers; the tail bristles straight up; up on tiptoe.
					r.pose("arm_l", Vector3(0.75, 0, 0.35))
					r.pose("arm_r", Vector3(0.75, 0, -0.35))
					r.pose("forearm_l", Vector3(-1.1, 0, 0))
					r.pose("forearm_r", Vector3(-1.1, 0, 0))
					r.pose("spine", Vector3(-0.25, 0, 0))
					r.pose("head", Vector3(-0.35, j * 2.0, 0))
					r.pose("tail", Vector3(-1.5, j, 0))
					r.bscale("tail", Vector3.ONE * 1.25)
					r.pose("foot_l", Vector3(0.5, 0, 0))
					r.pose("foot_r", Vector3(0.5, 0, 0))
					r.root_pos.y = 0.12
				else:
					# One paw on the crown, the other flung low; the head ducks under the blow.
					r.pose("arm_r", Vector3(-1.15, 0, -0.2))
					r.pose("forearm_r", Vector3(-1.8, 0, 0))
					r.pose("arm_l", Vector3(0.35, 0, 0.75))
					r.pose("forearm_l", Vector3(-0.2, 0, 0))
					r.pose("head", Vector3(0.35, j * 2.0, j))
					r.pose("neck", Vector3(0.15, 0, 0))
					r.pose("spine_2", Vector3(0.12, 0, 0))
					r.pose("tail", Vector3(-1.2, j * 3.0, 0))
				r.root_scale = Vector3(1.04, 0.96, 1.04)
			else:
				# Settle: rubbing the sore spot, ears back, a grumpy head shake.
				var k := clampf((t - 0.43) / 0.5, 0.0, 1.0)
				breathe(r, t, 0.6)
				r.pose("ear_l", Vector3(-0.5, 0, 0.25))
				r.pose("ear_r", Vector3(-0.5, 0, -0.25))
				r.pose("head", Vector3(0.1, sin(t * 7.0) * 0.18 * (1.0 - k * 0.6), 0))
				r.pose("jaw", Vector3(0.2, 0, 0))
				if where == "tail":
					r.pose("arm_l", Vector3(0.6, 0, 0.3))
					r.pose("forearm_l", Vector3(-1.0 + sin(t * 14.0) * 0.25, 0, 0))
					r.pose("arm_r", Vector3(-0.15, 0, -0.42))
					r.pose("forearm_r", Vector3(-0.4, 0, 0))
					r.pose("tail", Vector3(-0.9, sin(t * 9.0) * 0.3, 0))
				else:
					r.pose("arm_r", Vector3(-1.05, 0, -0.15))
					r.pose("forearm_r", Vector3(-1.75 + sin(t * 14.0) * 0.2, 0, 0))
					r.pose("arm_l", Vector3(-0.1, 0, 0.42))
					r.pose("forearm_l", Vector3(-0.35, 0, 0))
					r.pose("tail", Vector3(-0.5, 0, 0))
				r.cheeks_puff = 0.4
		"feint":
			# r1 animation major: a real fake-out. A 0.25 s lunge with a foot stamp, a 0.2 s freeze, then a snicker
			# behind the paw with a 6 Hz head bob.
			if t < 0.25:
				var k := t / 0.25
				r.rate = 40.0
				r.root_rot.x = -0.35 * k
				r.root_pos.z = -0.35 * k
				r.pose("spine", Vector3(0.35, 0, 0))
				r.pose("thigh_r", Vector3(-0.7, 0, 0))
				r.pose("shin_r", Vector3(0.5, 0, 0))
				r.pose("arm_l", Vector3(-0.6, 0, -0.1))
				r.pose("arm_r", Vector3(-0.6, 0, 0.1))
				r.pose("jaw", Vector3(0.4, 0, 0))
				r.pose("ear_l", Vector3(0.6, 0, 0))
				r.pose("ear_r", Vector3(0.6, 0, 0))
			elif t < 0.45:
				r.rate = 40.0
				r.root_rot.x = -0.35
				r.root_pos.z = -0.35
				r.pose("spine", Vector3(0.35, 0, 0))
				r.pose("arm_l", Vector3(-0.6, 0, -0.1))
				r.pose("arm_r", Vector3(-0.6, 0, 0.1))
			else:
				var bob := sin((t - 0.45) * TAU * 6.0)
				breathe(r, t)
				arms_rest(r)
				r.pose("arm_l", Vector3(-1.1, 0, 0.15))
				r.pose("forearm_l", Vector3(-2.0, 0.3, 0))
				r.pose("head", Vector3(0.12 + bob * 0.08, 0.25, 0))
				r.pose("spine_2", Vector3(0.1 + bob * 0.05, 0, 0))
				r.pose("arm_r", Vector3(-0.35, 0, -0.2))
				r.pose("forearm_r", Vector3(-0.6, 0, 0))
				r.pose("tail", Vector3(0.2, sin(t * 10.0) * 0.5, 0))
				r.cheeks_puff = 0.5 + 0.3 * maxf(0.0, bob)
				r.root_pos.y = maxf(0.0, bob) * 0.03
		"dangle":
			# r1 animation: hanging off the lip by both paws, legs bicycling, tail windmilling, then a casual one-paw
			# hang before he hauls himself up.
			var ph := t * TAU * 2.2
			r.rate = 20.0
			var casual := clampf((t - 0.8) / 0.3, 0.0, 1.0)
			r.pose("arm_l", Vector3(-2.7, 0, 0.15))
			r.pose("forearm_l", Vector3(-0.2, 0, 0))
			r.pose("arm_r", Vector3(lerpf(-2.7, -0.3, casual), 0, lerpf(-0.15, -0.6, casual)))
			r.pose("forearm_r", Vector3(lerpf(-0.2, -1.6, casual), 0, 0))
			r.pose("thigh_l", Vector3(-0.6 + sin(ph) * 0.7, 0, 0.1))
			r.pose("thigh_r", Vector3(-0.6 - sin(ph) * 0.7, 0, -0.1))
			r.pose("shin_l", Vector3(0.8 + maxf(0.0, cos(ph)) * 0.8, 0, 0))
			r.pose("shin_r", Vector3(0.8 + maxf(0.0, -cos(ph)) * 0.8, 0, 0))
			r.pose("tail", Vector3(-0.6, sin(t * TAU * 3.0) * 1.1, 0))
			r.pose("tail_2", Vector3(0, sin(t * TAU * 3.0 - 0.8) * 0.6, 0))
			r.pose("head", Vector3(-0.3 * (1.0 - casual), 0.35 * casual, 0))
			r.pose("jaw", Vector3(0.45 * (1.0 - casual), 0, 0))
			r.pose("coat_l", Vector3(-0.4, 0, 0.2))
			r.pose("coat_r", Vector3(-0.4, 0, -0.2))
		"tumble":
			# Soot tumble: tucked into a ball for the backward arc (the boss spins the root).
			r.rate = 24.0
			r.pose("thigh_l", Vector3(-1.6, 0, 0.2))
			r.pose("thigh_r", Vector3(-1.6, 0, -0.2))
			r.pose("shin_l", Vector3(2.0, 0, 0))
			r.pose("shin_r", Vector3(2.0, 0, 0))
			r.pose("arm_l", Vector3(-0.9, 0, -0.2))
			r.pose("arm_r", Vector3(-0.9, 0, 0.2))
			r.pose("forearm_l", Vector3(-1.6, 0, 0))
			r.pose("forearm_r", Vector3(-1.6, 0, 0))
			r.pose("spine", Vector3(0.45, 0, 0))
			r.pose("spine_2", Vector3(0.35, 0, 0))
			r.pose("head", Vector3(0.5, 0, 0))
			r.pose("tail", Vector3(-1.2, 0, 0))
			r.pose("jaw", Vector3(0.6, 0, 0))
			r.cheeks_puff = 1.0
		"cane_guard":
			# The deflect: cane snapped across the chest, a sniff of disdain.
			r.rate = 40.0
			r.pose("arm_r", Vector3(-1.05, 0, -0.3))
			r.pose("forearm_r", Vector3(-1.2, 0.6, 0))
			r.pose("hand_r", Vector3(0, 0, 1.4))
			r.pose("arm_l", Vector3(-0.8, 0, 0.35))
			r.pose("forearm_l", Vector3(-1.3, -0.5, 0))
			r.pose("head", Vector3(-0.25, -0.3, 0.1))
			r.pose("spine", Vector3(-0.1, 0, 0))
			r.root_pos.z = 0.15
			r.chest_inflate = 0.8
		"tail_swat":
			breathe(r, t)
			arms_rest(r)
			var tell: float = p.get("tell", 0.5)
			if t < tell:
				var jit := sin(t * 188.0) * 0.08
				r.bscale("tail", Vector3.ONE * 1.15)
				r.pose("tail", Vector3(-0.5, jit, jit))
				r.pose("head", Vector3(0, 0.6, 0))
				r.pose("neck", Vector3(0, 0.4, 0))
			else:
				var k := clampf((t - tell) / 0.2, 0.0, 1.0)
				r.rate = 30.0
				r.pose("tail", Vector3(-0.2, 1.2 * k, 0))
				r.pose("tail_2", Vector3(0, 0.6 * k, 0))
				r.pose("spine", Vector3(0, -0.3 * k, 0))
		"paw":
			breathe(r, t, 0.5)
			var scr := sin(t * TAU * 2.5)
			r.root_rot.x = -0.12
			r.pose("thigh_r", Vector3(-0.35 + scr * 0.25, 0, 0))
			r.pose("shin_r", Vector3(0.3 - scr * 0.2, 0, 0))
			r.pose("spine", Vector3(0.25, 0, 0))
			r.pose("head", Vector3(0.35, 0, 0))
			r.pose("arm_l", Vector3(0.4, 0, -0.1))
			r.pose("arm_r", Vector3(0.4, 0, 0.1))
			r.pose("forearm_l", Vector3(-0.8, 0, 0))
			r.pose("forearm_r", Vector3(-0.8, 0, 0))
			r.pose("ear_l", Vector3(0.5, 0, 0))
			r.pose("ear_r", Vector3(0.5, 0, 0))
			r.pose("tail", Vector3(-0.6, sin(t * 9.0) * 0.4, 0))
			r.cheeks_puff = 0.5 + 0.5 * maxf(0.0, sin(t * TAU * 2.5))
		"charge":
			r.rate = 20.0
			var ph := t * TAU * 4.0
			r.root_rot.x = -0.28
			r.root_pos.y = absf(sin(ph)) * 0.18
			r.pose("spine", Vector3(0.3, 0, 0))
			r.pose("spine_2", Vector3(0.15, 0, 0))
			r.pose("head", Vector3(0.1, 0, 0))
			r.pose("arm_l", Vector3(0.7, 0, -0.15))
			r.pose("arm_r", Vector3(0.7, 0, 0.15))
			r.pose("thigh_l", Vector3(-sin(ph) * 0.8, 0, 0))
			r.pose("thigh_r", Vector3(sin(ph) * 0.8, 0, 0))
			r.pose("shin_l", Vector3(maxf(0.0, cos(ph)) * 1.2, 0, 0))
			r.pose("shin_r", Vector3(maxf(0.0, -cos(ph)) * 1.2, 0, 0))
			r.pose("coat_l", Vector3(0.55, 0, 0.1))
			r.pose("coat_r", Vector3(0.55, 0, -0.1))
			r.pose("coat_l_2", Vector3(0.3 + sin(ph * 2.0) * 0.15, 0, 0))
			r.pose("coat_r_2", Vector3(0.3 - sin(ph * 2.0) * 0.15, 0, 0))
			r.pose("ear_l", Vector3(0.7, 0, 0))
			r.pose("ear_r", Vector3(0.7, 0, 0))
			r.pose("tail", Vector3(0.9, 0, 0))
			r.pose("jaw", Vector3(0.25, 0, 0))
		"stuck":
			r.rate = 16.0
			var kk := sin(t * TAU * 3.0)
			r.root_rot.x = -0.32
			r.root_pos.z = -0.35
			r.pose("spine", Vector3(0.55, 0, 0))
			r.pose("spine_2", Vector3(0.45, 0, 0))
			r.pose("spine_3", Vector3(0.35, 0, 0))
			r.pose("neck", Vector3(0.25, 0, 0))
			r.pose("thigh_l", Vector3(-0.25 + kk * 0.5, 0, 0.15))
			r.pose("thigh_r", Vector3(-0.25 - kk * 0.5, 0, -0.15))
			r.pose("shin_l", Vector3(0.6 + maxf(0.0, kk) * 0.6, 0, 0))
			r.pose("shin_r", Vector3(0.6 + maxf(0.0, -kk) * 0.6, 0, 0))
			r.pose("arm_l", Vector3(0.9 + sin(t * 11.0) * 0.3, 0, 0.5))
			r.pose("arm_r", Vector3(0.9 - sin(t * 11.0) * 0.3, 0, -0.5))
			r.pose("tail", Vector3(-1.1, sin(t * TAU * 2.5) * 0.7, 0))
			r.pose("tail_2", Vector3(-0.2, sin(t * TAU * 2.5 - 0.7) * 0.5, 0))
			r.pose("tail_3", Vector3(0, sin(t * TAU * 2.5 - 1.4) * 0.5, 0))
			r.pose("coat_l", Vector3(0.6, 0, 0.3))
			r.pose("coat_r", Vector3(0.6, 0, -0.3))
		"pull_free":
			var k := clampf(t / 0.6, 0.0, 1.0)
			r.root_rot.x = lerpf(-0.32, 0.1, k)
			r.pose("spine", Vector3(lerpf(0.55, -0.2, k), 0, 0))
			r.pose("head", Vector3(0, sin(t * 20.0) * 0.3 * (1.0 - k), 0))
			r.pose("arm_l", Vector3(0, 0, 0.6 * (1.0 - k)))
			r.pose("arm_r", Vector3(0, 0, -0.6 * (1.0 - k)))
			r.pose("tail", Vector3(-0.8, sin(t * 25.0) * 0.4, 0))
			r.cheeks_puff = 0.6
		"teeter":
			r.rate = 18.0
			var w := t * TAU / 0.6
			r.root_rot.x = sin(t * TAU * 1.5) * 0.2 + 0.05
			r.pose("arm_l", Vector3(sin(w) * 1.3, 0, 0.6))
			r.pose("arm_r", Vector3(sin(w + PI) * 1.3, 0, -0.6))
			r.pose("tail", Vector3(-1.4, 0, 0))
			r.pose("head", Vector3(0.3, sin(t * 4.0) * 0.2, 0))
			r.pose("jaw", Vector3(0.3, 0, 0))
		"dizzy":
			breathe(r, t)
			r.pose("head", Vector3(sin(t * TAU) * 0.26, cos(t * TAU) * 0.26, 0))
			r.pose("neck", Vector3(0, cos(t * TAU) * 0.1, 0))
			r.pose("arm_l", Vector3(-0.2, 0, 0.2 + sin(t * 3.0) * 0.15))
			r.pose("arm_r", Vector3(-0.2, 0, -0.2 - sin(t * 3.0) * 0.15))
			r.pose("jaw", Vector3(0.3, 0, 0))
			r.root_rot.z = sin(t * TAU * 0.8) * 0.09
			r.root_rot.x = cos(t * TAU * 0.8) * 0.06
			r.pose("tail", Vector3(0.5, 0, 0))
		"spin":
			# r1 animation: a dervish, not a T-pose: one paw clamps the hat brim, the cane arm sweeps out and back.
			r.rate = 18.0
			r.pose("arm_l", Vector3(-1.0, 0, 0.75))
			r.pose("forearm_l", Vector3(-1.5, 0, 0))
			r.pose("arm_r", Vector3(0.25 + sin(t * 9.0) * 0.15, 0, -1.2))
			r.pose("forearm_r", Vector3(-0.35, 0, -0.1))
			r.pose("spine", Vector3(0.1, sin(t * 9.0) * 0.12, 0))
			r.pose("coat_l", Vector3(0.87, 0, 0.5))
			r.pose("coat_r", Vector3(0.87, 0, -0.5))
			r.pose("coat_l_2", Vector3(0.3, 0, 0))
			r.pose("coat_r_2", Vector3(0.3, 0, 0))
			r.pose("tail", Vector3(0.9, 0, 0))
			r.pose("head", Vector3(-0.15, 0, 0))
			r.pose("ear_l", Vector3(0.6, 0, 0.3))
			r.pose("ear_r", Vector3(0.6, 0, -0.3))
			r.cheeks_puff = 0.6
			r.chest_inflate = 0.35
		"look_up":
			r.pose("head", Vector3(-0.87, 0, 0))
			r.pose("neck", Vector3(-0.3, 0, 0))
			r.pose("jaw", Vector3(0.6, 0, 0))
			r.pose("arm_l", Vector3(0.2, 0, 0.6))
			r.pose("arm_r", Vector3(0.2, 0, -0.6))
			r.cheeks_puff = 1.0
			r.chest_inflate = clampf(t / 0.6, 0.0, 1.0)
		"cough":
			var c := absf(sin(t * TAU * 1.5))
			r.pose("spine", Vector3(0.35 * c, 0, 0))
			r.pose("spine_2", Vector3(0.2 * c, 0, 0))
			r.pose("head", Vector3(0.3 * c, 0, 0))
			r.pose("jaw", Vector3(0.5 * c, 0, 0))
			r.pose("arm_r", Vector3(-1.0, 0, 0.2))
			r.pose("forearm_r", Vector3(-1.4, 0, 0))
			r.cheeks_puff = c
		"swell":
			# r1 animation major: a balloon wolf, not a big wolf. The belly (spine_2/3) swells non-uniformly while the
			# neck and arms are counter-scaled; the belly shoves the arms up and out, paws flail, feet kick.
			var k: float = p.get("k", clampf(t / 1.2, 0.0, 1.0))
			r.rate = 12.0
			r.chest_inflate = 1.0
			r.cheeks_puff = 1.0
			var b2 := lerpf(1.0, 1.55, k)
			var b3 := lerpf(1.0, 1.32, k)
			r.root_scale = Vector3.ONE * lerpf(1.0, 1.12, k)
			r.bscale("spine_2", Vector3(b2, lerpf(1.0, 1.35, k), b2))
			r.bscale("spine_3", Vector3(b3, lerpf(1.0, 1.18, k), b3))
			var inv := 1.0 / (b2 * b3)
			r.bscale("neck", Vector3.ONE * inv * lerpf(1.0, 1.15, k))
			r.bscale("arm_l", Vector3.ONE * inv * lerpf(1.0, 1.1, k))
			r.bscale("arm_r", Vector3.ONE * inv * lerpf(1.0, 1.1, k))
			var fl := sin(t * TAU * 5.0)
			r.pose("arm_l", Vector3(-0.6, 0, 1.4 * k))
			r.pose("arm_r", Vector3(-0.6, 0, -1.4 * k))
			r.pose("forearm_l", Vector3(-0.9 * k, 0, 0))
			r.pose("forearm_r", Vector3(-0.9 * k, 0, 0))
			r.pose("hand_l", Vector3(0, 0, fl * 0.6))
			r.pose("hand_r", Vector3(0, 0, -fl * 0.6))
			var kk := sin(t * TAU * 3.0)
			r.pose("thigh_l", Vector3(-0.6 + kk * 0.5, 0, 0.3))
			r.pose("thigh_r", Vector3(-0.6 - kk * 0.5, 0, -0.3))
			r.pose("shin_l", Vector3(0.4 + maxf(0.0, kk) * 0.6, 0, 0))
			r.pose("shin_r", Vector3(0.4 + maxf(0.0, -kk) * 0.6, 0, 0))
			r.pose("head", Vector3(-0.3, sin(t * 4.0) * 0.25, 0))
			r.pose("jaw", Vector3(0.35, 0, 0))
			r.pose("ear_l", Vector3(-0.5, 0, 0.4))
			r.pose("ear_r", Vector3(-0.5, 0, -0.4))
			r.pose("tail", Vector3(-1.0, sin(t * 9.0) * 0.5, 0))
		"wedged":
			# Belly stays round; the arms are pinned on the chimney rim pushing, the legs kick in the air.
			var kk := sin(t * TAU * 3.0)
			r.chest_inflate = 1.0
			r.cheeks_puff = 1.0
			r.root_scale = Vector3.ONE * 1.12
			r.bscale("spine_2", Vector3(1.55, 1.35, 1.55))
			r.bscale("spine_3", Vector3(1.32, 1.18, 1.32))
			var inv := 1.0 / (1.55 * 1.32)
			r.bscale("neck", Vector3.ONE * inv * 1.15)
			r.bscale("arm_l", Vector3.ONE * inv * 1.1)
			r.bscale("arm_r", Vector3.ONE * inv * 1.1)
			var push := sin(t * 7.0)
			r.pose("arm_l", Vector3(0.45 + push * 0.2, 0, 1.0))
			r.pose("arm_r", Vector3(0.45 - push * 0.2, 0, -1.0))
			r.pose("forearm_l", Vector3(-1.3, 0, 0))
			r.pose("forearm_r", Vector3(-1.3, 0, 0))
			r.pose("thigh_l", Vector3(-1.2 + kk * 0.5, 0, 0.3))
			r.pose("thigh_r", Vector3(-1.2 - kk * 0.5, 0, -0.3))
			r.pose("shin_l", Vector3(0.3 + maxf(0.0, kk) * 0.6, 0, 0))
			r.pose("shin_r", Vector3(0.3 + maxf(0.0, -kk) * 0.6, 0, 0))
			r.pose("head", Vector3(0.05, sin(t * 3.0) * 0.3, 0))
			r.pose("jaw", Vector3(0.35, 0, 0))
			r.pose("tail", Vector3(-0.8, sin(t * 6.0) * 0.6, 0))
			var bo := float(p.get("boing", 0.0))
			r.root_scale *= Vector3(1.0 + bo * 0.08, 1.0 - bo * 0.12, 1.0 + bo * 0.08)
		"float_away":
			r.rate = 12.0
			r.chest_inflate = clampf(1.0 - t / 0.3, 0.0, 1.0)
			r.cheeks_puff = 1.0
			r.pose("arm_l", Vector3(-1.6, 0, 0.6))
			r.pose("arm_r", Vector3(-1.6, 0, -0.6))
			r.pose("thigh_l", Vector3(-0.8, 0, 0.4))
			r.pose("thigh_r", Vector3(-0.8, 0, -0.4))
			r.pose("jaw", Vector3(0.7, 0, 0))
			r.pose("tail", Vector3(-1.2, 0, 0))
		"pose_cork":
			r.pose("arm_l", Vector3(0, 0, 1.0))
			r.pose("arm_r", Vector3(0, 0, -1.0))
		_:
			breathe(r, t)
			arms_rest(r)
