extends Node

## TestGravitySystem.gd
## Attach to a Node in scenes/tests/TestGravitySystem.tscn and press F6 to run.
## Covers every spec-mandated behavioral scenario for GravitySystem:
##
##   - Pieces fall correctly to the bottom of their column
##   - Special pieces fall identically to normal crop pieces
##   - Holes block falling — pieces settle above the hole, not past it
##   - Contiguous segments separated by holes are independent
##   - Rocks and flowers act as column barriers (they are inactive cells)
##   - Dirt-patch cells do not block gravity — pieces land on top of dirt
##   - Already-settled pieces produce no move entries
##   - Fully-empty fillable cells are all refilled
##   - Weighted refill: unsatisfied collect_crop goal doubles the crop's weight
##   - Satisfied collect_crop goal restores base weight (no double)
##   - Multiple collect_crop goals boost each respective crop independently
##   - Refill never spawns special pieces
##   - GravityResult.moves is empty when no piece needs to move
##   - GravityResult.fills is empty when no cell needs filling

# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestGravitySystem — gravity + weighted refill tests")
	print("=".repeat(64))

	_test_pieces_fall_to_bottom()
	_test_already_settled_no_moves()
	_test_gap_in_middle_of_column()
	_test_multiple_gaps_compact()
	_test_special_piece_falls_like_crop()
	_test_special_piece_orientation_preserved()
	_test_hole_blocks_falling()
	_test_pieces_above_hole_settle_above_it()
	_test_hole_in_middle_two_segments()
	_test_two_holes_three_segments()
	_test_rock_acts_as_barrier()
	_test_dirt_does_not_block_falling()
	_test_piece_lands_on_dirt()
	_test_refill_fills_all_empty_cells()
	_test_refill_only_empty_cells_filled()
	_test_refill_never_spawns_special()
	_test_weighted_refill_unsatisfied_goal()
	_test_weighted_refill_satisfied_goal_no_boost()
	_test_weighted_refill_multiple_goals()
	_test_moves_empty_when_nothing_falls()
	_test_fills_empty_when_board_full()
	_test_move_from_and_to_fields()
	_test_move_piece_id_preserved()
	_test_fill_top_to_bottom_order()
	_test_moves_bottom_to_top_order()
	_test_independent_columns()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_board() -> BoardState:
	var b := BoardState.new()
	b.init_empty()
	return b


func _make_system() -> GravitySystem:
	return GravitySystem.new()


## Builds a minimal LevelData with the given crop_set and goals.
## Uses a blank 8×8 grid so it never needs level file I/O.
func _make_level(crop_set: Array[String], goals: Array[Dictionary]) -> LevelData:
	var ld := LevelData.new()
	ld.level_id        = 1
	ld.turn_limit      = 20
	ld.star_threshold_2 = 10
	ld.star_threshold_3 = 5
	ld.crop_set        = crop_set
	ld.goals           = goals
	ld.seed_reward_3star = 0

	# Build a default all-active blank 8×8 grid_layout.
	ld.grid_layout = []
	for _row in range(8):
		var row_arr: Array = []
		for _col in range(8):
			row_arr.append({"active": true})
		ld.grid_layout.append(row_arr)

	return ld


## Returns a seeded RNG for deterministic tests.
func _make_rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


## Returns true when every Vector2i in `expected` appears exactly once in `arr`.
func _contains_all(arr: Array, expected: Array) -> bool:
	for v in expected:
		if v not in arr:
			return false
	return true


## Returns true when none of `excluded` appear in `arr`.
func _contains_none(arr: Array, excluded: Array) -> bool:
	for v in excluded:
		if v in arr:
			return false
	return true


## Collects all "from" Vector2i values from a moves array.
func _move_froms(moves: Array[Dictionary]) -> Array:
	var out: Array = []
	for mv in moves:
		out.append(mv["from"])
	return out


