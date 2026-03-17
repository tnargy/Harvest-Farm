class_name SpecialPieceHandler
extends RefCounted

## SpecialPieceHandler.gd
## Pure calculation layer for special piece activation effects.
## Given a BoardState snapshot and activation context, returns a ClearResult
## describing which cells to clear and how many seeds are earned.
##
## No board mutation occurs here — BoardController is responsible for acting
## on the returned ClearResult. This class holds no state between calls.


# ── ClearResult ───────────────────────────────────────────────────────────────

class ClearResult:
	## All cell coordinates that should be cleared as a result of this
	## activation. Coordinates are unique (no duplicates). Includes the cell
	## occupied by the special piece itself.
	var cells: Array[Vector2i] = []

	## Seeds earned from this activation, sourced from balance.tres.
	var seeds_earned: int = 0

	## The special piece type that produced this result.
	## One of: "bushel_basket", "scarecrow", "watering_can", "wheelbarrow"
	var special_type: String = ""

	func _init(
		p_cells: Array[Vector2i],
		p_seeds: int,
		p_type: String
	) -> void:
		cells        = p_cells
		seeds_earned = p_seeds
		special_type = p_type


# ── Public API ────────────────────────────────────────────────────────────────

## Resolves a special piece activation and returns a ClearResult.
##
## Parameters:
##   board        – Current BoardState (read-only; this method never mutates it).
##   special_pos  – Grid position (row, col) of the special piece being activated.
##   swap_partner – Grid position of the piece the special was swapped with.
##                  Required for Scarecrow (determines target crop type).
##                  Ignored for all other piece types.
##   balance      – Loaded Balance resource for seed reward constants.
##
## Returns a ClearResult, or null with a push_error if the cell at special_pos
## does not hold a recognised special piece.
func resolve(
	board: BoardState,
	special_pos: Vector2i,
	swap_partner: Vector2i,
	balance: Balance
) -> ClearResult:
	var cs: BoardState.CellState = board.get_cell(special_pos.x, special_pos.y)

	match cs.piece:
		"bushel_basket":
			return _resolve_bushel_basket(board, special_pos, balance)
		"scarecrow":
			return _resolve_scarecrow(board, special_pos, swap_partner, balance)
		"watering_can":
			return _resolve_watering_can(board, special_pos, balance)
		"wheelbarrow":
			return _resolve_wheelbarrow(board, special_pos, balance)
		_:
			push_error(
				"SpecialPieceHandler.resolve: cell at (%d,%d) does not hold a "
				+ "recognised special piece (piece='%s')."
				% [special_pos.x, special_pos.y, cs.piece]
			)
			return null


# ── Bushel Basket ─────────────────────────────────────────────────────────────

## Clears the entire row (horizontal orientation) or entire column
## (vertical orientation) that the Bushel Basket occupies.
## Orientation is read from CellState.special_orientation, which is set at
## spawn time by BoardController and stored in the piece's cell.
##
## Spec §5.2:
##   "Clears all pieces in either the row or the column it occupies,
##    determined by match orientation: horizontal match → clears row;
##    vertical match → clears column."
##
## Only active cells are included; holes are excluded.
func _resolve_bushel_basket(
	board: BoardState,
	pos: Vector2i,
	balance: Balance
) -> ClearResult:
	var cs: BoardState.CellState = board.get_cell(pos.x, pos.y)
	var orientation: String = cs.special_orientation
	var result_cells: Array[Vector2i] = []

	if orientation == "horizontal":
		# Clear every active cell in the same row.
		for col in range(BoardState.GRID_SIZE):
			if board.is_in_bounds(pos.x, col) and board.get_cell(pos.x, col).active:
				result_cells.append(Vector2i(pos.x, col))
	else:
		# "vertical" (or unset — fall back to column to avoid silent no-ops).
		# Clear every active cell in the same column.
		for row in range(BoardState.GRID_SIZE):
			if board.is_in_bounds(row, pos.y) and board.get_cell(row, pos.y).active:
				result_cells.append(Vector2i(row, pos.y))

	return ClearResult.new(
		result_cells,
		balance.SEED_REWARD_SPECIAL_BUSHEL,
		"bushel_basket"
	)


# ── Scarecrow ─────────────────────────────────────────────────────────────────

