extends Node

## TestSpecialPieceHandler.gd
## Attach to a Node in a test scene and press F6 to run.
## Covers every spec-mandated behavioral scenario for SpecialPieceHandler:
##   - Bushel Basket: row clear (horizontal) vs column clear (vertical)
##   - Scarecrow: clears all matching crop type from swap-partner
##   - Watering Can: 3×3 centred, clamped at edges and corners
##   - Wheelbarrow: full cross (row + column, intersection counted once)

# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestSpecialPieceHandler — special piece activation tests")
	print("=".repeat(64))

	_test_bushel_basket_horizontal()
	_test_bushel_basket_vertical()
	_test_bushel_basket_holes_excluded()
	_test_scarecrow_clears_partner_crop()
	_test_scarecrow_clears_only_matching_crop()
	_test_scarecrow_consumes_itself()
	_test_scarecrow_no_double_count_own_cell()
	_test_watering_can_centre()
	_test_watering_can_top_left_corner()
	_test_watering_can_top_right_corner()
	_test_watering_can_bottom_left_corner()
	_test_watering_can_bottom_right_corner()
	_test_watering_can_top_edge()
	_test_watering_can_left_edge()
	_test_watering_can_holes_excluded()
	_test_wheelbarrow_full_cross()
	_test_wheelbarrow_intersection_not_duplicated()
	_test_wheelbarrow_holes_excluded()
	_test_seeds_bushel()
	_test_seeds_scarecrow()
	_test_seeds_watering_can()
	_test_seeds_wheelbarrow()
	_test_clear_result_type_field()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_board() -> BoardState:
	var b := BoardState.new()
	b.init_empty()
	return b


func _make_handler() -> SpecialPieceHandler:
	return SpecialPieceHandler.new()


func _make_balance() -> Balance:
	return load("res://resources/balance.tres") as Balance


## Returns true when `coords` contains exactly the same Vector2i values as
## `expected`, regardless of order.
func _cells_match(coords: Array, expected: Array) -> bool:
	if coords.size() != expected.size():
		return false
	for v in expected:
		if v not in coords:
			return false
	return true


## Returns true when every Vector2i in `expected` appears in `coords`.
func _cells_contain_all(coords: Array, expected: Array) -> bool:
	for v in expected:
		if v not in coords:
			return false
	return true


## Returns true when none of the Vector2i in `excluded` appear in `coords`.
func _cells_contain_none(coords: Array, excluded: Array) -> bool:
	for v in excluded:
		if v in coords:
			return false
	return true


# ── Suite: Bushel Basket — horizontal ─────────────────────────────────────────

func _test_bushel_basket_horizontal() -> void:
	_current_suite = "Bushel Basket / horizontal → clears row"
	print("\n── %s ──" % _current_suite)

	# Spec §5.2 behavioral scenario:
	# "Given a Bushel Basket was created from a horizontal 4-in-a-line match
	#  and sits at (4,4), when the player activates it, then all pieces in
	#  row 4 are cleared. The column is not affected."

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Fill the entire board with crop 'a' so we can verify column integrity.
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

	# Place the Bushel Basket at (4,4) with horizontal orientation.
	board.place_piece(4, 4, "bushel_basket", true, "horizontal")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 3), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# All 8 cells in row 4 must be cleared.
	var expected_row: Array[Vector2i] = []
	for col in range(8):
		expected_row.append(Vector2i(4, col))
	_assert(
		_cells_match(result.cells, expected_row),
		"horizontal Bushel Basket at (4,4) clears exactly all 8 cells in row 4"
	)

	# No cell from another row should appear.
	_assert(
		_cells_contain_none(result.cells, [Vector2i(3, 4), Vector2i(5, 4)]),
		"horizontal Bushel Basket does NOT clear cells in the column (rows 3 and 5)"
	)


# ── Suite: Bushel Basket — vertical ───────────────────────────────────────────

