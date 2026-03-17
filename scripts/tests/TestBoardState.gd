extends Node

## TestBoardState.gd
## Attach to a Node in a test scene and run the scene, or call run_all() from
## another script. Validates BoardState.init_from_level() against level_01.tres
## (all-active, no obstacles) and level_20.tres (holes, rocks, dirt, flowers).
## Every assertion maps to a named spec scenario. Prints a full pass/fail report
## to the Output panel.

const LEVEL_01_PATH := "res://resources/levels/level_01.tres"
const LEVEL_20_PATH := "res://resources/levels/level_20.tres"

# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestBoardState — BoardState + CellState init tests")
	print("=".repeat(64))

	_test_level_01()
	_test_level_20()
	_test_cell_state_helpers()
	_test_accessor_methods()
	_test_mutation_methods()

	_print_summary()


# ── Suite: level_01 (all-active, no obstacles) ────────────────────────────────

func _test_level_01() -> void:
	_current_suite = "level_01 (all-active, no obstacles)"
	print("\n── %s ──" % _current_suite)

	var level_data: LevelData = load(LEVEL_01_PATH)
	_assert(level_data != null, "level_01.tres loads as a non-null resource")

	var board := BoardState.new()
	var warnings := board.init_from_level(level_data)

	# ── Grid dimensions ──
	_assert(board.cells.size() == 8,
		"grid has exactly 8 rows")

	for row in range(8):
		_assert(board.cells[row].size() == 8,
			"row %d has exactly 8 columns" % row)

	# ── All 64 cells are active ──
	var active_cells := board.get_all_active_cells()
	_assert(active_cells.size() == 64,
		"all 64 cells are active (0 holes)")

	# ── No holes anywhere ──
	var hole_found := false
	for row in range(8):
		for col in range(8):
			if not board.get_cell(row, col).active:
				hole_found = true
	_assert(not hole_found,
		"no inactive (hole) cells exist in level_01")

	# ── All cells have obstacle == "none" ──
	var unexpected_obstacle := false
	for row in range(8):
		for col in range(8):
			if board.get_cell(row, col).obstacle != "none":
				unexpected_obstacle = true
	_assert(not unexpected_obstacle,
		"every cell has obstacle == 'none'")

	# ── No dirt, no flowers, no rocks ──
	_assert(board.get_cells_with_obstacle("dirt").size() == 0,
		"zero dirt cells in level_01")
	_assert(board.get_cells_with_obstacle("flower").size() == 0,
		"zero flower cells in level_01")
	_assert(board.get_cells_with_obstacle("rock").size() == 0,
		"zero rock cells in level_01")

	# ── All 64 cells can hold a piece ──
	var non_holdable := 0
	for row in range(8):
		for col in range(8):
			if not board.get_cell(row, col).can_hold_piece():
				non_holdable += 1
	_assert(non_holdable == 0,
		"all 64 cells can_hold_piece() in level_01")

	# ── No starting pieces declared → all cells are empty ──
	_assert(board.count_pieces() == 0,
		"count_pieces() == 0 before random fill (no starting_piece overrides in level_01)")
	_assert(board.count_empty_fillable_cells() == 64,
		"count_empty_fillable_cells() == 64 before fill")

	# ── Turn counters copied from LevelData ──
	_assert(board.turn_limit == 20,
		"turn_limit == 20 (from level_01 LevelData)")
	_assert(board.turns_remaining == 20,
		"turns_remaining == 20 at init")

	# ── Score and seeds start at zero ──
	_assert(board.score == 0,
		"score == 0 at init")
	_assert(board.seeds_earned == 0,
		"seeds_earned == 0 at init")

	# ── No warnings on a clean level ──
	_assert(warnings.size() == 0,
		"init_from_level returns no warnings for level_01")

	# ── all_dirt_cleared and all_flowers_cleared return true when none present ──
	_assert(board.all_dirt_cleared(),
		"all_dirt_cleared() == true when no dirt exists")
	_assert(board.all_flowers_cleared(),
		"all_flowers_cleared() == true when no flowers exist")


# ── Suite: level_20 (holes, rocks, dirt, flowers) ────────────────────────────

