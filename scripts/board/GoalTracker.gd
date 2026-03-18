class_name GoalTracker
extends RefCounted

## GoalTracker.gd
## Tracks live progress for all goals in the current level run.
## Initialised once from a LevelData resource, then notified of game events
## by BoardController. Returns newly-completed goal indices on each
## notification so the caller can update UI or trigger win checks.
##
## No board mutation occurs here. GoalTracker is pure progress accounting.
##
## Supported goal types (matching LevelData.goals schema):
##   { "type": "score",        "target": int }
##   { "type": "clear_dirt" }
##   { "type": "clear_flowers" }
##   { "type": "collect_crop", "crop": String, "target": int }


# ── GoalState ─────────────────────────────────────────────────────────────────

class GoalState:
	## The original goal definition dictionary from LevelData.goals.
	var definition: Dictionary = {}

	## Whether this goal has been satisfied. Once true, never goes back to
	## false — goals cannot un-complete mid-run.
	var complete: bool = false

	## Running numerator for goals that accumulate a count.
	## Score goals  : current score (mirrored from notify_score_updated).
	## Collect-crop : pieces of the target crop cleared so far.
	## Clear-dirt    : not used (completion driven by board query result).
	## Clear-flowers : not used (completion driven by board query result).
	var progress: int = 0

	## Convenience accessor — the goal type string.
	func goal_type() -> String:
		return definition.get("type", "")


# ── Fields ────────────────────────────────────────────────────────────────────

## Ordered list of GoalState objects, one per entry in LevelData.goals.
## Index matches the original goals array so UI can reference by index.
var _goals: Array[GoalState] = []

## True once init() has been called successfully.
var _initialised: bool = false


# ── Initialisation ────────────────────────────────────────────────────────────

## Prepares the tracker from the level's goal definitions.
## Must be called before any notify_* method.
## Safe to call again to reset for a retry.
func init(level_data: LevelData) -> void:
	_goals.clear()
	for goal_def in level_data.goals:
		var gs := GoalState.new()
		gs.definition = goal_def
		gs.complete   = false
		gs.progress   = 0
		_goals.append(gs)
	_initialised = true


# ── Notification API ──────────────────────────────────────────────────────────
## Each notify_* method returns an Array[int] of goal indices that became
## complete as a direct result of THIS notification. Already-complete goals
## are never included. An empty array means nothing newly completed.

## Called after the score changes (e.g. at the end of every match resolution).
## current_score is the new cumulative score for this run.
func notify_score_updated(current_score: int) -> Array[int]:
	_assert_initialised("notify_score_updated")
	var newly_done: Array[int] = []
	for i in range(_goals.size()):
		var gs: GoalState = _goals[i]
		if gs.goal_type() != "score":
			continue
		gs.progress = current_score
		if not gs.complete and current_score >= gs.definition.get("target", 0):
			gs.complete = true
			newly_done.append(i)
	return newly_done


## Called with every batch of pieces cleared (matches, cascades, special
## effects all use the same path). `cleared_pieces` is an Array of
## Dictionaries, one per cleared piece:
##
##   { "crop": String }   — the piece identifier that was on the cell
##
## Special pieces are included with their identifier string (e.g.
## "bushel_basket"). Callers should pass the identifier that was in the
## cell at the time of clearing. GoalTracker only counts normal crop strings
## against collect_crop goals; special-piece identifiers will simply never
## match a crop goal's "crop" field.
##
## Returns newly-completed goal indices.
func notify_pieces_cleared(cleared_pieces: Array) -> Array[int]:
	_assert_initialised("notify_pieces_cleared")
	var newly_done: Array[int] = []
	for i in range(_goals.size()):
		var gs: GoalState = _goals[i]
		if gs.complete or gs.goal_type() != "collect_crop":
			continue
		var target_crop: String = gs.definition.get("crop", "")
		var target_count: int   = gs.definition.get("target", 0)
		for piece_info in cleared_pieces:
			if piece_info.get("crop", "") == target_crop:
				gs.progress += 1
		if gs.progress >= target_count:
			gs.complete = true
			newly_done.append(i)
	return newly_done


## Called after any obstacle-clearing event resolves (dirt cleared, flower
## cleared). `remaining_dirt` and `remaining_flowers` are the counts still
## present on the board AFTER the clear event.
##
## Passing current counts (rather than deltas) makes the call idempotent and
## avoids drift from missed notifications.
##
## Returns newly-completed goal indices.
func notify_obstacles_updated(remaining_dirt: int, remaining_flowers: int) -> Array[int]:
	_assert_initialised("notify_obstacles_updated")
	var newly_done: Array[int] = []
	for i in range(_goals.size()):
		var gs: GoalState = _goals[i]
		if gs.complete:
			continue
		match gs.goal_type():
			"clear_dirt":
				if remaining_dirt == 0:
					gs.complete = true
					newly_done.append(i)
			"clear_flowers":
				if remaining_flowers == 0:
					gs.complete = true
					newly_done.append(i)
	return newly_done


# ── Query API ─────────────────────────────────────────────────────────────────

## Returns true only when every goal is satisfied.
## This is the win condition check — BoardController calls this after all
## notifications for a turn have been dispatched.
func all_goals_complete() -> bool:
	_assert_initialised("all_goals_complete")
	for gs in _goals:
		if not gs.complete:
			return false
	return true


## Returns the GoalState at index i (0-indexed, matching LevelData.goals order).
## Returns null and pushes an error for out-of-range indices.
func get_goal_state(index: int) -> GoalState:
	if index < 0 or index >= _goals.size():
		push_error("GoalTracker.get_goal_state: index %d out of range (size=%d)." % [index, _goals.size()])
		return null
	return _goals[index]


## Returns the total number of goals being tracked.
func goal_count() -> int:
	return _goals.size()


## Returns the number of goals that are currently complete.
func completed_goal_count() -> int:
	var n := 0
	for gs in _goals:
		if gs.complete:
			n += 1
	return n


## Returns the current progress value for goal at index i.
## For score goals    : the last score passed to notify_score_updated.
## For collect_crop   : the number of matching pieces cleared so far.
## For clear_dirt/flowers : always 0 (completion is binary, no numeric progress).
## Returns -1 for out-of-range indices.
func get_progress(index: int) -> int:
	if index < 0 or index >= _goals.size():
		push_error("GoalTracker.get_progress: index %d out of range (size=%d)." % [index, _goals.size()])
		return -1
	return _goals[index].progress


## Returns the target value for goal at index i, or 0 for goals without one.
func get_target(index: int) -> int:
	if index < 0 or index >= _goals.size():
		push_error("GoalTracker.get_target: index %d out of range (size=%d)." % [index, _goals.size()])
		return 0
	var gs: GoalState = _goals[index]
	match gs.goal_type():
		"score":
			return gs.definition.get("target", 0)
		"collect_crop":
			return gs.definition.get("target", 0)
		_:
			return 0


# ── Private helpers ───────────────────────────────────────────────────────────

func _assert_initialised(caller: String) -> void:
	if not _initialised:
		push_error("GoalTracker.%s called before init()." % caller)
