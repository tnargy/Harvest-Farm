class_name GravitySystem
extends RefCounted

## GravitySystem.gd
## Pure gravity and weighted refill calculator for the 8×8 board.
## Given a BoardState snapshot, computes which pieces fall and which new pieces
## fill empty cells. Returns a GravityResult — no board mutation occurs here.
## BoardController is responsible for applying the result.
##
## Gravity rules (spec §6.1):
##   - Pieces fall straight down within their column.
##   - Holes block falling — pieces settle at the lowest available active cell
##     above a hole (or above the bottom of the board).
##   - Rocks and flowers occupy their cell fully; pieces cannot pass through or
##     land on them, but pieces above them can fall past them to lower active
##     cells that can hold a piece.
##   - Special pieces fall identically to normal crop pieces (spec §6.2).
##   - Landing on a dirt-patch cell does NOT clear the dirt (spec §6.2).
##
## Refill rules (spec §6.3):
##   - Once gravity has settled, remaining empty fillable cells are filled from
##     above the topmost active cell in each column.
##   - New pieces are chosen by weighted random from the level's crop_set.
##   - Base weight for every crop type is 1.
##   - If the level has an active "collect_crop" goal that is not yet satisfied,
##     that crop's weight is raised to 2.
##   - Weights reset to 1 for all crops once that goal is satisfied.
##   - Special pieces are never spawned during refill.


# ── GravityResult ─────────────────────────────────────────────────────────────

class GravityResult:
	## Each entry describes one piece that fell from its origin to its
	## destination. Ordered bottom-to-top within each column so BoardController
	## can apply moves without pieces overwriting each other.
	##
	## Array of Dictionaries, each with:
	##   "from"        : Vector2i  — original cell (row, col)
	##   "to"          : Vector2i  — destination cell (row, col)
	##   "piece"       : String    — piece identifier
	##   "is_special"  : bool
	##   "orientation" : String    — special_orientation value (may be "")
	var moves: Array[Dictionary] = []

	## Each entry describes one new piece introduced by refill.
	##
	## Array of Dictionaries, each with:
	##   "cell"        : Vector2i  — destination cell (row, col)
	##   "piece"       : String    — crop identifier chosen by weighted random
	##
	## New pieces are never special. Ordered top-to-bottom within each column
	## (the piece entering highest in the column is listed first) so
	## BoardController can animate them falling in sequence.
	var fills: Array[Dictionary] = []

	func _init(
		p_moves: Array[Dictionary],
		p_fills: Array[Dictionary]
	) -> void:
		moves = p_moves
		fills = p_fills


# ── Public API ────────────────────────────────────────────────────────────────

## Computes the full gravity + refill result for the current board state.
##
## Parameters:
##   board        – Current BoardState (read-only; never mutated here).
##   level_data   – LevelData resource for this run (crop_set and goals).
##   collected    – Dictionary mapping crop id → int count already collected
##                  this run. Used to decide whether a collect_crop goal is
##                  still active (unsatisfied). Pass {} if no tracking exists yet.
##   rng          – Optional RandomNumberGenerator. If null, a new one is
##                  created and randomised. Inject a seeded RNG in tests for
##                  deterministic output.
##   avoid_initial_matches – When true, fills cells in row-major order and
##                  rejects crops that would form a 3-in-a-row with already-placed
##                  neighbors. Use for the initial board fill only; mid-level
##                  refills intentionally allow matches (they cascade and score).
##
## Returns a GravityResult containing all moves and fills needed to bring the
## board to its settled, fully-filled state.
func calculate(
	board: BoardState,
	level_data: LevelData,
	collected: Dictionary,
	rng: RandomNumberGenerator,
	avoid_initial_matches: bool = false
) -> GravityResult:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var all_moves: Array[Dictionary] = []
	var all_fills: Array[Dictionary] = []

	# Build the weighted crop table once — shared across all columns.
	var weighted_crops: Array[String] = _build_weighted_crops(level_data, collected)

	for col in range(BoardState.GRID_SIZE):
		var col_moves := _apply_gravity_column(board, col)
		all_moves.append_array(col_moves)

	if avoid_initial_matches:
		all_fills = _fill_match_aware(board, all_moves, weighted_crops, rng)
	else:
		for col in range(BoardState.GRID_SIZE):
			# Collect only this column's moves for the per-column fill helper.
			var col_moves: Array[Dictionary] = []
			for mv in all_moves:
				if mv["from"].y == col:
					col_moves.append(mv)
			var col_fills := _apply_refill_column(board, col, col_moves, weighted_crops, rng)
			all_fills.append_array(col_fills)

	return GravityResult.new(all_moves, all_fills)


# ── Weighted crop table ───────────────────────────────────────────────────────

