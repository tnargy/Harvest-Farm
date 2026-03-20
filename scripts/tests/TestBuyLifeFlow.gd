extends Node

var passed := 0
var failed := 0
var output_log := ""

func log_msg(msg: String) -> void:
	print(msg)
	output_log += msg + "\n"

func check(condition: bool, test_name: String) -> void:
	if condition:
		passed += 1
		log_msg("PASS: " + test_name)
	else:
		failed += 1
		push_error("FAIL: " + test_name)
		log_msg("FAIL: " + test_name)

func _ready() -> void:
	log_msg("--- Starting Buy Life Flow Test ---")

	# 1. Reset everything so we have a clean slate
	SaveData.reset()
	SaveData.set_lives(0)
	SaveData.add_seeds(100)

	# 2. Inject mock fail payload
	ScreenData.set_payload({
		"outcome": "fail",
		"level_id": 1,
		"lives_remaining": 0,
		"incomplete_goals": []
	})

	# 3. Load and instantiate FailScreen
	var packed := load("res://scenes/ui/FailScreen.tscn") as PackedScene
	var screen = packed.instantiate()
	add_child(screen)

	# Wait for UI to initialize
	await get_tree().process_frame

	# 4. Verify initial UI state
	var buy_button = screen.get_node("ButtonRow/BuyLifeButton") as Button
	var retry_button = screen.get_node("ButtonRow/RetryButton") as Button

	check(buy_button != null, "Found BuyLifeButton")
	check(retry_button != null, "Found RetryButton")

	check(buy_button.visible, "Buy Life button is visible when lives == 0")
	check(not buy_button.disabled, "Buy Life button is enabled when seeds >= 30")
	check(retry_button.disabled, "Retry button is disabled when lives == 0")

	# 5. Simulate click
	log_msg("Simulating Buy Life button press...")
	buy_button.pressed.emit()

	# Wait for signals to propagate
	await get_tree().process_frame

	# 6. Verify game state changed
	check(SaveData.get_lives() == 1, "Lives increased to 1 after purchase")
	check(SaveData.get_seeds() == 70, "Seeds decreased by 30 (cost of life)")

	# 7. Verify UI reacted to the state change
	check(not buy_button.visible, "Buy Life button hides after purchase")
	check(not retry_button.disabled, "Retry button becomes enabled after purchase")

	screen.queue_free()

	log_msg("----------------------------------")
	if failed == 0:
		log_msg("ALL TESTS PASSED (%d passed)" % passed)
	else:
		log_msg("FAILED: %d passed, %d failed" % [passed, failed])

	var f = FileAccess.open("res://test_results_buylife.txt", FileAccess.WRITE)
	if f:
		f.store_string(output_log)
		f.close()

	get_tree().quit(1 if failed > 0 else 0)