func _test_level_20() -> void:
	_current_suite = "level_20 (holes, rocks, dirt, flowers)"
	print("\n── %s ──" % _current_suite)

	var level_data: LevelData = load(LEVEL_20_PATH)
	_assert(level_data != null, "level_20.tres loads as a non-null resource")

	var board := BoardState.new()
	var warnings := board.init_from_level(level_data)

	# ── Dimensions still 8×8 ──
	_assert(board.cells.size() == 8,
		"grid has exactly 8 rows")
	for row in range(8):
		_assert(board.cells[row].size() == 8,
			"row %d has exactly 8 columns" % row)

	# ── Holes: (0,0), (0,7), (7,0), (7,7) ──
	var expected_holes: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 7),
		Vector2i(7, 0), Vector2i(7, 7),
	]
	for pos in expected_holes:
		_assert(not board.get_cell(pos.x, pos.y).active,
			"cell (%d,%d) is a hole (inactive)" % [pos.x, pos.y])

	# ── Active cell count == 60 (64 − 4 holes) ──
	_assert(board.get_all_active_cells().size() == 60,
		"60 active cells (64 − 4 holes)")

	# ── Rocks: (1,2), (1,5), (6,2), (6,5) ──
	var expected_rocks: Array[Vector2i] = [
		Vector2i(1, 2), Vector2i(1, 5),
		Vector2i(6, 2), Vector2i(6, 5),
	]
	for pos in expected_rocks:
		var cs := board.get_cell(pos.x, pos.y)
		_assert(cs.active and cs.obstacle == "rock",
			"cell (%d,%d) is an active rock" % [pos.x, pos.y])

	_assert(board.get_cells_with_obstacle("rock").size() == 4,
		"total rock count == 4")

	# ── Rocks cannot hold pieces ──
	for pos in expected_rocks:
		_assert(not board.get_cell(pos.x, pos.y).can_hold_piece(),
			"rock at (%d,%d) cannot hold a piece" % [pos.x, pos.y])

	# ── Dirt patches: 8 total ──
	#    (2,1), (2,6), (3,3), (3,4), (4,3), (4,4), (5,1), (5,6)
	var expected_dirt: Array[Vector2i] = [
		Vector2i(2, 1), Vector2i(2, 6),
		Vector2i(3, 3), Vector2i(3, 4),
		Vector2i(4, 3), Vector2i(4, 4),
		Vector2i(5, 1), Vector2i(5, 6),
	]
	for pos in expected_dirt:
		var cs := board.get_cell(pos.x, pos.y)
		_assert(cs.active and cs.obstacle == "dirt",
			"cell (%d,%d) is a dirt patch" % [pos.x, pos.y])

	_assert(board.get_cells_with_obstacle("dirt").size() == 8,
		"total dirt count == 8")
	_assert(board.count_dirt() == 8,
		"count_dirt() == 8")

	# ── Dirt cells CAN hold a piece on top (spec: dirt underlays a piece) ──
	for pos in expected_dirt:
		_assert(board.get_cell(pos.x, pos.y).can_hold_piece(),
			"dirt cell (%d,%d) can_hold_piece() == true" % [pos.x, pos.y])

	# ── all_dirt_cleared() is false when dirt is present ──
	_assert(not board.all_dirt_cleared(),
		"all_dirt_cleared() == false while dirt patches remain")

	# ── Flowers: 8 total ──
	#    (0,3), (0,4), (3,0), (3,7), (4,0), (4,7), (7,3), (7,4)
	var expected_flowers: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(0, 4),
		Vector2i(3, 0), Vector2i(3, 7),
		Vector2i(4, 0), Vector2i(4, 7),
		Vector2i(7, 3), Vector2i(7, 4),
	]
	for pos in expected_flowers:
		var cs := board.get_cell(pos.x, pos.y)
		_assert(cs.active and cs.obstacle == "flower",
			"cell (%d,%d) is a flower" % [pos.x, pos.y])

	_assert(board.get_cells_with_obstacle("flower").size() == 8,
		"total flower count == 8")
	_assert(board.count_flowers() == 8,
		"count_flowers() == 8")

	# ── Flowers spawn at full HP == 3 ──
	for pos in expected_flowers:
		_assert(board.get_cell(pos.x, pos.y).flower_hp == 3,
			"flower at (%d,%d) has flower_hp == 3 (Wilted / full HP)" % [pos.x, pos.y])

	# ── Flowers cannot hold pieces (spec: flower occupies a full cell) ──
	for pos in expected_flowers:
		_assert(not board.get_cell(pos.x, pos.y).can_hold_piece(),
			"flower at (%d,%d) cannot hold a piece" % [pos.x, pos.y])

	# ── all_flowers_cleared() is false when flowers are present ──
	_assert(not board.all_flowers_cleared(),
		"all_flowers_cleared() == false while flowers remain")

	# ── Turn counters ──
	_assert(board.turn_limit == 30,
		"turn_limit == 30 (from level_20 LevelData)")
	_assert(board.turns_remaining == 30,
		"turns_remaining == 30 at init")

	# ── No warnings for a valid level ──
	_assert(warnings.size() == 0,
		"init_from_level returns no warnings for level_20")


