class_name BoardController
extends RefCounted

## BoardController.gd
## Orchestrates one complete level run.
##
## Responsibilities:
##   - Validate and execute player swaps (spec §4.1, §5.1)
##   - Detect and resolve matches (MatchFinder)
##   - Spawn special pieces at the swap-origin cell (spec §5.1)
##   - Activate special pieces included in a swap (spec §5.2)
##   - Clear dirt patches and damage flowers via adjacency (spec §3.3)
##   - Apply gravity and refill (GravitySystem)
##   - Detect and resolve cascades with multipliers (spec §6.4)
##   - Calculate and accumulate score (ScoreCalculator)
##   - Track goal progress (GoalTracker)
##   - Decrement turns and detect win/fail (spec §9)
##
## BoardController is NOT a Node — it holds no scene state and performs no
## rendering. The game scene owns it and reads its public fields each frame.
##
## Sequence for a player swap (§4 → §5 → §6 → §7 → §8):
##   1. Validate swap (both cells in bounds, active, not two specials, creates match).
##   2. Execute swap on BoardState.
##   3. If either swapped piece is a special, activate it; collect cleared cells.
##   4. Resolve matches from MatchFinder; spawn specials; accumulate match cells.
##   5. Clear all collected cells from the board.
##   6. Process obstacle adjacency (dirt / flower) for cleared cells.
##   7. Apply gravity + refill (GravitySystem).
##   8. Score the turn (ScoreCalculator); notify GoalTracker.
##   9. Cascade loop: detect new matches → resolve → gravity → score → repeat.
##  10. Decrement turns; check win/fail.


# ── TurnResult ────────────────────────────────────────────────────────────────

class TurnResult:
	## True when the swap was accepted and a full turn resolved.
	var accepted: bool = false

	## True when the swap was rejected (no match would form, or two specials).
	## When rejected, no turn is consumed and the board is unchanged.
	var rejected: bool = false

	## Indices of goals newly completed this turn (matches GoalTracker indices).
	var newly_completed_goals: Array[int] = []

	## Points scored this turn (all matches + cascades combined).
	var points_earned: int = 0

	## Seeds earned this turn (from special piece activations).
	var seeds_earned: int = 0

	## Number of cascade levels that fired this turn (0 = none).
	var cascade_levels: int = 0

	## True when all goals are now complete (win condition met).
	var win: bool = false

	## True when turns_remaining reached 0 with goals unsatisfied (fail).
	var fail: bool = false


# ── Fields ────────────────────────────────────────────────────────────────────

## The board being controlled. Set by init().
var board: BoardState = null

## Level data for this run. Set by init().
var level_data: LevelData = null

## Balance resource. Set by init().
var balance: Balance = null

## GoalTracker instance for this run. Set by init().
var goal_tracker: GoalTracker = null

## Injected RNG — allows deterministic tests. If null at init time, a new
## randomised RNG is created.
var rng: RandomNumberGenerator = null

# ── Private subsystems (created in init) ─────────────────────────────────────

var _match_finder: MatchFinder = null
var _special_handler: SpecialPieceHandler = null
var _gravity_system: GravitySystem = null
var _score_calculator: ScoreCalculator = null

## Running count of each crop collected this run. Used by GravitySystem for
## weighted refill and by GoalTracker via notify_pieces_cleared.
## Keys are crop id strings; values are int counts.
var _collected: Dictionary = {}


# ── Initialisation ────────────────────────────────────────────────────────────

## Sets up a fresh run for the given level.
##
## Parameters:
##   p_board      – A BoardState that has already been initialised via
##                  init_from_level(). BoardController does NOT call
##                  init_from_level() itself.
##   p_level_data – The LevelData resource for this run.
##   p_balance    – The loaded Balance resource.
##   p_rng        – Optional seeded RNG for deterministic tests. Pass null to
##                  get a freshly randomised generator.
func init(
	p_board: BoardState,
	p_level_data: LevelData,
	p_balance: Balance,
	p_rng: RandomNumberGenerator = null
) -> void:
	board        = p_board
	level_data   = p_level_data
	balance      = p_balance

	if p_rng != null:
		rng = p_rng
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	goal_tracker = GoalTracker.new()
	goal_tracker.init(level_data)

	_match_finder     = MatchFinder.new()
	_special_handler  = SpecialPieceHandler.new()
	_gravity_system   = GravitySystem.new()
	_score_calculator = ScoreCalculator.new()

	_collected = {}


