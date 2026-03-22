extends Node

## TestGoalTracker.gd
## Attach to a Node in scenes/tests/TestGoalTracker.tscn and press F6 to run.
##
## Covers:
##   - Score goal completes when threshold met; play continues (multi-goal level).
##   - Score goal not complete while under threshold.
##   - collect_crop increments from match clears, cascade clears, special-effect clears.
##   - collect_crop ignores pieces whose crop string does not match the goal.
##   - collect_crop ignores special-piece identifiers (they are not crops).
##   - clear_dirt completes when remaining_dirt reaches 0; not before.
##   - clear_flowers completes when remaining_flowers reaches 0; not before.
##   - all_goals_complete() returns false until every goal is satisfied.
##   - all_goals_complete() returns true only after every goal is satisfied.
##   - Newly-completed indices returned correctly from each notify_* call.
##   - Already-complete goals are never re-reported as newly done.
##   - get_progress() and get_target() return correct values.
##   - goal_count() and completed_goal_count() are consistent.


# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count := 0
var _fail_count := 0
var _current_suite := ""


func _ready() -> void:
	run_all()


func run_all() -> void:
	print("=".repeat(64))
	print("TestGoalTracker — GoalTracker progress-tracking tests")
	print("=".repeat(64))

	_test_score_goal_basics()
	_test_score_goal_not_complete_below_threshold()
	_test_multi_goal_score_completes_early()
	_test_collect_crop_from_matches()
	_test_collect_crop_from_cascades()
	_test_collect_crop_from_special_effects()
	_test_collect_crop_ignores_wrong_crop()
	_test_collect_crop_ignores_special_piece_identifiers()
	_test_clear_dirt_goal()
	_test_clear_flowers_goal()
	_test_all_goals_complete_guard()
	_test_newly_completed_indices()
	_test_already_complete_not_re_reported()
	_test_progress_and_target_accessors()
	_test_goal_count_accessors()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

## Builds a minimal LevelData with the supplied goals array.
## grid_layout, crop_set, star thresholds etc. are left at defaults — GoalTracker
## only reads the goals field, so the rest does not matter for these tests.
func _make_level(goals: Array) -> LevelData:
	var ld := LevelData.new()
	ld.level_id         = 1
	ld.turn_limit       = 20
	ld.star_threshold_2 = 10
	ld.star_threshold_3 = 5
	ld.crop_set         = ["strawberry", "carrot", "corn", "eggplant"]
	ld.goals.assign(goals)
	return ld


func _make_tracker() -> GoalTracker:
	return GoalTracker.new()


## Builds a cleared_pieces array where every entry has the given crop string.
func _pieces(crop: String, count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append({"crop": crop})
	return result


## Builds a mixed cleared_pieces array from a Dictionary of { crop: count }.
func _mixed_pieces(counts: Dictionary) -> Array:
	var result: Array = []
	for crop in counts.keys():
		for i in range(counts[crop]):
			result.append({"crop": crop})
	return result


# ── Suite: score goal basics ──────────────────────────────────────────────────

func _test_score_goal_basics() -> void:
	_current_suite = "score goal — basics"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "score", "target": 500}]))

	# Not complete before any notification.
	_assert(not tracker.all_goals_complete(), "not complete before any score notification")
	_assert(tracker.get_goal_state(0).complete == false, "goal state complete=false before score")

	# Notify with score below target — still incomplete.
	var done := tracker.notify_score_updated(499)
	_assert(done.is_empty(), "score 499 < 500: no newly completed goals")
	_assert(not tracker.all_goals_complete(), "not complete at score 499")
	_assert(tracker.get_progress(0) == 499, "progress mirrors current score (499)")

	# Notify with score exactly at target — completes.
	done = tracker.notify_score_updated(500)
	_assert(done == [0], "score 500 == target: index 0 newly completed")
	_assert(tracker.all_goals_complete(), "all_goals_complete true at score 500")
	_assert(tracker.get_goal_state(0).complete == true, "goal state complete=true at score 500")
	_assert(tracker.get_progress(0) == 500, "progress mirrors current score (500)")

	# Notify above target — already complete, no re-report.
	done = tracker.notify_score_updated(800)
	_assert(done.is_empty(), "score 800 after completion: no re-report")
	_assert(tracker.get_progress(0) == 800, "progress still updates after completion (800)")


# ── Suite: score goal not complete below threshold ────────────────────────────

func _test_score_goal_not_complete_below_threshold() -> void:
	_current_suite = "score goal — remains incomplete below threshold"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "score", "target": 1000}]))

	for score in [0, 100, 500, 999]:
		var done := tracker.notify_score_updated(score)
		_assert(done.is_empty(), "score %d < 1000: not complete" % score)

	_assert(not tracker.all_goals_complete(), "still incomplete after all sub-threshold updates")


