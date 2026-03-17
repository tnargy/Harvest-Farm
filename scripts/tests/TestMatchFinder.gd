extends Node

## TestMatchFinder.gd
## Attach to a Node in scenes/tests/TestMatchFinder.tscn and press F6 to run.
## Covers every spec-mandated match shape, orientation storage, the no-double-
## counting rule between L/T and straights, invalid-swap rejection, and the
## two-specials-cannot-be-combined rule.

# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestMatchFinder — MatchFinder shape detection tests")
	print("=".repeat(64))

	_test_straight_3()
	_test_straight_4()
	_test_straight_5()
	_test_l_shape()
	_test_t_shape()
	_test_orientation()
	_test_no_double_counting()
	_test_would_swap_create_match()
	_test_invalid_swap_two_specials()
	_test_swap_guards()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_board() -> BoardState:
	var b := BoardState.new()
	b.init_empty()
	return b


func _make_finder() -> MatchFinder:
	return MatchFinder.new()


## Returns the first MatchResult with the given shape, or null.
func _first(results: Array, shape: String) -> Object:
	for r in results:
		if r.shape == shape:
			return r
	return null


## Returns true when `coords` contains exactly the same Vector2i values as
## `expected`, regardless of order.
func _cells_match(coords: Array, expected: Array) -> bool:
	if coords.size() != expected.size():
		return false
	for v in expected:
		if v not in coords:
			return false
	return true


# ── Suite: straight-3 ─────────────────────────────────────────────────────────

func _test_straight_3() -> void:
	_current_suite = "straight-3 match"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Horizontal: a a a at row 4, cols 2-4
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"..aaa...",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"horizontal straight-3: exactly 1 match found")

	var mr := _first(results, "match_3")
	_assert(mr != null,
		"horizontal straight-3: shape == 'match_3'")
	_assert(mr != null and mr.orientation == "horizontal",
		"horizontal straight-3: orientation == 'horizontal'")
	_assert(mr != null and not mr.spawns_special,
		"horizontal straight-3: spawns_special == false")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4)]),
		"horizontal straight-3: correct cells")

	# Vertical: b b b at col 5, rows 1-3
	board.fill_from_strings([
		"........",
		".....b..",
		".....b..",
		".....b..",
		"........",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	_assert(results.size() == 1,
		"vertical straight-3: exactly 1 match found")

	mr = _first(results, "match_3")
	_assert(mr != null,
		"vertical straight-3: shape == 'match_3'")
	_assert(mr != null and mr.orientation == "vertical",
		"vertical straight-3: orientation == 'vertical'")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]),
		"vertical straight-3: correct cells")

	# No match: only 2 in a row
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"..aa....",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	_assert(results.is_empty(),
		"two-in-a-row: no match found (minimum is 3)")


# ── Suite: straight-4 ─────────────────────────────────────────────────────────

