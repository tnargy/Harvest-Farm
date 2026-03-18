extends Node

## TestScoreCalculator.gd
## Attach to a Node in a test scene and press F6 to run.
## Covers:
##   - All five match shapes producing correct totals against balance defaults.
##   - Cascade multiplier at chain levels 1 and 2 matching spec example values.
##   - score_overrides applied correctly when a key is present.
##   - score_overrides fallback to balance default when the key is absent.
##   - Special activation bonus: default, overridden, and cascade-scaled.

# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestScoreCalculator — ScoreCalculator scoring tests")
	print("=".repeat(64))

	_test_match_shapes_default()
	_test_cascade_multipliers()
	_test_score_overrides_applied()
	_test_score_overrides_fallback()
	_test_special_activation_bonus()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

## Builds a Balance resource populated with the spec-documented default values.
func _make_balance() -> Balance:
	var b := Balance.new()
	b.SCORE_MATCH_3_PER_PIECE        = 50
	b.SCORE_MATCH_4_PER_PIECE        = 100
	b.SCORE_MATCH_5_PER_PIECE        = 150
	b.SCORE_MATCH_L_PER_PIECE        = 100
	b.SCORE_MATCH_T_PER_PIECE        = 120
	b.SCORE_SPECIAL_ACTIVATION_BONUS = 200
	b.CASCADE_MULTIPLIER_PER_LEVEL   = 0.5
	b.CASCADE_MULTIPLIER_CAP         = 3.0
	return b


## Builds a minimal MatchFinder.MatchResult for testing.
## piece_count must equal the number of Vector2i cells you want in the result.
func _make_result(shape: String, piece_count: int) -> MatchFinder.MatchResult:
	var cells: Array[Vector2i] = []
	for i in range(piece_count):
		cells.append(Vector2i(i, 0))
	return MatchFinder.MatchResult.new(cells, shape, "horizontal")


func _make_calculator() -> ScoreCalculator:
	return ScoreCalculator.new()


# ── Suite: all five shapes, balance defaults, no cascade ─────────────────────

func _test_match_shapes_default() -> void:
	_current_suite = "match shapes — balance defaults, no cascade"
	print("\n── %s ──" % _current_suite)

	var balance    := _make_balance()
	var calculator := _make_calculator()
	var overrides  := {}

	# match_3: 3 pieces × 50 = 150
	var r3 := _make_result("match_3", 3)
	_assert(
		calculator.calculate_match_score(r3, balance, overrides) == 150,
		"match_3: 3 × 50 = 150"
	)

	# match_4: 4 pieces × 100 + 200 special bonus = 600
	var r4 := _make_result("match_4", 4)
	_assert(
		calculator.calculate_match_score(r4, balance, overrides) == 600,
		"match_4: 4 × 100 + 200 special bonus = 600"
	)

	# match_5: 5 pieces × 150 + 200 special bonus = 950
	var r5 := _make_result("match_5", 5)
	_assert(
		calculator.calculate_match_score(r5, balance, overrides) == 950,
		"match_5: 5 × 150 + 200 special bonus = 950"
	)

	# match_l: 5 pieces × 100 + 200 special bonus = 700
	var rl := _make_result("match_l", 5)
	_assert(
		calculator.calculate_match_score(rl, balance, overrides) == 700,
		"match_l: 5 × 100 + 200 special bonus = 700"
	)

	# match_t: 5 pieces × 120 + 200 special bonus = 800
	var rt := _make_result("match_t", 5)
	_assert(
		calculator.calculate_match_score(rt, balance, overrides) == 800,
		"match_t: 5 × 120 + 200 special bonus = 800"
	)


# ── Suite: cascade multipliers ────────────────────────────────────────────────

