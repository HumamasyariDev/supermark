extends Node
## Critique W1 r1 QA: loads W1 normally, then adds the fixed copy of the W1 reachability bot under the world root
## (the shipped w1_bot.gd does not parse). Args: --w1bot-tests=w1-3,w1-2,... (default all) --w1bot-out=<abs json>.
## Run: python tools/godot.py run res://tests/critique_w1/W1BotQA.tscn --headless --seconds 1500 -- --profile=<fresh> --w1bot-out=<abs>




func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var keeper := Node.new()
	keeper.name = "W1BotQAKeeper"
	keeper.process_mode = Node.PROCESS_MODE_ALWAYS
	keeper.set_script(load("res://tests/critique_w1/w1_bot_qa_keeper.gd"))
	get_tree().root.add_child.call_deferred(keeper)
	get_tree().change_scene_to_file.call_deferred("res://scenes/worlds/w1/W1.tscn")
