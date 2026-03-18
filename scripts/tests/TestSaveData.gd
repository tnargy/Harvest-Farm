extends Node

const SaveDataScript = preload("res://scripts/persistence/SaveData.gd")

## TestSaveData.gd
## Attach to a Node in scenes/tests/TestSaveData.tscn and press F6 to run.
##
## Covers all public SaveData methods and every spec §13 behavioral rule:
##
## Defaults:
##   - Fresh instance produces correct post-reset values (lives = MAX_LIVES,
##     seeds = 0, all stars = 0, audio on, regen = 0)
##
## Level progress:
##   - get_stars returns 0 for uncompleted levels
##   - record_level_complete stores the star rating
##   - star rating is NEVER decreased on replay (spec §9)
##   - level 1 is always unlocked
##   - level N unlocks only when level N-1 is completed
##   - get_highest_unlocked advances as levels are completed
##   - get_highest_unlocked returns TOTAL_LEVELS when all levels are complete
##
## Seed economy:
##   - add_seeds increases balance correctly
##   - spend_seeds deducts balance and returns true on success
##   - spend_seeds returns false without mutating balance when insufficient
##   - seed balance never goes below 0
##   - spending exact balance reduces to 0 (not negative)
##
## Lives:
##   - consume_life deducts one life per call
##   - consume_life no-ops and does not crash at 0 lives
##   - set_lives stores the given count
##
## Regen timestamp:
##   - get/set next_regen_utc round-trips correctly
##   - clearing to 0 works
##
## Audio:
##   - sound and music both default to enabled
##   - set_sound_enabled / set_music_enabled toggles persist
##
## Reset:
##   - reset() restores all fields to spec §13 defaults
##   - highest_unlocked = 1 after reset
##
## Save / load:
##   - full round-trip preserves every field faithfully
##   - corrupt JSON falls back to defaults without crashing
##   - wrong save version falls back to defaults
##   - missing file falls back to defaults
##
## Signals:
##   - seeds_changed emitted with correct new balance on add_seeds
##   - seeds_changed emitted with correct new balance on spend_seeds
##   - seeds_changed NOT emitted when spend_seeds fails (insufficient balance)
##   - lives_changed emitted with correct new count on set_lives
##   - lives_changed emitted with correct new count on consume_life
##   - lives_changed NOT emitted when consume_life no-ops at 0


# ── Test runner ───────────────────────────────────────────────────────────────

var _pass_count    := 0
var _fail_count    := 0
var _current_suite := ""

const TEST_SAVE_PATH := "user://test_save_data.json"


func _ready() -> void:
	run_all()
	_cleanup_test_file()