func _test_bushel_basket_vertical() -> void:
	_current_suite = "Bushel Basket / vertical → clears column"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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

	# Place the Bushel Basket at (4,4) with vertical orientation.
	board.place_piece(4, 4, "bushel_basket", true, "vertical")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(3, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# All 8 cells in column 4 must be cleared.
	var expected_col: Array[Vector2i] = []
	for row in range(8):
		expected_col.append(Vector2i(row, 4))
	_assert(
		_cells_match(result.cells, expected_col),
		"vertical Bushel Basket at (4,4) clears exactly all 8 cells in column 4"
	)

	# No cell from the same row (but different column) should appear.
	_assert(
		_cells_contain_none(result.cells, [Vector2i(4, 3), Vector2i(4, 5)]),
		"vertical Bushel Basket does NOT clear cells in the row (cols 3 and 5)"
	)


# ── Suite: Bushel Basket — holes excluded ─────────────────────────────────────

func _test_bushel_basket_holes_excluded() -> void:
	_current_suite = "Bushel Basket / holes excluded from cleared set"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Row 2 has holes at columns 0 and 7.
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"XaaaaaaX",  # holes at col 0 and col 7, active cells at cols 1-6
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])

	board.place_piece(2, 3, "bushel_basket", true, "horizontal")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(2, 3), Vector2i(2, 2), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Holes at (2,0) and (2,7) must not appear.
	_assert(
		not (Vector2i(2, 0) in result.cells),
		"hole at (2,0) is excluded from horizontal Bushel Basket clear"
	)
	_assert(
		not (Vector2i(2, 7) in result.cells),
		"hole at (2,7) is excluded from horizontal Bushel Basket clear"
	)

	# Active cells in the row must be present (cols 1–6 = 6 cells).
	_assert(
		result.cells.size() == 6,
		"horizontal Bushel Basket clears exactly 6 active cells when row has 2 holes"
	)


# ── Suite: Scarecrow — clears partner crop type ───────────────────────────────

func _test_scarecrow_clears_partner_crop() -> void:
	_current_suite = "Scarecrow / clears all cells matching swap-partner crop"
	print("\n── %s ──" % _current_suite)

	# Spec §5.2 behavioral scenario:
	# "Given a Scarecrow at (4,4) and 7 Strawberry pieces scattered across
	#  the board, when the player swaps the Scarecrow with an adjacent
	#  Strawberry, then all 7 Strawberry pieces on the board are removed
	#  simultaneously."
	#
	# We model the pre-swap state: partner cell still holds the crop.

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# 'S' = scarecrow placeholder; we'll override with place_piece.
	# 's' = strawberry (single char shorthand).
	# '.' = empty.
	board.fill_from_strings([
		"s.......",
		"..s.....",
		"....s...",
		"......s.",
		"....S...",   # Scarecrow at (4,4); 's' at (4,5) is partner
		".....s..",
		"...s....",
		"s.......",
	])

	# The fill_from_strings places 'S' as a crop piece "S".
	# We override (4,4) with the actual Scarecrow special piece.
	board.place_piece(4, 4, "scarecrow", true, "")
	# Partner is the 's' at (4,5) — place an 's' crop there.
	board.place_piece(4, 5, "s", false, "")

	# Manually count 's' cells for verification (excluding (4,4) which is scarecrow).
	var strawberry_positions: Array[Vector2i] = []
	for row in range(8):
		for col in range(8):
			var cs: BoardState.CellState = board.get_cell(row, col)
			if cs.active and cs.piece == "s" and not cs.is_special:
				strawberry_positions.append(Vector2i(row, col))

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# All strawberry positions must be in the result.
	_assert(
		_cells_contain_all(result.cells, strawberry_positions),
		"Scarecrow result includes all %d strawberry cells" % strawberry_positions.size()
	)

	# The Scarecrow cell itself must be in the result.
	_assert(
		Vector2i(4, 4) in result.cells,
		"Scarecrow cell (4,4) is included in the cleared set"
	)

	# Total = scarecrow + all strawberries.
	_assert(
		result.cells.size() == strawberry_positions.size() + 1,
		"cleared cell count equals strawberry count + 1 (scarecrow itself)"
	)


# ── Suite: Scarecrow — only matching crop cleared ─────────────────────────────

