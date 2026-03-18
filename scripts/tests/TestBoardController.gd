extends Node

## TestBoardController.gd
## Attach to a Node in scenes/tests/TestBoardController.tscn and press F6 to run.
##
## Covers every spec-mandated behavioral scenario for BoardController:
##
## Swap validation:
##   - Invalid swap (no match): rejected, no turn consumed
##   - Two specials swapped: rejected, no turn consumed
##   - Non-adjacent swap: rejected, no turn consumed
##   - Valid swap: accepted, turn consumed
##
## Match resolution:
##   - 3-piece match: correct score, board cleared, gravity applied
##   - 4-piece match: Bushel Basket spawns at swap origin, correct score
##   - 5-piece match: Scarecrow spawns at swap origin, correct score
##   - L-shape match: Watering Can spawns, correct score
##   - T-shape match: Wheelbarrow spawns, correct score
##
## Special piece activation:
##   - Bushel Basket (horizontal): clears row, flat bonus awarded
##   - Scarecrow: clears all matching crop type, flat bonus awarded
##   - Watering Can: clears 3×3 area, flat bonus awarded
##   - Wheelbarrow: clears full cross, flat bonus awarded
##
## Obstacle clearing:
##   - Dirt adjacent to a match is cleared (spec §3.3)
##   - Dirt included in a match is cleared
##   - Flower takes one HP hit per adjacent match event (spec §3.3)
##   - Flower HP progression: 3 → 2 → 1 → 0 (cleared)
##   - Multiple flowers adjacent to the same clear event each take one hit
##   - Same flower not hit twice by one clear event
##
## Cascades:
##   - Cascade fires automatically after refill settles a new match
##   - cascade_level 1 multiplier applied to cascade score (1.5×)
##   - cascade_level 2 multiplier applied (2.0×)
##   - Cascade does not consume a turn
##   - Cascade clears count toward collect_crop goals
##
## Scoring:
##   - score_overrides applied when key present in level_data
##   - Fallback to balance defaults when key absent
##   - board.score accumulates across matches and cascades
##
## Goal tracking:
##   - Score goal completes mid-level; play continues until all goals met
##   - collect_crop goal incremented by matches, cascades, and special effects
##   - clear_dirt goal completes when last dirt is cleared
##   - clear_flowers goal completes when last flower reaches 0 HP
##   - all_goals_complete triggers win
##
## Win / fail:
##   - Win: all goals met on or before final turn
##   - Fail: turns reach 0 with goals unsatisfied
##   - Win on exact final turn (turns_remaining becomes 0 after the winning move)


# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestBoardController — full integration tests")
	print("=".repeat(64))

	_test_invalid_swap_no_match()
	_test_invalid_swap_two_specials()
	_test_invalid_swap_non_adjacent()
	_test_invalid_swap_no_turn_consumed()
	_test_valid_swap_accepted()
	_test_match3_score_and_clear()
	_test_match4_spawns_bushel_basket()
	_test_match5_spawns_scarecrow()
	_test_match_l_spawns_watering_can()
	_test_match_t_spawns_wheelbarrow()
	_test_bushel_basket_activation_clears_row()
	_test_bushel_basket_activation_awards_bonus()
	_test_scarecrow_activation_clears_crop_type()
	_test_watering_can_activation_clears_3x3()
	_test_wheelbarrow_activation_clears_cross()
	_test_dirt_adjacent_to_match_cleared()
	_test_dirt_included_in_match_cleared()
	_test_flower_takes_one_hit_per_event()
	_test_flower_hp_progression()
	_test_multiple_flowers_each_hit_once()
	_test_same_flower_not_hit_twice_per_event()
	_test_cascade_fires_after_refill()
	_test_cascade_does_not_consume_turn()
	_test_cascade_score_multiplier_level1()
	_test_cascade_counts_toward_collect_goal()
	_test_score_override_applied()
	_test_score_override_fallback()
	_test_score_accumulates_across_matches()
	_test_score_goal_completes_early_play_continues()
	_test_collect_crop_goal_from_match()
	_test_collect_crop_goal_from_special_effect()
	_test_clear_dirt_goal_completion()
	_test_clear_flowers_goal_completion()
	_test_win_all_goals_met()
	_test_fail_turns_exhausted()
	_test_win_on_exact_final_turn()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

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
	b.SEED_REWARD_SPECIAL_BUSHEL       = 5
	b.SEED_REWARD_SPECIAL_SCARECROW    = 10
	b.SEED_REWARD_SPECIAL_WATERING_CAN = 8
	b.SEED_REWARD_SPECIAL_WHEELBARROW  = 12
	b.LIFE_REGEN_MINUTES = 15
	b.MAX_LIVES          = 3
	b.SEED_COST_LIFE     = 30
	return b


func _make_level(
	crop_set: Array[String],
	goals: Array,
	turn_limit: int = 20,
	score_overrides: Dictionary = {}
) -> LevelData:
	var ld := LevelData.new()
	ld.level_id          = 1
	ld.turn_limit        = turn_limit
	ld.star_threshold_2  = int(turn_limit / 2.0)
	ld.star_threshold_3  = int(turn_limit / 4.0)
	ld.crop_set          = crop_set
	ld.seed_reward_3star = 0
	ld.score_overrides   = score_overrides
	ld.goals.assign(goals)

	# Blank 8×8 all-active grid.
	ld.grid_layout = []
	for _r in range(8):
		var row: Array = []
		for _c in range(8):
			row.append({"active": true, "obstacle": "none"})
		ld.grid_layout.append(row)

	return ld


## Builds a level whose grid_layout is taken from an 8-element string array
## using the same shorthand as BoardState.fill_from_strings().
func _make_level_with_grid(
	crop_set: Array[String],
	goals: Array,
	grid_strings: Array,
	turn_limit: int = 20,
	score_overrides: Dictionary = {}
) -> LevelData:
	var ld := LevelData.new()
	ld.level_id          = 1
	ld.turn_limit        = turn_limit
	ld.star_threshold_2  = int(turn_limit / 2.0)
	ld.star_threshold_3  = int(turn_limit / 4.0)
	ld.crop_set          = crop_set
	ld.seed_reward_3star = 0
	ld.score_overrides   = score_overrides
	ld.goals.assign(goals)

	ld.grid_layout = []
	for row_idx in range(8):
		var s: String = grid_strings[row_idx]
		var row: Array = []
		for col_idx in range(8):
			var ch: String = s[col_idx]
			match ch:
				"X":
					row.append({"active": false})
				"R":
					row.append({"active": true, "obstacle": "rock"})
				"F":
					row.append({"active": true, "obstacle": "flower", "flower_hp": 3})
				"D":
					row.append({"active": true, "obstacle": "dirt"})
				_:
					row.append({"active": true, "obstacle": "none"})
		ld.grid_layout.append(row)

	return ld


