class_name MatchFinder
extends RefCounted

## MatchFinder.gd
## Stateless match detection for the 8×8 board.
## All methods take a BoardState and return results — no state is mutated here.
## BoardController is responsible for acting on the results.

# ── MatchResult ───────────────────────────────────────────────────────────────

class MatchResult:
	## All cell coordinates that are part of this match.
	var cells: Array[Vector2i] = []

	## Shape identifier. One of:
	## "match_3", "match_4", "match_5", "match_l", "match_t"
	var shape: String = ""

	## "horizontal" or "vertical".
	## For straight matches: the direction of the run.
	## For L-shape: the direction of the longer arm (the 3-piece run).
	## For T-shape: the direction of the spine (the 3-piece run).
	## Used by BoardController to set special_orientation on Bushel Basket spawns.
	var orientation: String = ""

	## True when this match causes a special piece to spawn.
	var spawns_special: bool = false

	## Which special piece to spawn. "" when spawns_special is false.
	## One of: "bushel_basket", "scarecrow", "watering_can", "wheelbarrow"
	var special_type: String = ""

	## The cell where the player initiated the swap that produced this match.
	## The special piece (if any) spawns here.
	## Set by the caller (BoardController) via find_matches_for_swap(); left as
	## Vector2i(-1,-1) when found by find_matches() during cascade scanning.
	var swap_origin: Vector2i = Vector2i(-1, -1)

	func _init(
		p_cells: Array[Vector2i],
		p_shape: String,
		p_orientation: String,
		p_swap_origin: Vector2i = Vector2i(-1, -1)
	) -> void:
		cells       = p_cells
		shape       = p_shape
		orientation = p_orientation
		swap_origin = p_swap_origin

		match p_shape:
			"match_4":
				spawns_special = true
				special_type   = "bushel_basket"
			"match_5":
				spawns_special = true
				special_type   = "scarecrow"
			"match_l":
				spawns_special = true
				special_type   = "watering_can"
			"match_t":
				spawns_special = true
				special_type   = "wheelbarrow"
			_:
				spawns_special = false
				special_type   = ""


# ── Public API ────────────────────────────────────────────────────────────────

## Finds all valid matches currently on the board.
## Used during cascade scanning where there is no swap origin.
## Returns an Array[MatchResult], possibly empty.
##
## Detection priority (to prevent double-counting):
##   1. T-shapes  (5 cells crossing at middle)
##   2. L-shapes  (5 cells bending at corner)
##   3. Straight-5
##   4. Straight-4
##   3. Straight-3
##
## Cells claimed by a higher-priority match are excluded from lower-priority
## scans via the `claimed` set.
func find_matches(board: BoardState) -> Array[MatchResult]:
	return _find_all(board, Vector2i(-1, -1))


## Finds all valid matches that would result from swapping cells a and b,
## tagging each MatchResult with the correct swap_origin.
## Does NOT validate whether the swap is legal — call would_swap_create_match
## first if you need the validity check.
func find_matches_for_swap(board: BoardState, a: Vector2i, b: Vector2i) -> Array[MatchResult]:
	board.swap_pieces(a, b)
	var results := _find_all(board, a)
	board.swap_pieces(a, b)  # restore
	return results


## Returns true if swapping cells a and b would produce at least one valid
## match of 3 or more. Also returns false if either cell is not a normal
## swappable piece (hole, rock, flower, empty) or if both cells hold special
## pieces (spec: two specials cannot be combined).
func would_swap_create_match(board: BoardState, a: Vector2i, b: Vector2i) -> bool:
	# ── Guard: both cells must be in-bounds and active ──
	if not board.is_in_bounds(a.x, a.y) or not board.is_in_bounds(b.x, b.y):
		return false

	var ca := board.get_cell(a.x, a.y)
	var cb := board.get_cell(b.x, b.y)

	if not ca.active or not cb.active:
		return false

	# ── Guard: both cells must hold a piece ──
	if ca.piece == "" or cb.piece == "":
		return false

	# ── Guard: rocks and flowers cannot be swapped ──
	if ca.obstacle == "rock" or ca.obstacle == "flower":
		return false
	if cb.obstacle == "rock" or cb.obstacle == "flower":
		return false

	# ── Guard: two special pieces cannot be swapped together (spec §5.1) ──
	if ca.is_special and cb.is_special:
		return false

	# ── Guard: only orthogonal swaps (spec §4.1) ──
	var delta := Vector2i(abs(a.x - b.x), abs(a.y - b.y))
	if delta != Vector2i(1, 0) and delta != Vector2i(0, 1):
		return false

	# ── Simulate swap and check for matches ──
	board.swap_pieces(a, b)
	var found := not _find_all(board, a).is_empty()
	board.swap_pieces(a, b)  # restore
	return found