## Clears all pieces on the board that share the same crop type as the piece
## the Scarecrow was swapped with (the swap partner).
##
## Spec §5.2:
##   "Clears all pieces on the board that share the same crop type as the
##    piece it was swapped with."
##
## The Scarecrow cell itself is included in the cleared set (it is consumed).
## If the swap partner cell is empty, inactive, or holds a special piece,
## no additional cells beyond the Scarecrow itself are cleared and a warning
## is pushed — this represents a logic error by the caller.
func _resolve_scarecrow(
	board: BoardState,
	pos: Vector2i,
	swap_partner: Vector2i,
	balance: Balance
) -> ClearResult:
	var result_cells: Array[Vector2i] = []

	# Determine target crop type from the swap partner.
	var target_crop: String = ""
	if board.is_in_bounds(swap_partner.x, swap_partner.y):
		var partner_cs: BoardState.CellState = board.get_cell(swap_partner.x, swap_partner.y)
		# The swap has already occurred before resolve() is called, so the
		# partner cell now holds the Scarecrow and the Scarecrow cell holds
		# what was the partner. We need the original partner crop.
		# BoardController swaps first, then calls resolve() — see note below.
		#
		# IMPORTANT: BoardController calls resolve() BEFORE committing the swap
		# on the board, passing the pre-swap partner position. At that point the
		# partner cell still holds the original crop. If the partner cell holds
		# a non-special crop, that is the target.
		if not partner_cs.is_special and partner_cs.piece != "":
			target_crop = partner_cs.piece
		else:
			push_warning(
				"SpecialPieceHandler._resolve_scarecrow: swap partner at "
				+ "(%d,%d) does not hold a normal crop (piece='%s', is_special=%s). "
				+ "No crop-type sweep will occur."
				% [swap_partner.x, swap_partner.y, partner_cs.piece, str(partner_cs.is_special)]
			)
	else:
		push_warning(
			"SpecialPieceHandler._resolve_scarecrow: swap_partner (%d,%d) is "
			+ "out of bounds. No crop-type sweep will occur."
			% [swap_partner.x, swap_partner.y]
		)

	# Always include the Scarecrow's own cell.
	result_cells.append(pos)

	# Sweep the board for all cells holding the target crop type.
	if target_crop != "":
		for row in range(BoardState.GRID_SIZE):
			for col in range(BoardState.GRID_SIZE):
				var coord := Vector2i(row, col)
				if coord == pos:
					continue  # already added above
				var cell: BoardState.CellState = board.get_cell(row, col)
				if cell.active and cell.piece == target_crop and not cell.is_special:
					result_cells.append(coord)

	return ClearResult.new(
		result_cells,
		balance.SEED_REWARD_SPECIAL_SCARECROW,
		"scarecrow"
	)


# ── Watering Can ──────────────────────────────────────────────────────────────

## Clears all pieces in the 3×3 area centred on the Watering Can's cell.
## The region is clamped to the board boundaries — at an edge or corner, only
## in-bound cells are included. Only active cells are included.
##
## Spec §5.2:
##   "Clears all pieces in the 3×3 area centered on the cell it occupies
##    at activation."
func _resolve_watering_can(
	board: BoardState,
	pos: Vector2i,
	balance: Balance
) -> ClearResult:
	var result_cells: Array[Vector2i] = []

	# Clamp the 3×3 window to board boundaries.
	var row_min: int = clampi(pos.x - 1, 0, BoardState.GRID_SIZE - 1)
	var row_max: int = clampi(pos.x + 1, 0, BoardState.GRID_SIZE - 1)
	var col_min: int = clampi(pos.y - 1, 0, BoardState.GRID_SIZE - 1)
	var col_max: int = clampi(pos.y + 1, 0, BoardState.GRID_SIZE - 1)

	for row in range(row_min, row_max + 1):
		for col in range(col_min, col_max + 1):
			if board.get_cell(row, col).active:
				result_cells.append(Vector2i(row, col))

	return ClearResult.new(
		result_cells,
		balance.SEED_REWARD_SPECIAL_WATERING_CAN,
		"watering_can"
	)


# ── Wheelbarrow ───────────────────────────────────────────────────────────────

## Clears the entire row AND entire column the Wheelbarrow occupies (full
## cross pattern). The cell at the intersection is included once only.
##
## Spec §5.2:
##   "Clears the entire row AND entire column it occupies at activation
##    (full cross pattern)."
##
## Only active cells are included; holes are excluded.
func _resolve_wheelbarrow(
	board: BoardState,
	pos: Vector2i,
	balance: Balance
) -> ClearResult:
	# Use a dictionary keyed by Vector2i to deduplicate the intersection cell.
	var seen: Dictionary = {}

	# Entire row.
	for col in range(BoardState.GRID_SIZE):
		if board.is_in_bounds(pos.x, col) and board.get_cell(pos.x, col).active:
			var coord := Vector2i(pos.x, col)
			seen[coord] = true

	# Entire column.
	for row in range(BoardState.GRID_SIZE):
		if board.is_in_bounds(row, pos.y) and board.get_cell(row, pos.y).active:
			var coord := Vector2i(row, pos.y)
			seen[coord] = true

	var result_cells: Array[Vector2i] = []
	for coord in seen.keys():
		result_cells.append(coord)

	return ClearResult.new(
		result_cells,
		balance.SEED_REWARD_SPECIAL_WHEELBARROW,
		"wheelbarrow"
	)