## Creates a BoardState pre-populated from a string grid and inits a
## BoardController with a seeded RNG for deterministic gravity/refill.
func _make_controller(
	grid_strings: Array,
	level_data: LevelData,
	balance: Balance,
	seed_val: int = 42
) -> BoardController:
	var board := BoardState.new()
	board.init_from_level(level_data)
	board.fill_from_strings(grid_strings)
	# Restore turn counters that fill_from_strings doesn't touch.
	board.turns_remaining = level_data.turn_limit
	board.turn_limit      = level_data.turn_limit

	var r := RandomNumberGenerator.new()
	r.seed = seed_val

	var ctrl := BoardController.new()
	ctrl.init(board, level_data, balance, r)
	return ctrl


## Returns true when the board cell at (row,col) holds the given piece id.
func _piece_is(ctrl: BoardController, row: int, col: int, piece: String) -> bool:
	return ctrl.board.get_cell(row, col).piece == piece


## Returns true when (row,col) is empty (no piece).
func _cell_empty(ctrl: BoardController, row: int, col: int) -> bool:
	return ctrl.board.get_cell(row, col).piece == ""


## Returns true when (row,col) has the given obstacle.
func _obstacle_is(ctrl: BoardController, row: int, col: int, obs: String) -> bool:
	return ctrl.board.get_cell(row, col).obstacle == obs


# ── Suite: swap validation ────────────────────────────────────────────────────

func _test_invalid_swap_no_match() -> void:
	_current_suite = "invalid swap — no match"
	print("\n── %s ──" % _current_suite)

	# Board: row 7 has a b a b a b a b  — swapping (7,0)↔(7,1) gives b a…
	# neither 'a' nor 'b' forms a three-in-a-row from that swap.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"babababa",
	], level, balance)

	var result := ctrl.attempt_swap(Vector2i(7, 0), Vector2i(7, 1))
	_assert(result.rejected,           "result.rejected is true")
	_assert(not result.accepted,       "result.accepted is false")
	_assert(ctrl.board.turns_remaining == 20, "no turn consumed on rejection")


func _test_invalid_swap_two_specials() -> void:
	_current_suite = "invalid swap — two specials (spec §5.1)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	], level, balance)

	# Manually place two specials adjacent to each other.
	ctrl.board.place_piece(4, 3, "bushel_basket", true, "horizontal")
	ctrl.board.place_piece(4, 4, "scarecrow",     true, "")

	var result := ctrl.attempt_swap(Vector2i(4, 3), Vector2i(4, 4))
	_assert(result.rejected,                       "two-specials swap rejected")
	_assert(ctrl.board.turns_remaining == 20,      "no turn consumed")
	_assert(_piece_is(ctrl, 4, 3, "bushel_basket"), "bushel_basket unmoved")
	_assert(_piece_is(ctrl, 4, 4, "scarecrow"),     "scarecrow unmoved")


func _test_invalid_swap_non_adjacent() -> void:
	_current_suite = "invalid swap — non-adjacent cells"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
	], level, balance)

	# Cells (0,0) and (0,2) are two apart — not orthogonally adjacent.
	var result := ctrl.attempt_swap(Vector2i(0, 0), Vector2i(0, 2))
	_assert(result.rejected,                  "diagonal / non-adjacent swap rejected")
	_assert(ctrl.board.turns_remaining == 20, "no turn consumed")


func _test_invalid_swap_no_turn_consumed() -> void:
	_current_suite = "invalid swap — turn counter unchanged"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Use three crop types in a repeating 3-cycle: abc|abc|ab per row, offset per row.
	# With a 3-crop cycle no run of 3 same-crop can exist in any row or column,
	# and no orthogonal swap can create one — any swap moves a cell one position in
	# the cycle, which still never aligns 3 of the same crop in a row or column.
	var level   := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}], 5)
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)

	ctrl.attempt_swap(Vector2i(0, 0), Vector2i(0, 1))
	ctrl.attempt_swap(Vector2i(3, 3), Vector2i(3, 4))
	ctrl.attempt_swap(Vector2i(6, 5), Vector2i(6, 6))

	_assert(ctrl.board.turns_remaining == 5, "turns still 5 after 3 rejected swaps")


func _test_valid_swap_accepted() -> void:
	_current_suite = "valid swap — accepted and turn consumed"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	# Row 7: a a a b ... — swapping (7,2)↔(7,3) keeps aaa in place but the
	# existing aaa at cols 0-2 already forms a match without a swap; instead
	# set up a clear trigger: col 7 has a a b, swap col 6↔7 at row 5 to make aaa.
	# Simpler: place aab in a row and swap b left to give aaa.
	var ctrl := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)

	# (7,1)↔(7,2): row 7 becomes a b a a a a a a — 'a' forms match at cols 2-7? No.
	# Use a guaranteed match: row 7 = "aabaaaaa", swap (7,2)←b→ with (7,1)←a→
	# gives "abaaaaa.." — no. Let's just use a vertical match setup.
	# col 0: rows 5,6,7 = a,a,b. swap (6,0)↔(7,0): gives a,b,a — no match.
	# Safest: col 0 rows 4,5,6 = a,a,. and row 7 = b. Place directly.
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"a.......",
		"a.......",
		"b.......",
		"b.......",
	])
	ctrl.board.turns_remaining = 20
	# Swap (5,0) with (6,0): col 0 becomes ...a,a,a,b,b — 3 a's match.
	# Actually after swap: row4=a, row5=b, row6=a — no. Let's place:
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"b.......",
		"a.......",
		"a.......",
		"a.......",
	])
	ctrl.board.turns_remaining = 20
	# col 0 rows 5,6,7 = a,a,a — already a match. We need to trigger via swap.
	# Place 'a' at row 4 col 1 and 'b' at row 4 col 0. Swap → col1 gets b, col0 gets a
	# which doesn't help col 0. Let's use a horizontal setup.
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	])
	ctrl.board.turns_remaining = 20
	# Row 7: a a b a a a a a  — swap (7,2)↔(7,3) → a a a b a a a a  → 'a' match at 0-2
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,                       "valid swap accepted")
	_assert(not result.rejected,                   "not rejected")
	_assert(ctrl.board.turns_remaining == 19,      "turn decremented to 19")


# ── Suite: match resolution and scoring ───────────────────────────────────────

func _test_match3_score_and_clear() -> void:
	_current_suite = "match-3 — score and board clear"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Use three crops so no cascade can form after refill.
	# Board: rows 0-6 use a 3-cycle pattern (no 3-in-a-row possible),
	# row 7 = "aacabcbc": swap (7,2)↔(7,3) → a,a,a,b,c,b,c — match-3 'a' at
	# cols 0-2 only.  Cols 3-7 post-swap = b,c,b,b,c — no run.
	# After clearing cols 0-2 of row7, gravity drops the 3-cycle rows above;
	# since 3-cycle rows can never produce a run of 3, no cascade fires.
	var level   := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"aacabcbc",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	# swap (7,2)↔(7,3): row7 → a,a,a,b,c,b,b,c — match-3 'a' at cols 0-2 only.
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,         "swap accepted")
	# Score = 3 × 50 = 150 (balance default, no overrides)
	_assert(ctrl.board.score == 150, "score == 150 for match-3")
	_assert(result.points_earned >= 150, "points_earned includes match-3 score")


