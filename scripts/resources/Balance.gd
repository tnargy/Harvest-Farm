class_name Balance
extends Resource

## Balance.gd
## Single source of truth for all tunable gameplay constants.
## All values are set in balance.tres — never hardcode these elsewhere.

# ── Seed Economy ──────────────────────────────────────────────────────────────

## Seeds required to purchase one life (only available when player has 0 lives).
@export var SEED_COST_LIFE: int = 0

## Seeds dropped when a Bushel Basket special piece activates.
@export var SEED_REWARD_SPECIAL_BUSHEL: int = 0

## Seeds dropped when a Scarecrow special piece activates.
@export var SEED_REWARD_SPECIAL_SCARECROW: int = 0

## Seeds dropped when a Watering Can special piece activates.
@export var SEED_REWARD_SPECIAL_WATERING_CAN: int = 0

## Seeds dropped when a Wheelbarrow special piece activates.
@export var SEED_REWARD_SPECIAL_WHEELBARROW: int = 0

# ── Cascade Multipliers ───────────────────────────────────────────────────────

## Fractional bonus added per cascade chain step.
## Formula: 1 + (CASCADE_MULTIPLIER_PER_LEVEL × chain_level)
## Example at 0.5: chain level 1 → 1.5×, chain level 2 → 2.0×
@export var CASCADE_MULTIPLIER_PER_LEVEL: float = 0.5

## Maximum total cascade multiplier regardless of chain length.
@export var CASCADE_MULTIPLIER_CAP: float = 3.0

# ── Lives System ──────────────────────────────────────────────────────────────

## Minutes of real-world time between each life regeneration tick.
@export var LIFE_REGEN_MINUTES: int = 15

## Maximum number of lives a player can hold at one time.
@export var MAX_LIVES: int = 3

# ── Default Scoring ───────────────────────────────────────────────────────────
## These are the default per-event point values used unless a level's
## score_overrides dictionary provides a replacement for a given key.

## Points awarded per piece in a 3-piece straight match (150 total).
@export var SCORE_MATCH_3_PER_PIECE: int = 50

## Points awarded per piece in a 4-piece straight match (400 total).
@export var SCORE_MATCH_4_PER_PIECE: int = 100

## Points awarded per piece in a 5-piece straight match (750 total).
@export var SCORE_MATCH_5_PER_PIECE: int = 150

## Points awarded per piece in an L-shape match (500 total).
@export var SCORE_MATCH_L_PER_PIECE: int = 100

## Points awarded per piece in a T-shape match (600 total).
@export var SCORE_MATCH_T_PER_PIECE: int = 120

## Flat bonus awarded when any special piece activates.
@export var SCORE_SPECIAL_ACTIVATION_BONUS: int = 200

# ── Helpers ───────────────────────────────────────────────────────────────────

## Returns the cascade multiplier for a given chain level, capped at
## CASCADE_MULTIPLIER_CAP.
## chain_level is 1-indexed: the first automatic cascade is chain_level 1.
func get_cascade_multiplier(chain_level: int) -> float:
	var raw: float = 1.0 + CASCADE_MULTIPLIER_PER_LEVEL * chain_level
	return minf(raw, CASCADE_MULTIPLIER_CAP)

## Returns the seed reward for a given special piece type string.
## Valid keys: "bushel_basket", "scarecrow", "watering_can", "wheelbarrow"
## Returns 0 and prints a warning for unrecognised keys.
func get_seed_reward_for_special(piece_type: String) -> int:
	match piece_type:
		"bushel_basket":
			return SEED_REWARD_SPECIAL_BUSHEL
		"scarecrow":
			return SEED_REWARD_SPECIAL_SCARECROW
		"watering_can":
			return SEED_REWARD_SPECIAL_WATERING_CAN
		"wheelbarrow":
			return SEED_REWARD_SPECIAL_WHEELBARROW
		_:
			push_warning("Balance.get_seed_reward_for_special: unknown piece type '%s'" % piece_type)
			return 0

## Returns the default score per piece for a given match shape key.
## Valid keys: "match_3", "match_4", "match_5", "match_l", "match_t"
## Returns 0 and prints a warning for unrecognised keys.
func get_default_score_per_piece(match_shape: String) -> int:
	match match_shape:
		"match_3":
			return SCORE_MATCH_3_PER_PIECE
		"match_4":
			return SCORE_MATCH_4_PER_PIECE
		"match_5":
			return SCORE_MATCH_5_PER_PIECE
		"match_l":
			return SCORE_MATCH_L_PER_PIECE
		"match_t":
			return SCORE_MATCH_T_PER_PIECE
		_:
			push_warning("Balance.get_default_score_per_piece: unknown match shape '%s'" % match_shape)
			return 0

## Validates that all required constants have been given non-zero values.
## Returns an Array of error strings. An empty array means the resource is valid.
func validate() -> Array[String]:
	var errors: Array[String] = []

	if SEED_COST_LIFE <= 0:
		errors.append("SEED_COST_LIFE must be greater than 0.")
	if SEED_REWARD_SPECIAL_BUSHEL <= 0:
		errors.append("SEED_REWARD_SPECIAL_BUSHEL must be greater than 0.")
	if SEED_REWARD_SPECIAL_SCARECROW <= 0:
		errors.append("SEED_REWARD_SPECIAL_SCARECROW must be greater than 0.")
	if SEED_REWARD_SPECIAL_WATERING_CAN <= 0:
		errors.append("SEED_REWARD_SPECIAL_WATERING_CAN must be greater than 0.")
	if SEED_REWARD_SPECIAL_WHEELBARROW <= 0:
		errors.append("SEED_REWARD_SPECIAL_WHEELBARROW must be greater than 0.")
	if CASCADE_MULTIPLIER_PER_LEVEL <= 0.0:
		errors.append("CASCADE_MULTIPLIER_PER_LEVEL must be greater than 0.")
	if CASCADE_MULTIPLIER_CAP < 1.0:
		errors.append("CASCADE_MULTIPLIER_CAP must be at least 1.0.")
	if CASCADE_MULTIPLIER_CAP < (1.0 + CASCADE_MULTIPLIER_PER_LEVEL):
		errors.append("CASCADE_MULTIPLIER_CAP is lower than one chain step would produce — check both values.")
	if LIFE_REGEN_MINUTES <= 0:
		errors.append("LIFE_REGEN_MINUTES must be greater than 0.")
	if MAX_LIVES <= 0:
		errors.append("MAX_LIVES must be greater than 0.")
	if SCORE_MATCH_3_PER_PIECE <= 0:
		errors.append("SCORE_MATCH_3_PER_PIECE must be greater than 0.")
	if SCORE_MATCH_4_PER_PIECE <= 0:
		errors.append("SCORE_MATCH_4_PER_PIECE must be greater than 0.")
	if SCORE_MATCH_5_PER_PIECE <= 0:
		errors.append("SCORE_MATCH_5_PER_PIECE must be greater than 0.")
	if SCORE_MATCH_L_PER_PIECE <= 0:
		errors.append("SCORE_MATCH_L_PER_PIECE must be greater than 0.")
	if SCORE_MATCH_T_PER_PIECE <= 0:
		errors.append("SCORE_MATCH_T_PER_PIECE must be greater than 0.")
	if SCORE_SPECIAL_ACTIVATION_BONUS <= 0:
		errors.append("SCORE_SPECIAL_ACTIVATION_BONUS must be greater than 0.")

	return errors
