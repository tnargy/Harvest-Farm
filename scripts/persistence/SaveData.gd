extends Node

## SaveData.gd — Layer 3 Persistence
##
## Autoload singleton that owns all persistent player data for Harvest Match.
## Writes to disk after every meaningful state change (level complete, life
## consumed, seeds earned or spent). Has no dependency on UI layers (4–9).
##
## Spec reference : §13 Persistence & Save Data
## Build layer    : 3 (no upstream code dependencies)
##
## Registered in project.godot as the "SaveData" autoload so every scene can
## reach it via the global name SaveData.

# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

const TOTAL_LEVELS := 50

## Path written to disk. Reassignable before calling load_or_initialize() so
## tests can redirect writes without touching the real save file.
var save_path := "user://save_data.json"

# ─────────────────────────────────────────────────────────────────────────────
# Signals
# ─────────────────────────────────────────────────────────────────────────────

## Emitted after any change to the seed balance. Carries the new balance.
signal seeds_changed(new_balance: int)

## Emitted after any change to the lives count. Carries the new count.
signal lives_changed(new_count: int)

# ─────────────────────────────────────────────────────────────────────────────
# Private state
# ─────────────────────────────────────────────────────────────────────────────

## Loaded at startup; supplies MAX_LIVES for the default-state calculation.
## Tests set this directly before calling load_or_initialize() / _apply_defaults().
var _balance: Balance = null

## Best star rating per level. Size = TOTAL_LEVELS. Index 0 → level 1.
## 0 = never completed. Valid range per element: 0–3.
var _stars: Array = []

## Seed balance. Never negative (spec §11.2).
var _seeds: int = 0

## Current lives count. Layer 4 is responsible for clamping to MAX_LIVES
## before calling set_lives(); SaveData stores whatever it receives.
var _lives: int = 3

## UTC Unix timestamp (seconds) when the next life-regeneration tick fires.
## 0 means no schedule is active (lives are at maximum or timer never started).
## Layer 4 owns the regen calculation; this field is storage only.
var _next_regen_utc: int = 0

## Sound-effects toggle. Defaults to on (spec §15).
var _sound_enabled: bool = true

## Background-music toggle. Defaults to on (spec §15).
var _music_enabled: bool = true

# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error(
			"SaveData._ready: failed to load balance.tres — "
			+ "MAX_LIVES unavailable; default state will use fallback value 3."
		)
	load_or_initialize()


## Loads save data from disk, or resets to spec defaults if no valid file
## exists or the file cannot be parsed. Call this after overriding save_path
## (e.g. in tests) to trigger a fresh load cycle.
func load_or_initialize() -> void:
	if not _load():
		_apply_defaults()

# ─────────────────────────────────────────────────────────────────────────────
# Level progress — public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns the best star rating (0–3) ever earned on level_id (1-indexed).
## 0 means the level has never been completed.
func get_stars(level_id: int) -> int:
	assert(
		level_id >= 1 and level_id <= TOTAL_LEVELS,
		"SaveData.get_stars: level_id out of range (%d)." % level_id
	)
	return _stars[level_id - 1]


## Returns true when level_id has been completed at least once (≥ 1 star).
func is_level_completed(level_id: int) -> bool:
	return get_stars(level_id) >= 1


## Returns true when the level is available to start.
## Level 1 is always unlocked. Level N unlocks when level N-1 is completed
## (spec §12.1: strict linear order).
func is_level_unlocked(level_id: int) -> bool:
	assert(
		level_id >= 1 and level_id <= TOTAL_LEVELS,
		"SaveData.is_level_unlocked: level_id out of range (%d)." % level_id
	)
	if level_id == 1:
		return true
	return is_level_completed(level_id - 1)


## Returns the level_id of the highest level that is currently unlocked (1–50).
## "Unlocked" means the player may enter it; it may or may not be completed.
## Because unlocking is strictly linear, this is the first uncompleted level
## (or TOTAL_LEVELS when every level has been beaten).
func get_highest_unlocked() -> int:
	for i in range(TOTAL_LEVELS):
		if _stars[i] == 0:
			return i + 1   # level_id is 1-indexed; this level is unlocked but not yet beaten
	# Every level has been completed — the last level is the highest unlocked.
	return TOTAL_LEVELS


## Records a completed level. Per spec §9 a star rating is never decreased:
## if the new stars value is ≤ the stored best, the best is unchanged.
## The save is always flushed because the attempt itself is a state change.
## stars must be 1–3.
func record_level_complete(level_id: int, stars: int) -> void:
	assert(
		level_id >= 1 and level_id <= TOTAL_LEVELS,
		"SaveData.record_level_complete: level_id out of range (%d)." % level_id
	)
	assert(
		stars >= 1 and stars <= 3,
		"SaveData.record_level_complete: stars out of range (%d); must be 1–3." % stars
	)
	if stars > _stars[level_id - 1]:
		_stars[level_id - 1] = stars
	_save()