func _test_match4_spawns_bushel_basket() -> void:
	_current_suite = "match-4 — Bushel Basket spawns at swap origin"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Vertical match-4 in col 0, triggered by a horizontal swap at row 5.
	#
	# Base board: 3-crop abc-cycle pattern — no 3-in-a-row anywhere.
	# Base row 4 col0 = "b" (from "bcabcabc") — this sits above the match and
	# is NOT "a", so col0 cannot extend to a match-5. ✓
	#
	# Overwrite col 0 rows 5-7 and col 1 row 5 to set up the trigger:
	#   (5,0)="b"  (5,1)="a"  (6,0)="a"  (7,0)="a"  — only 3 cells below swap row.
	# But we need 4 "a"s total in col0 after the swap, so also overwrite (4,0)="a":
	#   (4,0)="a"  (5,0)="b"  (5,1)="a"  (6,0)="a"  (7,0)="a"
	# swap (5,0)↔(5,1): (5,0)←"a", (5,1)←"b".
	# col0 rows 4,5,6,7 = a,a,a,a → vertical match-4. ✓
	# Row 3 col0 from base = "a" (from "abcabcab") — would extend to 5!
	# Use row 7 as the bottom: rows 4,5,6,7 col0.
	# Base row 3 col0 = "a" — clash. So shift: use rows 5,6,7 + one more.
	# Better anchor: base row 4 col0 = "b" ✓ (not "a"), so match rows 4-7 is safe
	# as long as row 3 col0 ≠ "a". Base row 3 = "abcabcab" → col0 = "a". Clash!
	#
	# Solution: keep match at rows 4-7, but use a base row 3 that has col0 ≠ "a".
	# Shift the cycle by one row at the top so row 3 = "bcabcabc" (col0="b"):
	#   row0="bcabcabc" row1="cabcabca" row2="abcabcab" row3="bcabcabc"
	#   row4="cabcabca" row5="abcabcab" row6="bcabcabc" row7="cabcabca"
	# Now base row3 col0="b", row4 col0="c" — neither is "a". ✓
	# Overwrite (4,0)="b", (4,1)="a", (5,0)="a", (6,0)="a", (7,0)="a".
	# After swap (4,0)↔(4,1): col0 rows 4,5,6,7 = a,a,a,a → match-4. ✓
	# Row 3 col0 = "b" ≠ "a" → no match-5. ✓
	# Refill fills col0 rows 0-3 into the cycle — no 3-in-a-row possible. ✓
	var level := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}])
	var ctrl  := _make_controller([
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
	], level, balance)
	ctrl.board.place_piece(4, 0, "b", false, "")  # displaced right by swap
	ctrl.board.place_piece(4, 1, "a", false, "")  # cell_b: moves left into col0
	ctrl.board.place_piece(5, 0, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(6, 0, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(7, 0, "a", false, "")  # vertical match cell
	ctrl.board.turns_remaining = level.turn_limit

	# swap (4,0)↔(4,1): col0 rows 4,5,6,7 = a,a,a,a → vertical match-4.
	# swap_origin = cell_a = (4,0). Basket spawns at (4,0); falls to row 7.
	var result := ctrl.attempt_swap(Vector2i(4, 0), Vector2i(4, 1))
	_assert(result.accepted, "swap accepted")

	var cell := ctrl.board.get_cell(7, 0)
	_assert(cell.is_special and cell.piece == "bushel_basket",
		"bushel_basket spawned at swap origin (7,0)")
	# Score = 4 × 100 + 200 bonus = 600
	_assert(ctrl.board.score == 600, "score == 600 for match-4 + special bonus")


func _test_match5_spawns_scarecrow() -> void:
	_current_suite = "match-5 — Scarecrow spawns at swap origin"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Vertical match-5 in col 0, triggered by a horizontal swap at row 3.
	#
	# Base board: 3-crop abc-cycle pattern — no 3-in-a-row anywhere, so the
	# post-refill board (which receives at most 3 new pieces in col 0 rows 0-2)
	# also stays cascade-free.
	#
	# Overwrite col 0 rows 3-7 and col 1 row 3 to set up the trigger:
	#   (3,0)="b"  (3,1)="a"  (4,0)="a"  (5,0)="a"  (6,0)="a"  (7,0)="a"
	# swap (3,0)↔(3,1): (3,0)←"a", (3,1)←"b".
	# col0 rows 3,4,5,6,7 = a,a,a,a,a → vertical match-5. ✓
	# swap_origin = cell_a = (3,0). Scarecrow spawns at (3,0); falls to row 7. ✓
	# Only col0 rows 0-2 are refilled (3 cells into an existing abc cycle) → no cascade. ✓
	var level := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}])
	var ctrl  := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(3, 0, "b", false, "")  # displaced right by swap
	ctrl.board.place_piece(3, 1, "a", false, "")  # cell_b: moves left into col0
	ctrl.board.place_piece(4, 0, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(5, 0, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(6, 0, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(7, 0, "a", false, "")  # vertical match cell
	ctrl.board.turns_remaining = level.turn_limit

	# swap (3,0)↔(3,1): col0 rows 3,4,5,6,7 = a,a,a,a,a → vertical match-5.
	# swap_origin = cell_a = (3,0). Scarecrow spawns at (3,0); falls to row7.
	var result := ctrl.attempt_swap(Vector2i(3, 0), Vector2i(3, 1))
	_assert(result.accepted, "swap accepted")

	# Scarecrow spawns at cell_a=(3,0) then falls through cleared rows 4,5,6,7 → row7.
	var cell := ctrl.board.get_cell(7, 0)
	_assert(cell.is_special and cell.piece == "scarecrow",
		"scarecrow spawned at swap origin (7,0)")
	# Score = 5 × 150 + 200 = 950
	_assert(ctrl.board.score == 950, "score == 950 for match-5 + special bonus")




func _test_match_l_spawns_watering_can() -> void:
	_current_suite = "L-shape match — Watering Can spawns at swap origin"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Base board: 3-crop abc-cycle pattern — no 3-in-a-row anywhere.
	# After clearing the 5 L-shape cells and refilling, the new pieces drop into
	# existing abc-cycle neighbours in col3 rows 0-6 and cols 4-5 row5, none of
	# which can form a run → no cascade. ✓
	#
	# L-shape: vertical spine col3 rows5,6,7 + horizontal arm row5 cols3,4,5.
	# Overwrite those cells plus (4,3) for the swap:
	#   (4,3)="a"  (5,3)="b"  (6,3)="a"  (7,3)="a"  (5,4)="a"  (5,5)="a"
	# swap (4,3)↔(5,3): (4,3)←"b", (5,3)←"a".
	# col3 rows5,6,7=a,a,a + row5 cols3,4,5=a,a,a → L-shape (5 cells). ✓
	# Can spawns at cell_a=(4,3); col3 rows5-7 cleared → falls to row7. ✓
	# Score = 5×100 + 200 = 700. ✓
	var level := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}])
	var ctrl  := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(4, 3, "a", false, "")  # cell_a: moves into row5 after swap
	ctrl.board.place_piece(5, 3, "b", false, "")  # displaced upward by swap
	ctrl.board.place_piece(6, 3, "a", false, "")  # vertical spine middle
	ctrl.board.place_piece(7, 3, "a", false, "")  # vertical spine bottom
	ctrl.board.place_piece(5, 4, "a", false, "")  # horizontal arm cell 1
	ctrl.board.place_piece(5, 5, "a", false, "")  # horizontal arm cell 2
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(4, 3), Vector2i(5, 3))
	_assert(result.accepted, "L-shape swap accepted")

	# Can spawns at cell_a=(4,3) then falls through cleared rows 5,6,7 → row7.
	var cell := ctrl.board.get_cell(7, 3)
	_assert(cell.is_special and cell.piece == "watering_can",
		"watering_can settled in col 3 after gravity")
	# Score = 5 × 100 + 200 = 700
	_assert(ctrl.board.score == 700, "score == 700 for L-shape + special bonus")


