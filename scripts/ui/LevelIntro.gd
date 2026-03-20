extends Control

## LevelIntro.gd
## Layer 8 — Level Intro Screen
##
## Displays the level number, turn limit, and goal list before the player
## commits to starting. Reads level data from SaveData.get_current_level()
## (set by ScreenRouter.go_level_intro before navigation).
##
## Contains NO game logic. Read-only except for navigation calls.

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _level_label:        Label         = $ContentContainer/LevelLabel
@onready var _turn_limit_label:   Label         = $ContentContainer/TurnLimitLabel
@onready var _goals_container:    VBoxContainer = $ContentContainer/GoalsContainer
@onready var _start_button:       Button        = $ButtonRow/StartButton
@onready var _back_button:        Button        = $ButtonRow/BackButton
@onready var _seed_balance_label: Label         = $SeedBalanceBar/SeedBalanceLabel
@onready var _lives_balance_label: Label        = $SeedBalanceBar/LivesBalanceLabel

# ── Data ──────────────────────────────────────────────────────────────────────

var _level_data: LevelData = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	var level_id: int = SaveData.get_current_level()

	var path := "res://resources/levels/level_%02d.tres" % level_id
	_level_data = load(path) as LevelData

	if _level_data == null:
		push_warning("LevelIntro._ready: could not load level data at '%s'." % path)
		_level_label.text      = "Level %d" % level_id
		_turn_limit_label.text = "Turns: —"
		_start_button.disabled = true
		var err_lbl := Label.new()
		err_lbl.text = "Level data not available."
		_goals_container.add_child(err_lbl)
	else:
		_level_label.text      = "Level %d" % _level_data.level_id
		_turn_limit_label.text = "Turns: %d" % _level_data.turn_limit
		_build_goal_list()
		_start_button.disabled = false

	_refresh_seed_balance()
	_refresh_lives_balance()
	SaveData.seeds_changed.connect(_refresh_seed_balance)
	SaveData.lives_changed.connect(_refresh_lives_balance)

	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)


func _exit_tree() -> void:
	if SaveData.seeds_changed.is_connected(_refresh_seed_balance):
		SaveData.seeds_changed.disconnect(_refresh_seed_balance)
	if SaveData.lives_changed.is_connected(_refresh_lives_balance):
		SaveData.lives_changed.disconnect(_refresh_lives_balance)


# ── Goal list ─────────────────────────────────────────────────────────────────

func _build_goal_list() -> void:
	for child in _goals_container.get_children():
		child.queue_free()

	if _level_data == null:
		return

	for goal in _level_data.goals:
		var lbl := Label.new()
		lbl.text = "• " + GoalFormatter.format_goal(goal)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_goals_container.add_child(lbl)


# ── Seed balance ──────────────────────────────────────────────────────────────

func _refresh_seed_balance(_new_balance: int = 0) -> void:
	_seed_balance_label.text = str(SaveData.get_seeds())


func _refresh_lives_balance(_new_count: int = 0) -> void:
	_lives_balance_label.text = str(SaveData.get_lives())


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	ScreenRouter.go_gameplay()


func _on_back_pressed() -> void:
	ScreenRouter.go_level_select()
