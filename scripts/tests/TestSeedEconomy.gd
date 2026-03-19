extends Node

const SaveDataScript = preload("res://scripts/persistence/SaveData.gd")
const LivesManagerScript = preload("res://scripts/lives/LivesManager.gd")
const BalanceScript = preload("res://scripts/resources/Balance.gd")
const SeedEconomyScript = preload("res://scripts/economy/SeedEconomy.gd")
const LevelDataScript = preload("res://scripts/resources/LevelData.gd")

# TestSeedEconomy.gd
# Exercises SeedEconomy behaviors:
#  - flush_turn_seeds accumulates seeds, ignores zero/negative
#  - flush_level_win awards seeds only on 3-star with positive reward
#  - can_buy_life gate: requires 0 lives AND sufficient seeds
#  - buy_life delegates to LivesManager.purchase_life_with_seeds and enforces
#    the same gates, returning the correct bool and mutating state accordingly
#
# Mirrors the style of TestLivesManager.gd: self-contained, uses an isolated
# test save file and constructs all instances directly (no autoload globals).

var _pass_count = 0
var _fail_count = 0
var _current_suite = ""
const TEST_SAVE_PATH = "user://test_seed_economy_data.json"

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

func _make_se(sd: SaveDataScript, lm: Node) -> Node:
	var se = SeedEconomyScript.new()
	# SeedEconomy assumes SaveData, LivesManager, and Balance autoloads; tests inject them.
	se._save = sd
	se._lives = lm
	se._balance = sd._balance
	return se

# ──────────────────────────────────────────────────────────────────────────────
# Tests — flush_turn_seeds
# ──────────────────────────────────────────────────────────────────────────────

func _test_flush_turn_seeds_adds_to_balance() -> void:
	_current_suite = "flush_turn_seeds adds positive amount to seed balance"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 0
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	se.flush_turn_seeds(5)
	_assert(se.get_seeds() == 5, "get_seeds() == 5 after flush_turn_seeds(5) from 0")

func _test_flush_turn_seeds_zero_is_noop() -> void:
	_current_suite = "flush_turn_seeds(0) is a no-op"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 10
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	se.flush_turn_seeds(0)
	_assert(se.get_seeds() == 10, "get_seeds() unchanged at 10 after flush_turn_seeds(0)")

func _test_flush_turn_seeds_negative_is_noop() -> void:
	_current_suite = "flush_turn_seeds(negative) is a no-op"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 10
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	se.flush_turn_seeds(-3)
	_assert(se.get_seeds() == 10, "get_seeds() unchanged at 10 after flush_turn_seeds(-3)")

# ──────────────────────────────────────────────────────────────────────────────
# Tests — flush_level_win
# ──────────────────────────────────────────────────────────────────────────────

func _test_flush_level_win_3star_adds_reward() -> void:
	_current_suite = "flush_level_win adds seed_reward_3star on 3-star completion"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 0
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ld = LevelDataScript.new()
	ld.seed_reward_3star = 20
	se.flush_level_win(ld, 3)
	_assert(se.get_seeds() == 20, "get_seeds() == 20 after flush_level_win with 3 stars and reward 20")

func _test_flush_level_win_1star_no_reward() -> void:
	_current_suite = "flush_level_win does not award seeds on 1-star completion"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 10
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ld = LevelDataScript.new()
	ld.seed_reward_3star = 20
	se.flush_level_win(ld, 1)
	_assert(se.get_seeds() == 10, "get_seeds() unchanged at 10 after flush_level_win with 1 star")

func _test_flush_level_win_2star_no_reward() -> void:
	_current_suite = "flush_level_win does not award seeds on 2-star completion"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 10
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ld = LevelDataScript.new()
	ld.seed_reward_3star = 20
	se.flush_level_win(ld, 2)
	_assert(se.get_seeds() == 10, "get_seeds() unchanged at 10 after flush_level_win with 2 stars")

func _test_flush_level_win_3star_zero_reward_is_noop() -> void:
	_current_suite = "flush_level_win is a no-op when seed_reward_3star == 0"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	sd._seeds = 10
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ld = LevelDataScript.new()
	ld.seed_reward_3star = 0
	se.flush_level_win(ld, 3)
	_assert(se.get_seeds() == 10, "get_seeds() unchanged at 10 when seed_reward_3star == 0")