func _test_scarecrow_clears_only_matching_crop() -> void:
	_current_suite = "Scarecrow / does NOT clear non-matching crop types"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Place Scarecrow at (3,3). Partner (swap target) is crop 'a' at (3,4).
	# Fill board with 'a' and 'b' crops — only 'a' should be cleared.
	board.fill_from_strings([
		"abababab",
		"babababa",
		"abababab",
		"bab.baba",   # (3,3) will be overridden with scarecrow, (3,4) = 'a'
		"abababab",
		"babababa",
		"abababab",
		"babababa",
	])
	board.place_piece(3, 3, "scarecrow", true, "")
	board.place_piece(3, 4, "a", false, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(3, 3), Vector2i(3, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# No 'b' crop cells should be in the result.
	var b_in_result := false
	for coord in result.cells:
		if coord == Vector2i(3, 3):
			continue  # scarecrow cell
		var cs: BoardState.CellState = board.get_cell(coord.x, coord.y)
		if cs.piece == "b":
			b_in_result = true
			break
	_assert(not b_in_result, "Scarecrow does not clear crop 'b' cells when partner is crop 'a'")

	# All 'a' crop cells should be in the result.
	var a_positions: Array[Vector2i] = []
	for row in range(8):
		for col in range(8):
			var cs: BoardState.CellState = board.get_cell(row, col)
			if cs.active and cs.piece == "a" and not cs.is_special:
				a_positions.append(Vector2i(row, col))
	_assert(
		_cells_contain_all(result.cells, a_positions),
		"all crop 'a' cells are included in Scarecrow clear result"
	)


# ── Suite: Scarecrow — always consumes itself ─────────────────────────────────

func _test_scarecrow_consumes_itself() -> void:
	_current_suite = "Scarecrow / own cell always included in result"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Board with NO pieces of the partner crop type (partner is 'z', absent).
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaSaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])
	board.place_piece(3, 3, "scarecrow", true, "")
	# Partner is 'z' — place it manually; no other 'z' on board.
	board.place_piece(3, 4, "z", false, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(3, 3), Vector2i(3, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		Vector2i(3, 3) in result.cells,
		"Scarecrow cell is always in result even when no matching crop exists beyond partner"
	)


# ── Suite: Scarecrow — own cell not double-counted ────────────────────────────

func _test_scarecrow_no_double_count_own_cell() -> void:
	_current_suite = "Scarecrow / own cell is not double-counted"
	print("\n── %s ──" % _current_suite)

	# Edge case: if the Scarecrow's own cell somehow held the same identifier
	# as the target crop (shouldn't happen in normal play since it's a special
	# piece, but the handler must skip pos when sweeping).

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(4, 4, "scarecrow", true, "")
	board.place_piece(4, 5, "a", false, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Count occurrences of (4,4) in result.cells — must be exactly 1.
	var own_cell_count := 0
	for coord in result.cells:
		if coord == Vector2i(4, 4):
			own_cell_count += 1
	_assert(
		own_cell_count == 1,
		"Scarecrow own cell (4,4) appears exactly once in result.cells (not duplicated)"
	)


# ── Suite: Watering Can — centre of board ─────────────────────────────────────

func _test_watering_can_centre() -> void:
	_current_suite = "Watering Can / 3×3 at centre of board"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(3, 3, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(3, 3), Vector2i(3, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# 3×3 centred at (3,3) → rows 2–4, cols 2–4 → exactly 9 cells.
	var expected: Array[Vector2i] = []
	for row in range(2, 5):
		for col in range(2, 5):
			expected.append(Vector2i(row, col))

	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (3,3) clears exactly the 9-cell 3×3 area (rows 2-4, cols 2-4)"
	)


# ── Suite: Watering Can — top-left corner (0,0) ───────────────────────────────

func _test_watering_can_top_left_corner() -> void:
	_current_suite = "Watering Can / clamped at top-left corner (0,0)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(0, 0, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(0, 0), Vector2i(0, 1), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 0–1, cols 0–1 → 4 cells.
	var expected: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1),
		Vector2i(1, 0), Vector2i(1, 1),
	]
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (0,0) clears exactly 4 cells clamped to top-left corner"
	)


# ── Suite: Watering Can — top-right corner (0,7) ─────────────────────────────

func _test_watering_can_top_right_corner() -> void:
	_current_suite = "Watering Can / clamped at top-right corner (0,7)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(0, 7, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(0, 7), Vector2i(1, 7), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 0–1, cols 6–7 → 4 cells.
	var expected: Array[Vector2i] = [
		Vector2i(0, 6), Vector2i(0, 7),
		Vector2i(1, 6), Vector2i(1, 7),
	]
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (0,7) clears exactly 4 cells clamped to top-right corner"
	)


# ── Suite: Watering Can — bottom-left corner (7,0) ───────────────────────────

func _test_watering_can_bottom_left_corner() -> void:
	_current_suite = "Watering Can / clamped at bottom-left corner (7,0)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(7, 0, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(7, 0), Vector2i(6, 0), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 6–7, cols 0–1 → 4 cells.
	var expected: Array[Vector2i] = [
		Vector2i(6, 0), Vector2i(6, 1),
		Vector2i(7, 0), Vector2i(7, 1),
	]
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (7,0) clears exactly 4 cells clamped to bottom-left corner"
	)


# ── Suite: Watering Can — bottom-right corner (7,7) ──────────────────────────

func _test_watering_can_bottom_right_corner() -> void:
	_current_suite = "Watering Can / clamped at bottom-right corner (7,7)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(7, 7, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(7, 7), Vector2i(6, 7), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 6–7, cols 6–7 → 4 cells.
	var expected: Array[Vector2i] = [
		Vector2i(6, 6), Vector2i(6, 7),
		Vector2i(7, 6), Vector2i(7, 7),
	]
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (7,7) clears exactly 4 cells clamped to bottom-right corner"
	)