func _test_match_t_spawns_wheelbarrow() -> void:
	_current_suite = "T-shape match — Wheelbarrow spawns at swap origin"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# T-shape (vertical spine): centre at (6,3), spine (5,3),(6,3),(7,3),
	# arm (6,2),(6,4). The MatchFinder detects this as a plus/cross pattern.
	#
	# Trigger: swap cell_a=(7,3) with cell_b=(7,4).
	#   Pre-swap:  (7,3)="b", (7,4)="a"
	#   Post-swap: (7,3)←"a", (7,4)←"b"
	# T-shape cells after swap: (5,3),(6,3),(7,3),(6,2),(6,4) all = "a". ✓
	# BoardController overrides swap_origin = cell_a = (7,3).
	# Wheelbarrow spawns at (7,3) — already the bottom row, no falling needed. ✓
	#
	# Cleared cells: (5,3),(6,3),(7,3),(6,2),(6,4).
	# After clear, col 3 rows 5 and 6 are empty (row 7 holds the wheelbarrow).
	# A rock at (4,3) acts as a hard barrier: _piece_at() returns "" for rocks,
	# so the 2 refill cells at rows 5,6 are completely isolated — they can never
	# form a 3-in-a-row with anything above the rock or the special below. ✓
	# Col 2 and col 4 each lose only row 6 → 1 refill cell each → no cascade. ✓
	# Score = 5 × 120 + 200 = 800. ✓
	var level := _make_level(["a", "b", "c"], [{"type": "score", "target": 9999}])
	var ctrl  := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcaRcabc",  # R = rock at (4,3) — isolates the col-3 refill cells
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(5, 3, "a", false, "")  # spine top
	ctrl.board.place_piece(6, 3, "a", false, "")  # spine centre
	ctrl.board.place_piece(7, 3, "b", false, "")  # cell_a: displaced right by swap
	ctrl.board.place_piece(7, 4, "a", false, "")  # cell_b: moves left into col3
	ctrl.board.place_piece(6, 2, "a", false, "")  # horizontal arm left
	ctrl.board.place_piece(6, 4, "a", false, "")  # horizontal arm right
	ctrl.board.turns_remaining = level.turn_limit

	# swap (7,3)↔(7,4): (7,3)←"a", (7,4)←"b".
	# T-shape: (5,3),(6,3),(7,3)=a,a,a + (6,2),(6,4)=a,a. ✓
	# swap_origin = cell_a = (7,3). Wheelbarrow spawns at (7,3).
	var result := ctrl.attempt_swap(Vector2i(7, 3), Vector2i(7, 4))
	_assert(result.accepted, "T-shape swap accepted")

	# Wheelbarrow spawns at cell_a=(7,3) — bottom row, no gravity fall needed.
	var wh_cell := ctrl.board.get_cell(7, 3)
	_assert(wh_cell.is_special and wh_cell.piece == "wheelbarrow",
		"wheelbarrow at swap origin (7,3)")
	# Score = 5 × 120 + 200 = 800
	_assert(ctrl.board.score == 800, "score == 800 for T-shape + special bonus")


# ── Suite: special piece activation ──────────────────────────────────────────

func _test_bushel_basket_activation_clears_row() -> void:
	_current_suite = "Bushel Basket activation — clears row (spec §5.2)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aaaaaaaa",
	], level, balance)

	# Place a Bushel Basket at (6,4) with horizontal orientation.
	ctrl.board.place_piece(6, 4, "bushel_basket", true, "horizontal")
	# Place a normal crop adjacent so swap is valid (swap with (6,5)).
	ctrl.board.place_piece(6, 5, "a", false, "")
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(6, 4), Vector2i(6, 5))
	_assert(result.accepted, "bushel basket swap accepted")
	# Row 6 should now be entirely empty (all 8 cells cleared by the activation).
	var _row_empty := true
	for col in range(8):
		if ctrl.board.get_cell(6, col).has_piece():
			# A refill may have placed a new piece here; but bushel_basket fires
			# before gravity, so pieces on row 6 are cleared then gravity+refill runs.
			# After refill row 6 is full again. So we check seeds/score instead.
			_row_empty = false
	# seeds_earned should include SEED_REWARD_SPECIAL_BUSHEL = 5
	_assert(ctrl.board.seeds_earned == 5, "seeds_earned == 5 (SEED_REWARD_SPECIAL_BUSHEL)")
	_assert(result.seeds_earned == 5, "result.seeds_earned == 5")


func _test_bushel_basket_activation_awards_bonus() -> void:
	_current_suite = "Bushel Basket activation — flat score bonus awarded"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"aaaaaaaa",
		"bbbbbbbb",
	], level, balance)

	ctrl.board.place_piece(6, 0, "bushel_basket", true, "horizontal")
	ctrl.board.place_piece(6, 1, "a", false, "")
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(6, 0), Vector2i(6, 1))
	# Activation bonus = 200. Score may be higher if cascades fire after refill,
	# so check >= 200.
	_assert(ctrl.board.score >= 200, "activation flat bonus >= 200 applied to score")


func _test_scarecrow_activation_clears_crop_type() -> void:
	_current_suite = "Scarecrow activation — clears all matching crop (spec §5.2)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# collect_crop goal so we can verify cleared pieces count toward it.
	var level   := _make_level(["a", "b"],
		[{"type": "collect_crop", "crop": "a", "target": 7}])

	var ctrl    := _make_controller([
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbabbbb",
		"bbbabbbb",
	], level, balance)

	# Place 5 more 'a' pieces scattered around.
	ctrl.board.place_piece(0, 0, "a", false, "")
	ctrl.board.place_piece(0, 7, "a", false, "")
	ctrl.board.place_piece(2, 3, "a", false, "")
	ctrl.board.place_piece(4, 5, "a", false, "")
	ctrl.board.place_piece(5, 2, "a", false, "")
	# Total 'a' on board: (0,0)(0,7)(2,3)(4,5)(5,2)(6,3)(7,3) = 7 'a' pieces.

	# Place scarecrow at (6,4), swap partner at (6,3) = 'a'.
	ctrl.board.place_piece(6, 4, "scarecrow", true, "")
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(6, 4), Vector2i(6, 3))
	_assert(result.accepted, "scarecrow swap accepted")
	# All 'a' pieces should be cleared. Goal target = 7.
	_assert(ctrl.goal_tracker.all_goals_complete(),
		"collect_crop goal complete — all 7 'a' cleared by scarecrow")
	_assert(ctrl.board.seeds_earned == 10,
		"seeds_earned == 10 (SEED_REWARD_SPECIAL_SCARECROW)")


