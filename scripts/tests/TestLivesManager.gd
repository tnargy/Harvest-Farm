extends Node

const SaveDataScript = preload("res://scripts/persistence/SaveData.gd")
const LivesManagerScript = preload("res://scripts/lives/LivesManager.gd")
const BalanceScript = preload("res://scripts/resources/Balance.gd")

# TestLivesManager.gd
# Exercises LivesManager behaviors:
#  - consuming a life and scheduling regen
#  - purchasing a life with seeds (only when at 0)
#  - reconciliation of missed regen intervals on app start
#  - add_lives clamping and regen clearing
#  - seconds-until-next-life reporting
#
# Mirrors the style of TestSaveData.gd: self-contained, uses an isolated
# test save file and constructs instances directly.

var _pass_count = 0
var _fail_count = 0
var _current_suite = ""
const TEST_SAVE_PATH = "user://test_lives_data.json"

# ──────────────────────────────────────────────────────────────────────────────
# Utilities
# ──────────────────────────────────────────────────────────────────────────────

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("  PASS ", msg)
	else:
		_fail_count += 1
		print("  FAIL ", msg)

func _cleanup_test_file() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		var dir = DirAccess.open("user://")
		if dir:
			dir.remove(TEST_SAVE_PATH)

func _make_balance() -> Balance:
	var b = BalanceScript.new()
	# Use values matching resources/balance.tres by default.
	# Tests may override individual fields if needed.
	b.SEED_COST_LIFE = 30
	b.SEED_REWARD_SPECIAL_BUSHEL = 5
	b.SEED_REWARD_SPECIAL_SCARECROW = 10
	b.SEED_REWARD_SPECIAL_WATERING_CAN = 8
	b.SEED_REWARD_SPECIAL_WHEELBARROW = 12
	b.CASCADE_MULTIPLIER_PER_LEVEL = 0.5
	b.CASCADE_MULTIPLIER_CAP = 3.0
	b.LIFE_REGEN_MINUTES = 15
	b.MAX_LIVES = 3
	b.SCORE_MATCH_3_PER_PIECE = 50
	return b

func _make_sd() -> SaveDataScript:
	var sd = SaveDataScript.new()
	sd._balance = _make_balance()
	sd.save_path = TEST_SAVE_PATH
	sd._apply_defaults()
	# Ensure no leftover file interferes.
	_cleanup_test_file()
	return sd

func _make_lm(sd: SaveDataScript) -> Node:
	var lm = LivesManagerScript.new()
	# LivesManager assumes SaveData autoload and balance resource; tests inject them.
	lm._save = sd
	lm._balance = sd._balance
	return lm

# ──────────────────────────────────────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────────────────────────────────────

func _test_default_lives() -> void:
	_current_suite = "defaults — lives manager starts with MAX_LIVES"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var lm = _make_lm(sd)
	_assert(lm.get_lives() == sd._balance.MAX_LIVES, "initial lives = MAX_LIVES")

func _test_consume_life_schedules_regen() -> void:
	_current_suite = "consume_life schedules regen when below max"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	# start at max
	sd._lives = sd._balance.MAX_LIVES
	var lm = _make_lm(sd)
	var before = sd.get_lives()
	_assert(before == sd._balance.MAX_LIVES, "pre-consume at MAX_LIVES")
	var ok = lm.consume_life()
	_assert(ok, "consume_life returned true at MAX_LIVES")
	_assert(sd.get_lives() == sd._balance.MAX_LIVES - 1, "lives decremented after consume")
	_assert(sd.get_next_regen_utc() != 0, "next_regen_utc scheduled after consume")

func _test_consume_noop_at_zero() -> void:
	_current_suite = "consume_life no-ops at 0"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._lives = 0
	sd._next_regen_utc = 0
	var lm = _make_lm(sd)
	var ok = lm.consume_life()
	_assert(not ok, "consume_life returned false at 0")
	_assert(sd.get_lives() == 0, "lives remain 0 after no-op")
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc unchanged when no-op")