func run_all() -> void:
	print("=".repeat(64))
	print("TestSaveData — persistence layer (Layer 3)")
	print("=".repeat(64))

	# Defaults
	_test_defaults_lives()
	_test_defaults_seeds()
	_test_defaults_regen()
	_test_defaults_audio()
	_test_defaults_stars()

	# Level progress
	_test_get_stars_initially_zero()
	_test_is_level_completed_initially_false()
	_test_record_level_complete_stores_stars()
	_test_record_level_complete_upgrades_stars()
	_test_star_rating_never_decreased()
	_test_star_rating_never_decreased_two_star_replay()
	_test_level_1_always_unlocked_fresh()
	_test_level_1_always_unlocked_after_completion()
	_test_level_2_locked_initially()
	_test_level_2_unlocks_after_level_1_complete()
	_test_level_3_still_locked_when_only_level_1_done()
	_test_is_level_unlocked_sequential()
	_test_get_highest_unlocked_fresh()
	_test_get_highest_unlocked_after_one_completion()
	_test_get_highest_unlocked_after_several_completions()
	_test_get_highest_unlocked_all_complete()

	# Seed economy
	_test_add_seeds_increases_balance()
	_test_add_seeds_accumulates()
	_test_add_seeds_zero_is_noop()
	_test_spend_seeds_success()
	_test_spend_seeds_returns_true_on_success()
	_test_spend_seeds_exact_balance()
	_test_spend_seeds_insufficient_returns_false()
	_test_spend_seeds_insufficient_does_not_mutate()
	_test_seeds_never_negative_on_empty_balance()

	# Lives
	_test_consume_life_deducts_one()
	_test_consume_life_multiple()
	_test_consume_life_noop_at_zero()
	_test_consume_life_noop_does_not_go_negative()
	_test_set_lives_stores_value()
	_test_set_lives_to_zero()

	# Regen timestamp
	_test_regen_timestamp_default_zero()
	_test_regen_timestamp_set_and_get()
	_test_regen_timestamp_clear_to_zero()

	# Audio
	_test_audio_defaults_on()
	_test_set_sound_enabled_false()
	_test_set_sound_enabled_retoggle()
	_test_set_music_enabled_false()
	_test_set_music_enabled_retoggle()

	# Reset
	_test_reset_seeds()
	_test_reset_lives()
	_test_reset_regen()
	_test_reset_audio()
	_test_reset_stars()
	_test_reset_highest_unlocked()

	# Save / load
	_test_save_load_stars()
	_test_save_load_seeds()
	_test_save_load_lives()
	_test_save_load_regen_utc()
	_test_save_load_sound_disabled()
	_test_save_load_music_disabled()
	_test_load_missing_file_falls_back_to_defaults()
	_test_load_corrupt_json_falls_back_to_defaults()
	_test_load_wrong_version_falls_back_to_defaults()

	# Signals
	_test_seeds_changed_on_add()
	_test_seeds_changed_value_on_add()
	_test_seeds_changed_on_spend()
	_test_seeds_changed_value_on_spend()
	_test_seeds_changed_not_emitted_on_failed_spend()
	_test_lives_changed_on_set_lives()
	_test_lives_changed_value_on_set_lives()
	_test_lives_changed_on_consume()
	_test_lives_changed_value_on_consume()
	_test_lives_changed_not_emitted_when_consume_noop()

	_print_summary()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_balance() -> Balance:
	var b := Balance.new()
	b.MAX_LIVES                    = 3
	b.LIFE_REGEN_MINUTES           = 15
	b.SEED_COST_LIFE               = 30
	b.SEED_REWARD_SPECIAL_BUSHEL       = 5
	b.SEED_REWARD_SPECIAL_SCARECROW    = 10
	b.SEED_REWARD_SPECIAL_WATERING_CAN = 8
	b.SEED_REWARD_SPECIAL_WHEELBARROW  = 12
	b.CASCADE_MULTIPLIER_PER_LEVEL     = 0.5
	b.CASCADE_MULTIPLIER_CAP           = 3.0
	b.SCORE_MATCH_3_PER_PIECE          = 50
	b.SCORE_MATCH_4_PER_PIECE          = 100
	b.SCORE_MATCH_5_PER_PIECE          = 150
	b.SCORE_MATCH_L_PER_PIECE          = 100
	b.SCORE_MATCH_T_PER_PIECE          = 120
	b.SCORE_SPECIAL_ACTIVATION_BONUS   = 200
	return b


## Creates a SaveData instance with defaults applied.
## _ready() is intentionally NOT called so tests are self-contained and
## do not touch the real save file or require the autoload to be live.
## The _balance and save_path fields are set up manually instead.
func _make_sd() -> SaveDataScript:
	var sd: SaveDataScript = SaveDataScript.new()
	sd._balance  = _make_balance()
	sd.save_path = TEST_SAVE_PATH
	sd._apply_defaults()
	return sd


## Creates a fresh second SaveDataScript instance that loads from TEST_SAVE_PATH.
## Used by round-trip tests after the first instance has already called _save().
func _make_loader() -> SaveDataScript:
	var sd2: SaveDataScript = SaveDataScript.new()
	sd2._balance  = _make_balance()
	sd2.save_path = TEST_SAVE_PATH
	sd2.load_or_initialize()
	return sd2


func _cleanup_test_file() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("test_save_data.json")


# ── Signal capture ────────────────────────────────────────────────────────────

var _seeds_signal_count := 0
var _seeds_signal_last  := -1
var _lives_signal_count := 0
var _lives_signal_last  := -1


func _on_seeds_changed(new_balance: int) -> void:
	_seeds_signal_count += 1
	_seeds_signal_last   = new_balance