# ─────────────────────────────────────────────────────────────────────────────
# Seed economy — public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns the current seed balance.
func get_seeds() -> int:
	return _seeds


## Adds amount (≥ 0) seeds to the balance. Saves immediately and emits
## seeds_changed with the updated balance.
func add_seeds(amount: int) -> void:
	assert(
		amount >= 0,
		"SaveData.add_seeds: amount must be non-negative (got %d)." % amount
	)
	_seeds += amount
	seeds_changed.emit(_seeds)
	_save()


## Attempts to deduct amount (≥ 0) seeds from the balance.
## Returns true and flushes on success.
## Returns false without mutating any state when the balance is insufficient
## (spec §11.2: balance cannot go below 0).
func spend_seeds(amount: int) -> bool:
	assert(
		amount >= 0,
		"SaveData.spend_seeds: amount must be non-negative (got %d)." % amount
	)
	if _seeds < amount:
		return false
	_seeds -= amount
	seeds_changed.emit(_seeds)
	_save()
	return true

# ─────────────────────────────────────────────────────────────────────────────
# Lives — public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns the current lives count.
func get_lives() -> int:
	return _lives


## Directly sets the lives count. Layer 4 is responsible for computing the
## correct clamped value (e.g. capping to MAX_LIVES) before calling this.
## Saves immediately and emits lives_changed.
func set_lives(count: int) -> void:
	assert(
		count >= 0,
		"SaveData.set_lives: count must be non-negative (got %d)." % count
	)
	_lives = count
	lives_changed.emit(_lives)
	_save()


## Deducts one life. No-ops silently when lives are already 0 (spec §10).
## Saves immediately and emits lives_changed on a successful deduction.
func consume_life() -> void:
	if _lives <= 0:
		return
	_lives -= 1
	lives_changed.emit(_lives)
	_save()


## Returns the UTC Unix timestamp for the next scheduled life-regen tick.
## 0 = no schedule active (lives at maximum or timer never started).
## Layer 4 reads and writes this value via the dedicated setter below.
func get_next_regen_utc() -> int:
	return _next_regen_utc


## Stores the UTC Unix timestamp for the next life-regen tick.
## Pass 0 to clear the schedule (lives are now at maximum). Saves immediately.
func set_next_regen_utc(timestamp: int) -> void:
	assert(
		timestamp >= 0,
		"SaveData.set_next_regen_utc: timestamp must be non-negative (got %d)." % timestamp
	)
	_next_regen_utc = timestamp
	_save()

# ─────────────────────────────────────────────────────────────────────────────
# Audio preferences — public API
# ─────────────────────────────────────────────────────────────────────────────

## Returns true when sound effects are enabled (default: true per spec §15).
func is_sound_enabled() -> bool:
	return _sound_enabled


## Sets the sound-effects toggle and saves immediately.
func set_sound_enabled(value: bool) -> void:
	_sound_enabled = value
	_save()


## Returns true when background music is enabled (default: true per spec §15).
func is_music_enabled() -> bool:
	return _music_enabled


## Sets the music toggle and saves immediately.
func set_music_enabled(value: bool) -> void:
	_music_enabled = value
	_save()

# ─────────────────────────────────────────────────────────────────────────────
# Reset — public API
# ─────────────────────────────────────────────────────────────────────────────

## Clears all save data and resets to the post-reset defaults described in
## spec §13:
##   lives  = Balance.MAX_LIVES  (sourced from balance.tres, never hardcoded)
##   seeds  = 0
##   stars  = all 0  (no levels completed)
##   regen  = 0  (no schedule)
##   audio  = both on
## Saves immediately after applying defaults.
func reset() -> void:
	_apply_defaults()
	_save()

# ─────────────────────────────────────────────────────────────────────────────
# Serialisation — private helpers
# ─────────────────────────────────────────────────────────────────────────────

## Resets all in-memory fields to their spec §13 post-reset defaults.
## Does NOT write to disk — callers that want persistence should call reset()
## or follow up with _save().
func _apply_defaults() -> void:
	_stars = []
	_stars.resize(TOTAL_LEVELS)
	_stars.fill(0)
	_seeds = 0
	# Source MAX_LIVES from balance.tres (spec: no hardcoded balance values).
	# Fall back to 3 only when _balance is unavailable (edge case in tests).
	_lives = _balance.MAX_LIVES if _balance != null else 3
	_next_regen_utc = 0
	_sound_enabled  = true
	_music_enabled  = true