func _test_purchase_life_with_seeds() -> void:
	_current_suite = "purchase life with seeds only allowed at 0 lives"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	# At 0 lives with exact seed cost
	sd._lives = 0
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var ok = lm.purchase_life_with_seeds()
	_assert(ok, "purchase_life_with_seeds returned true with exact seeds at 0 lives")
	_assert(sd.get_lives() == 1, "one life granted after purchase")
	_assert(sd.get_seeds() == 0, "seeds deducted by SEED_COST_LIFE")
	# Ensure regen scheduled if not at max
	if sd.get_lives() < bal.MAX_LIVES:
		_assert(sd.get_next_regen_utc() != 0, "regen scheduled after purchase when below max")

func _test_purchase_fails_when_not_zero() -> void:
	_current_suite = "purchase life fails when player has > 0 lives"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 1
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var ok = lm.purchase_life_with_seeds()
	_assert(not ok, "purchase_life_with_seeds returned false when lives > 0")
	_assert(sd.get_seeds() == bal.SEED_COST_LIFE, "seeds unchanged when purchase disallowed")

func _test_reconcile_grants_missing_lives() -> void:
	_current_suite = "reconcile grants missed lives when app reopened"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	# Start with a single life and schedule next_regen in the past so multiple ticks elapsed.
	sd._lives = 1
	var interval = int(bal.LIFE_REGEN_MINUTES) * 60
	var now = int(Time.get_unix_time_from_system())
	# Simulate app closed for 60 minutes (4 intervals) — set next_regen so ticks >= 4
	sd._next_regen_utc = now - (4 * interval)
	var lm = _make_lm(sd)
	# call reconcile
	lm.force_reconcile()
	# After reconciliation, player should be at MAX_LIVES
	_assert(sd.get_lives() == bal.MAX_LIVES, "reconcile granted lives up to MAX_LIVES")
	# Next regen should be cleared when at max
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc cleared when MAX_LIVES reached")

func _test_add_lives_clamps_and_clears_regen() -> void:
	_current_suite = "add_lives clamps to MAX_LIVES and clears regen timestamp"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	# Start one below max and schedule a regen
	sd._lives = bal.MAX_LIVES - 1
	sd._next_regen_utc = int(Time.get_unix_time_from_system()) + 60
	var lm = _make_lm(sd)
	lm.add_lives(5) # should clamp
	_assert(sd.get_lives() == bal.MAX_LIVES, "add_lives clamped to MAX_LIVES")
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc cleared when reached MAX_LIVES")

func _test_seconds_until_next_life() -> void:
	_current_suite = "get_seconds_until_next_life reports remaining seconds"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var lm = _make_lm(sd)
	var now = int(Time.get_unix_time_from_system())
	sd._next_regen_utc = now + 5
	var secs = lm.get_seconds_until_next_life()
	_assert(secs > 0 and secs <= 5, "seconds until next life within expected window (<=5)")

# ──────────────────────────────────────────────────────────────────────────────
# Runner
# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_run_all()
	_cleanup_test_file()

func _run_all() -> void:
	print("=".repeat(64))
	print("TestLivesManager — Layer 4 Lives System")
	print("=".repeat(64))

	_test_default_lives()
	_test_consume_life_schedules_regen()
	_test_consume_noop_at_zero()
	_test_purchase_life_with_seeds()
	_test_purchase_fails_when_not_zero()
	_test_reconcile_grants_missing_lives()
	_test_add_lives_clamps_and_clears_regen()
	_test_seconds_until_next_life()

	print("\n" + "=".repeat(64))
	if _fail_count == 0:
		print("RESULT: ALL %d TESTS PASSED" % _pass_count)
	else:
		print("RESULT: %d PASSED — %d FAILED" % [_pass_count, _fail_count])
	print("=".repeat(64))