# ──────────────────────────────────────────────────────────────────────────────
# Tests — can_buy_life
# ──────────────────────────────────────────────────────────────────────────────

func _test_can_buy_life_true_when_eligible() -> void:
	_current_suite = "can_buy_life returns true when lives == 0 and seeds >= SEED_COST_LIFE"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 0
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	_assert(se.can_buy_life() == true, "can_buy_life() == true with 0 lives and exact seed cost")

func _test_can_buy_life_false_when_has_lives() -> void:
	_current_suite = "can_buy_life returns false when lives > 0"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 1
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	_assert(se.can_buy_life() == false, "can_buy_life() == false when lives == 1")

func _test_can_buy_life_false_when_insufficient_seeds() -> void:
	_current_suite = "can_buy_life returns false when seeds < SEED_COST_LIFE"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 0
	sd._seeds = bal.SEED_COST_LIFE - 1
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	_assert(se.can_buy_life() == false, "can_buy_life() == false when seeds == SEED_COST_LIFE - 1")

# ──────────────────────────────────────────────────────────────────────────────
# Tests — buy_life
# ──────────────────────────────────────────────────────────────────────────────

func _test_buy_life_success() -> void:
	_current_suite = "buy_life succeeds: returns true, deducts seeds, grants one life"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 0
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ok = se.buy_life()
	_assert(ok == true, "buy_life() returned true when eligible")
	_assert(sd.get_seeds() == 0, "seeds deducted by SEED_COST_LIFE after successful buy_life")
	_assert(sd.get_lives() == 1, "lives == 1 after successful buy_life from 0")

func _test_buy_life_fails_when_has_lives() -> void:
	_current_suite = "buy_life fails when player already has lives"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 1
	sd._seeds = bal.SEED_COST_LIFE
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ok = se.buy_life()
	_assert(ok == false, "buy_life() returned false when lives == 1")
	_assert(sd.get_seeds() == bal.SEED_COST_LIFE, "seeds unchanged when buy_life disallowed due to existing lives")
	_assert(sd.get_lives() == 1, "lives unchanged at 1 when buy_life disallowed")

func _test_buy_life_fails_when_insufficient_seeds() -> void:
	_current_suite = "buy_life fails when seeds < SEED_COST_LIFE"
	print("\n── %s ──" % _current_suite)
	var sd = _make_sd()
	var bal = sd._balance
	sd._lives = 0
	sd._seeds = bal.SEED_COST_LIFE - 1
	var lm = _make_lm(sd)
	var se = _make_se(sd, lm)
	var ok = se.buy_life()
	_assert(ok == false, "buy_life() returned false when seeds == SEED_COST_LIFE - 1")
	_assert(sd.get_seeds() == bal.SEED_COST_LIFE - 1, "seeds unchanged when buy_life disallowed due to insufficient seeds")
	_assert(sd.get_lives() == 0, "lives still 0 when buy_life disallowed due to insufficient seeds")

# ──────────────────────────────────────────────────────────────────────────────
# Runner
# ──────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_run_all()
	_cleanup_test_file()

func _run_all() -> void:
	print("=".repeat(64))
	print("TestSeedEconomy — Layer 5 Seed Economy")
	print("=".repeat(64))

	_test_flush_turn_seeds_adds_to_balance()
	_test_flush_turn_seeds_zero_is_noop()
	_test_flush_turn_seeds_negative_is_noop()
	_test_flush_level_win_3star_adds_reward()
	_test_flush_level_win_1star_no_reward()
	_test_flush_level_win_2star_no_reward()
	_test_flush_level_win_3star_zero_reward_is_noop()
	_test_can_buy_life_true_when_eligible()
	_test_can_buy_life_false_when_has_lives()
	_test_can_buy_life_false_when_insufficient_seeds()
	_test_buy_life_success()
	_test_buy_life_fails_when_has_lives()
	_test_buy_life_fails_when_insufficient_seeds()

	print("\n" + "=".repeat(64))
	if _fail_count == 0:
		print("RESULT: ALL %d TESTS PASSED" % _pass_count)
	else:
		print("RESULT: %d PASSED — %d FAILED" % [_pass_count, _fail_count])
	print("=".repeat(64))
