extends Node
## Waits for W1 to be the current scene, then attaches the bot copy to the world root.

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and "world_id" in cs and cs.get_node_or_null("Level") != null and get_tree().get_first_node_in_group("player") != null:
			var dev := get_node_or_null("/root/Dev")
			if dev and dev.has_arg("qa-buffer"):
				var pl := get_tree().get_first_node_in_group("player")
				var prof: Variant = pl.get("p")
				if prof:
					print("[W1BotQA] jump_buffer_time %s -> %s (test override)" % [prof.get("jump_buffer_time"), dev.arg("qa-buffer", "0.133")])
					prof.set("jump_buffer_time", float(dev.arg("qa-buffer", "0.133")))
			if dev and dev.has_arg("qa-remove"):
				for nm in String(dev.arg("qa-remove", "")).split(","):
					var victim := cs.get_node_or_null("Level/" + nm)
					print("[W1BotQA] test-only removal of %s: %s" % [nm, victim != null])
					if victim:
						victim.queue_free()
			var bot := Node.new()
			bot.name = "W1BotQA"
			bot.set_script(load("res://tests/critique_w1/w1_bot_qa_copy.gd"))
			cs.add_child(bot)
			return
	print("[W1BotQA] TIMEOUT waiting for W1")
	get_tree().quit(2)