func _on_lives_changed(new_count: int) -> void:
	_lives_signal_count += 1
	_lives_signal_last   = new_count


func _reset_signal_captures() -> void:
	_seeds_signal_count = 0
	_seeds_signal_last  = -1
	_lives_signal_count = 0
	_lives_signal_last  = -1


# ── Suite: defaults ───────────────────────────────────────────────────────────

func _test_defaults_lives() -> void:
	_current_suite = "defaults — lives"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_lives() == 3, "lives = MAX_LIVES (3) on fresh data")


func _test_defaults_seeds() -> void:
	_current_suite = "defaults — seeds"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_seeds() == 0, "seeds = 0 on fresh data")


func _test_defaults_regen() -> void:
	_current_suite = "defaults — regen timestamp"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc = 0 on fresh data")


func _test_defaults_audio() -> void:
	_current_suite = "defaults — audio"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.is_sound_enabled(), "sound_enabled = true on fresh data")
	_assert(sd.is_music_enabled(), "music_enabled = true on fresh data")


func _test_defaults_stars() -> void:
	_current_suite = "defaults — all star ratings zero"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	# Spot checks
	_assert(sd.get_stars(1)  == 0, "stars[1]  = 0")
	_assert(sd.get_stars(25) == 0, "stars[25] = 0")
	_assert(sd.get_stars(50) == 0, "stars[50] = 0")
	# Exhaustive count check
	var all_zero := true
	for i in range(1, SaveDataScript.TOTAL_LEVELS + 1):
		if sd.get_stars(i) != 0:
			all_zero = false
			break
	_assert(all_zero, "all 50 star ratings = 0 on fresh data")


# ── Suite: level progress ─────────────────────────────────────────────────────

func _test_get_stars_initially_zero() -> void:
	_current_suite = "level progress — get_stars initially zero"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_stars(1)  == 0, "level 1 starts at 0 stars")
	_assert(sd.get_stars(10) == 0, "level 10 starts at 0 stars")
	_assert(sd.get_stars(50) == 0, "level 50 starts at 0 stars")


func _test_is_level_completed_initially_false() -> void:
	_current_suite = "level progress — is_level_completed initially false"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(not sd.is_level_completed(1),  "level 1 not completed initially")
	_assert(not sd.is_level_completed(50), "level 50 not completed initially")


func _test_record_level_complete_stores_stars() -> void:
	_current_suite = "level progress — record_level_complete stores stars"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 2)
	_assert(sd.get_stars(1) == 2,     "level 1 shows 2 stars after completion")
	_assert(sd.is_level_completed(1), "level 1 is_level_completed = true")


func _test_record_level_complete_upgrades_stars() -> void:
	_current_suite = "level progress — record_level_complete upgrades to higher stars"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(3, 1)
	_assert(sd.get_stars(3) == 1, "level 3 has 1 star after first completion")
	sd.record_level_complete(3, 3)
	_assert(sd.get_stars(3) == 3, "level 3 upgraded to 3 stars on better replay")


func _test_star_rating_never_decreased() -> void:
	_current_suite = "level progress — star rating never decreased (spec §9)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(5, 3)
	_assert(sd.get_stars(5) == 3, "level 5 has 3 stars")
	sd.record_level_complete(5, 1)
	_assert(sd.get_stars(5) == 3, "level 5 stays 3 stars after 1-star replay")


func _test_star_rating_never_decreased_two_star_replay() -> void:
	_current_suite = "level progress — 3-star not replaced by 2-star replay"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(7, 3)
	sd.record_level_complete(7, 2)
	_assert(sd.get_stars(7) == 3, "level 7 stays 3 stars after 2-star replay")


func _test_level_1_always_unlocked_fresh() -> void:
	_current_suite = "level progress — level 1 always unlocked (fresh)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.is_level_unlocked(1), "level 1 is unlocked on fresh data")


func _test_level_1_always_unlocked_after_completion() -> void:
	_current_suite = "level progress — level 1 always unlocked (after completion)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 3)
	_assert(sd.is_level_unlocked(1), "level 1 still unlocked after completion")


