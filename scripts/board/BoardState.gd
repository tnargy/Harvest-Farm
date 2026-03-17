class_name BoardState
extends RefCounted

## BoardState.gd
## Authoritative in-memory representation of the 8×8 board for one level run.
## Holds the grid of CellState objects plus run-level counters (turns, score,
## seeds earned). Contains NO match logic, gravity, or scoring — pure data and
## structural accessors only.

# ── Constants ─────────────────────────────────────────────────────────────────

const GRID_SIZE       := 8
const OBSTACLE_NONE   := "none"
const OBSTACLE_ROCK   := "rock"
const OBSTACLE_DIRT   := "dirt"
const OBSTACLE_FLOWER := "flower"

# ── CellState ─────────────────────────────────────────────────────────────────

class CellState:
	## Whether this cell participates in gameplay.
	## false = hole: no piece, cannot be targeted, pieces cannot fall through.
	var active: bool = true

	## Obstacle occupying this cell.
	## One of: "none", "rock", "dirt", "flower"
	## Rocks and flowers prevent a normal piece from occupying the cell.
	## Dirt underlays a piece — both coexist in the same cell.
	var obstacle: String = "none"

	## Current HP of a flower obstacle (1–3). 0 when no flower is present.
	## Wilted = 3, Budding = 2, Blooming = 1, Cleared = 0 (obstacle removed).
	var flower_hp: int = 0

	## Crop or special-piece identifier string occupying this cell.
	## Empty string means the cell is vacant (waiting for gravity/refill).
	## Rocks and flowers always have piece == "".
	var piece: String = ""

	## True when the piece in this cell is a special piece
	## (bushel_basket, scarecrow, watering_can, wheelbarrow).
	var is_special: bool = false

	## Orientation the Bushel Basket was created with.
	## "horizontal" → clears row on activation.
	## "vertical"   → clears column on activation.
	## Only meaningful when piece == "bushel_basket"; "" otherwise.
	var special_orientation: String = ""

	# ── CellState helpers ──────────────────────────────────────────────────

	## True when this cell can hold a piece (active, not a rock, not a flower).
	func can_hold_piece() -> bool:
		return active and obstacle != OBSTACLE_ROCK and obstacle != OBSTACLE_FLOWER

	## True when this cell is active, holds no piece, and is not occupied by a
	## rock or flower obstacle. Rocks and flowers fully occupy their cell even
	## though piece == "" — the cell is not available for gameplay.
	func is_empty() -> bool:
		return active and piece == "" and obstacle != OBSTACLE_ROCK and obstacle != OBSTACLE_FLOWER

	## True when this cell has a piece (crop or special) sitting on it.
	func has_piece() -> bool:
		return active and piece != ""

	## Returns a debug-friendly one-line description.
	func debug_string() -> String:
		if not active:
			return "[hole]"
		var obs := "" if obstacle == "none" else ("|%s%s" % [
			obstacle,
			("(%d)" % flower_hp) if obstacle == OBSTACLE_FLOWER else ""
		])
		var pc := "" if piece == "" else (" piece=%s%s%s" % [
			piece,
			"(special)" if is_special else "",
			("[%s]" % special_orientation) if special_orientation != "" else ""
		])
		return "[active%s%s]" % [obs, pc]


# ── BoardState fields ─────────────────────────────────────────────────────────

## The 8×8 grid. Indexed as cells[row][col], row 0 = top, col 0 = left.
var cells: Array = []   # Array[Array[CellState]], built in init_from_level

## Turn limit copied from LevelData at init. Never changes after init.
var turn_limit: int = 0

## Turns the player has remaining. Decremented by BoardController each turn.
var turns_remaining: int = 0

## Accumulated score for this run.
var score: int = 0

## Seeds earned during this run (from special piece activations).
## Handed off to the save system when the run ends.
var seeds_earned: int = 0


# ── Initialisation ────────────────────────────────────────────────────────────