func _test_straight_4() -> void:
	_current_suite = "straight-4 match (Bushel Basket)"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Horizontal 4-in-a-line
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"..aaaa..",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"horizontal straight-4: exactly 1 match found")

	var mr := _first(results, "match_4")
	_assert(mr != null,
		"horizontal straight-4: shape == 'match_4'")
	_assert(mr != null and mr.spawns_special,
		"horizontal straight-4: spawns_special == true")
	_assert(mr != null and mr.special_type == "bushel_basket",
		"horizontal straight-4: special_type == 'bushel_basket'")
	_assert(mr != null and mr.orientation == "horizontal",
		"horizontal straight-4: orientation == 'horizontal'")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5)]),
		"horizontal straight-4: correct cells")

	# Vertical 4-in-a-line
	board.fill_from_strings([
		"........",
		"...a....",
		"...a....",
		"...a....",
		"...a....",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	mr = _first(results, "match_4")
	_assert(mr != null,
		"vertical straight-4: shape == 'match_4'")
	_assert(mr != null and mr.orientation == "vertical",
		"vertical straight-4: orientation == 'vertical'")
	_assert(mr != null and mr.special_type == "bushel_basket",
		"vertical straight-4: special_type == 'bushel_basket'")


# ── Suite: straight-5 ─────────────────────────────────────────────────────────

func _test_straight_5() -> void:
	_current_suite = "straight-5 match (Scarecrow)"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Horizontal 5-in-a-line
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		".aaaaa..",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"horizontal straight-5: exactly 1 match found")

	var mr := _first(results, "match_5")
	_assert(mr != null,
		"horizontal straight-5: shape == 'match_5'")
	_assert(mr != null and mr.spawns_special,
		"horizontal straight-5: spawns_special == true")
	_assert(mr != null and mr.special_type == "scarecrow",
		"horizontal straight-5: special_type == 'scarecrow'")
	_assert(mr != null and mr.orientation == "horizontal",
		"horizontal straight-5: orientation == 'horizontal'")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3),
			Vector2i(4, 4), Vector2i(4, 5)]),
		"horizontal straight-5: correct cells")

	# Vertical 5-in-a-line
	board.fill_from_strings([
		"........",
		"....a...",
		"....a...",
		"....a...",
		"....a...",
		"....a...",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	mr = _first(results, "match_5")
	_assert(mr != null,
		"vertical straight-5: shape == 'match_5'")
	_assert(mr != null and mr.special_type == "scarecrow",
		"vertical straight-5: special_type == 'scarecrow'")
	_assert(mr != null and mr.orientation == "vertical",
		"vertical straight-5: orientation == 'vertical'")


# ── Suite: L-shape ────────────────────────────────────────────────────────────

func _test_l_shape() -> void:
	_current_suite = "L-shape match (Watering Can)"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Rotation A — vertical spine up, right arm:
	#   (2,3) (1,3) (0,3)   ← vertical spine
	#   (2,4) (2,5)         ← horizontal arm right
	#
	#   col:  0 1 2 3 4 5 6 7
	# row 0:  . . . a . . . .
	# row 1:  . . . a . . . .
	# row 2:  . . . a a a . .
	board.fill_from_strings([
		"...a....",
		"...a....",
		"...aaa..",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"L-shape rotation A: exactly 1 match found")

	var mr := _first(results, "match_l")
	_assert(mr != null,
		"L-shape rotation A: shape == 'match_l'")
	_assert(mr != null and mr.spawns_special,
		"L-shape rotation A: spawns_special == true")
	_assert(mr != null and mr.special_type == "watering_can",
		"L-shape rotation A: special_type == 'watering_can'")
	_assert(mr != null and mr.cells.size() == 5,
		"L-shape rotation A: 5 cells")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3),
			Vector2i(2, 4), Vector2i(2, 5)]),
		"L-shape rotation A: correct cells")

	# Rotation C — vertical spine down, right arm:
	#   (0,2) (1,2) (2,2)   ← vertical spine
	#   (0,3) (0,4)         ← horizontal arm right
	#
	#   col:  0 1 2 3 4 5 6 7
	# row 0:  . . a a a . . .
	# row 1:  . . a . . . . .
	# row 2:  . . a . . . . .
	board.fill_from_strings([
		"..aaa...",
		"..a.....",
		"..a.....",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	mr = _first(results, "match_l")
	_assert(mr != null,
		"L-shape rotation C: shape == 'match_l'")
	_assert(mr != null and mr.cells.size() == 5,
		"L-shape rotation C: 5 cells")


# ── Suite: T-shape ────────────────────────────────────────────────────────────

func _test_t_shape() -> void:
	_current_suite = "T-shape match (Wheelbarrow)"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Horizontal spine T:
	#   spine:  (3,1) (3,2) (3,3)
	#   arm up: (2,2)
	#   arm dn: (4,2)
	#
	#   col:  0 1 2 3 4 5 6 7
	# row 2:  . . a . . . . .
	# row 3:  . a a a . . . .
	# row 4:  . . a . . . . .
	board.fill_from_strings([
		"........",
		"........",
		"..a.....",
		".aaa....",
		"..a.....",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"T-shape horizontal spine: exactly 1 match found")

	var mr := _first(results, "match_t")
	_assert(mr != null,
		"T-shape horizontal spine: shape == 'match_t'")
	_assert(mr != null and mr.spawns_special,
		"T-shape horizontal spine: spawns_special == true")
	_assert(mr != null and mr.special_type == "wheelbarrow",
		"T-shape horizontal spine: special_type == 'wheelbarrow'")
	_assert(mr != null and mr.cells.size() == 5,
		"T-shape horizontal spine: 5 cells")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3),
			Vector2i(2, 2), Vector2i(4, 2)]),
		"T-shape horizontal spine: correct cells")

	# Vertical spine T:
	#   spine:  (1,3) (2,3) (3,3)
	#   arm lt: (2,2)
	#   arm rt: (2,4)
	#
	#   col:  0 1 2 3 4 5 6 7
	# row 1:  . . . a . . . .
	# row 2:  . . a a a . . .
	# row 3:  . . . a . . . .
	board.fill_from_strings([
		"........",
		"...a....",
		"..aaa...",
		"...a....",
		"........",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	_assert(results.size() == 1,
		"T-shape vertical spine: exactly 1 match found")

	mr = _first(results, "match_t")
	_assert(mr != null,
		"T-shape vertical spine: shape == 'match_t'")
	_assert(mr != null and mr.orientation == "vertical",
		"T-shape vertical spine: orientation == 'vertical'")
	_assert(mr != null and _cells_match(mr.cells, [
			Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
			Vector2i(2, 2), Vector2i(2, 4)]),
		"T-shape vertical spine: correct cells")


# ── Suite: orientation ────────────────────────────────────────────────────────

func _test_orientation() -> void:
	_current_suite = "orientation stored correctly"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Horizontal straight-4 → orientation == "horizontal"
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"..aaaa..",
		"........",
		"........",
		"........",
	])
	var results := finder.find_matches(board)
	var mr      := _first(results, "match_4")
	_assert(mr != null and mr.orientation == "horizontal",
		"straight-4 horizontal: orientation == 'horizontal' (Bushel Basket will clear row)")

	# Vertical straight-4 → orientation == "vertical"
	board.fill_from_strings([
		"........",
		"...a....",
		"...a....",
		"...a....",
		"...a....",
		"........",
		"........",
		"........",
	])
	results = finder.find_matches(board)
	mr      = _first(results, "match_4")
	_assert(mr != null and mr.orientation == "vertical",
		"straight-4 vertical: orientation == 'vertical' (Bushel Basket will clear column)")