func _test_level_2_locked_initially() -> void:
	_current_suite = "level progress — level 2 locked initially"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(not sd.is_level_unlocked(2), "level 2 locked on fresh data")


func _test_level_2_unlocks_after_level_1_complete() -> void:
	_current_suite = "level progress — level 2 unlocks after level 1 complete"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 1)
	_assert(sd.is_level_unlocked(2), "level 2 unlocked after level 1 completed")


func _test_level_3_still_locked_when_only_level_1_done() -> void:
	_current_suite = "level progress — level 3 locked when only level 1 done"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 1)
	_assert(not sd.is_level_unlocked(3), "level 3 still locked when level 2 not done")


func _test_is_level_unlocked_sequential() -> void:
	_current_suite = "level progress — unlock follows strict linear order"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	for lvl in range(1, 6):
		_assert(not sd.is_level_unlocked(lvl + 1),
			"level %d locked before level %d completed" % [lvl + 1, lvl])
		sd.record_level_complete(lvl, 1)
		_assert(sd.is_level_unlocked(lvl + 1),
			"level %d unlocked after level %d completed" % [lvl + 1, lvl])


func _test_get_highest_unlocked_fresh() -> void:
	_current_suite = "level progress — get_highest_unlocked = 1 on fresh data"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_highest_unlocked() == 1, "highest unlocked = 1 on fresh data")


func _test_get_highest_unlocked_after_one_completion() -> void:
	_current_suite = "level progress — get_highest_unlocked = 2 after level 1 done"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 1)
	_assert(sd.get_highest_unlocked() == 2, "highest unlocked = 2 after level 1 done")


func _test_get_highest_unlocked_after_several_completions() -> void:
	_current_suite = "level progress — get_highest_unlocked advances correctly"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.record_level_complete(1, 1)
	sd.record_level_complete(2, 2)
	sd.record_level_complete(3, 3)
	_assert(sd.get_highest_unlocked() == 4, "highest unlocked = 4 after levels 1–3 done")


func _test_get_highest_unlocked_all_complete() -> void:
	_current_suite = "level progress — get_highest_unlocked = TOTAL_LEVELS when all done"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	for i in range(1, SaveDataScript.TOTAL_LEVELS + 1):
		sd.record_level_complete(i, 1)
	_assert(sd.get_highest_unlocked() == SaveDataScript.TOTAL_LEVELS,
		"highest unlocked = %d when all levels complete" % SaveDataScript.TOTAL_LEVELS)


# ── Suite: seed economy ───────────────────────────────────────────────────────

func _test_add_seeds_increases_balance() -> void:
	_current_suite = "seed economy — add_seeds increases balance"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(10)
	_assert(sd.get_seeds() == 10, "seeds = 10 after adding 10")


func _test_add_seeds_accumulates() -> void:
	_current_suite = "seed economy — add_seeds accumulates"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(10)
	sd.add_seeds(5)
	_assert(sd.get_seeds() == 15, "seeds = 15 after adding 10 then 5")


func _test_add_seeds_zero_is_noop() -> void:
	_current_suite = "seed economy — add_seeds(0) is a no-op"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(7)
	sd.add_seeds(0)
	_assert(sd.get_seeds() == 7, "balance unchanged after add_seeds(0)")


func _test_spend_seeds_success() -> void:
	_current_suite = "seed economy — spend_seeds deducts balance"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(30)
	sd.spend_seeds(20)
	_assert(sd.get_seeds() == 10, "balance = 10 after spending 20 from 30")


func _test_spend_seeds_returns_true_on_success() -> void:
	_current_suite = "seed economy — spend_seeds returns true on success"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(30)
	var ok: bool = sd.spend_seeds(30)
	_assert(ok, "spend_seeds returns true when balance is sufficient")


func _test_spend_seeds_exact_balance() -> void:
	_current_suite = "seed economy — spend_seeds with exact balance reduces to 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(30)
	sd.spend_seeds(30)
	_assert(sd.get_seeds() == 0, "balance = 0 after spending exact balance")


func _test_spend_seeds_insufficient_returns_false() -> void:
	_current_suite = "seed economy — spend_seeds returns false when insufficient (spec §11.2)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(5)
	var ok: bool = sd.spend_seeds(10)
	_assert(not ok, "spend_seeds returns false when balance is insufficient")