## Populates the board from a LevelData resource.
## Assumes level_data has already passed LevelData.validate() with no errors.
## Returns an Array[String] of any non-fatal warnings encountered during init
## (e.g. a starting_piece placed on a cell that can't hold one). An empty array
## means init completed cleanly.
func init_from_level(level_data: LevelData) -> Array[String]:
	var warnings: Array[String] = []

	turn_limit       = level_data.turn_limit
	turns_remaining  = level_data.turn_limit
	score            = 0
	seeds_earned     = 0

	cells = []

	for row in range(GRID_SIZE):
		var row_array: Array = []

		for col in range(GRID_SIZE):
			var cell_def: Dictionary = level_data.grid_layout[row][col]
			var cs := CellState.new()

			# ── active / hole ──
			cs.active = cell_def.get("active", true)

			if not cs.active:
				# Hole — everything else stays at defaults (empty, no obstacle).
				row_array.append(cs)
				continue

			# ── obstacle ──
			var obs: String = cell_def.get("obstacle", OBSTACLE_NONE)
			cs.obstacle = obs

			if obs == OBSTACLE_FLOWER:
				cs.flower_hp = cell_def.get("flower_hp", 3)

			# ── starting piece override ──
			var sp: String = cell_def.get("starting_piece", "")
			if sp != "":
				if not cs.can_hold_piece():
					warnings.append(
						"init_from_level: grid_layout[%d][%d] has starting_piece '%s' " \
						+ "but cell cannot hold a piece (obstacle='%s'). Ignored." \
						% [row, col, sp, obs]
					)
				else:
					# Detect whether the starting piece is a special piece.
					var special_types := ["bushel_basket", "scarecrow", "watering_can", "wheelbarrow"]
					cs.piece             = sp
					cs.is_special        = sp in special_types
					cs.special_orientation = ""  # orientation set at spawn time by BoardController

			row_array.append(cs)

		cells.append(row_array)

	return warnings


# ── Accessors ─────────────────────────────────────────────────────────────────

## Returns the CellState at (row, col).
## Caller must ensure coordinates are in-bounds (use is_in_bounds first).
func get_cell(row: int, col: int) -> CellState:
	return cells[row][col]


## Returns true when (row, col) is within the 8×8 grid.
func is_in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < GRID_SIZE and col >= 0 and col < GRID_SIZE