# ── Suite: Watering Can — top edge (non-corner) ───────────────────────────────

func _test_watering_can_top_edge() -> void:
	_current_suite = "Watering Can / clamped at top edge (0,4)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(0, 4, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(0, 4), Vector2i(0, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 0–1, cols 3–5 → 6 cells.
	var expected: Array[Vector2i] = []
	for row in range(0, 2):
		for col in range(3, 6):
			expected.append(Vector2i(row, col))
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (0,4) clears exactly 6 cells clamped to top edge"
	)


# ── Suite: Watering Can — left edge (non-corner) ──────────────────────────────

func _test_watering_can_left_edge() -> void:
	_current_suite = "Watering Can / clamped at left edge (4,0)"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(4, 0, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 0), Vector2i(4, 1), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Clamped: rows 3–5, cols 0–1 → 6 cells.
	var expected: Array[Vector2i] = []
	for row in range(3, 6):
		for col in range(0, 2):
			expected.append(Vector2i(row, col))
	_assert(
		_cells_match(result.cells, expected),
		"Watering Can at (4,0) clears exactly 6 cells clamped to left edge"
	)


# ── Suite: Watering Can — holes excluded from 3×3 ────────────────────────────

func _test_watering_can_holes_excluded() -> void:
	_current_suite = "Watering Can / holes excluded from 3×3 area"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Place holes at (2,2) and (4,4) — both within the 3×3 around (3,3).
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"aaXaaaaa",   # hole at (2,2)
		"aaaaaaaa",
		"aaaaXaaa",   # hole at (4,4)
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])
	board.place_piece(3, 3, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(3, 3), Vector2i(3, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		not (Vector2i(2, 2) in result.cells),
		"hole at (2,2) is excluded from Watering Can 3×3 area"
	)
	_assert(
		not (Vector2i(4, 4) in result.cells),
		"hole at (4,4) is excluded from Watering Can 3×3 area"
	)
	_assert(
		result.cells.size() == 7,
		"Watering Can at (3,3) clears 7 active cells when 2 holes exist in the 3×3"
	)


# ── Suite: Wheelbarrow — full cross ───────────────────────────────────────────

func _test_wheelbarrow_full_cross() -> void:
	_current_suite = "Wheelbarrow / full cross clears entire row AND column"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(4, 3, "wheelbarrow", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 3), Vector2i(4, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Row 4 (all 8 cols) + col 3 (all 8 rows) = 8 + 8 - 1 (intersection) = 15.
	var expected: Array[Vector2i] = []
	for col in range(8):
		expected.append(Vector2i(4, col))
	for row in range(8):
		if row != 4:  # avoid duplicating intersection
			expected.append(Vector2i(row, 3))

	_assert(
		result.cells.size() == 15,
		"Wheelbarrow at (4,3) on full board produces exactly 15 cleared cells"
	)
	_assert(
		_cells_match(result.cells, expected),
		"Wheelbarrow at (4,3) clears exactly row 4 + column 3 (full cross)"
	)


# ── Suite: Wheelbarrow — intersection not duplicated ─────────────────────────

func _test_wheelbarrow_intersection_not_duplicated() -> void:
	_current_suite = "Wheelbarrow / intersection cell appears exactly once"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

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
	board.place_piece(2, 5, "wheelbarrow", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(2, 5), Vector2i(2, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")

	# Count occurrences of the intersection cell (2,5) in result.cells.
	var intersection_count := 0
	for coord in result.cells:
		if coord == Vector2i(2, 5):
			intersection_count += 1
	_assert(
		intersection_count == 1,
		"Wheelbarrow intersection cell (2,5) appears exactly once in result.cells"
	)

	# Total should be 8 + 8 - 1 = 15 for a full board.
	_assert(
		result.cells.size() == 15,
		"Wheelbarrow at (2,5) on full board produces 15 unique cells"
	)


# ── Suite: Wheelbarrow — holes excluded ───────────────────────────────────────

func _test_wheelbarrow_holes_excluded() -> void:
	_current_suite = "Wheelbarrow / holes excluded from cross"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	# Hole at (4,0) (in the row) and (2,3) (in the column).
	board.fill_from_strings([
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaXaaaa",   # hole at (2,3)
		"aaaaaaaa",
		"Xaaaaaaa",   # hole at (4,0)
		"aaaaaaaa",
		"aaaaaaaa",
		"aaaaaaaa",
	])
	board.place_piece(4, 3, "wheelbarrow", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 3), Vector2i(4, 4), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		not (Vector2i(4, 0) in result.cells),
		"hole at (4,0) is excluded from Wheelbarrow row sweep"
	)
	_assert(
		not (Vector2i(2, 3) in result.cells),
		"hole at (2,3) is excluded from Wheelbarrow column sweep"
	)
	# 15 full cross - 2 holes = 13.
	_assert(
		result.cells.size() == 13,
		"Wheelbarrow cross with 2 holes produces 13 active cells"
	)


# ── Suite: seed rewards ───────────────────────────────────────────────────────

func _test_seeds_bushel() -> void:
	_current_suite = "Seeds / Bushel Basket returns SEED_REWARD_SPECIAL_BUSHEL"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	board.fill_from_strings([
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
	])
	board.place_piece(4, 4, "bushel_basket", true, "horizontal")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 3), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		result.seeds_earned == balance.SEED_REWARD_SPECIAL_BUSHEL,
		"Bushel Basket seeds_earned equals balance.SEED_REWARD_SPECIAL_BUSHEL (%d)" \
			% balance.SEED_REWARD_SPECIAL_BUSHEL
	)


func _test_seeds_scarecrow() -> void:
	_current_suite = "Seeds / Scarecrow returns SEED_REWARD_SPECIAL_SCARECROW"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	board.fill_from_strings([
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
	])
	board.place_piece(4, 4, "scarecrow", true, "")
	board.place_piece(4, 5, "a", false, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		result.seeds_earned == balance.SEED_REWARD_SPECIAL_SCARECROW,
		"Scarecrow seeds_earned equals balance.SEED_REWARD_SPECIAL_SCARECROW (%d)" \
			% balance.SEED_REWARD_SPECIAL_SCARECROW
	)


func _test_seeds_watering_can() -> void:
	_current_suite = "Seeds / Watering Can returns SEED_REWARD_SPECIAL_WATERING_CAN"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	board.fill_from_strings([
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
	])
	board.place_piece(4, 4, "watering_can", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		result.seeds_earned == balance.SEED_REWARD_SPECIAL_WATERING_CAN,
		"Watering Can seeds_earned equals balance.SEED_REWARD_SPECIAL_WATERING_CAN (%d)" \
			% balance.SEED_REWARD_SPECIAL_WATERING_CAN
	)


func _test_seeds_wheelbarrow() -> void:
	_current_suite = "Seeds / Wheelbarrow returns SEED_REWARD_SPECIAL_WHEELBARROW"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	board.fill_from_strings([
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
	])
	board.place_piece(4, 4, "wheelbarrow", true, "")

	var result: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 4), Vector2i(4, 5), balance
	)

	_assert(result != null, "resolve() returns a non-null ClearResult")
	_assert(
		result.seeds_earned == balance.SEED_REWARD_SPECIAL_WHEELBARROW,
		"Wheelbarrow seeds_earned equals balance.SEED_REWARD_SPECIAL_WHEELBARROW (%d)" \
			% balance.SEED_REWARD_SPECIAL_WHEELBARROW
	)


