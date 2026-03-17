class_name LevelData
extends Resource

## LevelData.gd
## Per-level configuration resource. All level-specific data lives here.
## No game logic belongs in this file — only data declarations and structural
## validation. Place authored files under resources/levels/ as LevelData.tres.

# ── Identity ──────────────────────────────────────────────────────────────────

## Integer level index 1–50.
@export var level_id: int = 0

# ── Turn Limits & Star Thresholds ─────────────────────────────────────────────

## Total player turns allowed for this level.
@export var turn_limit: int = 0

## Turns remaining required to earn 2 stars.
## Must be less than turn_limit and greater than star_threshold_3.
@export var star_threshold_2: int = 0

## Turns remaining required to earn 3 stars.
## Must be less than star_threshold_2.
@export var star_threshold_3: int = 0

# ── Crop Configuration ────────────────────────────────────────────────────────

## Array of crop type identifier strings active on this level's board.
## Example: ["strawberry", "carrot", "corn", "sunflower"]
## All identifiers must be non-empty strings.
@export var crop_set: Array[String] = []

# ── Goals ─────────────────────────────────────────────────────────────────────

## Array of goal Dictionaries. All goals must be satisfied before or on the
## final turn for the player to win.
##
## Supported goal types and their required keys:
##
##   Score goal:
##     { "type": "score", "target": int }
##
##   Clear all dirt goal:
##     { "type": "clear_dirt" }
##
##   Clear all flowers goal:
##     { "type": "clear_flowers" }
##
##   Collect crop goal:
##     { "type": "collect_crop", "crop": String, "target": int }
##
## A level may contain any combination of these simultaneously.
@export var goals: Array[Dictionary] = []

# ── Grid Layout ───────────────────────────────────────────────────────────────

## 8×8 grid of cell descriptor Dictionaries.
## Outer array = rows (index 0 = top row), inner array = columns (index 0 = left).
##
## Each cell Dictionary must contain:
##   "active"   : bool   — false means this cell is a hole (dead space).
##
## Each cell Dictionary may optionally contain:
##   "obstacle" : String — one of: "none", "rock", "dirt", "flower"
##                         Omitting this key is equivalent to "none".
##   "starting_piece" : String — crop or special piece identifier placed here
##                               at level start. Omit or leave "" for random fill.
##
## Additional key required when obstacle == "flower":
##   "flower_hp" : int   — initial HP of the flower (1–3). Defaults to 3 if omitted.
##
## Cells where active == false (holes) must not declare an obstacle or starting_piece.
@export var grid_layout: Array[Array] = []

# ── Rewards ───────────────────────────────────────────────────────────────────

## Seeds awarded to the player on 3-star level completion.
@export var seed_reward_3star: int = 0

# ── Score Overrides ───────────────────────────────────────────────────────────

## Optional per-level overrides for default point values defined in balance.tres.
## Only keys present here override the balance default; all others fall back to
## the balance default.
##
## Recognised keys (matching Balance.gd scoring constant names):
##   "match_3"         → overrides SCORE_MATCH_3_PER_PIECE
##   "match_4"         → overrides SCORE_MATCH_4_PER_PIECE
##   "match_5"         → overrides SCORE_MATCH_5_PER_PIECE
##   "match_l"         → overrides SCORE_MATCH_L_PER_PIECE
##   "match_t"         → overrides SCORE_MATCH_T_PER_PIECE
##   "special_activation" → overrides SCORE_SPECIAL_ACTIVATION_BONUS
@export var score_overrides: Dictionary = {}

# ── Meta ──────────────────────────────────────────────────────────────────────

## Optional authoring metadata. Not used at runtime.
## Suggested keys: "author", "version", "notes"
@export var meta: Dictionary = {}

# ── Validation ────────────────────────────────────────────────────────────────

