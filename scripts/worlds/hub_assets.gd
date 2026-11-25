class_name HubAssets
extends RefCounted
## Every generated mesh and object scene the hub uses, preloaded so the threaded scene load pulls them in
## (no main-thread hitch when the page-turn transition swaps in the hub).

const SCENES := {
	"res://assets/props/hub/brass_chandelier_v3/brass_chandelier_v3.glb": preload("res://assets/props/hub/brass_chandelier_v3/brass_chandelier_v3.glb"),
	"res://assets/props/hub/grandfather_clock_v3/grandfather_clock_v3.glb": preload("res://assets/props/hub/grandfather_clock_v3/grandfather_clock_v3.glb"),
	"res://assets/props/hub/tea_table_set_v4/tea_table_set_v4.glb": preload("res://assets/props/hub/tea_table_set_v4/tea_table_set_v4.glb"),
	"res://assets/props/hub/wingback_armchair_v4/wingback_armchair_v4.glb": preload("res://assets/props/hub/wingback_armchair_v4/wingback_armchair_v4.glb"),
	"res://assets/characters/bramwell/bramwell.glb": preload("res://assets/characters/bramwell/bramwell.glb"),
	"res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb": preload("res://assets/props/pickups/golden_truffle_v2/golden_truffle_v2.glb"),
	"res://assets/props/hub/book_lectern/book_lectern.glb": preload("res://assets/props/hub/book_lectern/book_lectern.glb"),
	"res://assets/props/hub/bookshelf_tall/bookshelf_tall.glb": preload("res://assets/props/hub/bookshelf_tall/bookshelf_tall.glb"),
	"res://assets/props/hub/brass_chandelier/brass_chandelier.glb": preload("res://assets/props/hub/brass_chandelier/brass_chandelier.glb"),
	"res://assets/props/hub/fireplace/fireplace.glb": preload("res://assets/props/hub/fireplace/fireplace.glb"),
	"res://assets/props/hub/grandfather_clock/grandfather_clock.glb": preload("res://assets/props/hub/grandfather_clock/grandfather_clock.glb"),
	"res://assets/props/hub/library_globe/library_globe.glb": preload("res://assets/props/hub/library_globe/library_globe.glb"),
	"res://assets/props/hub/rolling_ladder/rolling_ladder.glb": preload("res://assets/props/hub/rolling_ladder/rolling_ladder.glb"),
	"res://assets/props/hub/tea_table_set/tea_table_set.glb": preload("res://assets/props/hub/tea_table_set/tea_table_set.glb"),
	"res://assets/props/hub/wingback_armchair/wingback_armchair.glb": preload("res://assets/props/hub/wingback_armchair/wingback_armchair.glb"),
	"res://assets/props/hub/wolf_door/wolf_door.glb": preload("res://assets/props/hub/wolf_door/wolf_door.glb"),
	"res://assets/props/w1/apple_tree/apple_tree.glb": preload("res://assets/props/w1/apple_tree/apple_tree.glb"),
	"res://assets/props/w1/brick_house/brick_house.glb": preload("res://assets/props/w1/brick_house/brick_house.glb"),
	"res://assets/props/w1/straw_house/straw_house.glb": preload("res://assets/props/w1/straw_house/straw_house.glb"),
	"res://assets/props/w1/windmill_body/windmill_body.glb": preload("res://assets/props/w1/windmill_body/windmill_body.glb"),
	"res://assets/props/w1/windmill_sails/windmill_sails.glb": preload("res://assets/props/w1/windmill_sails/windmill_sails.glb"),
	"res://assets/props/w2/bean_flower/bean_flower.glb": preload("res://assets/props/w2/bean_flower/bean_flower.glb"),
	"res://assets/props/w2/beanstalk_segment/beanstalk_segment.glb": preload("res://assets/props/w2/beanstalk_segment/beanstalk_segment.glb"),
	"res://assets/props/w2/jack_cottage/jack_cottage.glb": preload("res://assets/props/w2/jack_cottage/jack_cottage.glb"),
	"res://assets/props/w3/cupcake_tower/cupcake_tower.glb": preload("res://assets/props/w3/cupcake_tower/cupcake_tower.glb"),
	"res://assets/props/w3/gingerbread_cottage/gingerbread_cottage.glb": preload("res://assets/props/w3/gingerbread_cottage/gingerbread_cottage.glb"),
	"res://assets/props/w3/gumdrop/gumdrop.glb": preload("res://assets/props/w3/gumdrop/gumdrop.glb"),
	"res://assets/props/w3/gumdrop/gumdrop_violet.glb": preload("res://assets/props/w3/gumdrop/gumdrop_violet.glb"),
	"res://assets/props/w3/gumdrop/gumdrop_mint.glb": preload("res://assets/props/w3/gumdrop/gumdrop_mint.glb"),
	"res://assets/props/w3/lollipop_tree/lollipop_tree.glb": preload("res://assets/props/w3/lollipop_tree/lollipop_tree.glb"),
	"res://assets/props/w3/lollipop_tree/lollipop_tree_mint.glb": preload("res://assets/props/w3/lollipop_tree/lollipop_tree_mint.glb"),
	"res://assets/props/w3/lollipop_tree/lollipop_tree_red.glb": preload("res://assets/props/w3/lollipop_tree/lollipop_tree_red.glb"),
	"res://assets/props/vista/garden_fountain/garden_fountain.glb": preload("res://assets/props/vista/garden_fountain/garden_fountain.glb"),
	"res://assets/props/vista/topiary_pig/topiary_pig.glb": preload("res://assets/props/vista/topiary_pig/topiary_pig.glb"),
	"res://assets/props/vista/garden_gazebo/garden_gazebo.glb": preload("res://assets/props/vista/garden_gazebo/garden_gazebo.glb"),
	"res://assets/props/vista/garden_gate/garden_gate.glb": preload("res://assets/props/vista/garden_gate/garden_gate.glb"),
	"res://assets/props/vista/hot_air_balloon/hot_air_balloon.glb": preload("res://assets/props/vista/hot_air_balloon/hot_air_balloon.glb"),
	"res://assets/props/w1/stick_house/stick_house.glb": preload("res://assets/props/w1/stick_house/stick_house.glb"),
	"res://assets/props/w1/hay_bale/hay_bale.glb": preload("res://assets/props/w1/hay_bale/hay_bale.glb"),
	"res://assets/props/w1/birch_tree_v2/birch_tree_v2.glb": preload("res://assets/props/w1/birch_tree_v2/birch_tree_v2.glb"),
	"res://assets/props/w2/giant_castle/giant_castle.glb": preload("res://assets/props/w2/giant_castle/giant_castle.glb"),
	"res://scenes/objects/StorybookPortal.tscn": preload("res://scenes/objects/StorybookPortal.tscn"),
	"res://scenes/objects/WolfDoor.tscn": preload("res://scenes/objects/WolfDoor.tscn"),
	"res://scenes/objects/NPCTalker.tscn": preload("res://scenes/objects/NPCTalker.tscn"),
	"res://scenes/objects/Truffle.tscn": preload("res://scenes/objects/Truffle.tscn"),
	"res://scenes/objects/Acorn.tscn": preload("res://scenes/objects/Acorn.tscn"),
	"res://scenes/objects/BreakableCrate.tscn": preload("res://scenes/objects/BreakableCrate.tscn"),
	"res://scenes/objects/SignPost.tscn": preload("res://scenes/objects/SignPost.tscn"),
}


static func scene(path: String) -> PackedScene:
	if SCENES.has(path):
		return SCENES[path]
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	push_warning("[Hub] missing scene " + path)
	return null