## Returns true when at least one valid swap exists anywhere on the board.
## Used to detect a deadlocked board state.
func has_any_valid_swap(board: BoardState) -> bool:
	for row in range(BoardState.GRID_SIZE):
		for col in range(BoardState.GRID_SIZE):
			# Check swap with right neighbour and swap with bottom neighbour.
			for offset in [Vector2i(0, 1), Vector2i(1, 0)]:
				var a := Vector2i(row, col)
				var b : Vector2i = a + offset
				if board.is_in_bounds(b.x, b.y):
					if would_swap_create_match(board, a, b):
						return true
	return false


# ── Internal detection ────────────────────────────────────────────────────────

func _find_all(board: BoardState, swap_origin: Vector2i) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	# claimed tracks cells already assigned to a higher-priority match so they
	# are not double-counted in lower-priority scans.
	var claimed: Dictionary = {}  # Vector2i → true

	_find_t_shapes(board, swap_origin, results, claimed)
	_find_l_shapes(board, swap_origin, results, claimed)
	_find_straights(board, swap_origin, results, claimed)

	return results


# ── T-shape detection ─────────────────────────────────────────────────────────
#
# A T-shape is a straight run of 3 with a perpendicular run of 3 sharing the
# middle cell of the first run, making 5 unique cells total.
#
# Orientations (spine direction → label used for `orientation`):
#
#   Horizontal spine (─┬─):   Vertical spine (├):
#     a b c                     a
#       d                       b d e
#       e                       c
#
# We scan every cell as a candidate middle of a horizontal run-of-3 AND as the
# candidate middle of a vertical run-of-3, then check the crossing arm.

func _find_t_shapes(
	board: BoardState,
	swap_origin: Vector2i,
	results: Array[MatchResult],
	claimed: Dictionary
) -> void:
	for row in range(BoardState.GRID_SIZE):
		for col in range(BoardState.GRID_SIZE):
			var crop := _piece_at(board, row, col)
			if crop == "":
				continue

			# ── Vertical spine: (row-1, col), (row, col), (row+1, col) ──
			# Perpendicular arm (horizontal): (row, col-1), (row, col+1)
			# Checked first so a board that satisfies both descriptions (a pure +
			# shape) is always labelled "vertical" — Wheelbarrow clears both row
			# and column regardless, so the label only affects future-proofing.
			if _same_crop(board, crop, [
				Vector2i(row - 1, col), Vector2i(row + 1, col),
				Vector2i(row, col - 1), Vector2i(row, col + 1)
			]):
				var shape_cells: Array[Vector2i] = [
					Vector2i(row - 1, col), Vector2i(row, col), Vector2i(row + 1, col),
					Vector2i(row, col - 1), Vector2i(row, col + 1)
				]
				if not _any_claimed(shape_cells, claimed):
					var origin := swap_origin if swap_origin in shape_cells else Vector2i(row, col)
					var mr := MatchResult.new(shape_cells, "match_t", "vertical", origin)
					results.append(mr)
					_claim(shape_cells, claimed)
					continue

			# ── Horizontal spine: (row, col-1), (row, col), (row, col+1) ──
			# Perpendicular arm (vertical): (row-1, col), (row+1, col)
			if _same_crop(board, crop, [
				Vector2i(row, col - 1), Vector2i(row, col + 1),
				Vector2i(row - 1, col), Vector2i(row + 1, col)
			]):
				var shape_cells: Array[Vector2i] = [
					Vector2i(row, col - 1), Vector2i(row, col), Vector2i(row, col + 1),
					Vector2i(row - 1, col), Vector2i(row + 1, col)
				]
				if not _any_claimed(shape_cells, claimed):
					var origin := swap_origin if swap_origin in shape_cells else Vector2i(row, col)
					var mr := MatchResult.new(shape_cells, "match_t", "horizontal", origin)
					results.append(mr)
					_claim(shape_cells, claimed)