## Validates the structural integrity of this LevelData resource.
## Returns an Array of human-readable error strings.
## An empty array means the resource passed all checks.
func validate() -> Array[String]:
	var errors: Array[String] = []
	var prefix := "LevelData (level_id=%d):" % level_id

	# ── Identity ──
	if level_id < 1 or level_id > 50:
		errors.append("%s level_id must be between 1 and 50 (got %d)." % [prefix, level_id])

	# ── Turn limits ──
	if turn_limit <= 0:
		errors.append("%s turn_limit must be greater than 0 (got %d)." % [prefix, turn_limit])

	if star_threshold_2 <= 0:
		errors.append("%s star_threshold_2 must be greater than 0 (got %d)." % [prefix, star_threshold_2])

	if star_threshold_3 <= 0:
		errors.append("%s star_threshold_3 must be greater than 0 (got %d)." % [prefix, star_threshold_3])

	if star_threshold_2 >= turn_limit:
		errors.append(
			"%s star_threshold_2 (%d) must be less than turn_limit (%d)." \
			% [prefix, star_threshold_2, turn_limit]
		)

	if star_threshold_3 >= star_threshold_2:
		errors.append(
			"%s star_threshold_3 (%d) must be less than star_threshold_2 (%d)." \
			% [prefix, star_threshold_3, star_threshold_2]
		)

	# ── Crop set ──
	if crop_set.is_empty():
		errors.append("%s crop_set must contain at least one crop identifier." % prefix)

	for i in range(crop_set.size()):
		if crop_set[i].strip_edges() == "":
			errors.append("%s crop_set[%d] is an empty string." % [prefix, i])

	# ── Goals ──
	if goals.is_empty():
		errors.append("%s goals must contain at least one goal." % prefix)

	const VALID_GOAL_TYPES := ["score", "clear_dirt", "clear_flowers", "collect_crop"]

	for i in range(goals.size()):
		var goal: Dictionary = goals[i]

		if not goal.has("type"):
			errors.append("%s goals[%d] is missing required key 'type'." % [prefix, i])
			continue

		var gtype: String = goal["type"]

		if gtype not in VALID_GOAL_TYPES:
			errors.append(
				"%s goals[%d] has unknown type '%s'. Valid types: %s." \
				% [prefix, i, gtype, ", ".join(VALID_GOAL_TYPES)]
			)
			continue

		match gtype:
			"score":
				if not goal.has("target"):
					errors.append("%s goals[%d] (score) is missing required key 'target'." % [prefix, i])
				elif not (goal["target"] is int) or goal["target"] <= 0:
					errors.append(
						"%s goals[%d] (score) 'target' must be a positive integer (got %s)." \
						% [prefix, i, str(goal.get("target"))]
					)
			"collect_crop":
				if not goal.has("crop"):
					errors.append("%s goals[%d] (collect_crop) is missing required key 'crop'." % [prefix, i])
				elif (goal["crop"] as String).strip_edges() == "":
					errors.append("%s goals[%d] (collect_crop) 'crop' must not be empty." % [prefix, i])

				if not goal.has("target"):
					errors.append("%s goals[%d] (collect_crop) is missing required key 'target'." % [prefix, i])
				elif not (goal["target"] is int) or goal["target"] <= 0:
					errors.append(
						"%s goals[%d] (collect_crop) 'target' must be a positive integer (got %s)." \
						% [prefix, i, str(goal.get("target"))]
					)

				# Warn if collect_crop references a crop not in crop_set.
				if goal.has("crop") and (goal["crop"] as String).strip_edges() != "":
					if goal["crop"] not in crop_set:
						errors.append(
							"%s goals[%d] (collect_crop) references crop '%s' which is not in crop_set." \
							% [prefix, i, goal["crop"]]
						)

	# ── Grid layout ──
	if grid_layout.size() != 8:
		errors.append(
			"%s grid_layout must have exactly 8 rows (got %d)." % [prefix, grid_layout.size()]
		)
	else:
		const VALID_OBSTACLES := ["none", "rock", "dirt", "flower"]

		for row in range(8):
			var row_data: Array = grid_layout[row]

			if row_data.size() != 8:
				errors.append(
					"%s grid_layout[%d] must have exactly 8 columns (got %d)." \
					% [prefix, row, row_data.size()]
				)
				continue

			for col in range(8):
				var cell = row_data[col]
				var cell_id := "grid_layout[%d][%d]" % [row, col]

				if not (cell is Dictionary):
					errors.append("%s %s must be a Dictionary." % [prefix, cell_id])
					continue

				# active is required
				if not cell.has("active"):
					errors.append("%s %s is missing required key 'active'." % [prefix, cell_id])
					continue

				var is_active: bool = cell["active"]

				if not is_active:
					# Holes must not declare obstacle or starting_piece.
					if cell.has("obstacle") and cell["obstacle"] not in ["", "none"]:
						errors.append(
							"%s %s is inactive (hole) but declares obstacle '%s'. Holes must be empty." \
							% [prefix, cell_id, cell["obstacle"]]
						)
					if cell.has("starting_piece") and (cell["starting_piece"] as String).strip_edges() != "":
						errors.append(
							"%s %s is inactive (hole) but declares starting_piece '%s'. Holes must be empty." \
							% [prefix, cell_id, cell["starting_piece"]]
						)
					continue

				# Validate obstacle value if present.
				if cell.has("obstacle"):
					var obs: String = cell["obstacle"]
					if obs not in VALID_OBSTACLES:
						errors.append(
							"%s %s has unknown obstacle type '%s'. Valid types: %s." \
							% [prefix, cell_id, obs, ", ".join(VALID_OBSTACLES)]
						)

				# Flowers must have flower_hp in range 1–3.
				var obstacle_val: String = cell.get("obstacle", "none")
				if obstacle_val == "flower":
					var hp = cell.get("flower_hp", 3)
					if not (hp is int) or hp < 1 or hp > 3:
						errors.append(
							"%s %s (flower) 'flower_hp' must be an integer between 1 and 3 (got %s)." \
							% [prefix, cell_id, str(hp)]
						)

				# starting_piece, if set, must be a non-empty string.
				if cell.has("starting_piece"):
					var sp = cell["starting_piece"]
					if not (sp is String):
						errors.append(
							"%s %s 'starting_piece' must be a String (got %s)." \
							% [prefix, cell_id, str(sp)]
						)

	# ── Rewards ──
	if seed_reward_3star < 0:
		errors.append(
			"%s seed_reward_3star must be 0 or greater (got %d)." % [prefix, seed_reward_3star]
		)

	# ── Score overrides ──
	const VALID_OVERRIDE_KEYS := [
		"match_3", "match_4", "match_5", "match_l", "match_t", "special_activation"
	]
	for key in score_overrides.keys():
		if key not in VALID_OVERRIDE_KEYS:
			errors.append(
				"%s score_overrides contains unknown key '%s'. Valid keys: %s." \
				% [prefix, key, ", ".join(VALID_OVERRIDE_KEYS)]
			)
		else:
			var val = score_overrides[key]
			if not (val is int) or val <= 0:
				errors.append(
					"%s score_overrides['%s'] must be a positive integer (got %s)." \
					% [prefix, key, str(val)]
				)

	return errors
