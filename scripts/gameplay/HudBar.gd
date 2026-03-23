class_name HudBar
extends Panel

## HudBar.gd
## Reads game state from BoardState, GoalTracker, and SaveData and refreshes
## label text. Contains NO game logic — pure display.

@onready var _title_label:  Label         = $MarginContainer/VBoxContainer/TitleRow/TitleLabel
@onready var _turns_value:  Label         = $MarginContainer/VBoxContainer/StatsRow/TurnsBox/TurnsValue
@onready var _score_value:  Label         = $MarginContainer/VBoxContainer/StatsRow/ScoreBox/ScoreValue
@onready var _seeds_value:  Label         = $MarginContainer/VBoxContainer/StatsRow/SeedsBox/SeedsValue
@onready var _goals_list:   VBoxContainer = $MarginContainer/VBoxContainer/GoalsList

var _goal_labels: Array[Label] = []


## Called once when the level starts. Builds goal rows from LevelData.
func setup(level_data: LevelData, board_state: BoardState, goal_tracker: GoalTracker) -> void:
	_title_label.text = "Level %d" % level_data.level_id

	# Build one Label per goal in GoalsList.
	for child in _goals_list.get_children():
		child.queue_free()
	_goal_labels.clear()

	for i in range(goal_tracker.goal_count()):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 13)
		_goals_list.add_child(lbl)
		_goal_labels.append(lbl)

	update_hud(board_state, goal_tracker)


## Refreshes all dynamic labels. Call after every turn resolves.
func update_hud(board_state: BoardState, goal_tracker: GoalTracker) -> void:
	_turns_value.text = str(board_state.turns_remaining)
	_score_value.text = str(board_state.score)
	_seeds_value.text = str(SaveData.get_seeds())

	for i in range(goal_tracker.goal_count()):
		if i >= _goal_labels.size():
			break
		var gs = goal_tracker.get_goal_state(i)
		var lbl: Label = _goal_labels[i]
		lbl.text     = _goal_text(gs, goal_tracker.get_target(i))
		lbl.modulate = Color("88FF88") if gs.complete else Color("FFFFFF")


func _goal_text(gs: GoalTracker.GoalState, target: int) -> String:
	var gtype: String = gs.definition.get("type", "")
	match gtype:
		"score":
			return "Score: %d / %d" % [gs.progress, target]
		"collect_crop":
			var crop: String = gs.definition.get("crop", "?")
			return "%s: %d / %d" % [crop.capitalize(), gs.progress, target]
		"clear_dirt":
			return "Remove Crows" + (" ✓" if gs.complete else "")
		"clear_flowers":
			return "Clear Flowers" + (" ✓" if gs.complete else "")
		_:
			return gtype
