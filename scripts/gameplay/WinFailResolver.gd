class_name WinFailResolver
extends RefCounted

## WinFailResolver.gd
## Layer 7 — Win / Fail Resolution
##
## Connects to GameplayScene's level_won / level_failed signals, computes the
## star rating, persists results through SaveData and SeedEconomy, builds the
## result payload, and hands off to ScreenRouter for scene transition.
##
## Contains NO game logic. All values are read from injected dependencies.
## Call setup() from GameplayScene._ready() after all objects are initialised.


# ── Dependencies (injected via setup) ─────────────────────────────────────────

var _gameplay:     Node         = null   # GameplayScene — held for signal disconnection only
var _board_state:  BoardState   = null
var _level_data:   LevelData    = null
var _goal_tracker: GoalTracker  = null


# ── Initialisation ────────────────────────────────────────────────────────────

## Injects read-only dependencies and connects to GameplayScene signals.
## gameplay  – the GameplayScene node (typed as Node to avoid circular class dep)
## board_state – BoardState instance for the current run
## level_data  – LevelData resource for the current level
## goal_tracker – GoalTracker instance from BoardController
func setup(
	gameplay:     Node,
	board_state:  BoardState,
	level_data:   LevelData,
	goal_tracker: GoalTracker
) -> void:
	_gameplay     = gameplay
	_board_state  = board_state
	_level_data   = level_data
	_goal_tracker = goal_tracker

	_gameplay.level_won.connect(_on_level_won)
	_gameplay.level_failed.connect(_on_level_failed)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_level_won(turn_result: BoardController.TurnResult) -> void:
	var stars := _compute_stars()

	# ── Persist ──────────────────────────────────────────────────────────────
	# record_level_complete guards internally against star regression.
	SaveData.record_level_complete(_level_data.level_id, stars)

	# Grant 3-star seed bonus (SeedEconomy exits early if stars != 3).
	SeedEconomy.flush_level_win(_level_data, stars)

	# ── Build payload ─────────────────────────────────────────────────────────
	var bonus_seeds := 0
	if stars == 3:
		bonus_seeds = _level_data.seed_reward_3star

	var payload := {
		"outcome":          "win",
		"level_id":         _level_data.level_id,
		"stars":            stars,
		"turns_remaining":  _board_state.turns_remaining,
		"final_score":      _board_state.score,
		"seeds_this_run":   turn_result.seeds_earned,
		"bonus_seeds":      bonus_seeds,
	}

	# ── Transition ────────────────────────────────────────────────────────────
	_disconnect_signals()
	ScreenRouter.go_win(payload)


func _on_level_failed(turn_result: BoardController.TurnResult) -> void:
	# Consume one life unconditionally (spec §9).
	SaveData.consume_life()

	# ── Collect incomplete goal definitions ───────────────────────────────────
	var incomplete: Array[Dictionary] = []
	for i in range(_goal_tracker.goal_count()):
		var gs: GoalTracker.GoalState = _goal_tracker.get_goal_state(i)
		if not gs.complete:
			incomplete.append(gs.definition)

	# ── Build payload ─────────────────────────────────────────────────────────
	var payload := {
		"outcome":          "fail",
		"level_id":         _level_data.level_id,
		"lives_remaining":  SaveData.get_lives(),   # read AFTER consume_life
		"incomplete_goals": incomplete,
		"fail_reason":      turn_result.fail_reason,
	}

	# ── Transition ────────────────────────────────────────────────────────────
	_disconnect_signals()
	ScreenRouter.go_fail(payload)


# ── Star calculation ──────────────────────────────────────────────────────────

## Computes star rating from turns remaining and level thresholds.
## All values sourced from _board_state and _level_data — nothing hardcoded.
func _compute_stars() -> int:
	var turns_left: int = _board_state.turns_remaining
	var t3: int         = _level_data.star_threshold_3
	var t2: int         = _level_data.star_threshold_2

	if turns_left >= t3:
		return 3
	elif turns_left >= t2:
		return 2
	else:
		return 1


# ── Cleanup ───────────────────────────────────────────────────────────────────

func _disconnect_signals() -> void:
	if _gameplay == null:
		return
	if _gameplay.level_won.is_connected(_on_level_won):
		_gameplay.level_won.disconnect(_on_level_won)
	if _gameplay.level_failed.is_connected(_on_level_failed):
		_gameplay.level_failed.disconnect(_on_level_failed)
	_gameplay = null