func _test_spend_seeds_insufficient_does_not_mutate() -> void:
	_current_suite = "seed economy — balance unchanged on failed spend"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(5)
	sd.spend_seeds(10)
	_assert(sd.get_seeds() == 5, "balance remains 5 after failed spend of 10")


func _test_seeds_never_negative_on_empty_balance() -> void:
	_current_suite = "seed economy — balance never goes below 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	var ok: bool = sd.spend_seeds(1)
	_assert(not ok,              "spend_seeds returns false on 0 balance")
	_assert(sd.get_seeds() == 0, "balance remains 0 — not negative")


# ── Suite: lives ──────────────────────────────────────────────────────────────

func _test_consume_life_deducts_one() -> void:
	_current_suite = "lives — consume_life deducts one"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.consume_life()
	_assert(sd.get_lives() == 2, "lives = 2 after one consume_life")


func _test_consume_life_multiple() -> void:
	_current_suite = "lives — consume_life deducts correctly across multiple calls"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.consume_life()
	sd.consume_life()
	_assert(sd.get_lives() == 1, "lives = 1 after two consume_life calls")
	sd.consume_life()
	_assert(sd.get_lives() == 0, "lives = 0 after three consume_life calls")


func _test_consume_life_noop_at_zero() -> void:
	_current_suite = "lives — consume_life no-ops at 0 (spec §10)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_lives(0)
	sd.consume_life()
	_assert(sd.get_lives() == 0, "lives remain 0 after consume_life at 0")


func _test_consume_life_noop_does_not_go_negative() -> void:
	_current_suite = "lives — consume_life never produces negative lives"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_lives(0)
	sd.consume_life()
	sd.consume_life()
	_assert(sd.get_lives() >= 0, "lives >= 0 after double consume_life at 0")


func _test_set_lives_stores_value() -> void:
	_current_suite = "lives — set_lives stores value"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_lives(1)
	_assert(sd.get_lives() == 1, "lives = 1 after set_lives(1)")
	sd.set_lives(3)
	_assert(sd.get_lives() == 3, "lives = 3 after set_lives(3)")


func _test_set_lives_to_zero() -> void:
	_current_suite = "lives — set_lives(0) stores 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_lives(0)
	_assert(sd.get_lives() == 0, "lives = 0 after set_lives(0)")


# ── Suite: regen timestamp ────────────────────────────────────────────────────

func _test_regen_timestamp_default_zero() -> void:
	_current_suite = "regen timestamp — default is 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc = 0 on fresh data")


func _test_regen_timestamp_set_and_get() -> void:
	_current_suite = "regen timestamp — set and get round-trips"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_next_regen_utc(1700000000)
	_assert(sd.get_next_regen_utc() == 1700000000,
		"next_regen_utc = 1700000000 after set")


func _test_regen_timestamp_clear_to_zero() -> void:
	_current_suite = "regen timestamp — can be cleared back to 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_next_regen_utc(1700000000)
	sd.set_next_regen_utc(0)
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc = 0 after clearing")


# ── Suite: audio ──────────────────────────────────────────────────────────────

func _test_audio_defaults_on() -> void:
	_current_suite = "audio — both default to enabled"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_assert(sd.is_sound_enabled(), "sound on by default")
	_assert(sd.is_music_enabled(), "music on by default")


func _test_set_sound_enabled_false() -> void:
	_current_suite = "audio — set_sound_enabled(false)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_sound_enabled(false)
	_assert(not sd.is_sound_enabled(), "sound disabled after set_sound_enabled(false)")


func _test_set_sound_enabled_retoggle() -> void:
	_current_suite = "audio — set_sound_enabled re-enable"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_sound_enabled(false)
	sd.set_sound_enabled(true)
	_assert(sd.is_sound_enabled(), "sound re-enabled after set_sound_enabled(true)")


func _test_set_music_enabled_false() -> void:
	_current_suite = "audio — set_music_enabled(false)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_music_enabled(false)
	_assert(not sd.is_music_enabled(), "music disabled after set_music_enabled(false)")


