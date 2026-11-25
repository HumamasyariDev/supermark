class_name WorldRegistry
extends RefCounted
## Data-driven registry of every playable area (DESIGN_V2.md). Router, UI and the hub read it.

const WORLDS := {
	"HUB": {
		"scene": "res://scenes/hub/Hub.tscn",
		"display_name": "Mak Manor",
		"book_title": "The Grand Storybook Library",
		"music_key": "music_hub",
		"truffles_required": 0,
		"palette": [Color("5a3a22"), Color("7a1f2b"), Color("c9a24a")],
		"truffles": [
			{"id": "HUB-1", "name": "Top of the Library", "goal": "Climb the shelves to the very top"},
		],
	},
	"W1": {
		"scene": "res://scenes/worlds/w1/W1.tscn",
		"display_name": "Huff & Puff Hollow",
		"book_title": "The Three Little Pigs",
		"music_key": "music_w1",
		"truffles_required": 0,
		"palette": [Color("6fa84a"), Color("e8c95a"), Color("b5462e")],
		"truffles": [
			{"id": "W1-1", "name": "Straw House Siege", "goal": "Chase the wolves off the straw house"},
			{"id": "W1-2", "name": "Top of the Windmill", "goal": "Ride the sails up to the weathervane"},
			{"id": "W1-3", "name": "The Stick Scaffold", "goal": "Climb the scaffold to the treehouse"},
			{"id": "W1-4", "name": "Bust the Bellows", "goal": "Ham Slam all three bellows plates"},
			{"id": "W1-5", "name": "Lost Pages of the Hollow", "goal": "Find the five Lost Pages"},
			{"id": "W1-6", "name": "Up the Chimney", "goal": "Wall-kick up the inside of the chimney"},
			{"id": "W1-7", "name": "The Foreman's Haystacks", "goal": "Sniff out the Foreman, slam his haystack"},
			{"id": "W1-8", "name": "Buried Treasure", "goal": "Sniff the gold trail, slam where it ends"},
		],
	},
	"W2": {
		"scene": "res://scenes/worlds/w2/W2.tscn",
		"display_name": "Beanstalk Skyway",
		"book_title": "Jack and the Beanstalk",
		"music_key": "music_w2",
		"truffles_required": 3,
		"palette": [Color("4f9a3c"), Color("f4f2ea"), Color("9b8ad0")],
		"truffles": [
			{"id": "W2-1", "name": "Up the Beanstalk", "goal": "Climb the beanstalk to the first leaf"},
			{"id": "W2-2", "name": "Free the Golden Goose", "goal": "Press three switches to open the cage"},
			{"id": "W2-3", "name": "Fee-Fi-Fo-Hum", "goal": "Tiptoe to the sugar bowl by the Giant"},
			{"id": "W2-4", "name": "Leaf Bouncer", "goal": "Bounce the leaves to the upper cloudbank"},
			{"id": "W2-5", "name": "Lost Pages of the Sky", "goal": "Find the five Lost Pages"},
			{"id": "W2-6", "name": "Pea Pod Patrol", "goal": "Defeat the pea pod patrol"},
			{"id": "W2-7", "name": "Cloud Hopper", "goal": "Fly through all six rings in 32 seconds"},
			{"id": "W2-8", "name": "Top of the Stalk", "goal": "Reach the belfry at the top of the stalk"},
		],
	},
	"W3": {
		"scene": "res://scenes/worlds/w3/W3.tscn",
		"display_name": "Gingerbread Grove",
		"book_title": "Hansel and Gretel",
		"music_key": "music_w3",
		"truffles_required": 7,
		"palette": [Color("8a5a32"), Color("fbf3ea"), Color("ef8fb0")],
		"truffles": [
			{"id": "W3-1", "name": "The Breadcrumb Trail", "goal": "Follow the crumbs through the misty maze"},
			{"id": "W3-2", "name": "Sergeant Snap", "goal": "Topple the squad, stomp the Sergeant"},
			{"id": "W3-3", "name": "The Dunk Run", "goal": "Leapfrog the dunk convoy to the far bank"},
			{"id": "W3-4", "name": "The Sled Joust", "goal": "Climb the summit and win the sled race"},
			{"id": "W3-5", "name": "Lost Pages of the Grove", "goal": "Find the five Lost Pages"},
			{"id": "W3-6", "name": "The Kitchen Cage", "goal": "Slam down the chimney, escape the oven"},
			{"id": "W3-7", "name": "Gumdrop Hop", "goal": "Slam-bounce up the gumdrop spiral"},
			{"id": "W3-8", "name": "The Cauldron's Secret", "goal": "Slam the lid, then sniff out the geode"},
		],
	},
	"BOSS": {
		"scene": "res://scenes/boss/WolfRooftop.tscn",
		"display_name": "The Wolf's Rooftop",
		"book_title": "The Wolf's Own Tale",
		"music_key": "music_boss",
		"truffles_required": 12,
		"palette": [Color("7a1f2b"), Color("f08a3c"), Color("2b2340")],
		"truffles": [
			{"id": "BOSS-1", "name": "The Great Truffle"},
		],
	},
}

const ORDER := ["HUB", "W1", "W2", "W3", "BOSS"]


static func has_world(world_id: String) -> bool:
	return WORLDS.has(world_id)


static func get_world(world_id: String) -> Dictionary:
	return WORLDS.get(world_id, {})


static func scene_path(world_id: String) -> String:
	return String(get_world(world_id).get("scene", ""))


static func display_name(world_id: String) -> String:
	return String(get_world(world_id).get("display_name", world_id))


static func book_title(world_id: String) -> String:
	return String(get_world(world_id).get("book_title", ""))


static func music_key(world_id: String) -> String:
	return String(get_world(world_id).get("music_key", ""))


static func truffles_required(world_id: String) -> int:
	return int(get_world(world_id).get("truffles_required", -1))


static func truffles(world_id: String) -> Array:
	return get_world(world_id).get("truffles", [])


static func truffle_ids(world_id: String) -> Array:
	var out: Array = []
	for t in truffles(world_id):
		out.append(t["id"])
	return out


static func world_of_truffle(truffle_id: String) -> String:
	var dash := truffle_id.find("-")
	return truffle_id.substr(0, dash) if dash > 0 else ""


static func truffle_name(truffle_id: String) -> String:
	for t in truffles(world_of_truffle(truffle_id)):
		if t["id"] == truffle_id:
			return String(t["name"])
	return truffle_id


## One-line objective for a mission (entry banner, mission select). Empty when unknown.
static func truffle_goal(truffle_id: String) -> String:
	for t in truffles(world_of_truffle(truffle_id)):
		if String(t.get("id", "")) == truffle_id:
			return String(t.get("goal", ""))
	return ""


static func scene_exists(world_id: String) -> bool:
	var p := scene_path(world_id)
	return p != "" and ResourceLoader.exists(p)