# ── Suite: multi-goal — score completes early, play continues ─────────────────

func _test_multi_goal_score_completes_early() -> void:
	_current_suite = "multi-goal — score completes early, other goals remain"
	print("\n── %s ──" % _current_suite)

	# Level has two goals: score 800, collect 5 strawberries.
	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",        "target": 800},
		{"type": "collect_crop", "crop": "strawberry", "target": 5},
	]))

	# Score goal met on "turn 10" — collect goal still open.
	var done := tracker.notify_score_updated(800)
	_assert(done == [0], "score goal (index 0) completes at 800")
	_assert(not tracker.all_goals_complete(), "all_goals_complete false — collect goal still open")
	_assert(tracker.completed_goal_count() == 1, "1 of 2 goals complete")

	# Collecting fewer than 5 strawberries — still incomplete.
	done = tracker.notify_pieces_cleared(_pieces("strawberry", 3))
	_assert(done.is_empty(), "3 strawberries cleared: collect goal not yet done")
	_assert(not tracker.all_goals_complete(), "all_goals_complete still false at 3/5 strawberries")
	_assert(tracker.get_progress(1) == 3, "collect_crop progress == 3")

	# Collecting the remaining 2 — both goals now complete.
	done = tracker.notify_pieces_cleared(_pieces("strawberry", 2))
	_assert(done == [1], "collect goal (index 1) completes at 5 strawberries")
	_assert(tracker.all_goals_complete(), "all_goals_complete true after both goals met")
	_assert(tracker.completed_goal_count() == 2, "2 of 2 goals complete")


# ── Suite: collect_crop from matches ─────────────────────────────────────────

func _test_collect_crop_from_matches() -> void:
	_current_suite = "collect_crop — increments from match clears"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "collect_crop", "crop": "carrot", "target": 6}]))

	# Simulate a 3-piece match clearing 3 carrots.
	var done := tracker.notify_pieces_cleared(_pieces("carrot", 3))
	_assert(done.is_empty(), "3 carrots cleared: goal not yet done (need 6)")
	_assert(tracker.get_progress(0) == 3, "progress == 3 after first match")

	# A second 3-piece match clears the remaining 3.
	done = tracker.notify_pieces_cleared(_pieces("carrot", 3))
	_assert(done == [0], "6th carrot cleared: goal index 0 complete")
	_assert(tracker.get_progress(0) == 6, "progress == 6 after completion")


# ── Suite: collect_crop from cascades ────────────────────────────────────────

func _test_collect_crop_from_cascades() -> void:
	_current_suite = "collect_crop — increments from cascade clears"
	print("\n── %s ──" % _current_suite)

	# Spec §6.4: cascades count toward all goals normally.
	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "collect_crop", "crop": "corn", "target": 9}]))

	# Player match: 3 corn.
	tracker.notify_pieces_cleared(_pieces("corn", 3))
	_assert(tracker.get_progress(0) == 3, "3 corn after player match")

	# Cascade 1: 3 more corn — indistinguishable to GoalTracker from a normal clear.
	tracker.notify_pieces_cleared(_pieces("corn", 3))
	_assert(tracker.get_progress(0) == 6, "6 corn after cascade 1")

	# Cascade 2: 3 more corn — goal completes.
	var done := tracker.notify_pieces_cleared(_pieces("corn", 3))
	_assert(done == [0], "cascade 2 clears final 3 corn — goal complete")
	_assert(tracker.all_goals_complete(), "all_goals_complete true after cascade fulfils goal")


# ── Suite: collect_crop from special effects ──────────────────────────────────

func _test_collect_crop_from_special_effects() -> void:
	_current_suite = "collect_crop — increments from special piece effect clears"
	print("\n── %s ──" % _current_suite)

	# Spec §5.2 (Scarecrow): "All cleared Strawberries count toward any active
	# Strawberry collection goal."
	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "collect_crop", "crop": "strawberry", "target": 7}]))

	# Scarecrow wipes 7 strawberries in one activation.
	var done := tracker.notify_pieces_cleared(_pieces("strawberry", 7))
	_assert(done == [0], "7 strawberries from Scarecrow activation complete the goal")
	_assert(tracker.all_goals_complete(), "all_goals_complete true after Scarecrow activation")


# ── Suite: collect_crop ignores wrong crop ────────────────────────────────────

