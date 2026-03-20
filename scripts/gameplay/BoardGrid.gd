class_name BoardGrid
extends Control

## BoardGrid.gd
## Manages the visual 8×8 board.
## - Builds background cell tiles on setup.
## - Creates/destroys PieceNode children as the board changes.
## - Orchestrates all Tween-based animations (swap, bounce, clear, fall, drop-in).

const GRID_SIZE  := 8
const CELL_SIZE  := 48
const CELL_GAP   := 2
const CELL_STEP  := CELL_SIZE + CELL_GAP
const BOARD_SIZE := CELL_STEP * GRID_SIZE

const PIECE_NODE_SCENE := preload("res://scenes/gameplay/PieceNode.tscn")

const BG_CELL_COLOR_A := Color("3D5A2A")   # dark green
const BG_CELL_COLOR_B := Color("355226")   # slightly darker green (checkerboard)

@onready var _cell_layer:  Control = $CellLayer
@onready var _piece_layer: Control = $PieceLayer

## Vector2i → PieceNode. Only active cells with a piece have an entry.
var _pieces: Dictionary = {}

# ── Setup ─────────────────────────────────────────────────────────────────────

## Full initial build from a BoardState. Non-animated.
func setup(board_state: BoardState) -> void:
	_build_cell_layer(board_state)
	_build_piece_layer(board_state)


func _build_cell_layer(board_state: BoardState) -> void:
	for child in _cell_layer.get_children():
		child.queue_free()

	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cs: BoardState.CellState = board_state.get_cell(row, col)
			if not cs.active:
				continue
			var rect := ColorRect.new()
			rect.position = _cell_pos(row, col)
			rect.size     = Vector2(CELL_SIZE, CELL_SIZE)
			rect.color    = BG_CELL_COLOR_A if (row + col) % 2 == 0 else BG_CELL_COLOR_B
			_cell_layer.add_child(rect)


func _build_piece_layer(board_state: BoardState) -> void:
	for child in _piece_layer.get_children():
		child.queue_free()
	_pieces.clear()

	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cs: BoardState.CellState = board_state.get_cell(row, col)
			if not cs.active:
				continue
			if cs.obstacle == "rock":
				_spawn_piece_node(row, col, cs)
				continue
			if cs.obstacle == "flower":
				_spawn_piece_node(row, col, cs)
				continue
			if cs.piece != "":
				_spawn_piece_node(row, col, cs)


func _spawn_piece_node(row: int, col: int, cs: BoardState.CellState) -> Node:
	var node = PIECE_NODE_SCENE.instantiate()
	node.position = _cell_pos(row, col)
	node.size     = Vector2(CELL_SIZE, CELL_SIZE)
	_piece_layer.add_child(node)
	node.setup(cs.piece, cs.is_special, cs.obstacle, cs.flower_hp)
	_pieces[Vector2i(row, col)] = node
	return node

# ── Public animation entry point ──────────────────────────────────────────────

## Called by GameplayScene after attempt_swap() returns.
## Runs the full visual sequence and returns when all animations are done.
func animate_turn(
		cell_a: Vector2i,
		cell_b: Vector2i,
		result: BoardController.TurnResult,
		board_state: BoardState
) -> void:
	if result.rejected:
		await _animate_rejected_swap(cell_a, cell_b)
		return

	await _animate_accepted_swap(cell_a, cell_b, board_state)


# ── Rejected swap ─────────────────────────────────────────────────────────────

func _animate_rejected_swap(a: Vector2i, b: Vector2i) -> void:
	var node_a = _pieces.get(a)
	var node_b = _pieces.get(b)

	var pos_a := _cell_pos(a.x, a.y)
	var pos_b := _cell_pos(b.x, b.y)
	var dir_a := (pos_b - pos_a).normalized()

	# Nudge both pieces toward each other then spring back.
	var tw_a: Tween = null
	var tw_b: Tween = null
	if node_a != null:
		tw_a = node_a.animate_bounce(dir_a)
	if node_b != null:
		tw_b = node_b.animate_bounce(-dir_a)

	if tw_a != null:
		await tw_a.finished
	elif tw_b != null:
		await tw_b.finished
	else:
		await get_tree().create_timer(0.2).timeout