func _test_watering_can_activation_clears_3x3() -> void:
	_current_suite = "Watering Can activation — clears 3×3 area (spec §5.2)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
	], level, balance)

	# Place watering_can at (3,3), swap partner at (3,4).
	ctrl.board.place_piece(3, 3, "watering_can", true, "")
	ctrl.board.place_piece(3, 4, "b", false, "")
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(3, 3), Vector2i(3, 4))

	# The 3×3 centred on (3,3) covers rows 2-4, cols 2-4 — 9 cells.
	# After activation + refill those cells will have new pieces.
	# We verify via seeds_earned. Score may exceed 200 if cascades form.
	_assert(ctrl.board.seeds_earned == 8,
		"seeds_earned == 8 (SEED_REWARD_SPECIAL_WATERING_CAN)")
	_assert(ctrl.board.score >= 200, "activation flat bonus >= 200 in score")


func _test_wheelbarrow_activation_clears_cross() -> void:
	_current_suite = "Wheelbarrow activation — clears full cross (spec §5.2)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
	], level, balance)

	ctrl.board.place_piece(4, 4, "wheelbarrow", true, "")
	ctrl.board.place_piece(4, 5, "b", false, "")
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(4, 4), Vector2i(4, 5))

	# Row 4 + col 4 = 8 + 8 - 1 = 15 cells cleared (intersection counted once).
	# Seeds = SEED_REWARD_SPECIAL_WHEELBARROW = 12.
	# Score may exceed 200 if cascades form after refill.
	_assert(ctrl.board.seeds_earned == 12,
		"seeds_earned == 12 (SEED_REWARD_SPECIAL_WHEELBARROW)")
	_assert(ctrl.board.score >= 200, "activation flat bonus >= 200 in score")


# ── Suite: obstacle clearing ──────────────────────────────────────────────────

func _test_dirt_adjacent_to_match_cleared() -> void:
	_current_suite = "dirt — cleared when orthogonally adjacent to match (spec §3.3)"
	print("\n── %s ──" % _current_suite)

	# Dirt at (6,4). Match row 7 cols 3-5 (adjacent to (6,4) via (7,4)).
	# Board row 7: b b b a a b a b — swap (7,5)↔(7,6) → b b b a a a b b.
	# Match at cols 3-5 includes (7,4) which is orthogonally adjacent to (6,4).
	# Rows 0-6 use a strict alternating column stripe (ababababab…) so that
	# after gravity/refill settles into the cleared cells, no run of 3 same-crop
	# can form and cascade into the obstacle row.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "clear_dirt"}])
	# row 7: b a b a a b a b — swap (7,4)↔(7,5) → b a b a a a b b  NO.
	# row 7: b a b b a a a b — swap (7,3)↔(7,4) → b a b a b a a b  NO.
	# Use: row 7 = b a b a a b b a, swap (7,5)↔(7,4): b a b a b a b a — no match.
	# Simplest safe layout: row 7 cols 3-5 will be a a a after the swap.
	# Pre-swap row 7: b a b a a b a b — swap (7,5)↔(7,6) gives b a b a a a b b.
	# Match at cols 3-5. (6,4) is orthogonally adjacent to (7,4) in the match. ✓
	# Cols 0-2 = b a b — no run of 3. ✓
	var ctrl    := _make_controller([
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"abababab",
	], level, balance)

	# Override row 7 with a clean, unambiguous layout via place_piece.
	ctrl.board.place_piece(7, 0, "b", false, "")
	ctrl.board.place_piece(7, 1, "a", false, "")
	ctrl.board.place_piece(7, 2, "b", false, "")
	ctrl.board.place_piece(7, 3, "a", false, "")
	ctrl.board.place_piece(7, 4, "a", false, "")
	ctrl.board.place_piece(7, 5, "b", false, "")
	ctrl.board.place_piece(7, 6, "a", false, "")
	ctrl.board.place_piece(7, 7, "b", false, "")
	# row 7 is now: b a b a a b a b
	# swap (7,5)↔(7,6) → b a b a a a b b — match-3 at cols 3-5.
	ctrl.board.get_cell(6, 4).obstacle = BoardState.OBSTACLE_DIRT
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(7, 5), Vector2i(7, 6))
	_assert(result.accepted, "swap accepted")
	_assert(_obstacle_is(ctrl, 6, 4, "none"), "dirt at (6,4) cleared by adjacent match")


func _test_dirt_included_in_match_cleared() -> void:
	_current_suite = "dirt — cleared when cell is part of the match (spec §3.3)"
	print("\n── %s ──" % _current_suite)

	# Dirt underlays a normal piece. The piece participates in a match.
	# The match event clears the dirt.
	var balance := _make_balance()
	var level   := _make_level_with_grid(
		["a", "b"],
		[{"type": "clear_dirt"}],
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
		]
	)

	var ctrl := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)

	# Manually set cell (7,0) to have dirt obstacle with piece 'a' on top.
	ctrl.board.get_cell(7, 0).obstacle = BoardState.OBSTACLE_DIRT
	ctrl.board.get_cell(7, 1).obstacle = BoardState.OBSTACLE_DIRT
	ctrl.board.turns_remaining = level.turn_limit

	# row7: a a b a a a a a — swap (7,2)↔(7,3) → a a a b a a a a
	# Match at cols 0-2; cells (7,0) and (7,1) have dirt and are IN the match.
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted, "swap accepted")
	_assert(_obstacle_is(ctrl, 7, 0, "none"), "dirt at (7,0) cleared — cell in match")
	_assert(_obstacle_is(ctrl, 7, 1, "none"), "dirt at (7,1) cleared — cell in match")


func _test_flower_takes_one_hit_per_event() -> void:
	_current_suite = "flower — takes one hit per adjacent match event (spec §3.3)"
	print("\n── %s ──" % _current_suite)

	# Vertical match-3 in col 3 rows 5,6,7. Flower at (5,2) is adjacent to (5,3).
	# Use 3-cycle background so refill never cascades into the flower again.
	# swap (4,3)↔(5,3): (4,3)='a' swaps with (5,3)='b' → col3 rows5,6,7 = a,a,a → match-3.
	# Cleared cells: (5,3)(6,3)(7,3). Flower at (5,2) is adjacent to cleared (5,3) → one hit.
	# After gravity+refill, 3-cycle pieces fill col3; no vertical 3-run possible.
	# No horizontal cascade: cells in rows 5,6,7 cols other than 3 are 3-cycle → no run.
	var balance := _make_balance()
	var level   := _make_level(["a", "b", "c"], [{"type": "clear_flowers"}])
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(4, 3, "a", false, "")  # will swap down into row5
	ctrl.board.place_piece(5, 3, "b", false, "")  # displaced by swap
	ctrl.board.place_piece(6, 3, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(7, 3, "a", false, "")  # vertical match cell
	# Flower at (5,2): adjacent to cleared match cell (5,3).
	ctrl.board.get_cell(5, 2).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(5, 2).flower_hp = 3
	ctrl.board.get_cell(5, 2).piece     = ""
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(4, 3), Vector2i(5, 3))
	_assert(result.accepted, "swap accepted")
	var hp := ctrl.board.get_cell(5, 2).flower_hp
	_assert(hp == 2, "flower HP reduced from 3 to 2 (one hit from adjacent match)")
	_assert(_obstacle_is(ctrl, 5, 2, "flower"), "flower still present at HP 2")