# ── L-shape detection ─────────────────────────────────────────────────────────
#
# An L-shape is a run of 3 in one direction with a run of 3 in the perpendicular
# direction sharing one corner cell — 5 unique cells total.
#
# Four rotations exist. We enumerate all four by testing every cell as the
# corner (the shared cell):
#
#   Up-Right    Up-Left    Down-Right    Down-Left
#   c . .       . . c      c             . . .
#   c . .       . . c      c . .         . . c
#   c b b       b b c      . b b         b b .
#
# For each corner candidate at (row,col) with crop X, we need:
#   - A vertical arm of length 3 going up OR down (including the corner)
#   - A horizontal arm of length 2 extending right or left FROM the corner
#     (not including the corner — it's shared)
#
# More precisely, the four rotations:
#
#   UR: vertical arm (row,col),(row-1,col),(row-2,col)  + horizontal (row,col+1),(row,col+2)
#   UL: vertical arm (row,col),(row-1,col),(row-2,col)  + horizontal (row,col-1),(row,col-2)
#   DR: vertical arm (row,col),(row+1,col),(row+2,col)  + horizontal (row,col+1),(row,col+2)
#   DL: vertical arm (row,col),(row+1,col),(row+2,col)  + horizontal (row,col-1),(row,col-2)
#
# orientation = direction of the 3-cell arm (the "spine"):
#   UR/UL → "vertical"   DR/DL → "vertical"
# But we also need horizontal spines:
#   HL: horizontal arm (row,col),(row,col+1),(row,col+2) + vertical (row-1,col),(row+1,col) ← that's T
#
# Actually, by the spec an L is "3 + 2 at corner" — one arm of 3 and one arm
# of 2 meeting at one end of the 3-arm (not the middle). This distinguishes it
# from T (where the 2-arm meets the MIDDLE of the 3-arm).
#
# All four L rotations:
#
#  (A) Vertical 3-arm going up,   horizontal 2-arm going right from bottom corner
#  (B) Vertical 3-arm going up,   horizontal 2-arm going left  from bottom corner
#  (C) Vertical 3-arm going down, horizontal 2-arm going right from top corner
#  (D) Vertical 3-arm going down, horizontal 2-arm going left  from top corner
#  (E) Horizontal 3-arm going right, vertical 2-arm going down from left corner
#  (F) Horizontal 3-arm going right, vertical 2-arm going up   from left corner
#  (G) Horizontal 3-arm going left,  vertical 2-arm going down from right corner
#  (H) Horizontal 3-arm going left,  vertical 2-arm going up   from right corner

func _find_l_shapes(
	board: BoardState,
	swap_origin: Vector2i,
	results: Array[MatchResult],
	claimed: Dictionary
) -> void:
	for row in range(BoardState.GRID_SIZE):
		for col in range(BoardState.GRID_SIZE):
			var crop := _piece_at(board, row, col)
			if crop == "":
				continue

			# Each rotation is [spine_cells (3), arm_cells (2), orientation]
			var rotations: Array = [
				# (A) vertical spine up, right arm
				[
					[Vector2i(row, col), Vector2i(row - 1, col), Vector2i(row - 2, col)],
					[Vector2i(row, col + 1), Vector2i(row, col + 2)],
					"vertical"
				],
				# (B) vertical spine up, left arm
				[
					[Vector2i(row, col), Vector2i(row - 1, col), Vector2i(row - 2, col)],
					[Vector2i(row, col - 1), Vector2i(row, col - 2)],
					"vertical"
				],
				# (C) vertical spine down, right arm
				[
					[Vector2i(row, col), Vector2i(row + 1, col), Vector2i(row + 2, col)],
					[Vector2i(row, col + 1), Vector2i(row, col + 2)],
					"vertical"
				],
				# (D) vertical spine down, left arm
				[
					[Vector2i(row, col), Vector2i(row + 1, col), Vector2i(row + 2, col)],
					[Vector2i(row, col - 1), Vector2i(row, col - 2)],
					"vertical"
				],
				# (E) horizontal spine right, down arm
				[
					[Vector2i(row, col), Vector2i(row, col + 1), Vector2i(row, col + 2)],
					[Vector2i(row + 1, col), Vector2i(row + 2, col)],
					"horizontal"
				],
				# (F) horizontal spine right, up arm
				[
					[Vector2i(row, col), Vector2i(row, col + 1), Vector2i(row, col + 2)],
					[Vector2i(row - 1, col), Vector2i(row - 2, col)],
					"horizontal"
				],
				# (G) horizontal spine left, down arm
				[
					[Vector2i(row, col), Vector2i(row, col - 1), Vector2i(row, col - 2)],
					[Vector2i(row + 1, col), Vector2i(row + 2, col)],
					"horizontal"
				],
				# (H) horizontal spine left, up arm
				[
					[Vector2i(row, col), Vector2i(row, col - 1), Vector2i(row, col - 2)],
					[Vector2i(row - 1, col), Vector2i(row - 2, col)],
					"horizontal"
				],
			]

			for rotation in rotations:
				var spine: Array     = rotation[0]
				var arm: Array       = rotation[1]
				var orient: String   = rotation[2]

				# All 5 cells must be valid pieces of the same crop.
				var all_cells: Array[Vector2i] = []
				for v in spine:
					all_cells.append(v)
				for v in arm:
					all_cells.append(v)

				if _same_crop(board, crop, all_cells) and not _any_claimed(all_cells, claimed):
					var origin := swap_origin if swap_origin in all_cells else all_cells[0]
					var mr := MatchResult.new(all_cells, "match_l", orient, origin)
					results.append(mr)
					_claim(all_cells, claimed)
					break  # only one L per anchor cell