# ── Accepted swap ─────────────────────────────────────────────────────────────

func _animate_accepted_swap(a: Vector2i, b: Vector2i, board_state: BoardState) -> void:
	# Phase 1: visual swap of the two pieces.
	await _tween_swap_positions(a, b)

	# Swap tracking entries.
	var node_a = _pieces.get(a)
	var node_b = _pieces.get(b)
	if node_a != null:
		_pieces[b] = node_a
	else:
		_pieces.erase(b)
	if node_b != null:
		_pieces[a] = node_b
	else:
		_pieces.erase(a)

	# Phase 2: clear, fall, drop-in.
	await _animate_clear_fall_refill(board_state)


func _tween_swap_positions(a: Vector2i, b: Vector2i) -> void:
	var node_a = _pieces.get(a)
	var node_b = _pieces.get(b)
	var pos_a := _cell_pos(a.x, a.y)
	var pos_b := _cell_pos(b.x, b.y)

	var tw_a: Tween = null
	var tw_b: Tween = null
	if node_a != null:
		tw_a = node_a.animate_move_to(pos_b, 0.2)
	if node_b != null:
		tw_b = node_b.animate_move_to(pos_a, 0.2)

	if tw_a != null:
		await tw_a.finished
	elif tw_b != null:
		await tw_b.finished
	else:
		await get_tree().create_timer(0.2).timeout


# ── Clear / fall / refill ─────────────────────────────────────────────────────

func _animate_clear_fall_refill(board_state: BoardState) -> void:
	# Build per-column match data then animate in sequence.
	var cleared_nodes: Array = []
	var fall_pairs:     Array            = []   # Array of {node, from_row, to_row, col}
	var new_cells:      Array            = []   # Array of {row, col, cs}

	for col in range(GRID_SIZE):
		_diff_column(col, board_state, cleared_nodes, fall_pairs, new_cells)

	# Step 1: clear.
	var clear_tweens: Array[Tween] = []
	for node in cleared_nodes:
		clear_tweens.append(node.animate_clear())
	if clear_tweens.size() > 0:
		await clear_tweens[0].finished
	else:
		await get_tree().create_timer(0.02).timeout

	# Remove cleared nodes.
	for node in cleared_nodes:
		node.queue_free()
	# Remove their dict entries.
	var to_erase: Array[Vector2i] = []
	for coord in _pieces.keys():
		if not is_instance_valid(_pieces[coord]):
			to_erase.append(coord)
	for coord in to_erase:
		_pieces.erase(coord)

	# Step 2: fall + drop-in simultaneously.
	var motion_tweens: Array[Tween] = []

	for pair in fall_pairs:
		var node = pair["node"]
		var to_row: int     = pair["to_row"]
		var col_idx: int    = pair["col"]
		var target_pos      := _cell_pos(to_row, col_idx)
		motion_tweens.append(node.animate_move_to(target_pos, 0.25))
		_pieces[Vector2i(to_row, col_idx)] = node

	for entry in new_cells:
		var row: int = entry["row"]
		var col_idx: int = entry["col"]
		var cs: BoardState.CellState = entry["cs"]
		var node = _spawn_piece_node(row, col_idx, cs)
		motion_tweens.append(node.animate_drop_in((row + 1) * CELL_STEP))

	if motion_tweens.size() > 0:
		await motion_tweens[0].finished
	else:
		await get_tree().create_timer(0.02).timeout

	# Final sync: rebuild _pieces from authoritative board state.
	_sync_pieces_dict(board_state)


# ── Column diff ───────────────────────────────────────────────────────────────