# ── Public API ────────────────────────────────────────────────────────────────

## Attempts a player swap between the two given cell coordinates.
##
## Returns a TurnResult describing what happened. The caller should read
## TurnResult.rejected to decide whether to animate the bounce-back, and
## TurnResult.win / TurnResult.fail to transition screens.
func attempt_swap(cell_a: Vector2i, cell_b: Vector2i) -> TurnResult:
	var result := TurnResult.new()

	# ── 1. Guard: both cells in bounds and active ──────────────────────────
	if not board.is_in_bounds(cell_a.x, cell_a.y) \
			or not board.is_in_bounds(cell_b.x, cell_b.y):
		result.rejected = true
		return result

	var cs_a: BoardState.CellState = board.get_cell(cell_a.x, cell_a.y)
	var cs_b: BoardState.CellState = board.get_cell(cell_b.x, cell_b.y)

	if not cs_a.active or not cs_b.active:
		result.rejected = true
		return result

	# ── 2. Guard: two specials cannot be swapped (spec §5.1) ──────────────
	if cs_a.is_special and cs_b.is_special:
		result.rejected = true
		return result

	# ── 3. Guard: swap must be orthogonally adjacent ───────────────────────
	var row_diff: int = abs(cell_a.x - cell_b.x)
	var col_diff: int = abs(cell_a.y - cell_b.y)
	if not (row_diff + col_diff == 1):
		result.rejected = true
		return result

	# ── 4. Guard: at least one cell must hold a piece ─────────────────────
	if not cs_a.has_piece() or not cs_b.has_piece():
		result.rejected = true
		return result

	# ── 5. Guard: swap must create a match unless a special is involved ────
	# Special piece activation is always a valid move (the special fires
	# regardless of whether a crop match forms). For two normal pieces, the
	# swap must produce at least one match.
	var either_special: bool = cs_a.is_special or cs_b.is_special
	if not either_special:
		if not _match_finder.would_swap_create_match(board, cell_a, cell_b):
			result.rejected = true
			return result

	# ── 6. Execute swap ────────────────────────────────────────────────────
	board.swap_pieces(cell_a, cell_b)

	# Re-read cell states post-swap.
	# post_a = piece that MOVED INTO cell_a (was previously at cell_b).
	# post_b = piece that MOVED INTO cell_b (was previously at cell_a).
	var post_a: BoardState.CellState = board.get_cell(cell_a.x, cell_a.y)
	var post_b: BoardState.CellState = board.get_cell(cell_b.x, cell_b.y)

	# Track total points and seeds for this turn.
	var turn_points: int = 0
	var turn_seeds:  int = 0

	# Accumulate all newly-completed goal indices across the whole turn.
	var all_newly_done: Array[int] = []

	# ── 7. Resolve any special piece activations ───────────────────────────
	# Spec §5.2: activation fires when a special piece is included in a valid
	# swap. The effect resolves before gravity and refill run.
	#
	# After the swap:
	#   - cell_a holds what was in cell_b before the swap.
	#   - cell_b holds what was in cell_a before the swap.
	# So post_a is the piece that moved INTO cell_a (was at cell_b),
	# and post_b is the piece that moved INTO cell_b (was at cell_a).
	#
	# We activate whichever cell now holds the special. The swap_partner is
	# the other cell (the crop the special was swapped with).

	# Cells cleared by special activations this turn.
	var special_cleared: Array[Vector2i] = []

	# The special piece moved INTO cell_a came FROM cell_b, so the swap partner
	# (the crop it was swapped with) is now sitting at cell_b, and vice-versa.
	# SpecialPieceHandler.resolve() reads the partner cell to find the target crop
	# (Scarecrow), so we pass the cell that currently holds the partner crop.
	if post_a.is_special:
		var cr: SpecialPieceHandler.ClearResult = _special_handler.resolve(
			board, cell_a, cell_b, balance
		)
		if cr != null:
			for coord in cr.cells:
				if coord not in special_cleared:
					special_cleared.append(coord)
			turn_seeds  += cr.seeds_earned
			turn_points += _score_calculator.calculate_special_activation_score(
				balance, level_data.score_overrides
			)

	if post_b.is_special:
		# The special at cell_b came from cell_a; its swap partner crop is at cell_a.
		var cr: SpecialPieceHandler.ClearResult = _special_handler.resolve(
			board, cell_b, cell_a, balance
		)
		if cr != null:
			for coord in cr.cells:
				if coord not in special_cleared:
					special_cleared.append(coord)
			turn_seeds  += cr.seeds_earned
			turn_points += _score_calculator.calculate_special_activation_score(
				balance, level_data.score_overrides
			)

	# ── 8. Resolve normal matches ──────────────────────────────────────────
	# Only run normal match detection when no special piece activated.
	# When a special activates, its effect IS the mechanic for this swap —
	# no separate crop match is formed from the same move.
	#
	# The board is already in post-swap state. find_matches_for_swap() does its
	# own internal swap+restore, which would double-swap back to the original
	# layout and find nothing. Instead call find_matches() directly on the
	# already-swapped board, then stamp cell_a as the swap_origin on each result
	# so special-piece spawn positions are recorded correctly.
	var match_results: Array = []
	if special_cleared.is_empty():
		match_results = _match_finder.find_matches(board)
		for mr in match_results:
			var _mr: MatchFinder.MatchResult = mr
			# find_matches() never knows the real swap cell — it always falls back
			# to shape_cells[0] (topmost-leftmost cell of the match).  Unconditionally
			# override swap_origin with cell_a so special pieces always spawn at the
			# cell the player actually moved, regardless of which end the scanner
			# happened to anchor the shape on.
			_mr.swap_origin = cell_a

	# Cells cleared by normal matches (unique set).
	var match_cleared: Array[Vector2i] = []

	# Cells where special pieces should spawn (swap origin of special-spawning matches).
	# Stored as Array of {cell, type, orientation} so we can spawn after clearing.
	var spawns: Array[Dictionary] = []

	for mr in match_results:
		var match_result: MatchFinder.MatchResult = mr
		# Accumulate base match score (cascade_level 0 = player-initiated).
		turn_points += _score_calculator.calculate_match_score(
			match_result, balance, level_data.score_overrides, 0
		)
		for coord in match_result.cells:
			if coord not in match_cleared:
				match_cleared.append(coord)
		if match_result.spawns_special:
			spawns.append({
				"cell":        match_result.swap_origin,
				"type":        match_result.special_type,
				"orientation": match_result.orientation,
			})

	# ── 9. Merge all cells to clear this step ─────────────────────────────
	var all_cleared: Array[Vector2i] = []
	for coord in special_cleared:
		all_cleared.append(coord)
	for coord in match_cleared:
		if coord not in all_cleared:
			all_cleared.append(coord)

	# ── 10. Build piece-info list for GoalTracker before clearing ─────────
	var cleared_pieces: Array = _piece_infos_for_coords(all_cleared)

	# ── 11. Process obstacle adjacency (dirt / flower) ────────────────────
	_process_obstacle_adjacency(all_cleared)

	# ── 12. Clear pieces from the board ───────────────────────────────────
	for coord in all_cleared:
		var cs: BoardState.CellState = board.get_cell(coord.x, coord.y)
		if cs.has_piece():
			board.clear_piece(coord.x, coord.y)

	# ── 13. Spawn special pieces ───────────────────────────────────────────
	# Spec §5.1: spawns at the swap-origin cell of the qualifying match.
	for spawn in spawns:
		var sc: Vector2i = spawn["cell"]
		if not board.is_in_bounds(sc.x, sc.y):
			continue
		var spawn_cs: BoardState.CellState = board.get_cell(sc.x, sc.y)
		# Only spawn if the cell can currently hold a piece (it was cleared above).
		if spawn_cs.can_hold_piece():
			board.place_piece(sc.x, sc.y, spawn["type"], true, spawn["orientation"])

	# ── 14. Apply gravity + refill ─────────────────────────────────────────
	var gravity_result: GravitySystem.GravityResult = _gravity_system.calculate(
		board, level_data, _collected, rng
	)
	_apply_gravity_result(gravity_result)

	# ── 15. Update collected counts and notify GoalTracker ─────────────────
	_update_collected(cleared_pieces)
	var newly_done := goal_tracker.notify_pieces_cleared(cleared_pieces)
	for idx in newly_done:
		if idx not in all_newly_done:
			all_newly_done.append(idx)

	# Update score on board and notify score goal.
	board.score += turn_points
	board.seeds_earned += turn_seeds
	var score_done := goal_tracker.notify_score_updated(board.score)
	for idx in score_done:
		if idx not in all_newly_done:
			all_newly_done.append(idx)

	# Notify obstacle state.
	var obs_done := goal_tracker.notify_obstacles_updated(
		board.count_dirt(), board.count_flowers()
	)
	for idx in obs_done:
		if idx not in all_newly_done:
			all_newly_done.append(idx)

	# ── 16. Cascade loop ───────────────────────────────────────────────────
	var cascade_level: int = 0
	var cascade_matches: Array = _match_finder.find_matches(board)

	while not cascade_matches.is_empty():
		cascade_level += 1
		result.cascade_levels = cascade_level

		var cascade_cleared: Array[Vector2i] = []
		var cascade_spawns:  Array[Dictionary] = []
		var cascade_points:  int = 0

		for mr in cascade_matches:
			var match_result: MatchFinder.MatchResult = mr
			cascade_points += _score_calculator.calculate_match_score(
				match_result, balance, level_data.score_overrides, cascade_level
			)
			for coord in match_result.cells:
				if coord not in cascade_cleared:
					cascade_cleared.append(coord)
			if match_result.spawns_special:
				cascade_spawns.append({
					"cell":        match_result.swap_origin,
					"type":        match_result.special_type,
					"orientation": match_result.orientation,
				})

		var cascade_piece_infos: Array = _piece_infos_for_coords(cascade_cleared)
		_process_obstacle_adjacency(cascade_cleared)

		for coord in cascade_cleared:
			var cs: BoardState.CellState = board.get_cell(coord.x, coord.y)
			if cs.has_piece():
				board.clear_piece(coord.x, coord.y)

		for spawn in cascade_spawns:
			var sc: Vector2i = spawn["cell"]
			if not board.is_in_bounds(sc.x, sc.y):
				continue
			var spawn_cs: BoardState.CellState = board.get_cell(sc.x, sc.y)
			if spawn_cs.can_hold_piece():
				board.place_piece(sc.x, sc.y, spawn["type"], true, spawn["orientation"])

		var cascade_gravity: GravitySystem.GravityResult = _gravity_system.calculate(
			board, level_data, _collected, rng
		)
		_apply_gravity_result(cascade_gravity)

		turn_points += cascade_points
		_update_collected(cascade_piece_infos)

		var c_pieces_done := goal_tracker.notify_pieces_cleared(cascade_piece_infos)
		for idx in c_pieces_done:
			if idx not in all_newly_done:
				all_newly_done.append(idx)

		board.score += cascade_points
		# seeds_earned not incremented — seeds only come from special activations, not matches

		var c_score_done := goal_tracker.notify_score_updated(board.score)
		for idx in c_score_done:
			if idx not in all_newly_done:
				all_newly_done.append(idx)

		var c_obs_done := goal_tracker.notify_obstacles_updated(
			board.count_dirt(), board.count_flowers()
		)
		for idx in c_obs_done:
			if idx not in all_newly_done:
				all_newly_done.append(idx)

		# Check for further cascades.
		cascade_matches = _match_finder.find_matches(board)

	# ── 17. Decrement turn ─────────────────────────────────────────────────
	board.turns_remaining -= 1

	# ── 18. Populate TurnResult ────────────────────────────────────────────
	result.accepted              = true
	result.points_earned         = turn_points
	result.seeds_earned          = turn_seeds
	result.newly_completed_goals = all_newly_done

	if goal_tracker.all_goals_complete():
		result.win = true
	elif board.turns_remaining <= 0:
		result.fail = true

	return result