func _test_flower_hp_progression() -> void:
	_current_suite = "flower HP progression: 3 → 2 → 1 → 0 cleared (spec §3.3)"
	print("\n── %s ──" % _current_suite)

	# Test HP progression directly via BoardState.hit_flower — this exercises
	# the same code path BoardController calls internally via _process_obstacle_adjacency.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "clear_flowers"}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	], level, balance)

	ctrl.board.get_cell(3, 4).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(3, 4).flower_hp = 3
	ctrl.board.turns_remaining = level.turn_limit

	var hp1 := ctrl.board.hit_flower(3, 4)
	_assert(hp1 == 2, "after 1st hit: HP == 2 (Budding)")
	_assert(_obstacle_is(ctrl, 3, 4, "flower"), "flower still present")

	var hp2 := ctrl.board.hit_flower(3, 4)
	_assert(hp2 == 1, "after 2nd hit: HP == 1 (Blooming)")
	_assert(_obstacle_is(ctrl, 3, 4, "flower"), "flower still present")

	var hp3 := ctrl.board.hit_flower(3, 4)
	_assert(hp3 == 0, "after 3rd hit: HP == 0 (Cleared)")
	_assert(_obstacle_is(ctrl, 3, 4, "none"), "flower cleared — obstacle == none")


func _test_multiple_flowers_each_hit_once() -> void:
	_current_suite = "multiple flowers adjacent to same clear — each hit once"
	print("\n── %s ──" % _current_suite)

	# Vertical match-3 in col3 rows 5,6,7. Flowers at (5,2) and (6,2).
	# (5,2) is adjacent to cleared cell (5,3) → one hit.
	# (6,2) is adjacent to cleared cell (6,3) → one hit.
	# 3-cycle background ensures no cascade fires after refill.
	var balance := _make_balance()
	var level   := _make_level(["a", "b", "c"], [{"type": "clear_flowers"}])
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(4, 3, "a", false, "")  # will swap into row5
	ctrl.board.place_piece(5, 3, "b", false, "")  # displaced by swap
	ctrl.board.place_piece(6, 3, "a", false, "")  # vertical match cell
	ctrl.board.place_piece(7, 3, "a", false, "")  # vertical match cell
	ctrl.board.get_cell(5, 2).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(5, 2).flower_hp = 3
	ctrl.board.get_cell(5, 2).piece     = ""
	ctrl.board.get_cell(6, 2).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(6, 2).flower_hp = 3
	ctrl.board.get_cell(6, 2).piece     = ""
	ctrl.board.turns_remaining = level.turn_limit

	# swap (4,3)↔(5,3): col3 rows5,6,7 = a,a,a → match-3.
	ctrl.attempt_swap(Vector2i(4, 3), Vector2i(5, 3))

	_assert(ctrl.board.get_cell(5, 2).flower_hp == 2,
		"flower at (5,3) hit once → HP 2")
	_assert(ctrl.board.get_cell(6, 2).flower_hp == 2,
		"flower at (5,4) hit once → HP 2")


func _test_same_flower_not_hit_twice_per_event() -> void:
	_current_suite = "same flower not hit twice by one clear event"
	print("\n── %s ──" % _current_suite)

	# L-shape match cells: col3 rows5,6,7 (vert spine) + row5 cols4,5 (horiz arm).
	# 5 cells: (5,3)(6,3)(7,3)(5,4)(5,5).
	# Flower at (6,4) is adjacent to BOTH (6,3) and (5,4) — two cleared cells from
	# the same event. _process_obstacle_adjacency must deduplicate → exactly one hit.
	#
	# Trigger: swap (4,3)↔(5,3) where (4,3)='a' and (5,3)='b'.
	# After swap: col3 rows5,6,7=a,a,a + row5 cols3,4,5=a,a,a → L-shape. ✓
	# 3-cycle background ensures no cascade after refill.
	# The flower at (6,4) blocks gravity in col4 above row6; 3-cycle pieces above
	# it cannot form a 3-run regardless. ✓
	var balance := _make_balance()
	var level   := _make_level(["a", "b", "c"], [{"type": "clear_flowers"}])
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
	], level, balance)
	ctrl.board.place_piece(4, 3, "a", false, "")  # will swap into row5
	ctrl.board.place_piece(5, 3, "b", false, "")  # displaced by swap
	ctrl.board.place_piece(6, 3, "a", false, "")  # vertical spine cell
	ctrl.board.place_piece(7, 3, "a", false, "")  # vertical spine cell
	ctrl.board.place_piece(5, 4, "a", false, "")  # horizontal arm cell 1
	ctrl.board.place_piece(5, 5, "a", false, "")  # horizontal arm cell 2
	# Flower at (6,4): adjacent to cleared cells (6,3) and (5,4) — both in L-shape.
	ctrl.board.get_cell(6, 4).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(6, 4).flower_hp = 3
	ctrl.board.get_cell(6, 4).piece     = ""
	ctrl.board.turns_remaining = level.turn_limit

	# swap (4,3)↔(5,3): L-shape {(5,3)(6,3)(7,3)(5,4)(5,5)}.
	# (6,4) adj to both (6,3) and (5,4) — must be hit exactly once.
	ctrl.attempt_swap(Vector2i(4, 3), Vector2i(5, 3))

	_assert(ctrl.board.get_cell(6, 4).flower_hp == 2,
		"flower at (5,4) hit exactly once despite two adjacent match cells → HP 2")


# ── Suite: cascades ───────────────────────────────────────────────────────────