## For one column, compare the current _pieces dict with board_state to
## determine which nodes were cleared, which fell, and what new cells appeared.
func _diff_column(
		col: int,
		board_state: BoardState,
		cleared_nodes: Array,
		fall_pairs:    Array,
		new_cells:     Array
) -> void:
	# Pre: pieces currently tracked in _pieces, bottom-up.
	var pre_col: Array = []
	for row in range(GRID_SIZE - 1, -1, -1):
		var coord := Vector2i(row, col)
		if _pieces.has(coord):
			var node = _pieces[coord]
			pre_col.append({"row": row, "piece_id": node.piece_id, "node": node})

	# Post: what the board says should be there, bottom-up.
	var post_col: Array = []
	for row in range(GRID_SIZE - 1, -1, -1):
		var cs: BoardState.CellState = board_state.get_cell(row, col)
		if cs.active and (cs.piece != "" or cs.obstacle == "rock" or cs.obstacle == "flower"):
			post_col.append({"row": row, "piece_id": _effective_piece_id(cs), "cs": cs})

	# Greedy bottom-up matching by piece_id.
	var pre_ptr  := 0
	var post_ptr := 0

	while pre_ptr < pre_col.size() and post_ptr < post_col.size():
		var pre_item  = pre_col[pre_ptr]
		var post_item = post_col[post_ptr]
		if pre_item["piece_id"] == post_item["piece_id"]:
			# Piece survived; may have fallen.
			var from_row: int = pre_item["row"]
			var to_row:   int = post_item["row"]
			if from_row != to_row:
				fall_pairs.append({"node": pre_item["node"], "from_row": from_row, "to_row": to_row, "col": col})
				_pieces.erase(Vector2i(from_row, col))
			# else: same position, no animation needed
			pre_ptr  += 1
			post_ptr += 1
		else:
			# Pre piece was cleared (not found in post at this depth).
			cleared_nodes.append(pre_item["node"])
			_pieces.erase(Vector2i(pre_item["row"], col))
			pre_ptr += 1

	# Any remaining pre pieces were cleared.
	while pre_ptr < pre_col.size():
		cleared_nodes.append(pre_col[pre_ptr]["node"])
		_pieces.erase(Vector2i(pre_col[pre_ptr]["row"], col))
		pre_ptr += 1

	# Any remaining post cells are new (refill).
	while post_ptr < post_col.size():
		new_cells.append({"row": post_col[post_ptr]["row"], "col": col, "cs": post_col[post_ptr]["cs"]})
		post_ptr += 1


func _effective_piece_id(cs: BoardState.CellState) -> String:
	if cs.obstacle == "rock":   return "rock"
	if cs.obstacle == "flower": return "flower"
	return cs.piece


# ── Sync ──────────────────────────────────────────────────────────────────────

## Rebuilds _pieces from the authoritative board. Removes stale entries and
## creates missing nodes. Called at end of _animate_clear_fall_refill.
func _sync_pieces_dict(board_state: BoardState) -> void:
	# Remove any stale / invalid entries.
	var to_erase: Array[Vector2i] = []
	for coord in _pieces.keys():
		var cs: BoardState.CellState = board_state.get_cell(coord.x, coord.y)
		var expected := _effective_piece_id(cs)
		var node = _pieces[coord]
		if not is_instance_valid(node) or node.piece_id != expected:
			if is_instance_valid(node):
				node.queue_free()
			to_erase.append(coord)
	for coord in to_erase:
		_pieces.erase(coord)

	# Ensure every filled cell has a node.
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var cs: BoardState.CellState = board_state.get_cell(row, col)
			if not cs.active:
				continue
			var coord := Vector2i(row, col)
			var needs_node := (cs.piece != "" or cs.obstacle == "rock" or cs.obstacle == "flower")
			if needs_node and not _pieces.has(coord):
				_spawn_piece_node(row, col, cs)
			elif not needs_node and _pieces.has(coord):
				var node = _pieces[coord]
				if is_instance_valid(node):
					node.queue_free()
				_pieces.erase(coord)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _cell_pos(row: int, col: int) -> Vector2:
	return Vector2(col * CELL_STEP, row * CELL_STEP)


## Returns the board cell coordinate under local_pos, or Vector2i(-1,-1) if none.
func get_cell_at_local(local_pos: Vector2) -> Vector2i:
	var col := int(local_pos.x / CELL_STEP)
	var row := int(local_pos.y / CELL_STEP)
	if row >= 0 and row < GRID_SIZE and col >= 0 and col < GRID_SIZE:
		return Vector2i(row, col)
	return Vector2i(-1, -1)
