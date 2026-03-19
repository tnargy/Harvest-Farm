# Autoloaded singleton — intentionally no `class_name` to avoid autoload name conflict
extends Node

# LivesManager.gd — Layer 4 Lives System
# Responsibilities:
# - Manage lives count with regeneration over real time
# - Expose API to consume lives and purchase lives with seeds
# - On app launch, compute regen intervals since saved timestamp and apply
# - Persist changes through SaveData autoload (SaveData.set_lives, set_next_regen_utc, add/spend seeds)
#
# Notes:
# - All tunable values (MAX_LIVES, LIFE_REGEN_MINUTES, SEED_COST_LIFE) are read
#   from resources/balance.tres via the Balance resource. Do NOT hardcode these values.
# - SaveData is authoritative for persisted fields (lives, next_regen_utc, seeds).
# - This Node performs orchestration only — UI/UX is done elsewhere.

var _balance: Balance = null
var _save = null  # will point to the SaveData autoload

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error("LivesManager._ready: failed to load balance.tres — lives constants unavailable.")
	# SaveData is registered as an autoload named SaveData in project.godot
	_save = SaveData
	_reconcile_regen()


# Public API ---------------------------------------------------------------

# Returns the current lives count (delegates to SaveData).
func get_lives() -> int:
	return _save.get_lives()


# Returns true when the player currently has 0 lives.
func is_out_of_lives() -> bool:
	return get_lives() == 0


# Consumes one life if available.
# Returns true if a life was consumed; false if none were available (no-op).
# When consuming a life, ensure a regen timestamp is scheduled if none exists.
func consume_life() -> bool:
	var current = _save.get_lives()
	if current <= 0:
		return false

	# Delegate the mutation to SaveData (it emits lives_changed and saves).
	_save.consume_life()

	# If we're now below max and no regen is scheduled, schedule the next tick.
	if _save.get_next_regen_utc() == 0 and _save.get_lives() < _balance.MAX_LIVES:
		var now = int(Time.get_unix_time_from_system())
		var interval = int(_balance.LIFE_REGEN_MINUTES) * 60
		_save.set_next_regen_utc(now + interval)

	return true


# Purchase one life using seeds.
# Allowed only when the player has 0 lives (spec).
# Returns true if purchase succeeded, false otherwise.
func purchase_life_with_seeds() -> bool:
	var current = _save.get_lives()
	if current > 0:
		return false

	var cost = int(_balance.SEED_COST_LIFE)
	if cost <= 0:
		# Defensive: misconfigured balance — disallow purchase.
		return false

	# Spend seeds via SaveData — it will return false if insufficient.
	if not _save.spend_seeds(cost):
		return false

	# Grant a single life and persist via SaveData.
	var new_lives = min(current + 1, int(_balance.MAX_LIVES))
	_save.set_lives(new_lives)

	# If still below max and no regen scheduled, schedule the next tick.
	if _save.get_lives() < int(_balance.MAX_LIVES) and _save.get_next_regen_utc() == 0:
		var now = int(Time.get_unix_time_from_system())
		var interval = int(_balance.LIFE_REGEN_MINUTES) * 60
		_save.set_next_regen_utc(now + interval)

	return true


# Adds `count` lives (clamped). Useful for dev commands or test helpers.
# Persists via SaveData and clears regen if max reached.
func add_lives(count: int) -> void:
	assert(count >= 0)
	if count == 0:
		return
	var new = min(_save.get_lives() + count, int(_balance.MAX_LIVES))
	_save.set_lives(new)
	if new >= int(_balance.MAX_LIVES):
		_save.set_next_regen_utc(0)


# Returns seconds remaining until the next scheduled life regeneration tick.
# If no schedule is active (next_regen_utc == 0) returns 0.
func get_seconds_until_next_life() -> int:
	var next = _save.get_next_regen_utc()
	if next == 0:
		return 0
	var now = int(Time.get_unix_time_from_system())
	var remaining = next - now
	return max(0, remaining)


# Force reconciliation entry point for tests / debug UI.
func force_reconcile() -> void:
	_reconcile_regen()


# Private helpers ---------------------------------------------------------

# Reconcile saved regen timestamp with the current time.
# Grants missed lives (possibly multiple) based on elapsed intervals and advances/clears the timestamp.
func _reconcile_regen() -> void:
	var next_regen = _save.get_next_regen_utc()
	if next_regen == 0:
		# No schedule active.
		return

	var now = int(Time.get_unix_time_from_system())
	# Nothing to do yet.
	if now < next_regen:
		return

	var interval_seconds = int(_balance.LIFE_REGEN_MINUTES) * 60
	if interval_seconds <= 0:
		# Defensive: invalid balance config; avoid division by zero.
		_save.set_next_regen_utc(0)
		return

	# Compute how many ticks have elapsed since next_regen (inclusive).
	# Example: if next_regen was at T and now == T, ticks = 1.
	var elapsed = now - next_regen
	var ticks = int(elapsed / interval_seconds) + 1

	if ticks <= 0:
		return

	var current = _save.get_lives()
	# If already at or above max, clear schedule.
	if current >= int(_balance.MAX_LIVES):
		_save.set_next_regen_utc(0)
		return

	# Grant up to available slots.
	var space = int(_balance.MAX_LIVES) - current
	var grant = min(space, ticks)
	if grant > 0:
		_save.set_lives(current + grant)

	# Advance or clear the next_regen timestamp depending on whether we reached max.
	if _save.get_lives() >= int(_balance.MAX_LIVES):
		_save.set_next_regen_utc(0)
	else:
		# Advance the schedule forward by the number of ticks that were applied.
		var new_next = next_regen + ticks * interval_seconds
		# Ensure new_next is in the future; if somehow it's still <= now, compute the next slot.
		if new_next <= now:
			var extra = int((now - new_next) / interval_seconds) + 1
			new_next += extra * interval_seconds
		_save.set_next_regen_utc(new_next)