# ── Suite: no double-counting ─────────────────────────────────────────────────

func _test_no_double_counting() -> void:
	_current_suite = "L/T shapes not double-counted as two straights"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# L-shape placed on board — must produce 1 match_l, NOT a match_3 + match_3.
	#   col:  0 1 2 3 4 5 6 7
	# row 0:  . . . a . . . .
	# row 1:  . . . a . . . .
	# row 2:  . . . a a a . .
	board.fill_from_strings([
		"...a....",
		"...a....",
		"...aaa..",
		"........",
		"........",
		"........",
		"........",
		"........",
	])

	var results := finder.find_matches(board)
	_assert(results.size() == 1,
		"L-shape: total match count == 1 (not split into 2 straights)")
	_assert(_first(results, "match_l") != null,
		"L-shape: the single result is match_l, not match_3")
	_assert(_first(results, "match_3") == null,
		"L-shape: no spurious match_3 produced")

	# T-shape placed on board — must produce 1 match_t, NOT match_3 + match_3.
	board.fill_from_strings([
		"........",
		"........",
		"..a.....",
		".aaa....",
		"..a.....",
		"........",
		"........",
		"........",
	])

	results = finder.find_matches(board)
	_assert(results.size() == 1,
		"T-shape: total match count == 1 (not split into 2 straights)")
	_assert(_first(results, "match_t") != null,
		"T-shape: the single result is match_t, not match_3")
	_assert(_first(results, "match_3") == null,
		"T-shape: no spurious match_3 produced")