# ── Suite: CellState helper methods ──────────────────────────────────────────

func _test_cell_state_helpers() -> void:
	_current_suite = "CellState helper methods"
	print("\n── %s ──" % _current_suite)

	# ── Hole cell ──
	var hole := BoardState.CellState.new()
	hole.active = false
	_assert(not hole.can_hold_piece(),
		"hole: can_hold_piece() == false")
	_assert(not hole.is_empty(),
		"hole: is_empty() == false (holes are not 'empty' in gameplay terms)")
	_assert(not hole.has_piece(),
		"hole: has_piece() == false")

	# ── Normal active empty cell ──
	var empty_cell := BoardState.CellState.new()
	empty_cell.active   = true
	empty_cell.obstacle = "none"
	empty_cell.piece    = ""
	_assert(empty_cell.can_hold_piece(),
		"active empty cell: can_hold_piece() == true")
	_assert(empty_cell.is_empty(),
		"active empty cell: is_empty() == true")
	_assert(not empty_cell.has_piece(),
		"active empty cell: has_piece() == false")

	# ── Active cell with a crop piece ──
	var crop_cell := BoardState.CellState.new()
	crop_cell.active   = true
	crop_cell.obstacle = "none"
	crop_cell.piece    = "strawberry"
	_assert(crop_cell.can_hold_piece(),
		"cell with crop: can_hold_piece() == true")
	_assert(not crop_cell.is_empty(),
		"cell with crop: is_empty() == false")
	_assert(crop_cell.has_piece(),
		"cell with crop: has_piece() == true")

	# ── Rock cell ──
	var rock_cell := BoardState.CellState.new()
	rock_cell.active   = true
	rock_cell.obstacle = "rock"
	_assert(not rock_cell.can_hold_piece(),
		"rock cell: can_hold_piece() == false")
	_assert(not rock_cell.is_empty(),
		"rock cell: is_empty() == false (rocks occupy the cell)")
	_assert(not rock_cell.has_piece(),
		"rock cell: has_piece() == false")

	# ── Flower cell ──
	var flower_cell := BoardState.CellState.new()
	flower_cell.active    = true
	flower_cell.obstacle  = "flower"
	flower_cell.flower_hp = 3
	_assert(not flower_cell.can_hold_piece(),
		"flower cell: can_hold_piece() == false")
	_assert(not flower_cell.has_piece(),
		"flower cell: has_piece() == false (flowers hold no piece)")

	# ── Dirt cell with a piece on top ──
	# Spec: dirt underlays a normal or special piece — both coexist.
	var dirt_with_piece := BoardState.CellState.new()
	dirt_with_piece.active     = true
	dirt_with_piece.obstacle   = "dirt"
	dirt_with_piece.piece      = "watering_can"
	dirt_with_piece.is_special = true
	_assert(dirt_with_piece.can_hold_piece(),
		"dirt cell: can_hold_piece() == true (dirt underlays, doesn't block)")
	_assert(not dirt_with_piece.is_empty(),
		"dirt cell with piece: is_empty() == false")
	_assert(dirt_with_piece.has_piece(),
		"dirt cell with piece: has_piece() == true")

	# ── Special piece flags ──
	var special_cell := BoardState.CellState.new()
	special_cell.active              = true
	special_cell.obstacle            = "none"
	special_cell.piece               = "bushel_basket"
	special_cell.is_special          = true
	special_cell.special_orientation = "horizontal"
	_assert(special_cell.is_special,
		"special cell: is_special == true")
	_assert(special_cell.special_orientation == "horizontal",
		"special cell: special_orientation == 'horizontal'")


# ── Suite: Accessor methods ───────────────────────────────────────────────────