func _test_set_music_enabled_retoggle() -> void:
	_current_suite = "audio — set_music_enabled re-enable"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_music_enabled(false)
	sd.set_music_enabled(true)
	_assert(sd.is_music_enabled(), "music re-enabled after set_music_enabled(true)")


# ── Suite: reset ──────────────────────────────────────────────────────────────

func _test_reset_seeds() -> void:
	_current_suite = "reset — seeds restored to 0 (spec §13)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd._seeds = 999
	sd.reset()
	_assert(sd.get_seeds() == 0, "seeds = 0 after reset")


func _test_reset_lives() -> void:
	_current_suite = "reset — lives restored to MAX_LIVES (spec §13)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd._lives = 0
	sd.reset()
	_assert(sd.get_lives() == 3, "lives = MAX_LIVES (3) after reset")


func _test_reset_regen() -> void:
	_current_suite = "reset — regen timestamp restored to 0 (spec §13)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd._next_regen_utc = 9999999
	sd.reset()
	_assert(sd.get_next_regen_utc() == 0, "next_regen_utc = 0 after reset")


func _test_reset_audio() -> void:
	_current_suite = "reset — audio preferences restored to on"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd._sound_enabled = false
	sd._music_enabled = false
	sd.reset()
	_assert(sd.is_sound_enabled(), "sound = true after reset")
	_assert(sd.is_music_enabled(), "music = true after reset")


func _test_reset_stars() -> void:
	_current_suite = "reset — all star ratings cleared (spec §13)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd._stars[0]  = 3
	sd._stars[24] = 2
	sd._stars[49] = 1
	sd.reset()
	var all_zero := true
	for i in range(1, SaveDataScript.TOTAL_LEVELS + 1):
		if sd.get_stars(i) != 0:
			all_zero = false
			break
	_assert(all_zero, "all 50 star ratings = 0 after reset")


func _test_reset_highest_unlocked() -> void:
	_current_suite = "reset — only level 1 unlocked after reset (spec §13)"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	for i in range(1, 10):
		sd.record_level_complete(i, 1)
	sd.reset()
	_assert(sd.get_highest_unlocked() == 1,    "highest_unlocked = 1 after reset")
	_assert(sd.is_level_unlocked(1),           "level 1 unlocked after reset")
	_assert(not sd.is_level_unlocked(2),       "level 2 locked after reset")


# ── Suite: save / load ────────────────────────────────────────────────────────

func _test_save_load_stars() -> void:
	_current_suite = "save/load — star ratings preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._stars[0]  = 3   # level 1
	sd._stars[4]  = 2   # level 5
	sd._stars[49] = 1   # level 50
	_assert(sd._stars[0]  == 3, "pre-save: stars[0]  = 3")
	_assert(sd._stars[4]  == 2, "pre-save: stars[4]  = 2")
	_assert(sd._stars[49] == 1, "pre-save: stars[49] = 1")
	sd._save()
	var sd2 := _make_loader()
	_assert(sd2.get_stars(1)  == 3, "stars[1]  = 3 after load")
	_assert(sd2.get_stars(5)  == 2, "stars[5]  = 2 after load")
	_assert(sd2.get_stars(50) == 1, "stars[50] = 1 after load")
	_assert(sd2.get_stars(2)  == 0, "stars[2]  = 0 (unset) after load")


func _test_save_load_seeds() -> void:
	_current_suite = "save/load — seed balance preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._seeds = 42
	_assert(sd._seeds == 42, "pre-save: seeds = 42")
	sd._save()
	var sd2 := _make_loader()
	_assert(sd2.get_seeds() == 42, "seeds = 42 after load")


func _test_save_load_lives() -> void:
	_current_suite = "save/load — lives count preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._lives = 1
	_assert(sd._lives == 1, "pre-save: lives = 1")
	sd._save()
	var sd2 := _make_loader()
	_assert(sd2.get_lives() == 1, "lives = 1 after load")


func _test_save_load_regen_utc() -> void:
	_current_suite = "save/load — regen UTC timestamp preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._next_regen_utc = 1700000000
	_assert(sd._next_regen_utc == 1700000000, "pre-save: next_regen_utc = 1700000000")
	sd._save()
	var sd2 := _make_loader()
	_assert(sd2.get_next_regen_utc() == 1700000000,
		"next_regen_utc = 1700000000 after load")