# ── Private helpers ───────────────────────────────────────────────────────────

## Applies a GravityResult to the board by mutating piece positions.
## Moves are applied first (bottom-to-top order from GravityResult guarantees
## no piece overwrites another), then fills.
func _apply_gravity_result(gr: GravitySystem.GravityResult) -> void:
	for mv in gr.moves:
		var from: Vector2i = mv["from"]
		var to:   Vector2i = mv["to"]
		board.place_piece(to.x, to.y, mv["piece"], mv["is_special"], mv["orientation"])
		board.clear_piece(from.x, from.y)

	for fill in gr.fills:
		var cell: Vector2i = fill["cell"]
		board.place_piece(cell.x, cell.y, fill["piece"], false, "")


## Builds an Array of {"crop": String} Dictionaries for all cells in `coords`
## that currently hold a piece. Called BEFORE the cells are cleared so the
## piece identifiers are still present.
func _piece_infos_for_coords(coords: Array[Vector2i]) -> Array:
	var infos: Array = []
	for coord in coords:
		var cs: BoardState.CellState = board.get_cell(coord.x, coord.y)
		if cs.has_piece():
			infos.append({"crop": cs.piece})
	return infos


## Processes dirt and flower obstacle interactions for a set of cleared cells.
##
## Spec §3.3 dirt: "Cleared when a match is made that includes or is
##   orthogonally adjacent to that cell."
## Spec §3.3 flower: "Each orthogonally adjacent match reduces HP by 1."
##
## For every cleared coordinate, check the cell itself and its four orthogonal
## neighbours:
##   - If the cell (or neighbour) has dirt: clear it.
##   - If the cell (or neighbour) has a flower: apply one hit.
##
## A flower or dirt cell that is itself in the cleared set is treated as
## "included in the match" and also triggers the adjacency logic for its own
## neighbours.
func _process_obstacle_adjacency(cleared_coords: Array[Vector2i]) -> void:
	# Build a set of all cells that should be checked (cleared cells + their
	# orthogonal neighbours).
	var to_check: Dictionary = {}  # Vector2i → true

	for coord in cleared_coords:
		to_check[coord] = true
		for neighbour in board.get_orthogonal_neighbors(coord.x, coord.y):
			to_check[neighbour] = true

	# Dirt: clear on first hit. Flower: apply one hit per clearing event,
	# but cap at one hit per flower per call to avoid double-counting when
	# multiple cleared cells are adjacent to the same flower.
	var flowers_hit: Dictionary = {}  # Vector2i → true (already hit this call)

	for coord in to_check.keys():
		var cs: BoardState.CellState = board.get_cell(coord.x, coord.y)
		if cs.obstacle == BoardState.OBSTACLE_DIRT:
			board.clear_dirt(coord.x, coord.y)
		elif cs.obstacle == BoardState.OBSTACLE_FLOWER:
			if not flowers_hit.has(coord):
				board.hit_flower(coord.x, coord.y)
				flowers_hit[coord] = true


## Increments the _collected counts for each piece in a cleared-piece info list.
## Only non-special crop strings advance the count (special identifiers never
## match crop goal targets, but we track them here for completeness anyway —
## GoalTracker ignores non-matching strings itself).
func _update_collected(piece_infos: Array) -> void:
	for info in piece_infos:
		var crop: String = info.get("crop", "")
		if crop != "":
			_collected[crop] = _collected.get(crop, 0) + 1
