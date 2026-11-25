extends Node
## Boot node for visual_tour.tscn: hands control to tour_driver.gd (kept on the root) and lets it load W2.

func _ready() -> void:
	var d := Node.new()
	d.name = "CritiqueW2Tour"
	d.set_script(load("res://tests/critique_w2/tour_driver.gd"))
	get_tree().root.add_child.call_deferred(d)
