# Autoloaded singleton — intentionally no class_name to avoid autoload name conflict
extends Node
#
# SeedEconomy.gd — Layer 5 Seed Economy
# Responsibilities:
# - Orchestrate seed earning and spending rules described in the spec (§11)
# - Persist and read seed balance via the SaveData autoload
# - Delegate life purchases to the LivesManager autoload (do NOT duplicate spend/grant logic)
#
# Notes:
# - All tunable values are read from resources/balance.tres via the Balance resource.
#   Never hardcode numeric constants (SEED_COST_LIFE etc. are read from Balance).
# - This Node performs orchestration only — no UI or rendering logic here.
# - SaveData and LivesManager are expected to be registered as autoloads.
#

var _balance: Balance = null
var _save = null   # SaveData autoload
var _lives = null  # LivesManager autoload

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error("SeedEconomy._ready: failed to load balance.tres — seed constants unavailable.")
	# SaveData and LivesManager are registered as autoloads in project.godot
	_save = SaveData
	_lives = LivesManager


# Public API ---------------------------------------------------------------

# Returns the current seed balance (delegates to SaveData).
func get_seeds() -> int:
	return _save.get_seeds()


# Called after each turn to flush seeds earned this turn into persistent balance.
# No-op for non-positive values.
func flush_turn_seeds(seeds_earned: int) -> void:
	if seeds_earned <= 0:
		return
	_save.add_seeds(seeds_earned)


# Called on level win. Grants seed reward only for 3-star completions and when
# the level's configured reward is positive.
func flush_level_win(level_data: LevelData, stars_earned: int) -> void:
	if stars_earned != 3:
		return
	# Defensive: ensure level_data exposes the field and it's positive.
	if level_data == null:
		return
	var reward := int(level_data.seed_reward_3star)
	if reward <= 0:
		return
	_save.add_seeds(reward)


# Returns true only when player has 0 lives AND enough seeds to cover SEED_COST_LIFE.
func can_buy_life() -> bool:
	# Defensive checks
	if _balance == null:
		push_error("SeedEconomy.can_buy_life: balance.tres not loaded.")
		return false
	if _save == null:
		push_error("SeedEconomy.can_buy_life: SaveData autoload not available.")
		return false

	var lives: int = _save.get_lives()
	if lives != 0:
		return false

	var cost := int(_balance.SEED_COST_LIFE)
	# Defensive: disallow if misconfigured
	if cost <= 0:
		return false

	return _save.get_seeds() >= cost


# Attempt to buy a life using seeds. Delegates entirely to LivesManager.
# Returns whatever LivesManager.purchase_life_with_seeds() returns.
func buy_life() -> bool:
	if _lives == null:
		push_error("SeedEconomy.buy_life: LivesManager autoload not available.")
		return false
	return _lives.purchase_life_with_seeds()