func _test_accessor_methods() -> void:
	_current_suite = "BoardState accessor methods"
	print("\n── %s ──" % _current_suite)

	var level_data: LevelData = load(LEVEL_20_PATH)
	var board := BoardState.new()
	board.init_from_level(level_data)

	# ── is_in_bounds ──
	_assert(board.is_in_bounds(0, 0),     "is_in_bounds(0,0) == true")
	_assert(board.is_in_bounds(7, 7),     "is_in_bounds(7,7) == true")
	_assert(board.is_in_bounds(4, 4),     "is_in_bounds(4,4) == true")
	_assert(not board.is_in_bounds(-1, 0), "is_in_bounds(-1,0) == false")
	_assert(not board.is_in_bounds(0, -1), "is_in_bounds(0,-1) == false")
	_assert(not board.is_in_bounds(8, 0),  "is_in_bounds(8,0) == false")
	_assert(not board.is_in_bounds(0, 8),  "is_in_bounds(0,8) == false")

	# ── get_orthogonal_neighbors excludes holes ──
	# Cell (0,1) is active. Its neighbours:
	#   up    (-1,1) → out of bounds → excluded
	#   down  ( 1,1) → active        → included
	#   left  ( 0,0) → hole          → excluded (spec: holes cannot be targeted)
	#   right ( 0,2) → active        → included
	var neighbors_0_1 := board.get_orthogonal_neighbors(0, 1)
	_assert(neighbors_0_1.size() == 2,
		"get_orthogonal_neighbors(0,1) returns 2 neighbours (hole at (0,0) excluded)")
	_assert(Vector2i(1, 1) in neighbors_0_1,
		"(1,1) is a neighbour of (0,1)")
	_assert(Vector2i(0, 2) in neighbors_0_1,
		"(0,2) is a neighbour of (0,1)")
	_assert(Vector2i(0, 0) not in neighbors_0_1,
		"hole (0,0) is NOT a neighbour of (0,1)")

	# ── get_orthogonal_neighbors for a fully-surrounded interior cell ──
	# Cell (4,4) is a dirt patch — active with all four cardinal neighbours active.
	var neighbors_4_4 := board.get_orthogonal_neighbors(4, 4)
	_assert(neighbors_4_4.size() == 4,
		"get_orthogonal_neighbors(4,4) returns 4 active neighbours")

	# ── get_orthogonal_neighbors for a cell adjacent to a hole ──
	# Cell (1,0): up=(0,0) hole, down=(2,0) active, left=OOB, right=(1,1) active
	var neighbors_1_0 := board.get_orthogonal_neighbors(1, 0)
	_assert(neighbors_1_0.size() == 2,
		"get_orthogonal_neighbors(1,0) returns 2 (hole above, OOB to left)")
	_assert(Vector2i(2, 0) in neighbors_1_0,
		"(2,0) is a neighbour of (1,0)")
	_assert(Vector2i(1, 1) in neighbors_1_0,
		"(1,1) is a neighbour of (1,0)")

	# ── get_orthogonal_neighbors for a top-edge cell ──
	# Cell (0,3) is a flower — active.
	# Neighbours: up=OOB, down=(1,3) active, left=(0,2) active, right=(0,4) active
	var neighbors_0_3 := board.get_orthogonal_neighbors(0, 3)
	_assert(neighbors_0_3.size() == 3,
		"get_orthogonal_neighbors(0,3) returns 3 (top edge, OOB above)")


# ── Suite: Mutation methods ───────────────────────────────────────────────────