# ── Straight-line detection ───────────────────────────────────────────────────
#
# Scans each row for horizontal runs and each column for vertical runs.
# Emits match_5, match_4, or match_3 depending on run length.
# Runs longer than 5 are split into the longest match starting at the leftmost
# unclaimed cell (greedy left-to-right / top-to-bottom).

func _find_straights(
	board: BoardState,
	swap_origin: Vector2i,
	results: Array[MatchResult],
	claimed: Dictionary
) -> void:
	# ── Horizontal ──
	for row in range(BoardState.GRID_SIZE):
		var col := 0
		while col < BoardState.GRID_SIZE:
			var crop := _piece_at(board, row, col)
			if crop == "":
				col += 1
				continue

			# Extend run as far as it goes.
			var run_end := col + 1
			while run_end < BoardState.GRID_SIZE and _piece_at(board, row, run_end) == crop:
				run_end += 1
			var run_len := run_end - col

			if run_len >= 3:
				# Consume the longest match first (match_5 > match_4 > match_3).
				var match_len := mini(run_len, 5)
				var shape_cells: Array[Vector2i] = []
				for c in range(col, col + match_len):
					shape_cells.append(Vector2i(row, c))

				if not _any_claimed(shape_cells, claimed):
					var shape := _shape_for_length(match_len)
					var origin := swap_origin if swap_origin in shape_cells else shape_cells[0]
					results.append(MatchResult.new(shape_cells, shape, "horizontal", origin))
					_claim(shape_cells, claimed)

				col += match_len
			else:
				col += run_len

	# ── Vertical ──
	for col in range(BoardState.GRID_SIZE):
		var row := 0
		while row < BoardState.GRID_SIZE:
			var crop := _piece_at(board, row, col)
			if crop == "":
				row += 1
				continue

			var run_end := row + 1
			while run_end < BoardState.GRID_SIZE and _piece_at(board, run_end, col) == crop:
				run_end += 1
			var run_len := run_end - row

			if run_len >= 3:
				var match_len := mini(run_len, 5)
				var shape_cells: Array[Vector2i] = []
				for r in range(row, row + match_len):
					shape_cells.append(Vector2i(r, col))

				if not _any_claimed(shape_cells, claimed):
					var shape := _shape_for_length(match_len)
					var origin := swap_origin if swap_origin in shape_cells else shape_cells[0]
					results.append(MatchResult.new(shape_cells, shape, "vertical", origin))
					_claim(shape_cells, claimed)

				row += match_len
			else:
				row += run_len


# ── Utilities ─────────────────────────────────────────────────────────────────

## Returns the piece identifier at (row, col), or "" if the cell is out of
## bounds, inactive, a rock, a flower, or holds no piece.
## This is the single gating function for "can this cell participate in a match".
func _piece_at(board: BoardState, row: int, col: int) -> String:
	if not board.is_in_bounds(row, col):
		return ""
	var cs := board.get_cell(row, col)
	if not cs.active:
		return ""
	# Rocks and flowers never participate in matches.
	if cs.obstacle == "rock" or cs.obstacle == "flower":
		return ""
	return cs.piece  # may be "" for an empty cell — callers treat "" as no-match


## Returns true when every cell in `coords` holds `crop` as its piece.
func _same_crop(board: BoardState, crop: String, coords: Array) -> bool:
	if crop == "":
		return false
	for v in coords:
		if _piece_at(board, v.x, v.y) != crop:
			return false
	return true


## Returns true when any cell in `coords` is already in the claimed set.
func _any_claimed(coords: Array, claimed: Dictionary) -> bool:
	for v in coords:
		if claimed.has(v):
			return true
	return false


## Marks all cells in `coords` as claimed.
func _claim(coords: Array, claimed: Dictionary) -> void:
	for v in coords:
		claimed[v] = true


## Maps a run length to the correct shape string.
func _shape_for_length(length: int) -> String:
	match length:
		5: return "match_5"
		4: return "match_4"
		_: return "match_3"