func _test_collect_crop_ignores_wrong_crop() -> void:
	_current_suite = "collect_crop — ignores pieces of non-target crop"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "collect_crop", "crop": "eggplant", "target": 4}]))

	# Clear lots of non-eggplant pieces — should not advance the goal.
	var done := tracker.notify_pieces_cleared(
		_mixed_pieces({"strawberry": 5, "carrot": 5, "corn": 5})
	)
	_assert(done.is_empty(), "no eggplants cleared: goal not complete")
	_assert(tracker.get_progress(0) == 0, "progress remains 0 — wrong crops ignored")
	_assert(not tracker.all_goals_complete(), "all_goals_complete false — goal not started")

	# Now clear the target crop — should advance normally.
	done = tracker.notify_pieces_cleared(_pieces("eggplant", 4))
	_assert(done == [0], "4 eggplants cleared: goal complete")


# ── Suite: collect_crop ignores special-piece identifiers ─────────────────────

func _test_collect_crop_ignores_special_piece_identifiers() -> void:
	_current_suite = "collect_crop — ignores special-piece identifier strings"
	print("\n── %s ──" % _current_suite)

	# A collect_crop goal targeting "strawberry" must not accidentally complete
	# if a cell containing a special piece (e.g. "bushel_basket") is cleared.
	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "collect_crop", "crop": "strawberry", "target": 3}]))

	var specials: Array = [
		{"crop": "bushel_basket"},
		{"crop": "scarecrow"},
		{"crop": "watering_can"},
		{"crop": "wheelbarrow"},
	]
	var done := tracker.notify_pieces_cleared(specials)
	_assert(done.is_empty(), "special-piece clears do not advance strawberry collect goal")
	_assert(tracker.get_progress(0) == 0, "progress still 0 after special-piece clears")


# ── Suite: clear_dirt goal ────────────────────────────────────────────────────

func _test_clear_dirt_goal() -> void:
	_current_suite = "clear_dirt — completes when remaining_dirt reaches 0"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "clear_dirt"}]))

	# Board starts with 3 dirt patches — notify with decreasing counts.
	var done := tracker.notify_obstacles_updated(3, 0)
	_assert(done.is_empty(), "3 dirt remaining: not complete")
	_assert(not tracker.all_goals_complete(), "all_goals_complete false at 3 dirt")

	done = tracker.notify_obstacles_updated(2, 0)
	_assert(done.is_empty(), "2 dirt remaining: not complete")

	done = tracker.notify_obstacles_updated(1, 0)
	_assert(done.is_empty(), "1 dirt remaining: not complete")

	done = tracker.notify_obstacles_updated(0, 0)
	_assert(done == [0], "0 dirt remaining: goal index 0 complete")
	_assert(tracker.all_goals_complete(), "all_goals_complete true when all dirt cleared")

	# Idempotent — calling again with 0 dirt does not re-report.
	done = tracker.notify_obstacles_updated(0, 0)
	_assert(done.is_empty(), "second call with 0 dirt: no re-report")


# ── Suite: clear_flowers goal ─────────────────────────────────────────────────

func _test_clear_flowers_goal() -> void:
	_current_suite = "clear_flowers — completes when remaining_flowers reaches 0"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([{"type": "clear_flowers"}]))

	var done := tracker.notify_obstacles_updated(0, 2)
	_assert(done.is_empty(), "2 flowers remaining: not complete")
	_assert(not tracker.all_goals_complete(), "all_goals_complete false at 2 flowers")

	done = tracker.notify_obstacles_updated(0, 1)
	_assert(done.is_empty(), "1 flower remaining: not complete")

	done = tracker.notify_obstacles_updated(0, 0)
	_assert(done == [0], "0 flowers remaining: goal index 0 complete")
	_assert(tracker.all_goals_complete(), "all_goals_complete true when all flowers cleared")

	# Idempotent.
	done = tracker.notify_obstacles_updated(0, 0)
	_assert(done.is_empty(), "second call with 0 flowers: no re-report")


# ── Suite: all_goals_complete guard ──────────────────────────────────────────

func _test_all_goals_complete_guard() -> void:
	_current_suite = "all_goals_complete — only true when every goal satisfied"
	print("\n── %s ──" % _current_suite)

	# Three goals simultaneously — all must be met.
	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",         "target": 300},
		{"type": "clear_dirt"},
		{"type": "collect_crop",  "crop": "carrot", "target": 4},
	]))

	# Meet score goal only.
	tracker.notify_score_updated(300)
	_assert(not tracker.all_goals_complete(), "false: score met, dirt+collect still open")

	# Meet dirt goal only (score already met).
	tracker.notify_obstacles_updated(0, 0)
	_assert(not tracker.all_goals_complete(), "false: score+dirt met, collect still open")

	# Meet collect goal — now all three complete.
	tracker.notify_pieces_cleared(_pieces("carrot", 4))
	_assert(tracker.all_goals_complete(), "true: all three goals met")

	# Verify completed_goal_count.
	_assert(tracker.completed_goal_count() == 3, "completed_goal_count == 3")