func _test_mutation_methods() -> void:
	_current_suite = "BoardState mutation methods"
	print("\n── %s ──" % _current_suite)

	var level_data: LevelData = load(LEVEL_01_PATH)
	var board := BoardState.new()
	board.init_from_level(level_data)

	# ── place_piece / clear_piece ──
	board.place_piece(3, 3, "carrot")
	_assert(board.get_cell(3, 3).piece == "carrot",
		"place_piece: piece == 'carrot' after placement")
	_assert(not board.get_cell(3, 3).is_special,
		"place_piece: is_special == false for a crop")
	_assert(board.count_pieces() == 1,
		"count_pieces() == 1 after placing one piece")

	board.clear_piece(3, 3)
	_assert(board.get_cell(3, 3).piece == "",
		"clear_piece: piece == '' after clearing")
	_assert(board.count_pieces() == 0,
		"count_pieces() == 0 after clearing the only piece")

	# ── place_piece with special piece ──
	board.place_piece(2, 2, "bushel_basket", true, "vertical")
	var sc := board.get_cell(2, 2)
	_assert(sc.piece == "bushel_basket",
		"place_piece: special piece identifier stored correctly")
	_assert(sc.is_special,
		"place_piece: is_special == true for bushel_basket")
	_assert(sc.special_orientation == "vertical",
		"place_piece: special_orientation == 'vertical'")

	# ── swap_pieces ──
	board.place_piece(0, 0, "strawberry")
	board.place_piece(0, 1, "corn")
	board.swap_pieces(Vector2i(0, 0), Vector2i(0, 1))
	_assert(board.get_cell(0, 0).piece == "corn",
		"swap_pieces: (0,0) now holds 'corn'")
	_assert(board.get_cell(0, 1).piece == "strawberry",
		"swap_pieces: (0,1) now holds 'strawberry'")

	# ── swap_pieces preserves special flags ──
	board.place_piece(5, 5, "scarecrow", true, "")
	board.place_piece(5, 6, "sunflower", false, "")
	board.swap_pieces(Vector2i(5, 5), Vector2i(5, 6))
	_assert(board.get_cell(5, 6).piece == "scarecrow",
		"swap_pieces: scarecrow moved to (5,6)")
	_assert(board.get_cell(5, 6).is_special,
		"swap_pieces: is_special carried with the piece to (5,6)")
	_assert(not board.get_cell(5, 5).is_special,
		"swap_pieces: (5,5) is_special == false after sunflower moved in")

	# ── clear_dirt ──
	var board20 := BoardState.new()
	board20.init_from_level(load(LEVEL_20_PATH))
	_assert(board20.get_cell(2, 1).obstacle == "dirt",
		"pre-condition: (2,1) is dirt before clear_dirt")
	board20.clear_dirt(2, 1)
	_assert(board20.get_cell(2, 1).obstacle == "none",
		"clear_dirt: obstacle == 'none' after clearing dirt at (2,1)")
	_assert(board20.count_dirt() == 7,
		"count_dirt() == 7 after clearing one of 8 dirt patches")

	# clear_dirt on a non-dirt cell is a no-op
	board20.clear_dirt(0, 1)
	_assert(board20.get_cell(0, 1).obstacle == "none",
		"clear_dirt on non-dirt cell is a no-op")

	# ── all_dirt_cleared after manually clearing all dirt ──
	for pos in board20.get_cells_with_obstacle("dirt"):
		board20.clear_dirt(pos.x, pos.y)
	_assert(board20.all_dirt_cleared(),
		"all_dirt_cleared() == true after clearing all dirt patches")

	# ── hit_flower: HP decrements correctly ──
	var board20b := BoardState.new()
	board20b.init_from_level(load(LEVEL_20_PATH))

	# Spec scenario: Wilted (3HP) → one hit → Budding (2HP)
	var hp_after_first_hit := board20b.hit_flower(0, 3)
	_assert(hp_after_first_hit == 2,
		"hit_flower: Wilted (3HP) → 2HP (Budding) after first hit")
	_assert(board20b.get_cell(0, 3).obstacle == "flower",
		"hit_flower: obstacle remains 'flower' at 2HP")

	# Second hit → Blooming (1HP)
	var hp_after_second_hit := board20b.hit_flower(0, 3)
	_assert(hp_after_second_hit == 1,
		"hit_flower: Budding (2HP) → 1HP (Blooming) after second hit")
	_assert(board20b.get_cell(0, 3).obstacle == "flower",
		"hit_flower: obstacle remains 'flower' at 1HP")

	# Third hit → Cleared (0HP) — obstacle removed
	var hp_after_third_hit := board20b.hit_flower(0, 3)
	_assert(hp_after_third_hit == 0,
		"hit_flower: Blooming (1HP) → 0HP (Cleared) after third hit")
	_assert(board20b.get_cell(0, 3).obstacle == "none",
		"hit_flower: obstacle == 'none' after flower is cleared")
	_assert(board20b.get_cell(0, 3).flower_hp == 0,
		"hit_flower: flower_hp == 0 after clearing")

	# hit_flower on a non-flower cell returns 0 and is a no-op
	var noop_result := board20b.hit_flower(0, 1)
	_assert(noop_result == 0,
		"hit_flower on non-flower cell returns 0 (no-op)")
	_assert(board20b.get_cell(0, 1).obstacle == "none",
		"hit_flower on non-flower cell leaves obstacle unchanged")

	# ── count_flowers decrements as flowers are cleared ──
	var board20c := BoardState.new()
	board20c.init_from_level(load(LEVEL_20_PATH))
	_assert(board20c.count_flowers() == 8,
		"count_flowers() == 8 before any hits")

	# Clear one flower completely (3 hits)
	board20c.hit_flower(3, 0)
	board20c.hit_flower(3, 0)
	board20c.hit_flower(3, 0)
	_assert(board20c.count_flowers() == 7,
		"count_flowers() == 7 after one flower is fully cleared")

	# all_flowers_cleared requires ALL flowers gone
	_assert(not board20c.all_flowers_cleared(),
		"all_flowers_cleared() == false while 7 flowers remain")

	# Clear all remaining flowers
	for pos in board20c.get_cells_with_obstacle("flower"):
		board20c.hit_flower(pos.x, pos.y)
		board20c.hit_flower(pos.x, pos.y)
		board20c.hit_flower(pos.x, pos.y)
	_assert(board20c.all_flowers_cleared(),
		"all_flowers_cleared() == true after all 8 flowers fully hit")


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
