class_name ScoreCalculator
extends RefCounted

## ScoreCalculator.gd
## Pure stateless scoring resolver.
## Resolves points for a single MatchResult against balance.tres defaults and
## an optional score_overrides dictionary from LevelData.
## No state is held — every method is a pure function of its inputs.

# ── Public API ────────────────────────────────────────────────────────────────

## Returns the total points for a single match result.
##
## Parameters:
##   match_result  — a MatchFinder.MatchResult instance.
##   balance       — the loaded Balance resource (balance.tres).
##   score_overrides — the level's score_overrides Dictionary (may be empty).
##   cascade_level — 0 for a player-initiated match; 1, 2, … for cascades.
##                   cascade_level 0 means no cascade multiplier is applied.
##
## Returns the integer point total (before any external accumulation).
func calculate_match_score(
	match_result: MatchFinder.MatchResult,
	balance: Balance,
	score_overrides: Dictionary,
	cascade_level: int = 0
) -> int:
	var piece_count: int  = match_result.cells.size()
	var per_piece: int    = _resolve_per_piece(match_result.shape, balance, score_overrides)
	var base_points: int  = piece_count * per_piece

	var special_bonus: int = 0
	if match_result.spawns_special:
		special_bonus = _resolve_special_bonus(balance, score_overrides)

	var total_base: int = base_points + special_bonus

	if cascade_level <= 0:
		return total_base

	var multiplier: float = balance.get_cascade_multiplier(cascade_level)
	return int(float(total_base) * multiplier)


## Returns the flat special-piece activation bonus, respecting overrides.
## Used when a special piece is *activated* (not spawned).
##
## Parameters:
##   balance         — the loaded Balance resource.
##   score_overrides — the level's score_overrides Dictionary (may be empty).
##   cascade_level   — 0 for a player-initiated activation; 1+ for cascades.
func calculate_special_activation_score(
	balance: Balance,
	score_overrides: Dictionary,
	cascade_level: int = 0
) -> int:
	var bonus: int = _resolve_special_bonus(balance, score_overrides)

	if cascade_level <= 0:
		return bonus

	var multiplier: float = balance.get_cascade_multiplier(cascade_level)
	return int(float(bonus) * multiplier)


# ── Private helpers ───────────────────────────────────────────────────────────

## Resolves the per-piece point value for the given match shape.
## Checks score_overrides first; falls back to the balance default.
func _resolve_per_piece(
	shape: String,
	balance: Balance,
	score_overrides: Dictionary
) -> int:
	if score_overrides.has(shape):
		return score_overrides[shape] as int
	return balance.get_default_score_per_piece(shape)


## Resolves the special-piece activation bonus.
## Checks score_overrides["special_activation"] first; falls back to balance.
func _resolve_special_bonus(
	balance: Balance,
	score_overrides: Dictionary
) -> int:
	if score_overrides.has("special_activation"):
		return score_overrides["special_activation"] as int
	return balance.SCORE_SPECIAL_ACTIVATION_BONUS