func _test_save_load_sound_disabled() -> void:
	_current_suite = "save/load — sound_enabled = false preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._sound_enabled = false
	_assert(sd._sound_enabled == false, "pre-save: sound_enabled = false")
	sd._save()
	var sd2 := _make_loader()
	_assert(not sd2.is_sound_enabled(), "sound_enabled = false after load")


func _test_save_load_music_disabled() -> void:
	_current_suite = "save/load — music_enabled = false preserved"
	print("\n── %s ──" % _current_suite)
	var sd: SaveDataScript = _make_sd()
	sd._music_enabled = false
	_assert(sd._music_enabled == false, "pre-save: music_enabled = false")
	sd._save()
	var sd2 := _make_loader()
	_assert(not sd2.is_music_enabled(), "music_enabled = false after load")


func _test_load_missing_file_falls_back_to_defaults() -> void:
	_current_suite = "save/load — missing file falls back to defaults"
	print("\n── %s ──" % _current_suite)
	# Ensure no test file exists.
	_cleanup_test_file()
	var sd: SaveDataScript = SaveDataScript.new()
	sd._balance  = _make_balance()
	sd.save_path = TEST_SAVE_PATH
	sd.load_or_initialize()
	_assert(sd.get_seeds()          == 0, "seeds = 0 after missing-file load")
	_assert(sd.get_lives()          == 3, "lives = 3 after missing-file load")
	_assert(sd.get_stars(1)         == 0, "stars = 0 after missing-file load")
	_assert(sd.is_sound_enabled(),        "sound on after missing-file load")
	_assert(sd.is_music_enabled(),        "music on after missing-file load")


func _test_load_corrupt_json_falls_back_to_defaults() -> void:
	_current_suite = "save/load — corrupt JSON falls back to defaults"
	print("\n── %s ──" % _current_suite)
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string("this is not valid json {{{ ][")
	file.close()
	var sd: SaveDataScript = SaveDataScript.new()
	sd._balance  = _make_balance()
	sd.save_path = TEST_SAVE_PATH
	sd.load_or_initialize()
	_assert(sd.get_seeds()          == 0, "seeds = 0 after corrupt load")
	_assert(sd.get_lives()          == 3, "lives = 3 after corrupt load")
	_assert(sd.get_stars(1)         == 0, "stars = 0 after corrupt load")
	_assert(sd.is_sound_enabled(),        "sound on after corrupt load")
	_assert(sd.is_music_enabled(),        "music on after corrupt load")


func _test_load_wrong_version_falls_back_to_defaults() -> void:
	_current_suite = "save/load — wrong save version falls back to defaults"
	print("\n── %s ──" % _current_suite)
	# Write a save file with version = 99 to simulate a future/incompatible format.
	var stars_array: Array = []
	stars_array.resize(SaveDataScript.TOTAL_LEVELS)
	stars_array.fill(0)
	var data := {
		"version": 99,
		"stars": stars_array,
		"seeds": 500,
		"lives": 0,
		"next_regen_utc": 0,
		"sound_enabled": false,
		"music_enabled": false,
	}
	var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var sd: SaveDataScript = SaveDataScript.new()
	sd._balance  = _make_balance()
	sd.save_path = TEST_SAVE_PATH
	sd.load_or_initialize()
	_assert(sd.get_seeds()          == 0, "seeds = 0 after wrong-version load")
	_assert(sd.get_lives()          == 3, "lives = 3 after wrong-version load")
	_assert(sd.is_sound_enabled(),        "sound on after wrong-version load")


# ── Suite: signals ────────────────────────────────────────────────────────────

func _test_seeds_changed_on_add() -> void:
	_current_suite = "signals — seeds_changed emitted on add_seeds"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.seeds_changed.connect(_on_seeds_changed)
	sd.add_seeds(7)
	sd.seeds_changed.disconnect(_on_seeds_changed)
	_assert(_seeds_signal_count == 1, "seeds_changed emitted exactly once")