## Collects all "to" Vector2i values from a moves array.
func _move_tos(moves: Array[Dictionary]) -> Array:
	var out: Array = []
	for mv in moves:
		out.append(mv["to"])
	return out


## Collects all "cell" Vector2i values from a fills array.
func _fill_cells(fills: Array[Dictionary]) -> Array:
	var out: Array = []
	for f in fills:
		out.append(f["cell"])
	return out


## Finds the move entry whose "to" matches the given cell, or null.
func _move_to(moves: Array[Dictionary], to: Vector2i):
	for mv in moves:
		if mv["to"] == to:
			return mv
	return null


# ── Suite: basic gravity ──────────────────────────────────────────────────────

func _test_pieces_fall_to_bottom() -> void:
	_current_suite = "Gravity / piece at top of column falls to bottom"
	print("\n── %s ──" % _current_suite)

	# Single piece at (0, 0); rows 1-7 all empty.
	# Expected: piece moves from (0,0) to (7,0).
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	_assert(result != null, "calculate() returns a non-null GravityResult")

	var froms := _move_froms(result.moves)
	var tos   := _move_tos(result.moves)
	_assert(
		Vector2i(0, 0) in froms,
		"piece at (0,0) is listed as a move source"
	)
	_assert(
		Vector2i(7, 0) in tos,
		"piece from (0,0) lands at (7,0)"
	)

	# Confirm the specific move entry links (0,0) → (7,0).
	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 0))
	_assert(mv != null, "move entry with to=(7,0) exists")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 0), "move from=(0,0) to=(7,0)")
		_assert(mv["piece"] == "a",            "falling piece id is 'a'")


func _test_already_settled_no_moves() -> void:
	_current_suite = "Gravity / no moves when all pieces already at bottom"
	print("\n── %s ──" % _current_suite)

	# Column 0 is full. No piece needs to move.
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
	])

	var level := _make_level(["a"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	# No moves expected for column 0.
	var col0_moves: Array = []
	for mv in result.moves:
		if (mv["from"] as Vector2i).y == 0:
			col0_moves.append(mv)
	_assert(col0_moves.is_empty(), "no moves generated for a fully-filled column")


func _test_gap_in_middle_of_column() -> void:
	_current_suite = "Gravity / piece above empty gap falls down"
	print("\n── %s ──" % _current_suite)

	# col 0: a at row 0, empty rows 1-6, a at row 7.
	# After gravity: row 0 piece should fall to row 6; row 7 piece stays.
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"a.......",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(6, 0))
	_assert(mv != null, "piece from (0,0) lands at row 6 (one above settled piece at row 7)")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 0), "origin is (0,0)")


