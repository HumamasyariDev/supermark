extends Control
## Review scene: every dialog speaker's live 3D portrait in a grid (UI track evidence).

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UIStyle.PARCHMENT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.position = Vector2(40, 40)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	add_child(grid)
	var seen := {}
	for k in UISpeakers.list():
		var info: Array = UISpeakers.info(k)
		if seen.has(info[0]):
			continue
		seen[info[0]] = true
		var v := VBoxContainer.new()
		grid.add_child(v)
		var pv := UIModelView.new()
		pv.custom_minimum_size = Vector2(280, 300)
		pv.bust_fraction = 0.5
		pv.yaw_offset = float(info[2])
		v.add_child(pv)
		pv.set_model(String(info[0]), "bust")
		var l := UIStyle.label(String(k), 26, UIStyle.INK)
		v.add_child(l)
