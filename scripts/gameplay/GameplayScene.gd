extends Control

## GameplayScene.gd
## Top-level gameplay orchestrator for Layer 6.
##
## Responsibilities:
##   - Load the level specified by SaveData.get_current_level()
##   - Initialise BoardState, BoardController, BoardGrid, HudBar
##   - Accept touch/mouse drag input and translate to swap requests
##   - Call BoardController.attempt_swap(), flush seeds via SeedEconomy
##   - Drive all animations through BoardGrid.animate_turn()
##   - Update HudBar after each turn
##   - Emit level_won / level_failed when the board resolves to a terminal state
##
## No game logic lives here — orchestration only.

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player satisfies all goals. Carries the final TurnResult.
signal level_won(turn_result: BoardController.TurnResult)

## Emitted when turns run out with goals unsatisfied. Carries the final TurnResult.
signal level_failed(turn_result: BoardController.TurnResult)

# ── Constants ─────────────────────────────────────────────────────────────────

## Minimum drag distance (px) before the direction is committed.
const DRAG_THRESHOLD := 12.0

# ── Child refs ────────────────────────────────────────────────────────────────
@onready var _hud_bar         = $HudBar
@onready var _board_grid      = $BoardContainer/BoardGrid
@onready var _quit_button:    Button              = $QuitButton
@onready var _quit_confirm:   ConfirmationDialog  = $QuitConfirmDialog

# ── Game objects ──────────────────────────────────────────────────────────────
var _balance:          Balance          = null
var _level_data:       LevelData        = null
var _board_state:      BoardState       = null
var _board_controller: BoardController  = null
var _win_fail_resolver: WinFailResolver = null

# ── Input state ───────────────────────────────────────────────────────────────
var _drag_start_cell: Vector2i = Vector2i(-1, -1)
var _drag_start_pos:  Vector2  = Vector2.ZERO
var _animating:       bool     = false

# ── Hint state ────────────────────────────────────────────────────────────────
var _hint_timer: Timer = null
var _hint_rng:   RandomNumberGenerator = null
var _hint_match_finder: MatchFinder = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error("GameplayScene._ready: failed to load balance.tres.")
		return

	var level_id := SaveData.get_current_level()
	var path     := "res://resources/levels/level_%02d.tres" % level_id
	_level_data  = load(path) as LevelData
	if _level_data == null:
		push_error("GameplayScene._ready: could not load level data at '%s'." % path)
		return

	_board_state = BoardState.new()
	var warnings := _board_state.init_from_level(_level_data)
	for w in warnings:
		push_warning("GameplayScene._ready: %s" % w)

	_board_controller = BoardController.new()
	_board_controller.init(_board_state, _level_data, _balance)
	_board_controller.initial_fill()

	_win_fail_resolver = WinFailResolver.new()
	_win_fail_resolver.setup(self, _board_state, _level_data, _board_controller.goal_tracker)

	_board_grid.setup(_board_state)
	_hud_bar.setup(_level_data, _board_state, _board_controller.goal_tracker)

	_hint_rng = RandomNumberGenerator.new()
	_hint_rng.randomize()
	_hint_match_finder = MatchFinder.new()

	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.wait_time = _balance.HINT_DELAY_SECONDS
	_hint_timer.timeout.connect(_on_hint_timer_timeout)
	add_child(_hint_timer)
	_hint_timer.start()

	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_confirm.confirmed.connect(_on_quit_confirmed)


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _animating:
		return

	# ── Mouse ──────────────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		if mbe.button_index == MOUSE_BUTTON_LEFT:
			if mbe.pressed:
				_on_pointer_down(mbe.global_position)
			else:
				_on_pointer_up(mbe.global_position)

	elif event is InputEventMouseMotion:
		if _drag_start_cell != Vector2i(-1, -1):
			var mme := event as InputEventMouseMotion
			_check_drag_commit(mme.global_position)

	# ── Touch ──────────────────────────────────────────────────────────────
	elif event is InputEventScreenTouch:
		var ste := event as InputEventScreenTouch
		if ste.pressed:
			_on_pointer_down(ste.position)
		else:
			_on_pointer_up(ste.position)

	elif event is InputEventScreenDrag:
		if _drag_start_cell != Vector2i(-1, -1):
			var sde := event as InputEventScreenDrag
			_check_drag_commit(sde.position)


func _on_pointer_down(global_pos: Vector2) -> void:
	var local_pos: Vector2  = global_pos - _board_grid.global_position
	var cell: Vector2i      = _board_grid.get_cell_at_local(local_pos)
	if cell == Vector2i(-1, -1):
		return
	_drag_start_cell = cell
	_drag_start_pos  = global_pos


func _on_pointer_up(global_pos: Vector2) -> void:
	if _drag_start_cell == Vector2i(-1, -1):
		return
	_check_drag_commit(global_pos)
	_drag_start_cell = Vector2i(-1, -1)


func _check_drag_commit(global_pos: Vector2) -> void:
	if _drag_start_cell == Vector2i(-1, -1):
		return
	var delta := global_pos - _drag_start_pos
	if delta.length() < DRAG_THRESHOLD:
		return

	# Determine swap target cell from dominant axis.
	var target_cell := _drag_start_cell
	if abs(delta.x) >= abs(delta.y):
		target_cell.y += 1 if delta.x > 0 else -1
	else:
		target_cell.x += 1 if delta.y > 0 else -1

	var from_cell := _drag_start_cell
	_drag_start_cell = Vector2i(-1, -1)   # clear before async

	_do_swap(from_cell, target_cell)


# ── Swap execution ────────────────────────────────────────────────────────────

func _do_swap(cell_a: Vector2i, cell_b: Vector2i) -> void:
	if _animating:
		return
	_animating = true

	_board_grid.clear_hint()
	_hint_timer.stop()

	var result := _board_controller.attempt_swap(cell_a, cell_b)

	if result.accepted:
		SeedEconomy.flush_turn_seeds(result.seeds_earned)

	await _board_grid.animate_turn(cell_a, cell_b, result, _board_state)

	_hud_bar.update_hud(_board_state, _board_controller.goal_tracker)

	_animating = false

	if result.win:
		emit_signal("level_won", result)
	elif result.fail:
		emit_signal("level_failed", result)
	else:
		_hint_timer.start(_balance.HINT_DELAY_SECONDS)


# ── Quit ──────────────────────────────────────────────────────────────────────

func _on_quit_pressed() -> void:
	_quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	# Block any further input and stop the hint timer.
	_animating = true
	_hint_timer.stop()
	_board_grid.clear_hint()

	# Consume a life — quitting counts as a failed attempt.
	SaveData.consume_life()

	ScreenRouter.go_level_select()


# ── Hint ──────────────────────────────────────────────────────────────────────

func _on_hint_timer_timeout() -> void:
	# Sanity guard: board should never still be animating here, but defend anyway.
	if _animating:
		_hint_timer.start(_balance.HINT_DELAY_SECONDS)
		return

	var swap := _hint_match_finder.get_random_valid_swap(_board_state, _hint_rng)
	if swap.is_empty():
		return

	_board_grid.show_hint(swap["a"], swap["b"])