func _test_cascade_multipliers() -> void:
	_current_suite = "cascade multipliers — spec example values"
	print("\n── %s ──" % _current_suite)

	# Spec section 6.4:
	# CASCADE_MULTIPLIER_PER_LEVEL = 0.5, CASCADE_MULTIPLIER_CAP = 3.0
	# chain_level 1 → 1 + (0.5 × 1) = 1.5×
	# chain_level 2 → 1 + (0.5 × 2) = 2.0×

	var balance    := _make_balance()
	var calculator := _make_calculator()
	var overrides  := {}

	# Use a plain match_3 (no special bonus) so the arithmetic stays simple.
	# Base = 3 × 50 = 150
	var r3 := _make_result("match_3", 3)

	var score_cascade_1 := calculator.calculate_match_score(r3, balance, overrides, 1)
	# 150 × 1.5 = 225
	_assert(
		score_cascade_1 == 225,
		"cascade_level 1: 150 × 1.5 = 225"
	)

	var score_cascade_2 := calculator.calculate_match_score(r3, balance, overrides, 2)
	# 150 × 2.0 = 300
	_assert(
		score_cascade_2 == 300,
		"cascade_level 2: 150 × 2.0 = 300"
	)

	# Verify cascade_level 0 means no multiplier is applied.
	var score_no_cascade := calculator.calculate_match_score(r3, balance, overrides, 0)
	_assert(
		score_no_cascade == 150,
		"cascade_level 0: no multiplier, returns base 150"
	)

	# Verify CASCADE_MULTIPLIER_CAP is respected.
	# With PER_LEVEL = 0.5 and CAP = 3.0, chain_level 4 would be 3.0 (capped).
	var score_capped := calculator.calculate_match_score(r3, balance, overrides, 4)
	# 1 + (0.5 × 4) = 3.0 — exactly at cap.
	_assert(
		score_capped == 450,
		"cascade_level 4: 150 × 3.0 (cap) = 450"
	)

	# chain_level 6 would be 1 + 3.0 = 4.0 uncapped → clamped to 3.0.
	var score_overcap := calculator.calculate_match_score(r3, balance, overrides, 6)
	_assert(
		score_overcap == 450,
		"cascade_level 6 (over cap): still 150 × 3.0 = 450"
	)


# ── Suite: score_overrides applied ───────────────────────────────────────────

func _test_score_overrides_applied() -> void:
	_current_suite = "score_overrides — override values used when key present"
	print("\n── %s ──" % _current_suite)

	var balance    := _make_balance()
	var calculator := _make_calculator()

	# Override match_3 per-piece value to 75.
	# 3 × 75 = 225
	var overrides_m3 := {"match_3": 75}
	var r3            := _make_result("match_3", 3)
	_assert(
		calculator.calculate_match_score(r3, balance, overrides_m3) == 225,
		"match_3 override 75/piece: 3 × 75 = 225"
	)

	# Override match_4 per-piece value to 200 (plus default special bonus 200).
	# 4 × 200 + 200 = 1000
	var overrides_m4 := {"match_4": 200}
	var r4            := _make_result("match_4", 4)
	_assert(
		calculator.calculate_match_score(r4, balance, overrides_m4) == 1000,
		"match_4 override 200/piece: 4 × 200 + 200 bonus = 1000"
	)

	# Override special_activation bonus to 500.
	# match_5 base: 5 × 150 = 750; bonus: 500 → total 1250
	var overrides_bonus := {"special_activation": 500}
	var r5               := _make_result("match_5", 5)
	_assert(
		calculator.calculate_match_score(r5, balance, overrides_bonus) == 1250,
		"special_activation override 500: 5 × 150 + 500 = 1250"
	)

	# Override match_l per-piece to 80 and special_activation to 100.
	# 5 × 80 + 100 = 500
	var overrides_l := {"match_l": 80, "special_activation": 100}
	var rl           := _make_result("match_l", 5)
	_assert(
		calculator.calculate_match_score(rl, balance, overrides_l) == 500,
		"match_l override 80/piece + bonus 100: 5 × 80 + 100 = 500"
	)

	# Override match_t per-piece to 60 and special_activation to 50.
	# 5 × 60 + 50 = 350
	var overrides_t := {"match_t": 60, "special_activation": 50}
	var rt           := _make_result("match_t", 5)
	_assert(
		calculator.calculate_match_score(rt, balance, overrides_t) == 350,
		"match_t override 60/piece + bonus 50: 5 × 60 + 50 = 350"
	)