# ── Suite: would_swap_create_match ────────────────────────────────────────────

func _test_would_swap_create_match() -> void:
	_current_suite = "would_swap_create_match"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Valid swap: swapping (3,3) right completes a horizontal straight-3.
	#   col:  0 1 2 3 4 5 6 7
	# row 3:  . . a . a a . .   ← swap (3,3) 'b' with (3,2) 'a' → a a a
	# Place: row 3 = ..a.aa.. where (3,3)=b will be swapped left into the run.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"..ab.aa.",   # swap 'b' at (3,3) left to (3,2) → not right
		"........",
		"........",
		"........",
		"........",
	])
	# Swap (3,3) [b] with (3,2) [a] → row becomes ..ba.aa.
	# That doesn't help. Set up a cleaner case:
	# row 4: . a a . a .  → swap (4,3) [.] — can't swap empty.
	# Clean setup: row 2 = a a . a → swap (2,2)[.] won't work.
	# Use: row 5 = . b a a . . → swap (5,1)[b] with (5,0)[.] — no.
	# Simplest: a a b a → swap b with left a gives a a a b → match.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"aabaa...",   # (4,2)=b; swap with (4,1)=a → a b a a a → still no left-3
		"........",
		"........",
		"........",
	])
	# Actually cleanest: place a a . a a in a row, then swap center with adjacent.
	# row 3: a a b . .  → swap b(4,2) left → a b a.. no.
	# Just do: row 3 = . a a b a → swap b(3,3) right(3,4)=a → . a a a b → match!
	board.fill_from_strings([
		"........",
		"........",
		"........",
		".aabaa..",
		"........",
		"........",
		"........",
		"........",
	])
	# (3,3)=b, swap right to (3,4)=a → .aa a b. → no match for b.
	# swap left to (3,2)=a → .a ba a. → no.
	# Let's just use a direct known-good setup.
	# Row 0: a a . a  → swap (0,2)[.] — empty, not valid.
	# Row 0: a a b a  at cols 0-3 → swap b(0,2) with right a(0,3) → a a a b → match at 0-2.
	board.fill_from_strings([
		"aaba....",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])
	_assert(finder.would_swap_create_match(board, Vector2i(0, 2), Vector2i(0, 3)),
		"would_swap_create_match: returns true for a valid swap that completes a-a-a")

	# Spec behavioral scenario — invalid swap:
	# No valid match would result from swapping (2,2) and (2,3).
	# Board is filled so that every possible swap of those two cells produces
	# no 3-in-a-row. Use two crops arranged so no three of either are adjacent
	# after the swap. A simple isolated pair with mismatched neighbours works:
	#   row 2: . . a b . . . .   swap a(2,2) ↔ b(2,3)
	#   After:  . . b a . . . .  — neither side gains two same-crop neighbours.
	board.fill_from_strings([
		"........",
		"........",
		"..ab....",
		"........",
		"........",
		"........",
		"........",
		"........",
	])
	_assert(not finder.would_swap_create_match(board, Vector2i(2, 2), Vector2i(2, 3)),
		"would_swap_create_match: returns false for swap that creates no match (spec §4.1 scenario)")

	# Swapping a piece with an empty cell returns false.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"...a....",
		"........",
		"........",
		"........",
		"........",
	])
	_assert(not finder.would_swap_create_match(board, Vector2i(3, 3), Vector2i(3, 4)),
		"would_swap_create_match: returns false when one cell is empty")


# ── Suite: two-specials rejection ─────────────────────────────────────────────

