extends Node
## Headless test of juice_sfx.json through the real autoloads (Audio, Juice -> JuiceSfx child).
## Fires every event with representative params, then checks: every layer key resolves in the Audio index, cooldowns
## and per-second caps stop spam, voice priority and per-line cooldowns, pickup chain pitch rises, loops start and stop,
## UI events skip when ui_sfx is set, handoff events stay silent without Juice.owns(), and case selection by params.
## Run: python tools/godot.py run res://assets/audio/tests/JuiceSfxTest.tscn --headless --seconds 40 -- --profile=audio --out=<abs json>

var sfx: Node
var fails: Array = []
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var juice := get_node_or_null("/root/Juice")
	sfx = juice.get_node_or_null("JuiceSfx") if juice else null
	if sfx == null:
		sfx = load("res://assets/audio/juice_sfx.gd").new()
		add_child(sfx)
		await get_tree().process_frame
	var audio := get_node_or_null("/root/Audio")
	_ok(audio != null, "Audio autoload present")
	_ok(sfx.events.size() > 100, "events loaded: %d" % sfx.events.size())

	# 1. ownership: the player defers to Juice (mak_player._fb), so JuiceSfx must own player events; the boss still
	#    plays direct Audio calls, so boss events stay silent here until Juice.owns() exists.
	sfx.log_plays = true
	sfx.force_handoff = false
	var owns := juice != null and juice.has_method("owns")
	_ok(sfx.has_event("player_footstep") and sfx.has_event("player_jump_1") and sfx.has_event("player_bonk"), "player events owned by JuiceSfx")
	_ok(sfx.handle("player_footstep", Vector3.ZERO, {"surface": "wood", "speed": 6.0}), "player_footstep plays")
	_ok(sfx.played.size() > 0 and String(sfx.played[-1]["key"]).begins_with("footstep_wood"), "footstep follows the surface param")
	# fix stage r1: the boss events have no handoff any more (wolf_boss.gd asks Juice.handles per moment)
	_ok(sfx.has_event("boss_stomp") and sfx.has_event("boss_inhale") and sfx.has_event("boss_defeat"), "boss events owned by JuiceSfx (no handoff)")
	var handoffs: Array = sfx.events.keys().filter(func(k): return String(sfx.events[k].get("handoff", "")) == "owns")
	_ok(handoffs.is_empty() or owns, "no event still waits for a handoff: %s" % str(handoffs))
	_ok(sfx.has_event("object_crate_break") and sfx.has_event("object_npc_talk") and sfx.has_event("object_hazard_touch"), "objects: has_event true")
	_ok(not sfx.ambience.is_empty() and String(sfx.ambience.get("beds", {}).get("W2", "")) == "amb_w2", "ambience beds configured")
	_ok(audio == null or bool(audio.call("has_key", "amb_hub")) and bool(audio.call("has_key", "amb_boss")), "ambience bed keys resolve")
	sfx.force_handoff = true
	sfx.set("_scene_changed_at", -1e9)  # the test scene just loaded; world-entry suppression is checked in step 9

	# 2. every event with representative params; every played key must exist in the index
	var fams := ["woolly_wolf", "crow_bandit", "peapod_popper", "bumble_bruiser", "gingerbread_grenadier", "gummy_brute"]
	var kinds := ["jump", "double_jump", "triple_jump", "long_jump", "backflip", "side_flip", "wall_kick", "pole_jump", "rollout",
		"punch", "kick", "jump_kick", "dive", "slide", "stomp", "slam", "tail", "leaf", "gumdrop", "drum", "pad"]
	var surfaces := ["grass", "wood", "stone", "candy", "carpet", "jelly", "metal", "cloud", "unknown_surface"]
	var fired := 0
	# r1b: layers with chance < 1 (object_portal_page_turn 0.65) failed this check one run in three; the sweep forces chance
	sfx.set("force_chance", true)
	for ev in sfx.events.keys():
		var variants: Array = [{}]
		var spec: Dictionary = sfx.events[ev]
		for c in spec.get("cases", []):
			variants.append((c["when"] as Dictionary).duplicate())
		for v in variants:
			var p: Dictionary = {}
			for k in v.keys():
				var cond: Variant = v[k]
				if cond is Array:
					p[k] = (cond[1][0] if cond[0] == "in" else float(cond[1]) + 0.5)
				else:
					p[k] = cond
			p["surface"] = surfaces[fired % surfaces.size()]
			p["speed"] = 5.0
			p["impact"] = p.get("impact", 9.0)
			if not p.has("family"):
				p["family"] = fams[fired % fams.size()]
			sfx.call("_reset_cooldowns")
			sfx.handle(String(ev), Vector3(0, 1, -4), p)
			fired += 1
	await get_tree().create_timer(1.5).timeout  # delayed layers
	sfx.set("force_chance", false)
	var idx_keys: Dictionary = {}
	for k in audio.index.keys():
		idx_keys[k] = true
	var bad: Array = []
	for r in sfx.played:
		if not idx_keys.has(r["key"]):
			bad.append(r["key"])
	_ok(bad.is_empty(), "every played key exists (%d plays from %d firings) %s" % [sfx.played.size(), fired, str(bad)])
	var events_with_sound := {}
	for r in sfx.played:
		events_with_sound[r["event"]] = true
	var silent: Array = []
	for ev in sfx.events.keys():
		if not events_with_sound.has(ev) and not sfx.events[ev].get("silent", false) and not (sfx.events[ev].get("layers", []) as Array).is_empty():
			silent.append(ev)
	# r1b: a delayed layer (object_portal_page_turn has up to 0.8 s of delay jitter) can land within the 60 ms same-key gap
	# of another event's book_page_turn fired in the same sweep and is then skipped by design; such events get one solo retry
	if not silent.is_empty():
		sfx.set("force_chance", true)
		for ev in silent.duplicate():
			sfx.call("_reset_cooldowns")
			(sfx.get("_last_key") as Dictionary).clear()
			sfx.handle(String(ev), Vector3(0, 1, -4), {"surface": "grass", "speed": 5.0, "impact": 9.0, "family": "woolly_wolf"})
			await get_tree().create_timer(1.0).timeout
			if sfx.played.any(func(r): return r["event"] == ev):
				silent.erase(ev)
				print("NOTE %s played on its solo retry (same-key gap collision in the sweep)" % ev)
		sfx.set("force_chance", false)
	_ok(silent.is_empty(), "every non-silent event played something: missing %s" % str(silent))

	# 3. surface template + fallback
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("player_footstep", Vector3.ZERO, {"surface": "carpet", "speed": 6.0})
	sfx.call("_reset_cooldowns")
	sfx.handle("player_footstep", Vector3.ZERO, {"surface": "lava_unknown", "speed": 6.0})
	_ok(sfx.played.size() == 2 and sfx.played[0]["key"] == "footstep_carpet" and sfx.played[1]["key"] == "footstep_grass", "footstep surface + fallback: %s" % str(sfx.played.map(func(r): return r["key"])))

	# 4. spam control: 40 footsteps in one frame -> 1; 30 enemy_hurt over 1 s from one family -> capped
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	for i in 40:
		sfx.handle("player_footstep", Vector3.ZERO, {"surface": "grass", "speed": 6.0})
	_ok(sfx.played.size() == 1, "footstep cooldown: 40 same-frame calls -> %d play" % sfx.played.size())
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	var t_spam := Time.get_ticks_msec()
	for i in 30:
		sfx.handle("enemy_hurt", Vector3(0, 1, -5), {"family": "crow_bandit"})
		await get_tree().create_timer(1.0 / 30.0).timeout
	var spam_s := (Time.get_ticks_msec() - t_spam) / 1000.0  # timers snap to frames, so 30 waits can take longer than 1 s
	var hurt_plays: int = sfx.played.filter(func(r): return r["key"] == "enemy_hit").size()
	var hurt_cap := int(ceil(spam_s * 12.5)) + 1
	_ok(hurt_plays <= hurt_cap and hurt_plays >= 6 and hurt_plays < 30, "enemy_hurt 30 calls in %.2f s -> %d plays (cooldown 0.08 s, cap 12/s, limit %d)" % [spam_s, hurt_plays, hurt_cap])

	# 5. voice: per-line cooldown and priority
	await get_tree().create_timer(2.0).timeout
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	var v1: bool = sfx.call("_voice", audio, "voice_mak_jump1", 1, 0.25)
	var v2: bool = sfx.call("_voice", audio, "voice_mak_jump2", 1, 0.25)
	var v3: bool = sfx.call("_voice", audio, "voice_mak_hurt", 3, 0.25)
	_ok(v1 and not v2 and v3, "voice priority: first plays, equal priority blocked while busy, higher interrupts (%s %s %s)" % [v1, v2, v3])

	# 6. chain pitch for acorns
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	for i in 5:
		sfx.handle("object_acorn_collect", Vector3.ZERO, {})
		await get_tree().create_timer(0.1).timeout
	var pitches: Array = sfx.played.map(func(r): return r["pitch"])
	_ok(pitches.size() == 5 and float(pitches[4]) > float(pitches[0]) * 1.2, "acorn chain pitch rises: %s" % str(pitches))

	# 7. loops start and stop
	sfx.call("_reset_cooldowns")
	sfx.handle("player_slide_start", Vector3.ZERO, {"node": self})
	await get_tree().create_timer(0.3).timeout
	var looping: bool = sfx._loops.has("slide")
	sfx.handle("player_slide_end", Vector3.ZERO, {"node": self})
	await get_tree().create_timer(0.4).timeout
	_ok(looping and not sfx._loops.has("slide"), "slide loop starts and stops")
	sfx.handle("boss_tornado_spawn", Vector3(0, 0, -10), {})
	await get_tree().create_timer(0.2).timeout
	var t_on: bool = sfx._loops.has("tornado")
	sfx.handle("boss_tornado_end", Vector3.ZERO, {})
	await get_tree().create_timer(1.2).timeout
	_ok(t_on and not sfx._loops.has("tornado"), "tornado loop starts and stops")

	# 8. UI skip when ui_fx already played it; cases by kind
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("ui_move", Vector3.INF, {"ui_sfx": true})
	_ok(sfx.played.is_empty(), "ui_move skipped when ui_sfx is set")
	sfx.handle("player_jump", Vector3.ZERO, {"kind": "triple_jump"})
	_ok(sfx.played.size() >= 1 and sfx.played[0]["key"] == "jump_3", "player_jump kind triple_jump -> jump_3")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("player_land", Vector3.ZERO, {"impact": 14.0, "surface": "wood"})
	_ok(sfx.played.size() >= 1 and sfx.played[0]["key"] == "land_heavy", "player_land impact 14 -> land_heavy")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("enemy_defeat", Vector3.ZERO, {"family": "gummy_brute"})
	_ok(sfx.played.size() >= 1 and sfx.played[0]["key"] == "gummy_melt", "enemy_defeat gummy -> gummy_melt")
	var game := get_node_or_null("/root/Game")
	if game != null and "current_world" in game:
		var was: String = game.get("current_world")
		game.set("current_world", "HUB")
		sfx.played.clear()
		sfx.call("_reset_cooldowns")
		sfx.handle("player_footstep", Vector3.ZERO, {"surface": "grass", "speed": 6.0})
		game.set("current_world", was)
		_ok(sfx.played.size() >= 1 and sfx.played[0]["key"] == "footstep_wood", "HUB default surface grass -> footstep_wood")
	for key in ["door_slam", "sfx_seed_whoosh", "enemy_flap"]:
		_ok(audio == null or bool(audio.call("has_key", key)), "script key resolves: " + key)
	for pair in [["Daisy", "npc_greet_cow"], ["Cousin Pip", "npc_greet_piglet"], ["Mother Treacle", "npc_greet_granny"], ["Jack", "npc_greet_boy"]]:
		sfx.played.clear()
		sfx.call("_reset_cooldowns")
		sfx.handle("object_npc_greet", Vector3.ZERO, {"speaker": pair[0]})
		_ok(sfx.played.size() >= 1 and sfx.played[0]["key"] == pair[1], "object_npc_greet %s -> %s" % pair)

	# 9. fix stage r1 (critique round 1)
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("player_hurt", Vector3.ZERO, {})
	sfx.call("_reset_cooldowns")
	sfx.handle("player_heal", Vector3.ZERO, {})
	await get_tree().create_timer(0.2).timeout
	var cake: Array = sfx.played.filter(func(r): return String(r["key"]).begins_with("cake_slice"))
	_ok(cake.is_empty(), "hurt/heal no longer layer the HUD's cake sound: %s" % str(cake))
	if game != null and "health" in game:
		var hp: int = game.get("health")
		game.set("health", 0)
		sfx.played.clear()
		sfx.call("_reset_cooldowns")
		sfx.handle("player_hurt", Vector3.ZERO, {})
		_ok(sfx.played.is_empty(), "lethal hurt is skipped (death owns the moment)")
		game.set("health", hp)
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.set("_scene_changed_at", Time.get_ticks_msec() / 1000.0)
	sfx.handle("player_respawn", Vector3.ZERO, {})
	_ok(sfx.played.is_empty(), "respawn sting skipped right after a scene change (world entry)")
	sfx.set("_scene_changed_at", -1e9)
	sfx.handle("player_respawn", Vector3.ZERO, {})
	_ok(sfx.played.size() == 1 and sfx.played[0]["key"] == "respawn", "respawn sting plays later")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("boss_charge_start", Vector3(0, 0, -5), {})
	_ok(sfx.played.size() == 1 and sfx.played[0]["key"] == "boss_charge", "boss_charge_start: no doubled growl")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("boss_hit", Vector3(0, 1, -5), {"kind": "tail"})
	await get_tree().create_timer(0.15).timeout
	_ok(sfx.played.filter(func(r): return bool(r["voice"])).is_empty(), "boss tail hit: the wolf speaks its own line (no table voice)")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.call("_play_key", "punch", Vector3.INF, {}, {}, "t1")
	sfx.call("_play_key", "punch", Vector3.INF, {}, {}, "t2")
	_ok(sfx.played.size() == 1, "same key twice within 60 ms -> %d play" % sfx.played.size())
	if audio != null:
		sfx.call("_reset_cooldowns")
		audio.call("play_voice", "voice_wolf_laugh")
		var grunt: bool = sfx.call("_voice", audio, "voice_mak_hurt", 3, 0.25)
		var death: bool = sfx.call("_voice", audio, "voice_mak_blast", 4, 0.25)
		_ok(not grunt and death, "a line started outside JuiceSfx is not cut by a grunt (%s) but by priority 4 (%s)" % [grunt, death])
		audio.call("stop_voice")
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("ui_cake_low", Vector3.INF, {"ui_sfx": true, "health": 2})
	_ok(sfx.played.size() == 1 and sfx.played[0]["key"] == "low_health", "ui_cake_low -> low_health")
	# boss bed phases
	var worlds: Dictionary = sfx.ambience.get("worlds", {})
	_ok(worlds.has("HUB") and worlds.has("W1") and worlds.has("W2") and worlds.has("W3") and worlds.has("BOSS"), "layered beds for all five worlds")
	sfx.set("ambience_follow", false)
	sfx.call("_start_bed", "BOSS", worlds["BOSS"])
	await get_tree().create_timer(2.3).timeout
	var bed: Array = sfx.get("_bed")
	var vols := {}
	for b in bed:
		vols[b["key"]] = snappedf((b["player"] as AudioStreamPlayer).volume_db, 0.1)
	_ok(bed.size() == 6 and float(vols.get("amb_boss_la", 0.0)) < -50.0 and float(vols.get("amb_boss_wind_a", -99.0)) > -30.0,
		"boss bed phase 1: wind only, no rain %s" % str(vols))
	sfx.call("set_bed_phase", 3)
	await get_tree().create_timer(3.3).timeout
	var vols3 := {}
	for b in bed:
		vols3[b["key"]] = snappedf((b["player"] as AudioStreamPlayer).volume_db, 0.1)
	_ok(float(vols3.get("amb_boss_la", -99.0)) > -30.0 and float(vols3.get("amb_sky_loop", 0.0)) < -50.0, "boss bed phase 3: storm and rain %s" % str(vols3))
	sfx.call("_bed_fade_all", 0.1)
	sfx.set("bed_world", "")
	sfx.set("ambience_follow", true)

	# 10. fix stage r1b (critique r1 re-check)
	for key in ["bounce", "cloud_poof", "whoosh", "bee_buzz", "bee_buzz_loop", "slide_loop_grass", "slide_loop_wood", "slide_loop_candy", "slide_loop_stone"]:
		_ok(audio == null or bool(audio.call("has_key", key)), "r1b key resolves: " + key)
	if audio != null:
		_ok(not bool(audio.index["bee_buzz"]["loop"]) and bool(audio.index["bee_buzz_loop"]["loop"]), "bee_buzz (play_sfx from w2_life) is a one-shot; bee_buzz_loop loops")
	for pair in [["wood", "slide_loop_wood"], ["jelly", "slide_loop_candy"], ["grass", "slide_loop_grass"], ["metal", "slide_loop_stone"]]:
		sfx.call("_reset_cooldowns")
		sfx.handle("player_slide_start", Vector3.ZERO, {"surface": pair[0], "node": self})
		await get_tree().process_frame
		var lk := String(sfx._loops["slide"].get("key", "")) if sfx._loops.has("slide") else "(none)"
		sfx.handle("player_slide_end", Vector3.ZERO, {})
		await get_tree().create_timer(0.3).timeout
		_ok(lk == pair[1], "slide loop follows the surface: %s -> %s (%s)" % [pair[0], pair[1], lk])
	# the death line is cancelled by a respawn that comes first, and plays otherwise
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("player_death", Vector3.ZERO, {})
	await get_tree().create_timer(0.1).timeout
	sfx.set("_scene_changed_at", -1e9)
	sfx.handle("player_respawn", Vector3.ZERO, {})
	await get_tree().create_timer(0.6).timeout
	var blast1: int = sfx.played.filter(func(r): return r["key"] == "voice_mak_blast").size()
	sfx.played.clear()
	sfx.call("_reset_cooldowns")
	sfx.handle("player_death", Vector3.ZERO, {})
	await get_tree().create_timer(0.6).timeout
	var blast2: int = sfx.played.filter(func(r): return r["key"] == "voice_mak_blast").size()
	_ok(blast1 == 0 and blast2 == 1, "death line cancelled by an earlier respawn (%d) and plays at 0.4 s otherwise (%d)" % [blast1, blast2])
	if audio != null:
		audio.call("stop_voice")
	# curl sting into the boss, none into W1
	sfx.played.clear()
	sfx.call("_curl_sting", "W1")
	sfx.call("_curl_sting", "BOSS")
	await get_tree().create_timer(1.4).timeout
	var stings: Array = sfx.played.filter(func(r): return r["event"] == "curl_sting").map(func(r): return r["key"])
	_ok(stings == ["drum_roll", "thunder", "drum_boom"], "curl sting into the boss only: %s" % str(stings))
	_ok(not bool(sfx.get("force_chance")), "force_chance is off outside the sweep")

	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var res := {"checks": checks, "failures": fails, "events": sfx.events.size(), "firings": fired}
	print("JUICE_SFX_TEST ", JSON.stringify(res))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, " "))
	get_tree().quit(0 if fails.is_empty() else 1)


func _ok(cond: bool, what: String) -> void:
	checks += 1
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails.append(what)