func _test_seeds_changed_value_on_add() -> void:
	_current_suite = "signals — seeds_changed carries new balance after add"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.seeds_changed.connect(_on_seeds_changed)
	sd.add_seeds(7)
	sd.seeds_changed.disconnect(_on_seeds_changed)
	_assert(_seeds_signal_last == 7, "seeds_changed value = 7")


func _test_seeds_changed_on_spend() -> void:
	_current_suite = "signals — seeds_changed emitted on successful spend"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(20)
	_reset_signal_captures()
	sd.seeds_changed.connect(_on_seeds_changed)
	sd.spend_seeds(5)
	sd.seeds_changed.disconnect(_on_seeds_changed)
	_assert(_seeds_signal_count == 1, "seeds_changed emitted on spend")


func _test_seeds_changed_value_on_spend() -> void:
	_current_suite = "signals — seeds_changed carries correct balance after spend"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(20)
	_reset_signal_captures()
	sd.seeds_changed.connect(_on_seeds_changed)
	sd.spend_seeds(5)
	sd.seeds_changed.disconnect(_on_seeds_changed)
	_assert(_seeds_signal_last == 15, "seeds_changed value = 15 after spending 5 from 20")


func _test_seeds_changed_not_emitted_on_failed_spend() -> void:
	_current_suite = "signals — seeds_changed NOT emitted when spend fails"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.add_seeds(5)
	_reset_signal_captures()
	sd.seeds_changed.connect(_on_seeds_changed)
	sd.spend_seeds(10)   # should fail — balance insufficient
	sd.seeds_changed.disconnect(_on_seeds_changed)
	_assert(_seeds_signal_count == 0, "seeds_changed not emitted on failed spend")


func _test_lives_changed_on_set_lives() -> void:
	_current_suite = "signals — lives_changed emitted on set_lives"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.lives_changed.connect(_on_lives_changed)
	sd.set_lives(2)
	sd.lives_changed.disconnect(_on_lives_changed)
	_assert(_lives_signal_count == 1, "lives_changed emitted once on set_lives")


func _test_lives_changed_value_on_set_lives() -> void:
	_current_suite = "signals — lives_changed carries correct count after set_lives"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.lives_changed.connect(_on_lives_changed)
	sd.set_lives(2)
	sd.lives_changed.disconnect(_on_lives_changed)
	_assert(_lives_signal_last == 2, "lives_changed value = 2")


func _test_lives_changed_on_consume() -> void:
	_current_suite = "signals — lives_changed emitted on consume_life"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.lives_changed.connect(_on_lives_changed)
	sd.consume_life()
	sd.lives_changed.disconnect(_on_lives_changed)
	_assert(_lives_signal_count == 1, "lives_changed emitted once on consume_life")


func _test_lives_changed_value_on_consume() -> void:
	_current_suite = "signals — lives_changed carries correct count after consume"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	_reset_signal_captures()
	sd.lives_changed.connect(_on_lives_changed)
	sd.consume_life()
	sd.lives_changed.disconnect(_on_lives_changed)
	_assert(_lives_signal_last == 2, "lives_changed value = 2 after consuming from 3")


func _test_lives_changed_not_emitted_when_consume_noop() -> void:
	_current_suite = "signals — lives_changed NOT emitted when consume_life no-ops at 0"
	print("\n── %s ──" % _current_suite)
	var sd := _make_sd()
	sd.set_lives(0)
	_reset_signal_captures()
	sd.lives_changed.connect(_on_lives_changed)
	sd.consume_life()   # should no-op — no signal
	sd.lives_changed.disconnect(_on_lives_changed)
	_assert(_lives_signal_count == 0, "lives_changed not emitted on no-op consume at 0")


# ── Assertion helper ──────────────────────────────────────────────────────────

func _assert(condition: bool, description: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  %s" % description)
	else:
		_fail_count += 1
		print("  FAIL  [%s] %s" % [_current_suite, description])


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	print("\n" + "=".repeat(64))
	if _fail_count == 0:
		print("RESULT: ALL %d TESTS PASSED" % total)
	else:
		print("RESULT: %d / %d PASSED — %d FAILED" % [_pass_count, total, _fail_count])
	print("=".repeat(64))