func _test_invalid_swap_two_specials() -> void:
	_current_suite = "two special pieces cannot be swapped (spec §5.1)"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	# Place two different specials adjacent to each other.
	# Even if swapping them would technically form a match, the spec forbids it.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])
	# Place a bushel_basket and a scarecrow adjacent horizontally.
	board.place_piece(4, 3, "bushel_basket", true, "horizontal")
	board.place_piece(4, 4, "scarecrow",     true, "")
	# Also surround them so a match could theoretically form.
	board.place_piece(4, 2, "bushel_basket", false, "")
	board.place_piece(4, 5, "bushel_basket", false, "")

	_assert(not finder.would_swap_create_match(board, Vector2i(4, 3), Vector2i(4, 4)),
		"two specials adjacent: would_swap_create_match == false (spec §5.1)")

	# A special adjacent to a normal piece is a valid swap if it creates a match.
	# Swap scarecrow(3,3) right with 'a' at (3,4) — after swap:
	#   (3,3)=a, (3,4)=scarecrow, (3,5)=a, (3,6)=a
	#   'a' at (3,3),(3,5),(3,6) are not contiguous — no match.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	])
	board.place_piece(3, 3, "scarecrow", true, "")
	board.place_piece(3, 4, "a",         false, "")
	board.place_piece(3, 5, "a",         false, "")
	board.place_piece(3, 6, "a",         false, "")
	_assert(not finder.would_swap_create_match(board, Vector2i(3, 3), Vector2i(3, 4)),
		"special + normal swap: false when non-special side has no contiguous match")

	# Now place it so the normal piece DOES create a 3-match when swapped.
	# Layout before swap:
	#   (3,2)=a  (3,3)=a  (3,4)=scarecrow  (3,5)=a  (3,6)=a
	# Swap scarecrow(3,4) ↔ a(3,5):
	#   (3,2)=a  (3,3)=a  (3,4)=a  (3,5)=scarecrow  (3,6)=a
	#   'a' at (3,2),(3,3),(3,4) → contiguous match_3 ✓
	board.place_piece(3, 2, "a",         false, "")
	board.place_piece(3, 3, "a",         false, "")
	board.place_piece(3, 4, "scarecrow", true,  "")
	board.place_piece(3, 5, "a",         false, "")
	board.place_piece(3, 6, "a",         false, "")
	_assert(finder.would_swap_create_match(board, Vector2i(3, 4), Vector2i(3, 5)),
		"special + normal swap: true when normal-piece side creates a 3-match after swap")


# ── Suite: swap guards ────────────────────────────────────────────────────────

func _test_swap_guards() -> void:
	_current_suite = "would_swap_create_match guards"
	print("\n── %s ──" % _current_suite)

	var board  := _make_board()
	var finder := _make_finder()

	board.fill_from_strings([
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
		"aaaabbbb",
	])

	# Out-of-bounds cell.
	_assert(not finder.would_swap_create_match(board, Vector2i(-1, 0), Vector2i(0, 0)),
		"guard: out-of-bounds cell returns false")

	# Diagonal swap (spec: only orthogonal swaps permitted).
	_assert(not finder.would_swap_create_match(board, Vector2i(0, 0), Vector2i(1, 1)),
		"guard: diagonal swap returns false (spec §4.1: only orthogonal swaps)")

	# Swap with a rock cell.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"...aRa..",
		"........",
		"........",
		"........",
		"........",
	])
	_assert(not finder.would_swap_create_match(board, Vector2i(3, 3), Vector2i(3, 4)),
		"guard: swap with rock cell returns false")

	# Swap with a flower cell.
	board.fill_from_strings([
		"........",
		"........",
		"........",
		"...aFa..",
		"........",
		"........",
		"........",
		"........",
	])
	_assert(not finder.would_swap_create_match(board, Vector2i(3, 3), Vector2i(3, 4)),
		"guard: swap with flower cell returns false")

	# Swap with a hole.
	var board2 := BoardState.new()
	board2.init_empty()
	board2.fill_from_strings([
		"........",
		"........",
		"........",
		"...a....",
		"........",
		"........",
		"........",
		"........",
	])
	board2.get_cell(3, 4).active = false  # make (3,4) a hole
	_assert(not finder.would_swap_create_match(board2, Vector2i(3, 3), Vector2i(3, 4)),
		"guard: swap with hole returns false")


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