## Returns the four orthogonal neighbours of (row, col) that are both
## in-bounds AND active. Holes are excluded — the spec says holes cannot
## be targeted by any mechanic and pieces cannot interact through them.
func get_orthogonal_neighbors(row: int, col: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var offsets: Array[Vector2i] = [
		Vector2i(-1,  0),  # up
		Vector2i( 1,  0),  # down
		Vector2i( 0, -1),  # left
		Vector2i( 0,  1),  # right
	]
	for offset in offsets:
		var nr: int = row + offset.x
		var nc: int = col + offset.y
		if is_in_bounds(nr, nc) and cells[nr][nc].active:
			result.append(Vector2i(nr, nc))
	return result


# ── Board-wide queries ────────────────────────────────────────────────────────

## Returns all active cell coordinates as an Array[Vector2i].
func get_all_active_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if cells[row][col].active:
				result.append(Vector2i(row, col))
	return result


## Returns coordinates of all active cells whose obstacle == target_obstacle.
func get_cells_with_obstacle(target_obstacle: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cs: CellState = cells[row][col]
			if cs.active and cs.obstacle == target_obstacle:
				result.append(Vector2i(row, col))
	return result


## Returns the count of active cells that have piece != "".
func count_pieces() -> int:
	var n := 0
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if cells[row][col].has_piece():
				n += 1
	return n


## Returns the count of active cells that currently have no piece and can
## accept one (i.e. can_hold_piece() is true and piece == "").
func count_empty_fillable_cells() -> int:
	var n := 0
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cs: CellState = cells[row][col]
			if cs.can_hold_piece() and cs.piece == "":
				n += 1
	return n


## Returns true when every dirt-patch cell has been cleared (none remain).
func all_dirt_cleared() -> bool:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if cells[row][col].obstacle == OBSTACLE_DIRT:
				return false
	return true


## Returns true when every flower cell has been cleared (none remain).
func all_flowers_cleared() -> bool:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if cells[row][col].obstacle == OBSTACLE_FLOWER:
				return false
	return true


## Returns the count of remaining dirt-patch cells.
func count_dirt() -> int:
	return get_cells_with_obstacle(OBSTACLE_DIRT).size()


## Returns the count of remaining flower cells.
func count_flowers() -> int:
	return get_cells_with_obstacle(OBSTACLE_FLOWER).size()


# ── Mutation helpers (called by BoardController only) ─────────────────────────

## Places a piece on the cell at (row, col).
## Does not validate — BoardController is responsible for pre-checking.
func place_piece(row: int, col: int, piece_id: String, is_special_piece: bool = false, orientation: String = "") -> void:
	var cs: CellState = cells[row][col]
	cs.piece              = piece_id
	cs.is_special         = is_special_piece
	cs.special_orientation = orientation


## Removes the piece from the cell at (row, col), leaving the cell vacant.
func clear_piece(row: int, col: int) -> void:
	var cs: CellState = cells[row][col]
	cs.piece               = ""
	cs.is_special          = false
	cs.special_orientation = ""


## Clears the dirt obstacle from the cell at (row, col).
## Only valid when obstacle == "dirt"; silently no-ops otherwise to keep
## callers simple.
func clear_dirt(row: int, col: int) -> void:
	var cs: CellState = cells[row][col]
	if cs.obstacle == OBSTACLE_DIRT:
		cs.obstacle = OBSTACLE_NONE


## Applies one hit to the flower at (row, col).
## Decrements flower_hp by 1. When HP reaches 0, clears the flower obstacle
## entirely. Returns the new HP (0 = cleared).
func hit_flower(row: int, col: int) -> int:
	var cs: CellState = cells[row][col]
	if cs.obstacle != OBSTACLE_FLOWER:
		return 0
	cs.flower_hp -= 1
	if cs.flower_hp <= 0:
		cs.flower_hp = 0
		cs.obstacle  = OBSTACLE_NONE
	return cs.flower_hp


## Swaps the pieces (and their special flags/orientations) between two cells.
## Does not validate legality — BoardController handles that.
func swap_pieces(a: Vector2i, b: Vector2i) -> void:
	var ca: CellState = cells[a.x][a.y]
	var cb: CellState = cells[b.x][b.y]

	var tmp_piece       := ca.piece
	var tmp_special     := ca.is_special
	var tmp_orientation := ca.special_orientation

	ca.piece              = cb.piece
	ca.is_special         = cb.is_special
	ca.special_orientation = cb.special_orientation

	cb.piece              = tmp_piece
	cb.is_special         = tmp_special
	cb.special_orientation = tmp_orientation


# ── Test helpers ──────────────────────────────────────────────────────────────

## Creates a blank 8×8 board with all cells active and no obstacles.
## Useful for unit tests that need precise piece placement without a LevelData.
func init_empty() -> void:
	turn_limit      = 0
	turns_remaining = 0
	score           = 0
	seeds_earned    = 0
	cells           = []
	for row in range(GRID_SIZE):
		var row_array: Array = []
		for col in range(GRID_SIZE):
			row_array.append(CellState.new())
		cells.append(row_array)


## Populates pieces from an 8-element Array of Strings, each exactly 8
## characters long. One character per cell:
##   '.' → empty
##   'X' → hole (inactive)
##   'R' → rock obstacle (no piece)
##   'F' → flower obstacle, full HP=3 (no piece)
##   'D' → dirt obstacle (no piece — use lowercase for dirt+piece)
##   Any other character → crop piece whose identifier equals the char
##                         (single-char shorthand; tests map these manually)
##
## Piece identifiers longer than one character can be set directly via
## place_piece() after calling fill_from_strings().
##
## Example:
##   board.fill_from_strings([
##     "........",
##     "...aaa..",   # 'a' → piece id "a" at (1,3),(1,4),(1,5)
##     "........",
##     ...
##   ])
func fill_from_strings(rows: Array) -> void:
	for row in range(GRID_SIZE):
		var s: String = rows[row]
		for col in range(GRID_SIZE):
			var ch: String = s[col]
			var cs: CellState = cells[row][col]
			# Reset to defaults first.
			cs.active             = true
			cs.obstacle           = OBSTACLE_NONE
			cs.flower_hp          = 0
			cs.piece              = ""
			cs.is_special         = false
			cs.special_orientation = ""

			match ch:
				".":
					pass  # active, empty, no obstacle
				"X":
					cs.active = false
				"R":
					cs.obstacle = OBSTACLE_ROCK
				"F":
					cs.obstacle  = OBSTACLE_FLOWER
					cs.flower_hp = 3
				"D":
					cs.obstacle = OBSTACLE_DIRT
				_:
					cs.piece = ch


# ── Debug ─────────────────────────────────────────────────────────────────────

## Prints a compact ASCII representation of the board to the output log.
## Useful during development and test runs.
func debug_print() -> void:
	print("BoardState  turns=%d/%d  score=%d  seeds=%d" \
		% [turns_remaining, turn_limit, score, seeds_earned])
	print("    01234567")
	for row in range(GRID_SIZE):
		var line := "%d   " % row
		for col in range(GRID_SIZE):
			var cs: CellState = cells[row][col]
			if not cs.active:
				line += "X"
			elif cs.obstacle == OBSTACLE_ROCK:
				line += "R"
			elif cs.obstacle == OBSTACLE_FLOWER:
				line += "F"
			elif cs.obstacle == OBSTACLE_DIRT:
				if cs.piece != "":
					line += "d"   # dirt with a piece on top
				else:
					line += "D"   # bare dirt
			elif cs.piece != "":
				if cs.is_special:
					line += "S"
				else:
					line += cs.piece[0].to_upper()
			else:
				line += "."
		print(line)
