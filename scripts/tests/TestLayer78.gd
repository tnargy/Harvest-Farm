extends Node

## TestLayer78.gd
## Attach to a Node in scenes/tests/TestLayer78.tscn and press F6 to run.
## Tests WinFailResolver star logic, ScreenData payload transfer, and GoalFormatter formatting.

var passed := 0
var failed := 0
var output_log := ""

func log_msg(msg: String) -> void:
	print(msg)
	output_log += msg + "\n"

func _ready() -> void:
	log_msg("--- Starting Layer 7 & 8 Tests ---")

	test_goal_formatter()
	test_screen_data()
	test_star_calculation()
	test_ui_instantiation()

	log_msg("----------------------------------")
	if failed == 0:
		log_msg("ALL TESTS PASSED (%d passed)" % passed)
	else:
		log_msg("FAILED: %d passed, %d failed" % [passed, failed])

	var f = FileAccess.open("res://test_results_layer78.txt", FileAccess.WRITE)
	if f:
		f.store_string(output_log)
		f.close()

	get_tree().quit(1 if failed > 0 else 0)


func check(condition: bool, test_name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAILED: %s" % test_name)
		log_msg("FAILED: " + test_name)


func test_goal_formatter() -> void:
	log_msg("Running GoalFormatter tests...")

	var g_score = {"type": "score", "target": 4200}
	check(GoalFormatter.format_goal(g_score) == "Reach 4,200 points", "Score goal format")
	check(GoalFormatter.format_progress(g_score, 1000, false) == "1,000 / 4,200", "Score progress format")

	var g_dirt = {"type": "clear_dirt"}
	check(GoalFormatter.format_goal(g_dirt) == "Clear all dirt patches", "Clear dirt format")
	check(GoalFormatter.format_progress(g_dirt, 0, false) == "", "Clear dirt progress incomplete")
	check(GoalFormatter.format_progress(g_dirt, 0, true) == "Done", "Clear dirt progress complete")

	var g_flower = {"type": "clear_flowers"}
	check(GoalFormatter.format_goal(g_flower) == "Clear all flowers", "Clear flowers format")
	check(GoalFormatter.format_progress(g_flower, 0, false) == "", "Clear flowers progress incomplete")
	check(GoalFormatter.format_progress(g_flower, 0, true) == "Done", "Clear flowers progress complete")

	var g_crop = {"type": "collect_crop", "crop": "strawberry", "target": 15}
	check(GoalFormatter.format_goal(g_crop) == "Collect 15 Strawberry", "Collect crop format")
	check(GoalFormatter.format_progress(g_crop, 5, false) == "5 / 15", "Collect crop progress format")


func test_screen_data() -> void:
	log_msg("Running ScreenData tests...")

	# Clear any leftover state
	var _discard = ScreenData.consume()

	check(not ScreenData.has_payload(), "ScreenData starts empty")

	var payload := {"stars": 3, "score": 1000}
	ScreenData.set_payload(payload)
	check(ScreenData.has_payload(), "ScreenData has payload after set")

	# Mutate original payload to ensure it was duplicated
	payload["stars"] = 1

	var consumed: Dictionary = ScreenData.consume()
	check(consumed.get("stars", 0) == 3, "ScreenData payload is duplicated on set")
	check(consumed.get("score", 0) == 1000, "ScreenData payload fields match")

	check(not ScreenData.has_payload(), "ScreenData is cleared after consume")

	# Mutate consumed payload to ensure it was duplicated on get
	consumed["score"] = 500
	var empty: Dictionary = ScreenData.consume()
	check(empty.is_empty(), "ScreenData returns empty dict when no payload")


func test_star_calculation() -> void:
	log_msg("Running WinFailResolver star calculation tests...")

	var resolver := WinFailResolver.new()
	var board := BoardState.new()
	var level := LevelData.new()

	resolver._board_state = board
	resolver._level_data = level

	level.star_threshold_2 = 5
	level.star_threshold_3 = 10

	board.turns_remaining = 0
	check(resolver._compute_stars() == 1, "0 turns remaining -> 1 star")

	board.turns_remaining = 4
	check(resolver._compute_stars() == 1, "4 turns remaining -> 1 star")

	board.turns_remaining = 5
	check(resolver._compute_stars() == 2, "5 turns remaining -> 2 stars")

	board.turns_remaining = 9
	check(resolver._compute_stars() == 2, "9 turns remaining -> 2 stars")

	board.turns_remaining = 10
	check(resolver._compute_stars() == 3, "10 turns remaining -> 3 stars")

	board.turns_remaining = 15
	check(resolver._compute_stars() == 3, "15 turns remaining -> 3 stars")


func test_ui_instantiation() -> void:
	log_msg("Running UI instantiation tests...")

	var scenes = [
		"res://scenes/ui/MainMenu.tscn",
		"res://scenes/ui/LevelSelect.tscn",
		"res://scenes/ui/LevelIntro.tscn",
		"res://scenes/ui/WinScreen.tscn",
		"res://scenes/ui/FailScreen.tscn",
		"res://scenes/ui/NoLivesOverlay.tscn",
		"res://scenes/ui/SettingsScreen.tscn",
		"res://scenes/ui/components/LevelCell.tscn"
	]

	for path in scenes:
		# Provide dummy payload for screens that expect it in _ready
		ScreenData.set_payload({
			"outcome": "test",
			"level_id": 1,
			"stars": 3,
			"turns_remaining": 5,
			"final_score": 1000,
			"seeds_this_run": 10,
			"bonus_seeds": 0,
			"incomplete_goals": []
		})

		var packed := load(path) as PackedScene
		check(packed != null, "Scene loads: " + path)
		if packed:
			var inst = packed.instantiate()
			check(inst != null, "Scene instantiates: " + path)
			if inst:
				# Add to tree to trigger _ready and @onready resolution
				add_child(inst)
				check(inst.is_inside_tree(), "Scene added to tree: " + path)
				inst.queue_free()