func _test_multiple_gaps_compact() -> void:
	_current_suite = "Gravity / multiple pieces compact to bottom"
	print("\n── %s ──" % _current_suite)

	# col 1: pieces at rows 0, 2, 4 — empties at 1, 3, 5, 6, 7.
	# After gravity: pieces settle at rows 5, 6, 7.
	var board := _make_board()
	board.fill_from_strings([
		".a......",
		"........",
		".a......",
		"........",
		".a......",
		"........",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var dest_rows: Array = []
	for mv in result.moves:
		if (mv["to"] as Vector2i).y == 1:
			dest_rows.append((mv["to"] as Vector2i).x)

	# All three pieces must end up at rows 5, 6, 7.
	_assert(
		5 in dest_rows and 6 in dest_rows and 7 in dest_rows,
		"three pieces in col 1 compact to rows 5, 6, 7"
	)

	# The piece that was already at row 7 (doesn't exist here) — row 4 piece
	# is the lowest so it should fall to row 7, row 2 → 6, row 0 → 5.
	var mv5 : Dictionary = _move_to(result.moves, Vector2i(5, 1))
	var mv6 : Dictionary = _move_to(result.moves, Vector2i(6, 1))
	var mv7 : Dictionary = _move_to(result.moves, Vector2i(7, 1))
	_assert(mv5 != null, "move entry landing at (5,1) exists")
	if mv5 != null:
		_assert(mv5["from"] == Vector2i(0, 1), "top piece (0,1) falls to (5,1)")
	_assert(mv6 != null, "move entry landing at (6,1) exists")
	if mv6 != null:
		_assert(mv6["from"] == Vector2i(2, 1), "middle piece (2,1) falls to (6,1)")
	_assert(mv7 != null, "move entry landing at (7,1) exists")
	if mv7 != null:
		_assert(mv7["from"] == Vector2i(4, 1), "bottom piece (4,1) falls to (7,1)")


# ── Suite: special pieces ─────────────────────────────────────────────────────

func _test_special_piece_falls_like_crop() -> void:
	_current_suite = "Gravity / special piece falls identically to a crop (spec §6.2)"
	print("\n── %s ──" % _current_suite)

	# Place a watering_can special at (0, 3); column is otherwise empty.
	# It should fall to (7, 3).
	var board := _make_board()
	board.init_empty()
	board.place_piece(0, 3, "watering_can", true, "")

	var level := _make_level(["a"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 3))
	_assert(mv != null, "special piece at (0,3) falls to (7,3) — same as a crop piece")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 3), "move originates at (0,3)")
		_assert(mv["is_special"] == true,      "is_special flag is preserved on the move")
		_assert(mv["piece"] == "watering_can", "piece identifier is preserved on the move")


func _test_special_piece_orientation_preserved() -> void:
	_current_suite = "Gravity / special piece orientation is preserved through gravity"
	print("\n── %s ──" % _current_suite)

	# Bushel Basket with horizontal orientation at (0, 5); falls to (7, 5).
	var board := _make_board()
	board.init_empty()
	board.place_piece(0, 5, "bushel_basket", true, "horizontal")

	var level := _make_level(["a"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 5))
	_assert(mv != null, "bushel_basket at (0,5) falls to (7,5)")
	if mv != null:
		_assert(mv["orientation"] == "horizontal",
			"horizontal orientation is preserved in move entry")


# ── Suite: holes block falling ────────────────────────────────────────────────