# ── Suite: ClearResult.special_type field ────────────────────────────────────

func _test_clear_result_type_field() -> void:
	_current_suite = "ClearResult.special_type / correct type string for each piece"
	print("\n── %s ──" % _current_suite)

	var board := _make_board()
	var handler := _make_handler()
	var balance := _make_balance()

	board.fill_from_strings([
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
		"aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa",
	])

	# Bushel Basket
	board.place_piece(0, 0, "bushel_basket", true, "horizontal")
	var r1: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(0, 0), Vector2i(0, 1), balance
	)
	_assert(r1.special_type == "bushel_basket", "ClearResult.special_type is 'bushel_basket'")

	# Scarecrow
	board.place_piece(2, 0, "scarecrow", true, "")
	board.place_piece(2, 1, "a", false, "")
	var r2: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(2, 0), Vector2i(2, 1), balance
	)
	_assert(r2.special_type == "scarecrow", "ClearResult.special_type is 'scarecrow'")

	# Watering Can
	board.place_piece(4, 0, "watering_can", true, "")
	var r3: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(4, 0), Vector2i(4, 1), balance
	)
	_assert(r3.special_type == "watering_can", "ClearResult.special_type is 'watering_can'")

	# Wheelbarrow
	board.place_piece(6, 0, "wheelbarrow", true, "")
	var r4: SpecialPieceHandler.ClearResult = handler.resolve(
		board, Vector2i(6, 0), Vector2i(6, 1), balance
	)
	_assert(r4.special_type == "wheelbarrow", "ClearResult.special_type is 'wheelbarrow'")


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