## Builds a flat Array[String] of crop identifiers with duplicates representing
## weights. Each crop starts with weight 1 (appears once). Any crop that is the
## target of an unsatisfied "collect_crop" goal appears twice (weight 2).
##
## Spec §6.3:
##   "each crop type in the level's crop_set has a base weight of 1. If the
##    level has an active 'Collect X of crop Y' goal that is not yet met, crop Y
##    has its weight increased to 2. Weights reset to 1 for all crops once that
##    goal is satisfied."
func _build_weighted_crops(level_data: LevelData, collected: Dictionary) -> Array[String]:
	# Identify which crops have an unsatisfied collect_crop goal.
	var boosted: Dictionary = {}  # crop id → true
	for goal in level_data.goals:
		if goal.get("type", "") == "collect_crop":
			var crop: String = goal.get("crop", "")
			var target: int  = goal.get("target", 0)
			if crop == "" or target <= 0:
				continue
			var already: int = collected.get(crop, 0)
			if already < target:
				boosted[crop] = true

	var table: Array[String] = []
	for crop in level_data.crop_set:
		table.append(crop)          # base weight 1
		if boosted.has(crop):
			table.append(crop)      # extra entry → effective weight 2

	return table


# ── Column gravity ────────────────────────────────────────────────────────────

## Calculates piece movements for a single column due to gravity.
##
## Strategy:
##   Walk the column from the bottom row upward. Maintain a write pointer
##   pointing to the lowest empty fillable cell. When a piece is found above
##   the write pointer, record a move from that cell to the write pointer and
##   advance the pointer upward.
##
## Holes split the column into independent segments — a hole at row H means
## pieces above row H cannot fall past it. We rebuild the write pointer each
## time a new contiguous segment starts.
##
## Returns Array[Dictionary] of move entries (same schema as GravityResult.moves).
## The array is ordered bottom-to-top within the column.
func _apply_gravity_column(board: BoardState, col: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []

	# Collect all cells in this column that can hold a piece, top-to-bottom.
	# Holes (inactive cells), rocks, and flowers are excluded — they all act
	# as barriers that pieces cannot pass through or land on.
	var active_rows: Array[int] = []
	for row in range(BoardState.GRID_SIZE):
		if board.get_cell(row, col).can_hold_piece():
			active_rows.append(row)

	# Process each contiguous segment between holes independently.
	# A contiguous segment is a maximal run of active rows with no hole gaps.
	var segment_start := 0
	while segment_start < active_rows.size():
		# Find the end of this contiguous segment.
		var segment_end := segment_start
		while segment_end + 1 < active_rows.size() \
				and active_rows[segment_end + 1] == active_rows[segment_end] + 1:
			segment_end += 1

		# segment is active_rows[segment_start .. segment_end] (inclusive).
		# Apply gravity within this segment only.
		var seg_moves := _gravity_segment(board, col, active_rows, segment_start, segment_end)
		moves.append_array(seg_moves)

		segment_start = segment_end + 1

	return moves


## Applies gravity within one contiguous segment of active rows for a column.
## active_rows is the full active-rows array for the column; segment_start and
## segment_end are inclusive indices into it delimiting this segment.
##
## Algorithm — two-pointer write-down:
##   write  starts at the bottom of the segment and moves upward.
##   read   starts just above write and scans upward for the next piece.
##   When a piece is found at read, it belongs at write.  If read != write,
##   record a move.  Advance both pointers upward and repeat.
##
## Returns move entries ordered bottom-to-top (lowest destination row first),
## matching the GravityResult.moves contract.
func _gravity_segment(
	board: BoardState,
	col: int,
	active_rows: Array[int],
	segment_start: int,
	segment_end: int
) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []

	# write_idx  — index into active_rows; the next empty slot to fill.
	# Starts at the bottom of the segment and moves upward.
	var write_idx := segment_end

	# read_idx — scans upward from write_idx looking for the next piece.
	var read_idx := segment_end

	while read_idx >= segment_start:
		var read_row: int  = active_rows[read_idx]
		var cs: BoardState.CellState = board.get_cell(read_row, col)

		if cs.has_piece():
			var write_row: int = active_rows[write_idx]

			if read_idx != write_idx:
				# This piece needs to fall from read_row to write_row.
				moves.append({
					"dest_idx":    write_idx,   # kept for ordering; stripped below
					"from":        Vector2i(read_row,  col),
					"to":          Vector2i(write_row, col),
					"piece":       cs.piece,
					"is_special":  cs.is_special,
					"orientation": cs.special_orientation,
				})

			write_idx -= 1

		read_idx -= 1

	# moves was built bottom-to-top (write_idx descends), so the order is
	# already correct.  Strip the internal dest_idx key before returning.
	var result: Array[Dictionary] = []
	for mv in moves:
		result.append({
			"from":        mv["from"],
			"to":          mv["to"],
			"piece":       mv["piece"],
			"is_special":  mv["is_special"],
			"orientation": mv["orientation"],
		})
	return result


# ── Column refill ─────────────────────────────────────────────────────────────

## Calculates fill entries for empty fillable cells in a column after gravity
## has been applied (col_moves describes what moved, so we know the post-gravity
## state without mutating the board).
##
## "New pieces fall from above the topmost active cell in each column to fill
##  remaining empty active cells." (spec §6.3)
##
## Returns Array[Dictionary] of fill entries (same schema as GravityResult.fills),
## ordered top-to-bottom within the column (topmost fill first).
func _apply_refill_column(
	board: BoardState,
	col: int,
	col_moves: Array[Dictionary],
	weighted_crops: Array[String],
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	if weighted_crops.is_empty():
		return []

	# Build a set of cells that will be occupied after gravity settles.
	# Start from the current board state, then apply col_moves logically.
	var occupied_after: Dictionary = {}  # Vector2i → true

	# Mark all cells that currently have a piece AND are not being moved away.
	var moved_from: Dictionary = {}  # Vector2i → true
	for mv in col_moves:
		moved_from[mv["from"]] = true

	for row in range(BoardState.GRID_SIZE):
		var coord := Vector2i(row, col)
		var cs: BoardState.CellState = board.get_cell(row, col)
		if cs.has_piece() and not moved_from.has(coord):
			occupied_after[coord] = true

	# Mark destination cells of all moves as occupied.
	for mv in col_moves:
		occupied_after[mv["to"]] = true

	# Find all empty fillable cells in this column (post-gravity).
	var fills: Array[Dictionary] = []
	for row in range(BoardState.GRID_SIZE):
		var coord := Vector2i(row, col)
		var cs: BoardState.CellState = board.get_cell(row, col)
		if cs.can_hold_piece() and not occupied_after.has(coord):
			var crop := _pick_weighted(weighted_crops, rng)
			fills.append({
				"cell":  coord,
				"piece": crop,
			})

	# fills is already in top-to-bottom order because we iterated row 0 → 7.
	return fills


# ── Match-aware initial fill ──────────────────────────────────────────────────

## Fills all empty fillable cells in row-major order (top-left → bottom-right),
## rejecting crops that would complete a 3-in-a-row with already-placed
## neighbors. Because the scan is strictly left-to-right, top-to-bottom, only
## the two cells to the left and two cells above can already be decided — those
## are the only neighbors that need checking.
func _fill_match_aware(
	board: BoardState,
	all_moves: Array[Dictionary],
	weighted_crops: Array[String],
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	if weighted_crops.is_empty():
		return []

	# Build a virtual board: Vector2i → crop String for all post-gravity pieces.
	var virtual: Dictionary = {}

	var moved_from: Dictionary = {}
	for mv in all_moves:
		moved_from[mv["from"]] = true

	for row in range(BoardState.GRID_SIZE):
		for col in range(BoardState.GRID_SIZE):
			var coord := Vector2i(row, col)
			var cs: BoardState.CellState = board.get_cell(row, col)
			if cs.has_piece() and not moved_from.has(coord):
				virtual[coord] = cs.piece

	for mv in all_moves:
		virtual[mv["to"]] = mv["piece"]

	# Fill empty fillable cells in row-major order, avoiding matches.
	var fills: Array[Dictionary] = []
	for row in range(BoardState.GRID_SIZE):
		for col in range(BoardState.GRID_SIZE):
			var coord := Vector2i(row, col)
			var cs: BoardState.CellState = board.get_cell(row, col)
			if not cs.can_hold_piece() or virtual.has(coord):
				continue
			var forbidden := _forbidden_crops(virtual, row, col)
			var crop := _pick_avoiding(weighted_crops, forbidden, rng)
			virtual[coord] = crop
			fills.append({"cell": coord, "piece": crop})

	return fills


## Returns a Dictionary (crop → true) of crops that would complete a
## horizontal or vertical 3-in-a-row at (row, col) given the virtual board.
## Only checks the two cells to the left and two cells above — the row-major
## fill order guarantees no cells to the right or below are placed yet.
func _forbidden_crops(virtual: Dictionary, row: int, col: int) -> Dictionary:
	var forbidden: Dictionary = {}

	var l1: String = virtual.get(Vector2i(row, col - 1), "")
	var l2: String = virtual.get(Vector2i(row, col - 2), "")
	if l1 != "" and l1 == l2:
		forbidden[l1] = true

	var u1: String = virtual.get(Vector2i(row - 1, col), "")
	var u2: String = virtual.get(Vector2i(row - 2, col), "")
	if u1 != "" and u1 == u2:
		forbidden[u1] = true

	return forbidden


## Picks a crop from weighted_crops that is not in forbidden.
## Falls back to an unconstrained pick if every crop is forbidden
## (only possible when crop_set has fewer than 3 types).
func _pick_avoiding(
	weighted_crops: Array[String],
	forbidden: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	if forbidden.is_empty():
		return _pick_weighted(weighted_crops, rng)

	var allowed: Array[String] = []
	for crop in weighted_crops:
		if not forbidden.has(crop):
			allowed.append(crop)

	if allowed.is_empty():
		return _pick_weighted(weighted_crops, rng)

	return allowed[rng.randi_range(0, allowed.size() - 1)]


# ── Weighted random pick ──────────────────────────────────────────────────────

## Picks one entry from the weighted_crops flat table uniformly at random.
## The table encodes weights via repetition (weight-2 crops appear twice).
func _pick_weighted(weighted_crops: Array[String], rng: RandomNumberGenerator) -> String:
	var idx: int = rng.randi_range(0, weighted_crops.size() - 1)
	return weighted_crops[idx]