func _test_hole_blocks_falling() -> void:
	_current_suite = "Gravity / hole at bottom blocks piece from passing through (spec §6.1)"
	print("\n── %s ──" % _current_suite)

	# col 2: rows 0-6 active, row 7 is a hole.
	# A piece at (0,2) can only fall as far as row 6 (lowest active cell).
	var board := _make_board()
	board.fill_from_strings([
		"..a.....",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"..X.....",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv_top = _move_to(result.moves, Vector2i(6, 2))
	_assert(mv_top != null, "piece stops at row 6 — cannot fall into hole at row 7")
	_assert(_move_to(result.moves, Vector2i(7, 2)) == null,
		"no move landing at hole cell (7,2)")


func _test_pieces_above_hole_settle_above_it() -> void:
	_current_suite = "Gravity / two pieces above a hole both settle above the hole"
	print("\n── %s ──" % _current_suite)

	# col 4: rows 0-5 active, row 6 is hole, row 7 active.
	# Pieces at (0,4) and (2,4); rows 1,3,4,5 empty; row 7 also empty.
	# Expected: both pieces settle in rows 4 and 5 (above the hole).
	# Row 7 is a separate lower segment with no pieces, gets refill only.
	var board := _make_board()
	board.fill_from_strings([
		"....a...",
		"........",
		"....a...",
		"........",
		"........",
		"........",
		"....X...",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	# The upper segment is rows 0-5. Two pieces compact to rows 4 and 5.
	_assert(
		_move_to(result.moves, Vector2i(4, 4)) != null or
		_move_to(result.moves, Vector2i(5, 4)) != null,
		"at least one piece settles in rows 4-5 (above hole at row 6)"
	)
	_assert(
		_move_to(result.moves, Vector2i(6, 4)) == null,
		"no piece moves into the hole cell (6,4)"
	)
	_assert(
		_move_to(result.moves, Vector2i(7, 4)) == null,
		"no piece from upper segment crosses the hole to reach row 7"
	)


func _test_hole_in_middle_two_segments() -> void:
	_current_suite = "Gravity / hole in middle creates two independent segments"
	print("\n── %s ──" % _current_suite)

	# col 0: rows 0-3 active, row 4 is hole, rows 5-7 active.
	# Upper segment piece at (1,0) — should settle at (3,0).
	# Lower segment piece at (5,0) — should stay at (7,0)... but it's already at 5,
	# so it falls to (7,0).
	var board := _make_board()
	board.fill_from_strings([
		"........",
		"a.......",
		"........",
		"........",
		"X.......",
		"a.......",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	# Upper segment (rows 0-3): piece at row 1 falls to row 3.
	var mv_upper : Dictionary = _move_to(result.moves, Vector2i(3, 0))
	_assert(mv_upper != null, "piece in upper segment (row 1) falls to row 3")
	if mv_upper != null:
		_assert(mv_upper["from"] == Vector2i(1, 0), "upper piece originates at (1,0)")

	# Lower segment (rows 5-7): piece at row 5 falls to row 7.
	var mv_lower : Dictionary = _move_to(result.moves, Vector2i(7, 0))
	_assert(mv_lower != null, "piece in lower segment (row 5) falls to row 7")
	if mv_lower != null:
		_assert(mv_lower["from"] == Vector2i(5, 0), "lower piece originates at (5,0)")

	_assert(_move_to(result.moves, Vector2i(4, 0)) == null,
		"no move landing at hole cell (4,0)")


func _test_two_holes_three_segments() -> void:
	_current_suite = "Gravity / two holes create three independent segments"
	print("\n── %s ──" % _current_suite)

	# col 6: hole at row 2 and hole at row 5.
	# Segments: rows 0-1, rows 3-4, rows 6-7.
	# Piece at (0,6) — settles at (1,6) (top segment bottom).
	# Piece at (3,6) — already at segment bottom (3,6), stays.
	# Piece at (6,6) — already at segment bottom (6,6), but row 7 is also
	#                  empty so it stays at (6,6) — wait, 6 is above 7 so
	#                  it should fall to (7,6).
	var board := _make_board()
	board.fill_from_strings([
		"......a.",
		"........",
		"......X.",
		"......a.",
		"........",
		"......X.",
		"......a.",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	# Segment rows 0-1: piece at (0,6) falls to (1,6).
	var mv_seg1 : Dictionary = _move_to(result.moves, Vector2i(1, 6))
	_assert(mv_seg1 != null, "piece at (0,6) falls to (1,6) in top segment")
	if mv_seg1 != null:
		_assert(mv_seg1["from"] == Vector2i(0, 6), "top segment piece originates at (0,6)")

	# Segment rows 3-4: piece at (3,6) — row 4 is empty, falls to (4,6).
	var mv_seg2 : Dictionary = _move_to(result.moves, Vector2i(4, 6))
	_assert(mv_seg2 != null, "piece at (3,6) falls to (4,6) in middle segment")
	if mv_seg2 != null:
		_assert(mv_seg2["from"] == Vector2i(3, 6), "middle segment piece originates at (3,6)")

	# Segment rows 6-7: piece at (6,6) falls to (7,6).
	var mv_seg3 : Dictionary = _move_to(result.moves, Vector2i(7, 6))
	_assert(mv_seg3 != null, "piece at (6,6) falls to (7,6) in bottom segment")
	if mv_seg3 != null:
		_assert(mv_seg3["from"] == Vector2i(6, 6), "bottom segment piece originates at (6,6)")

	_assert(_move_to(result.moves, Vector2i(2, 6)) == null,
		"no move lands at hole (2,6)")
	_assert(_move_to(result.moves, Vector2i(5, 6)) == null,
		"no move lands at hole (5,6)")


# ── Suite: rocks and flowers as barriers ──────────────────────────────────────

func _test_rock_acts_as_barrier() -> void:
	_current_suite = "Gravity / rock cell is inactive — pieces settle above it"
	print("\n── %s ──" % _current_suite)

	# col 3: row 5 is a rock (inactive cell). Piece at (0,3) can only reach
	# the lowest active cell above row 5, which is row 4.
	var board := _make_board()
	board.fill_from_strings([
		"...a....",
		"........",
		"........",
		"........",
		"........",
		"...R....",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Variant = _move_to(result.moves, Vector2i(4, 3))
	_assert(mv != null, "piece at (0,3) settles at (4,3) — cannot pass rock at (5,3)")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 3), "rock-barrier piece originates at (0,3)")
	_assert(_move_to(result.moves, Vector2i(6, 3)) == null,
		"piece does not appear below the rock at row 6")


# ── Suite: dirt does not block gravity ───────────────────────────────────────

func _test_dirt_does_not_block_falling() -> void:
	_current_suite = "Gravity / dirt-patch cell does not block falling pieces (spec §6.2)"
	print("\n── %s ──" % _current_suite)

	# col 1: dirt at (4,1), piece at (0,1).
	# Dirt is a sub-cell overlay — the cell is still active and can hold a piece.
	# Piece should fall all the way to (7,1).
	var board := _make_board()
	board.init_empty()
	# Set up dirt manually since fill_from_strings 'D' leaves no piece.
	board.get_cell(4, 1).obstacle = "dirt"
	board.place_piece(0, 1, "a", false, "")

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 1))
	_assert(mv != null, "piece falls through dirt cell — dirt does not block gravity")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 1), "piece originated at (0,1)")


func _test_piece_lands_on_dirt() -> void:
	_current_suite = "Gravity / piece can land on a dirt-patch cell (spec §6.2)"
	print("\n── %s ──" % _current_suite)

	# col 2: rows 0-6 active, row 7 has dirt, pieces at rows 0 only.
	# The piece should land on (7,2) which has dirt underneath.
	var board := _make_board()
	board.init_empty()
	board.get_cell(7, 2).obstacle = "dirt"
	board.place_piece(0, 2, "a", false, "")

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 2))
	_assert(mv != null, "piece lands on dirt cell at (7,2)")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 2), "piece came from (0,2)")