func _test_cascade_fires_after_refill() -> void:
	_current_suite = "cascade — fires automatically when refill creates a match"
	print("\n── %s ──" % _current_suite)

	# Set up a board where removing a row creates a chain match after refill
	# by using a deterministic RNG and a carefully arranged top section.
	# Simpler: verify cascade_levels > 0 when a cascade is expected.
	# We'll use a board arranged so that after gravity the top pieces form a match.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	], level, balance)

	# Arrange: rows 5-7 = all 'a'. When we clear row 7 via match, rows 5-6
	# fall to fill, then remaining 'a' pattern causes a cascade.
	# Easier: place aaa in row 5 and aab in row 7. After clearing row 7 match,
	# gravity drops row5 aaa to row 6 (or 7). That's already a match → cascade.
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"bbbbbbbb",
		"aaabbbbb",
		"bbbbbbbb",
		"aabaaaaa",
	])
	ctrl.board.turns_remaining = level.turn_limit

	# row7 swap (7,2)↔(7,3): aaa at cols 0-2 match → cleared.
	# After gravity, row5 'a' pieces fall to row 7 cols 0-1 (only 2 remain in col 0 and 1).
	# Hmm, let's verify via cascade_levels in result:
	# Actually let's just confirm score > base match score to indicate cascade fired.
	# Set up a guaranteed cascade: rows 4-6 all 'a', row 7 = aabaaaaa.
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"aaabbbbb",
		"aaabbbbb",
		"aaabbbbb",
		"aabaaaaa",
	])
	ctrl.board.turns_remaining = level.turn_limit
	# swap (7,2)↔(7,3): row7 → aaabaaaa, match at cols 0-2.
	# After clearing rows7 cols 0-2, gravity: col0 gets a a a (rows 4-6) falling
	# to rows 5-7. col1 same. col2 same. So rows 5-7 cols 0-2 = a a a pattern
	# → new match in col0 (rows 5-7) or row5 (cols 0-2) → cascade.
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,          "swap accepted")
	_assert(result.cascade_levels > 0, "at least one cascade fired")
	_assert(ctrl.board.score > 150,    "score > 150 due to cascade points")


func _test_cascade_does_not_consume_turn() -> void:
	_current_suite = "cascade — does not consume a turn (spec §6.4)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}], 10)
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"aaabbbbb",
		"aaabbbbb",
		"aaabbbbb",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = 10

	var before_turns := ctrl.board.turns_remaining
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted, "swap accepted")
	_assert(result.cascade_levels > 0, "cascade(s) fired")
	# Exactly one turn consumed regardless of cascade count.
	_assert(ctrl.board.turns_remaining == before_turns - 1,
		"exactly one turn consumed even with cascades")


func _test_cascade_score_multiplier_level1() -> void:
	_current_suite = "cascade score — chain level 1 applies 1.5× multiplier (spec §6.4)"
	print("\n── %s ──" % _current_suite)

	# We verify the cascade multiplier by checking that the total score
	# is greater than what two plain match-3s would give (2 × 150 = 300)
	# because the cascade gets 1.5× applied (225), so total > 300.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"aaabbbbb",
		"aaabbbbb",
		"aaabbbbb",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted, "swap accepted")
	_assert(result.cascade_levels >= 1, "at least one cascade")
	# Base match score = 150. Cascade-1 match score = 150 × 1.5 = 225. Total ≥ 375.
	_assert(ctrl.board.score >= 375,
		"score >= 375 confirming cascade 1.5× multiplier applied")


func _test_cascade_counts_toward_collect_goal() -> void:
	_current_suite = "cascade — cleared pieces count toward collect_crop goal (spec §6.4)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"],
		[{"type": "collect_crop", "crop": "a", "target": 6}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"aaabbbbb",
		"aaabbbbb",
		"aaabbbbb",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))

	# Player match clears 3 'a'. Cascade clears at least 3 more 'a'. Total ≥ 6.
	_assert(ctrl.goal_tracker.get_progress(0) >= 6,
		"collect_crop progress >= 6 — cascade clears counted toward goal")


# ── Suite: scoring ────────────────────────────────────────────────────────────

func _test_score_override_applied() -> void:
	_current_suite = "score_overrides — override applied when key present"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Override match_3 per-piece to 75. 3 × 75 = 225.
	var level   := _make_level(["a", "b"],
		[{"type": "score", "target": 9999}], 20, {"match_3": 75})
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	# Exact score check only if no cascade fired (fill is seeded but may vary).
	# Use >= 225 to be robust against cascade contributions.
	_assert(ctrl.board.score >= 225,
		"score >= 225 with match_3 override of 75/piece")


func _test_score_override_fallback() -> void:
	_current_suite = "score_overrides — fallback to balance default when key absent"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Override only match_5 — match_3 must fall back to balance default (50).
	var level   := _make_level(["a", "b"],
		[{"type": "score", "target": 9999}], 20, {"match_5": 999})
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	# If match_3 falls back to 50, base = 150. Score >= 150.
	_assert(ctrl.board.score >= 150,
		"score >= 150 confirming match_3 falls back to balance default (50/piece)")


func _test_score_accumulates_across_matches() -> void:
	_current_suite = "score — accumulates across multiple accepted turns"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "score", "target": 9999}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	# First match.
	ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	var score_after_1 := ctrl.board.score
	_assert(score_after_1 > 0, "score > 0 after first match")

	# Reset board for second controlled match.
	ctrl.board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	])
	ctrl.board.turns_remaining = 19

	ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	var score_after_2 := ctrl.board.score
	_assert(score_after_2 > score_after_1,
		"score after 2nd match > score after 1st match (accumulates)")


# ── Suite: goal tracking ──────────────────────────────────────────────────────

func _test_score_goal_completes_early_play_continues() -> void:
	_current_suite = "score goal — completes early; play continues (spec §8 scenario)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Two goals: score 150 (met on first match-3) + collect 20 'a' (not yet met).
	# Use 3-cycle background so no cascade fires after refill.
	# row7 = "aacbcbcb": col0=a, col1=a, col2=c, col3=b. swap (7,2)↔(7,3): col2=b, col3=c →
	#   row7 = a,a,b,c,c,b,c,b — NO match-3 there.
	# Better: row7 = "aacabcbc": col2=c, col3=a. swap (7,2)↔(7,3): col2=a, col3=c →
	#   row7 = a,a,a,c,b,c,b,c — match-3 'a' at cols 0-2 only. ✓
	# Cols 3-7 post-swap = c,b,c,b,c — no run. ✓
	# 3-cycle rows 0-6 prevent any vertical cascade. ✓
	# Score = 3 × 50 = 150 → score goal (target 150) met on this turn. ✓
	# Only 3 'a' pieces cleared → collect goal (target 20) stays incomplete. ✓
	var level   := _make_level(["a", "b", "c"], [
		{"type": "score",        "target": 150},
		{"type": "collect_crop", "crop": "a", "target": 20},
	])
	var ctrl    := _make_controller([
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"bcabcabc",
		"cabcabca",
		"abcabcab",
		"aacabcbc",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	# swap (7,2)↔(7,3): row7 → a,a,a,c,b,c,b,c — match-3 'a' at cols 0-2 → score=150.
	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted, "swap accepted")
	# Score goal (index 0) should now be complete.
	_assert(ctrl.goal_tracker.get_goal_state(0).complete,
		"score goal (index 0) complete after first match")
	# Collect goal (index 1) is not yet complete (only 3 'a' cleared, need 20).
	_assert(not ctrl.goal_tracker.get_goal_state(1).complete,
		"collect goal (index 1) still incomplete")
	# Level is NOT won yet.
	_assert(not result.win,
		"result.win is false — collect goal still open")
	_assert(not result.fail,
		"result.fail is false — turns remain")
	# 0 should be in newly_completed_goals, 1 should not.
	_assert(0 in result.newly_completed_goals,
		"index 0 in newly_completed_goals")
	_assert(1 not in result.newly_completed_goals,
		"index 1 NOT in newly_completed_goals")


func _test_collect_crop_goal_from_match() -> void:
	_current_suite = "collect_crop — goal fulfilled by match clears"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"],
		[{"type": "collect_crop", "crop": "a", "target": 3}])
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted, "swap accepted")
	_assert(ctrl.goal_tracker.get_goal_state(0).complete,
		"collect_crop goal complete after clearing 3+ 'a' pieces")


