class_name GoalFormatter
extends RefCounted

## GoalFormatter.gd
## Pure static helper — converts a goal Dictionary (from LevelData.goals) into
## a human-readable String for display in LevelIntro, WinScreen, and FailScreen.
##
## No state. No mutations. No node dependency. Safe to call from any context.
##
## Supported goal types:
##   { "type": "score",        "target": int }
##   { "type": "clear_dirt" }
##   { "type": "clear_flowers" }
##   { "type": "collect_crop", "crop": String, "target": int }


## Returns a short, player-facing description of the given goal Dictionary.
## Falls back to the raw type string for unknown goal types.
static func format_goal(goal: Dictionary) -> String:
	var gtype: String = goal.get("type", "")
	match gtype:
		"score":
			var target: int = goal.get("target", 0)
			return "Reach %s points" % format_number(target)
		"clear_dirt":
			return "Remove all crows"
		"clear_flowers":
			return "Clear all flowers"
		"collect_crop":
			var crop: String   = goal.get("crop", "?")
			var target: int    = goal.get("target", 0)
			return "Collect %d %s" % [target, crop.capitalize()]
		_:
			return gtype.capitalize()


## Returns a short progress string for an in-progress or completed goal.
## Used by HUD and result screens to show "X / Y" where applicable.
## Binary goals (clear_dirt, clear_flowers) return "" when incomplete and
## a checkmark string when complete.
static func format_progress(goal: Dictionary, progress: int, complete: bool) -> String:
	var gtype: String = goal.get("type", "")
	match gtype:
		"score":
			var target: int = goal.get("target", 0)
			return "%s / %s" % [format_number(progress), format_number(target)]
		"collect_crop":
			var target: int = goal.get("target", 0)
			return "%d / %d" % [progress, target]
		"clear_dirt", "clear_flowers":
			return "Done" if complete else ""
		_:
			return "Done" if complete else ""


## Formats a large integer with comma separators (e.g. 4200 → "4,200").
static func format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count  := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