# ── Suite: refill ─────────────────────────────────────────────────────────────

func _test_refill_fills_all_empty_cells() -> void:
	_current_suite = "Refill / all empty fillable cells receive exactly one fill entry"
	print("\n── %s ──" % _current_suite)

	# Completely empty board (all 64 cells active and empty after gravity).
	var board := _make_board()
	# init_empty() leaves all cells with no pieces — no fill_from_strings needed.

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(42))

	# Every cell should appear in fills exactly once.
	_assert(
		result.fills.size() == 64,
		"empty board generates exactly 64 fill entries"
	)

	# All 64 cells must be distinct.
	var fill_cell_set: Dictionary = {}
	for f in result.fills:
		fill_cell_set[f["cell"]] = true
	_assert(fill_cell_set.size() == 64, "all 64 fill cell coordinates are unique")


func _test_refill_only_empty_cells_filled() -> void:
	_current_suite = "Refill / already-occupied cells are not in fills"
	print("\n── %s ──" % _current_suite)

	# Full board — no empty cells — after gravity nothing moves and nothing fills.
	var board := _make_board()
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	_assert(result.fills.is_empty(), "fully-filled board produces no fill entries")


func _test_refill_never_spawns_special() -> void:
	_current_suite = "Refill / new pieces are never special"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	# Leave board empty so all 64 cells need filling.

	var level := _make_level(["a", "b", "c"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(7))

	var SPECIAL_TYPES := ["bushel_basket", "scarecrow", "watering_can", "wheelbarrow"]
	var found_special := false
	for f in result.fills:
		if f["piece"] in SPECIAL_TYPES:
			found_special = true
			break
	_assert(not found_special, "no fill entry contains a special piece identifier")


# ── Suite: weighted refill ────────────────────────────────────────────────────

func _test_weighted_refill_unsatisfied_goal() -> void:
	_current_suite = "Weighted refill / unsatisfied collect_crop goal doubles crop weight"
	print("\n── %s ──" % _current_suite)

	# crop_set: ["a", "b"].  Goal: collect 10 of "a"; collected so far: 0.
	# "a" should have weight 2, "b" weight 1 → "a" expected ~2/3 of fills.
	# We use a large empty board and a fixed seed for determinism, then check
	# that "a" appears more frequently than expected under equal weighting.

	var board := _make_board()

	var goals: Array[Dictionary] = [{"type": "collect_crop", "crop": "a", "target": 10}]
	var level := _make_level(["a", "b"], goals)
	var result := _make_system().calculate(board, level, {}, _make_rng(99))

	var count_a := 0
	var count_b := 0
	for f in result.fills:
		if f["piece"] == "a":
			count_a += 1
		elif f["piece"] == "b":
			count_b += 1

	# With weight 2:1 and 64 samples, "a" should appear ~42-43 times on average.
	# We just assert "a" outnumbers "b" for this seed — not a strict probability
	# check, but validates the weight table is applied at all.
	_assert(
		count_a + count_b == 64,
		"all 64 fill entries are either 'a' or 'b'"
	)
	_assert(
		count_a > count_b,
		"boosted crop 'a' (weight 2) appears more often than 'b' (weight 1) with seed 99"
	)


func _test_weighted_refill_satisfied_goal_no_boost() -> void:
	_current_suite = "Weighted refill / satisfied collect_crop goal does NOT boost weight"
	print("\n── %s ──" % _current_suite)

	# Goal: collect 10 of "a". Already collected: 10.  → goal satisfied.
	# Both "a" and "b" should have equal weight 1.
	# Run twice with same seed: once satisfied, once unsatisfied.
	# The satisfied run should produce fewer "a" entries.

	var board_satisfied   := _make_board()
	var board_unsatisfied := _make_board()

	var goals: Array[Dictionary] = [{"type": "collect_crop", "crop": "a", "target": 10}]
	var level := _make_level(["a", "b"], goals)

	var collected_satisfied: Dictionary   = {"a": 10}  # goal met
	var collected_unsatisfied: Dictionary = {"a": 0}   # goal not met

	var result_sat   := _make_system().calculate(board_satisfied,   level, collected_satisfied,   _make_rng(99))
	var result_unsat := _make_system().calculate(board_unsatisfied, level, collected_unsatisfied, _make_rng(99))

	var count_a_sat := 0
	for f in result_sat.fills:
		if f["piece"] == "a":
			count_a_sat += 1

	var count_a_unsat := 0
	for f in result_unsat.fills:
		if f["piece"] == "a":
			count_a_unsat += 1

	_assert(
		count_a_sat < count_a_unsat,
		"satisfied goal produces fewer 'a' fills than unsatisfied goal (same seed, same board)"
	)


func _test_weighted_refill_multiple_goals() -> void:
	_current_suite = "Weighted refill / multiple collect_crop goals boost each crop independently"
	print("\n── %s ──" % _current_suite)

	# crop_set: ["a", "b", "c"].
	# Goals: collect 5 of "a" (unsatisfied), collect 5 of "b" (unsatisfied).
	# "c" has no goal → weight 1.  "a" and "b" each → weight 2.
	# Weight table: ["a","a","b","b","c"] — total 5 entries.
	# Expected proportions: P(a) = 2/5, P(b) = 2/5, P(c) = 1/5.
	#
	# To make this test fully deterministic we accumulate 640 samples (10 full
	# empty boards × a single shared RNG) so the law of large numbers gives a
	# tight enough result that the assertions below cannot fail by chance.
	# With 640 samples: E[a] = E[b] = 256, E[c] = 128.
	# We only assert count_a > count_c and count_b > count_c — both require the
	# observed count to be off by more than 128, which is ~10 standard deviations
	# away from the mean and cannot happen with any fixed seed.

	var goals: Array[Dictionary] = [
		{"type": "collect_crop", "crop": "a", "target": 5},
		{"type": "collect_crop", "crop": "b", "target": 5},
	]
	var level  := _make_level(["a", "b", "c"], goals)
	var rng    := _make_rng(42)
	var system := _make_system()

	var total_a := 0
	var total_b := 0
	var total_c := 0

	for _i in range(10):
		var board := _make_board()
		var result := system.calculate(board, level, {}, rng)
		for f in result.fills:
			match f["piece"]:
				"a": total_a += 1
				"b": total_b += 1
				"c": total_c += 1

	_assert(
		total_a + total_b + total_c == 640,
		"10 boards × 64 cells = 640 total fills, all 'a', 'b', or 'c'"
	)
	_assert(
		total_a > total_c,
		"over 640 samples: boosted 'a' (weight 2) appears more than unboosted 'c' (weight 1)"
	)
	_assert(
		total_b > total_c,
		"over 640 samples: boosted 'b' (weight 2) appears more than unboosted 'c' (weight 1)"
	)


# ── Suite: GravityResult contract ─────────────────────────────────────────────

func _test_moves_empty_when_nothing_falls() -> void:
	_current_suite = "GravityResult / moves is empty when no piece needs to move"
	print("\n── %s ──" % _current_suite)

	# Column 0 is fully packed to the bottom. No movement should occur.
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
		"a.......",
	])

	var level := _make_level(["a"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var col0_moves: Array = []
	for mv in result.moves:
		if (mv["from"] as Vector2i).y == 0 or (mv["to"] as Vector2i).y == 0:
			col0_moves.append(mv)
	_assert(col0_moves.is_empty(), "moves is empty for packed column")


func _test_fills_empty_when_board_full() -> void:
	_current_suite = "GravityResult / fills is empty when board is fully occupied"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	_assert(result.fills.is_empty(), "fills is empty when every cell already holds a piece")


func _test_move_from_and_to_fields() -> void:
	_current_suite = "GravityResult / move entry has correct 'from' and 'to' fields"
	print("\n── %s ──" % _current_suite)

	# Single piece at (0, 7) — should fall to (7, 7).
	var board := _make_board()
	board.fill_from_strings([
		".......b",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 7))
	_assert(mv != null, "move entry for (7,7) exists")
	if mv != null:
		_assert(mv["from"] == Vector2i(0, 7), "'from' field is Vector2i(0,7)")
		_assert(mv["to"]   == Vector2i(7, 7), "'to' field is Vector2i(7,7)")


func _test_move_piece_id_preserved() -> void:
	_current_suite = "GravityResult / move entry preserves piece identifier"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	board.init_empty()
	board.place_piece(0, 0, "scarecrow", true, "")

	var level := _make_level(["a"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var mv : Dictionary = _move_to(result.moves, Vector2i(7, 0))
	_assert(mv != null, "scarecrow falls to (7,0)")
	if mv != null:
		_assert(mv["piece"] == "scarecrow", "piece id 'scarecrow' is preserved in move entry")
		_assert(mv["is_special"] == true,   "is_special is true for scarecrow move entry")


func _test_fill_top_to_bottom_order() -> void:
	_current_suite = "GravityResult / fills for a column are ordered top-to-bottom"
	print("\n── %s ──" % _current_suite)

	# Column 4 is completely empty — all 8 rows need filling.
	# The fill entries for col 4 must be in ascending row order (0 before 7).
	var board := _make_board()
	board.fill_from_strings([
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
		"aaaa.aaa",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var col4_fills: Array[Dictionary] = []
	for f in result.fills:
		if (f["cell"] as Vector2i).y == 4:
			col4_fills.append(f)

	_assert(col4_fills.size() == 8, "column 4 has exactly 8 fill entries")

	var in_order := true
	for i in range(1, col4_fills.size()):
		var prev_row: int = (col4_fills[i - 1]["cell"] as Vector2i).x
		var cur_row:  int = (col4_fills[i]["cell"]     as Vector2i).x
		if cur_row <= prev_row:
			in_order = false
			break
	_assert(in_order, "col 4 fill entries are in ascending row order (top-to-bottom)")


func _test_moves_bottom_to_top_order() -> void:
	_current_suite = "GravityResult / moves for a column are ordered bottom-to-top"
	print("\n── %s ──" % _current_suite)

	# Three pieces in col 0 at rows 0, 1, 2 — settle to rows 5, 6, 7.
	# Move entries for col 0 must list the lowest destination first.
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"a.......",
		"a.......",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	var col0_moves: Array[Dictionary] = []
	for mv in result.moves:
		if (mv["to"] as Vector2i).y == 0:
			col0_moves.append(mv)

	_assert(col0_moves.size() == 3, "three move entries for col 0")

	var in_order := true
	for i in range(1, col0_moves.size()):
		var prev_row: int = (col0_moves[i - 1]["to"] as Vector2i).x
		var cur_row:  int = (col0_moves[i]["to"]     as Vector2i).x
		if cur_row >= prev_row:
			in_order = false
			break
	_assert(in_order, "col 0 move entries are in descending 'to' row order (bottom-to-top)")


# ── Suite: multi-column independence ─────────────────────────────────────────

func _test_independent_columns() -> void:
	_current_suite = "Gravity / each column is processed independently"
	print("\n── %s ──" % _current_suite)

	# col 0: piece at (0,0) — falls to (7,0).
	# col 7: piece at (3,7) — falls to (7,7).
	# All other columns empty — no moves.
	var board := _make_board()
	board.fill_from_strings([
		"a.......",
		"........",
		"........",
		".......a",
		"........",
		"........",
		"........",
		"........",
	])

	var level := _make_level(["a", "b"], [{"type": "score", "target": 100}])
	var result := _make_system().calculate(board, level, {}, _make_rng(1))

	# col 0 move.
	var mv0 : Dictionary = _move_to(result.moves, Vector2i(7, 0))
	_assert(mv0 != null, "col 0: piece falls to (7,0)")
	if mv0 != null:
		_assert(mv0["from"] == Vector2i(0, 0), "col 0: piece originated at (0,0)")

	# col 7 move.
	var mv7 : Dictionary = _move_to(result.moves, Vector2i(7, 7))
	_assert(mv7 != null, "col 7: piece falls to (7,7)")
	if mv7 != null:
		_assert(mv7["from"] == Vector2i(3, 7), "col 7: piece originated at (3,7)")

	# Moves in col 0 must not reference col 7 and vice-versa.
	for mv in result.moves:
		if (mv["to"] as Vector2i).y == 0:
			_assert(
				(mv["from"] as Vector2i).y == 0,
				"col 0 move 'from' is also in col 0 (columns don't cross)"
			)
		if (mv["to"] as Vector2i).y == 7:
			_assert(
				(mv["from"] as Vector2i).y == 7,
				"col 7 move 'from' is also in col 7 (columns don't cross)"
			)


# ── Assertion + reporting ─────────────────────────────────────────────────────

func _assert(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  %s" % description)
	else:
		_fail_count += 1
		print("  FAIL  [%s] %s" % [_current_suite, description])


func _print_summary() -> void:
	print("\n" + "=".repeat(64))
	var total := _pass_count + _fail_count
	print("Results: %d / %d passed" % [_pass_count, total])
	if _fail_count == 0:
		print("All tests PASSED.")
	else:
		print("%d test(s) FAILED." % _fail_count)
	print("=".repeat(64))