# ── Suite: score_overrides fallback ──────────────────────────────────────────

func _test_score_overrides_fallback() -> void:
	_current_suite = "score_overrides — fallback to balance default when key absent"
	print("\n── %s ──" % _current_suite)

	var balance    := _make_balance()
	var calculator := _make_calculator()

	# Overrides dict exists but does NOT contain the queried keys.
	# Results must match the pure-balance-default outcomes.
	var unrelated_overrides := {"match_5": 999}

	# match_3 default: 3 × 50 = 150
	var r3 := _make_result("match_3", 3)
	_assert(
		calculator.calculate_match_score(r3, balance, unrelated_overrides) == 150,
		"match_3 absent in overrides: falls back to balance default (150)"
	)

	# match_4 default: 4 × 100 + 200 = 600
	var r4 := _make_result("match_4", 4)
	_assert(
		calculator.calculate_match_score(r4, balance, unrelated_overrides) == 600,
		"match_4 absent in overrides: falls back to balance default (600)"
	)

	# match_l default: 5 × 100 + 200 = 700
	var rl := _make_result("match_l", 5)
	_assert(
		calculator.calculate_match_score(rl, balance, unrelated_overrides) == 700,
		"match_l absent in overrides: falls back to balance default (700)"
	)

	# match_t default: 5 × 120 + 200 = 800
	var rt := _make_result("match_t", 5)
	_assert(
		calculator.calculate_match_score(rt, balance, unrelated_overrides) == 800,
		"match_t absent in overrides: falls back to balance default (800)"
	)

	# special_activation absent from overrides — balance default 200 used.
	var overrides_no_bonus := {"match_3": 75}
	# match_5 base: 5 × 150 + 200 (balance default bonus) = 950
	var r5 := _make_result("match_5", 5)
	_assert(
		calculator.calculate_match_score(r5, balance, overrides_no_bonus) == 950,
		"special_activation absent in overrides: falls back to balance default (950)"
	)


# ── Suite: special activation bonus ──────────────────────────────────────────

func _test_special_activation_bonus() -> void:
	_current_suite = "special activation bonus — standalone activation scoring"
	print("\n── %s ──" % _current_suite)

	var balance    := _make_balance()
	var calculator := _make_calculator()

	# Default bonus with no cascade.
	_assert(
		calculator.calculate_special_activation_score(balance, {}) == 200,
		"activation default, no cascade: 200"
	)

	# Overridden bonus with no cascade.
	_assert(
		calculator.calculate_special_activation_score(balance, {"special_activation": 350}) == 350,
		"activation override 350, no cascade: 350"
	)

	# Default bonus with cascade_level 1: 200 × 1.5 = 300
	_assert(
		calculator.calculate_special_activation_score(balance, {}, 1) == 300,
		"activation default, cascade_level 1: 200 × 1.5 = 300"
	)

	# Default bonus with cascade_level 2: 200 × 2.0 = 400
	_assert(
		calculator.calculate_special_activation_score(balance, {}, 2) == 400,
		"activation default, cascade_level 2: 200 × 2.0 = 400"
	)

	# Overridden bonus absent — falls back to balance default 200.
	var overrides_absent := {"match_3": 99}
	_assert(
		calculator.calculate_special_activation_score(balance, overrides_absent) == 200,
		"activation override absent: fallback to balance default 200"
	)


# ── Assertion helper ──────────────────────────────────────────────────────────

func _assert(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  %s" % description)
	else:
		_fail_count += 1
		print("  FAIL  %s" % description)


# ── Summary ───────────────────────────────────────────────────────────────────

func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n" + "=".repeat(64))
	if _fail_count == 0:
		print("RESULT: ALL %d TESTS PASSED" % total)
	else:
		print("RESULT: %d / %d PASSED — %d FAILED" % [_pass_count, total, _fail_count])
	print("=".repeat(64))