# ── Suite: newly-completed indices ───────────────────────────────────────────

func _test_newly_completed_indices() -> void:
	_current_suite = "notify_* return values — correct newly-completed indices"
	print("\n── %s ──" % _current_suite)

	# Goals at indices: 0=score, 1=collect_crop, 2=clear_flowers.
	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",         "target": 200},
		{"type": "collect_crop",  "crop": "corn", "target": 3},
		{"type": "clear_flowers"},
	]))

	# Score and collect complete in the same batch of notifications.
	var done_score := tracker.notify_score_updated(200)
	_assert(done_score == [0], "score notify returns [0]")

	var done_pieces := tracker.notify_pieces_cleared(_pieces("corn", 3))
	_assert(done_pieces == [1], "pieces notify returns [1]")

	var done_obs := tracker.notify_obstacles_updated(0, 0)
	_assert(done_obs == [2], "obstacles notify returns [2]")


# ── Suite: already-complete not re-reported ───────────────────────────────────

func _test_already_complete_not_re_reported() -> void:
	_current_suite = "already-complete goals never re-appear in newly_done"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",        "target": 100},
		{"type": "collect_crop", "crop": "strawberry", "target": 2},
	]))

	# Complete both goals.
	tracker.notify_score_updated(100)
	tracker.notify_pieces_cleared(_pieces("strawberry", 2))

	# Subsequent notifications must return empty arrays.
	_assert(tracker.notify_score_updated(999).is_empty(),
		"score notify after completion: empty array")
	_assert(tracker.notify_pieces_cleared(_pieces("strawberry", 10)).is_empty(),
		"pieces notify after completion: empty array")
	_assert(tracker.notify_obstacles_updated(0, 0).is_empty(),
		"obstacles notify (irrelevant goals) after completion: empty array")


# ── Suite: progress and target accessors ─────────────────────────────────────

func _test_progress_and_target_accessors() -> void:
	_current_suite = "get_progress / get_target accessors"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",         "target": 500},
		{"type": "collect_crop",  "crop": "carrot", "target": 10},
		{"type": "clear_dirt"},
		{"type": "clear_flowers"},
	]))

	# Initial state.
	_assert(tracker.get_target(0) == 500,  "score goal target == 500")
	_assert(tracker.get_target(1) == 10,   "collect_crop goal target == 10")
	_assert(tracker.get_target(2) == 0,    "clear_dirt has no numeric target (0)")
	_assert(tracker.get_target(3) == 0,    "clear_flowers has no numeric target (0)")

	_assert(tracker.get_progress(0) == 0,  "score progress starts at 0")
	_assert(tracker.get_progress(1) == 0,  "collect_crop progress starts at 0")
	_assert(tracker.get_progress(2) == 0,  "clear_dirt progress is always 0")
	_assert(tracker.get_progress(3) == 0,  "clear_flowers progress is always 0")

	# After updates.
	tracker.notify_score_updated(250)
	tracker.notify_pieces_cleared(_pieces("carrot", 7))

	_assert(tracker.get_progress(0) == 250, "score progress == 250 after update")
	_assert(tracker.get_progress(1) == 7,   "collect_crop progress == 7 after 7 carrots")


# ── Suite: goal_count and completed_goal_count ────────────────────────────────

func _test_goal_count_accessors() -> void:
	_current_suite = "goal_count / completed_goal_count accessors"
	print("\n── %s ──" % _current_suite)

	var tracker := _make_tracker()
	tracker.init(_make_level([
		{"type": "score",        "target": 100},
		{"type": "collect_crop", "crop": "corn", "target": 3},
		{"type": "clear_dirt"},
	]))

	_assert(tracker.goal_count() == 3,           "goal_count == 3")
	_assert(tracker.completed_goal_count() == 0, "completed_goal_count == 0 initially")

	tracker.notify_score_updated(100)
	_assert(tracker.completed_goal_count() == 1, "completed_goal_count == 1 after score")

	tracker.notify_pieces_cleared(_pieces("corn", 3))
	_assert(tracker.completed_goal_count() == 2, "completed_goal_count == 2 after collect")

	tracker.notify_obstacles_updated(0, 0)
	_assert(tracker.completed_goal_count() == 3, "completed_goal_count == 3 after dirt")

	_assert(tracker.goal_count() == 3, "goal_count still 3 (unchanged)")


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