## Serialises current in-memory state and writes it to save_path.
## Logs an error and returns without crashing if the file cannot be opened.
func _save() -> void:
	var data := {
		"version"        : 1,
		"stars"          : _stars,
		"seeds"          : _seeds,
		"lives"          : _lives,
		"next_regen_utc" : _next_regen_utc,
		"sound_enabled"  : _sound_enabled,
		"music_enabled"  : _music_enabled,
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveData._save: could not open '%s' for writing (error %d)."
			% [save_path, FileAccess.get_open_error()]
		)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


## Attempts to load and parse the save file at save_path.
## Returns true if the file was read and deserialised without error.
## Returns false without mutating any state on file-missing, read, or parse
## failures — the caller is responsible for applying defaults in that case.
func _load() -> bool:
	if not FileAccess.file_exists(save_path):
		return false

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_warning(
			"SaveData._load: could not open '%s' for reading (error %d)."
			% [save_path, FileAccess.get_open_error()]
		)
		return false

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_warning(
			"SaveData._load: JSON parse failed at line %d: %s — applying defaults."
			% [json.get_error_line(), json.get_error_message()]
		)
		return false

	var parsed = json.data
	if not (parsed is Dictionary):
		push_warning(
			"SaveData._load: unexpected root type '%s' — applying defaults." % type_string(typeof(parsed))
		)
		return false

	return _deserialize(parsed as Dictionary)


## Validates every field in a parsed save Dictionary, then atomically commits
## all values to in-memory state. Returns false (without partially mutating
## state) on any validation failure so the caller can apply clean defaults.
func _deserialize(data: Dictionary) -> bool:
	# ── Format version ────────────────────────────────────────────────────────
	var version = data.get("version", null)
	if not (version is int) or (version as int) != 1:
		push_warning(
			"SaveData._deserialize: unknown save version '%s' — applying defaults." % str(version)
		)
		return false

	# ── Stars ─────────────────────────────────────────────────────────────────
	var raw_stars = data.get("stars", null)
	if not (raw_stars is Array) or (raw_stars as Array).size() != TOTAL_LEVELS:
		push_warning(
			"SaveData._deserialize: 'stars' field is missing or wrong size — applying defaults."
		)
		return false

	var tmp_stars: Array = []
	tmp_stars.resize(TOTAL_LEVELS)
	for i in range(TOTAL_LEVELS):
		var v = (raw_stars as Array)[i]
		# JSON integers may deserialise as int or float depending on context;
		# normalise defensively.
		if not (v is int or v is float):
			push_warning(
				"SaveData._deserialize: stars[%d] is not a number — applying defaults." % i
			)
			return false
		var iv: int = int(v)
		if iv < 0 or iv > 3:
			push_warning(
				"SaveData._deserialize: stars[%d] value %d out of range 0–3 — applying defaults."
				% [i, iv]
			)
			return false
		tmp_stars[i] = iv

	# ── Seeds ─────────────────────────────────────────────────────────────────
	var seeds_val = data.get("seeds", null)
	if not (seeds_val is int or seeds_val is float):
		push_warning("SaveData._deserialize: 'seeds' is not a number — applying defaults.")
		return false
	var tmp_seeds: int = int(seeds_val)
	if tmp_seeds < 0:
		push_warning("SaveData._deserialize: 'seeds' is negative — applying defaults.")
		return false

	# ── Lives ─────────────────────────────────────────────────────────────────
	var lives_val = data.get("lives", null)
	if not (lives_val is int or lives_val is float):
		push_warning("SaveData._deserialize: 'lives' is not a number — applying defaults.")
		return false
	var tmp_lives: int = int(lives_val)
	if tmp_lives < 0:
		push_warning("SaveData._deserialize: 'lives' is negative — applying defaults.")
		return false

	# ── Next regen UTC ────────────────────────────────────────────────────────
	var regen_val = data.get("next_regen_utc", null)
	if not (regen_val is int or regen_val is float):
		push_warning(
			"SaveData._deserialize: 'next_regen_utc' is not a number — applying defaults."
		)
		return false
	var tmp_regen: int = int(regen_val)
	if tmp_regen < 0:
		push_warning(
			"SaveData._deserialize: 'next_regen_utc' is negative — applying defaults."
		)
		return false

	# ── Audio (lenient: default to true if key is missing or wrong type) ──────
	var tmp_sound: bool = bool(data.get("sound_enabled", true))
	var tmp_music: bool = bool(data.get("music_enabled", true))

	# ── Atomic commit (all fields validated; apply together) ──────────────────
	_stars          = tmp_stars
	_seeds          = tmp_seeds
	_lives          = tmp_lives
	_next_regen_utc = tmp_regen
	_sound_enabled  = tmp_sound
	_music_enabled  = tmp_music

	return true