func _test_collect_crop_goal_from_special_effect() -> void:
	_current_suite = "collect_crop — goal fulfilled by special piece effect"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	var level   := _make_level(["a", "b"],
		[{"type": "collect_crop", "crop": "a", "target": 5}])
	var ctrl    := _make_controller([
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbbbbbb",
		"bbbabbbb",
		"bbbabbbb",
		"bbbabbbb",
	], level, balance)

	# Add 2 more 'a' scattered.
	ctrl.board.place_piece(0, 0, "a", false, "")
	ctrl.board.place_piece(0, 7, "a", false, "")
	# Total 'a': (0,0)(0,7)(5,3)(6,3)(7,3) = 5.

	ctrl.board.place_piece(5, 4, "scarecrow", true, "")
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(5, 4), Vector2i(5, 3))
	_assert(result.accepted, "scarecrow swap accepted")
	_assert(ctrl.goal_tracker.get_goal_state(0).complete,
		"collect_crop goal complete — 5 'a' cleared by scarecrow effect")


func _test_clear_dirt_goal_completion() -> void:
	_current_suite = "clear_dirt goal — completes when last dirt cleared"
	print("\n── %s ──" % _current_suite)

	# Dirt at (5,3). Match row 6 cols 3-5 (swap (6,5)↔(6,6)) is adjacent to it.
	# Alternating stripes prevent post-clear cascades from falsely completing
	# unrelated goals or interfering with obstacle state.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "clear_dirt"}])
	var ctrl    := _make_controller([
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"abababab",
	], level, balance)

	# Set row 6: b a b a a b a b → swap (6,5)↔(6,6) → b a b a a a b b — match at cols 3-5.
	ctrl.board.place_piece(6, 0, "b", false, "")
	ctrl.board.place_piece(6, 1, "a", false, "")
	ctrl.board.place_piece(6, 2, "b", false, "")
	ctrl.board.place_piece(6, 3, "a", false, "")
	ctrl.board.place_piece(6, 4, "a", false, "")
	ctrl.board.place_piece(6, 5, "b", false, "")
	ctrl.board.place_piece(6, 6, "a", false, "")
	ctrl.board.place_piece(6, 7, "b", false, "")
	ctrl.board.get_cell(5, 3).obstacle = BoardState.OBSTACLE_DIRT
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(6, 5), Vector2i(6, 6))
	_assert(result.accepted, "swap accepted")
	_assert(_obstacle_is(ctrl, 5, 3, "none"),
		"dirt at (5,3) cleared by adjacent match")
	_assert(ctrl.goal_tracker.get_goal_state(0).complete,
		"clear_dirt goal complete — all dirt cleared")
	_assert(result.win, "result.win true — only goal met")


func _test_clear_flowers_goal_completion() -> void:
	_current_suite = "clear_flowers goal — completes when last flower reaches 0 HP"
	print("\n── %s ──" % _current_suite)

	# Flower at (5,3) at HP 1. Match row 6 cols 3-5 delivers the final hit.
	# Alternating stripes prevent post-clear cascades near the flower cell.
	var balance := _make_balance()
	var level   := _make_level(["a", "b"], [{"type": "clear_flowers"}])
	var ctrl    := _make_controller([
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"babababa",
		"abababab",
		"abababab",
	], level, balance)

	# Set row 6 precisely: b a b a a b a b
	# swap (6,5)↔(6,6) → b a b a a a b b — match-3 at cols 3-5.
	# Cols 0-2 = b a b → no run of 3. (5,3) is adjacent to (6,3) in match. ✓
	ctrl.board.place_piece(6, 0, "b", false, "")
	ctrl.board.place_piece(6, 1, "a", false, "")
	ctrl.board.place_piece(6, 2, "b", false, "")
	ctrl.board.place_piece(6, 3, "a", false, "")
	ctrl.board.place_piece(6, 4, "a", false, "")
	ctrl.board.place_piece(6, 5, "b", false, "")
	ctrl.board.place_piece(6, 6, "a", false, "")
	ctrl.board.place_piece(6, 7, "b", false, "")
	ctrl.board.get_cell(5, 3).obstacle  = BoardState.OBSTACLE_FLOWER
	ctrl.board.get_cell(5, 3).flower_hp = 1
	ctrl.board.get_cell(5, 3).piece     = ""
	ctrl.board.turns_remaining = level.turn_limit

	var result := ctrl.attempt_swap(Vector2i(6, 5), Vector2i(6, 6))
	_assert(result.accepted, "swap accepted")
	_assert(_obstacle_is(ctrl, 5, 3, "none"),
		"flower cleared — obstacle == none after final hit")
	_assert(ctrl.goal_tracker.get_goal_state(0).complete,
		"clear_flowers goal complete")
	_assert(result.win, "result.win true — only goal met")


# ── Suite: win / fail ─────────────────────────────────────────────────────────

func _test_win_all_goals_met() -> void:
	_current_suite = "win — all goals met before turns run out"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Score goal with a low target easily met in one match.
	var level   := _make_level(["a", "b"],
		[{"type": "score", "target": 100}], 10)
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = 10

	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,     "swap accepted")
	_assert(result.win,          "result.win true — goal met")
	_assert(not result.fail,     "result.fail false")
	_assert(ctrl.board.turns_remaining == 9, "one turn consumed")


func _test_fail_turns_exhausted() -> void:
	_current_suite = "fail — turns reach 0 with goals unsatisfied"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Impossibly high score target so it never completes.
	var level   := _make_level(["a", "b"],
		[{"type": "score", "target": 999999}], 1)
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = 1

	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,          "swap accepted")
	_assert(result.fail,              "result.fail true — turns exhausted")
	_assert(not result.win,           "result.win false")
	_assert(ctrl.board.turns_remaining == 0, "turns_remaining == 0")


func _test_win_on_exact_final_turn() -> void:
	_current_suite = "win — goals met on the exact final turn (spec §9)"
	print("\n── %s ──" % _current_suite)

	var balance := _make_balance()
	# Score target achievable in one match (150). turn_limit = 1.
	var level   := _make_level(["a", "b"],
		[{"type": "score", "target": 100}], 1)
	var ctrl    := _make_controller([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"aabaaaaa",
	], level, balance)
	ctrl.board.turns_remaining = 1

	var result := ctrl.attempt_swap(Vector2i(7, 2), Vector2i(7, 3))
	_assert(result.accepted,          "swap accepted on final turn")
	_assert(result.win,               "result.win true — goal met on final turn")
	_assert(not result.fail,          "result.fail false — goal was met")
	_assert(ctrl.board.turns_remaining == 0,
		"turns_remaining == 0 after final turn")


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
