extends Control

## FailScreen.gd
## Layer 8 — Fail Screen
##
## Displays the level-failed result. Reads its payload from ScreenData and all
## live state from SaveData. Contains NO game logic — reads state and calls
## permitted write APIs (consume_life via LivesManager, buy_life via SeedEconomy)
## then delegates navigation to ScreenRouter.

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _title_label:        Label        = $ContentContainer/TitleLabel
@onready var _goals_container:    VBoxContainer = $ContentContainer/GoalsContainer
@onready var _lives_label:        Label        = $ContentContainer/LivesDisplay/LivesLabel
@onready var _regen_label:        Label        = $ContentContainer/LivesDisplay/RegenLabel
@onready var _no_moves_label:     Label        = $ContentContainer/NoMovesLabel
@onready var _no_turns_label:     Label        = $ContentContainer/NoTurnsLabel
@onready var _retry_button:       Button       = $ButtonRow/RetryButton
@onready var _buy_life_button:    Button       = $ButtonRow/BuyLifeButton
@onready var _level_select_button:Button       = $ButtonRow/LevelSelectButton
@onready var _seed_balance_label: Label        = $SeedBalanceBar/SeedBalanceLabel

# ── Data ──────────────────────────────────────────────────────────────────────

var _data:           Dictionary           = {}
var _level_data:     LevelData            = null
var _balance:        Balance              = null
## Set of incomplete goal type strings (and crop keys) for fast lookup.
var _incomplete_set: Array[Dictionary]    = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error("FailScreen._ready: failed to load balance.tres.")

	_data = ScreenData.consume()
	if _data.is_empty():
		push_error("FailScreen._ready: no payload found in ScreenData.")

	var raw_goals: Array = _data.get("incomplete_goals", [])
	_incomplete_set.clear()
	for g in raw_goals:
		if g is Dictionary:
			_incomplete_set.append(g)

	# Load level data for full goal list.
	var level_id: int = _data.get("level_id", 0)
	if level_id > 0:
		var path := "res://resources/levels/level_%02d.tres" % level_id
		_level_data = load(path) as LevelData
		if _level_data == null:
			push_warning("FailScreen._ready: could not load level data at '%s'." % path)

	_title_label.text = "Level %d Failed" % level_id

	_build_goal_rows()
	_refresh_lives_display()
	_refresh_button_states()
	_refresh_seed_balance()
	_no_moves_label.visible = (_data.get("fail_reason", "") == "no_moves")
	_no_turns_label.visible = (_data.get("fail_reason", "") == "no_turns")

	# Connect buttons.
	_retry_button.pressed.connect(_on_retry_pressed)
	_buy_life_button.pressed.connect(_on_buy_life_pressed)
	_level_select_button.pressed.connect(_on_level_select_pressed)

	# Live signals.
	SaveData.lives_changed.connect(_on_lives_changed)
	SaveData.seeds_changed.connect(_on_seeds_changed)


func _exit_tree() -> void:
	if SaveData.lives_changed.is_connected(_on_lives_changed):
		SaveData.lives_changed.disconnect(_on_lives_changed)
	if SaveData.seeds_changed.is_connected(_on_seeds_changed):
		SaveData.seeds_changed.disconnect(_on_seeds_changed)


# ── Goal rows ─────────────────────────────────────────────────────────────────

func _build_goal_rows() -> void:
	# Clear any existing children.
	for child in _goals_container.get_children():
		child.queue_free()

	if _level_data == null:
		return

	for goal in _level_data.goals:
		var row := HBoxContainer.new()

		var desc_label := Label.new()
		desc_label.text              = GoalFormatter.format_goal(goal)
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", 15)

		var status_label := Label.new()
		status_label.add_theme_font_size_override("font_size", 15)

		if _is_goal_incomplete(goal):
			# Highlight incomplete goals in red/orange.
			desc_label.modulate   = Color("FF6B6B")
			status_label.text     = "✗"
			status_label.modulate = Color("FF6B6B")
		else:
			desc_label.modulate   = Color("88FF88")
			status_label.text     = "✓"
			status_label.modulate = Color("88FF88")

		row.add_child(desc_label)
		row.add_child(status_label)
		_goals_container.add_child(row)


## Returns true when the given goal definition is in the incomplete set.
func _is_goal_incomplete(goal: Dictionary) -> bool:
	for incomplete_goal in _incomplete_set:
		if incomplete_goal.get("type", "") != goal.get("type", ""):
			continue
		# For collect_crop, also match the crop field.
		if goal.get("type", "") == "collect_crop":
			if incomplete_goal.get("crop", "") != goal.get("crop", ""):
				continue
		return true
	return false


# ── Display refresh ───────────────────────────────────────────────────────────

func _refresh_lives_display() -> void:
	if _balance == null:
		return
	var lives:    int = SaveData.get_lives()
	var max_lives: int = int(_balance.MAX_LIVES)
	_lives_label.text = "Lives: %d / %d" % [lives, max_lives]

	# Show regen countdown only when below max.
	if lives < max_lives:
		var secs: int = LivesManager.get_seconds_until_next_life()
		if secs > 0:
			var mm: int = secs / 60
			var ss: int = secs % 60
			_regen_label.text    = "Regenerating… %d:%02d" % [mm, ss]
			_regen_label.visible = true
		else:
			_regen_label.text    = "Regenerating… 0:00"
			_regen_label.visible = true
	else:
		_regen_label.visible = false


func _refresh_button_states() -> void:
	if _balance == null:
		return
	var lives: int = SaveData.get_lives()
	var seeds: int = SaveData.get_seeds()
	var cost:  int = int(_balance.SEED_COST_LIFE)

	# Retry is available only when the player has at least 1 life.
	_retry_button.disabled = (lives == 0)

	# Buy Life is visible only when the player has 0 lives.
	_buy_life_button.visible  = (lives == 0)
	_buy_life_button.disabled = (seeds < cost)
	_buy_life_button.text     = "Buy Life (%d 🌱)" % cost


func _refresh_seed_balance() -> void:
	_seed_balance_label.text = str(SaveData.get_seeds())


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_retry_pressed() -> void:
	var level_id: int = _data.get("level_id", 0)
	if level_id <= 0:
		push_error("FailScreen._on_retry_pressed: invalid level_id in payload.")
		return
	# Life is consumed here; WinFailResolver already consumed one on fail,
	# but retry requires consuming another (spec §9 / fail screen spec §14).
	LivesManager.consume_life()
	ScreenRouter.go_level_intro(level_id)


func _on_buy_life_pressed() -> void:
	# SeedEconomy handles spend + grant atomically.
	var ok := SeedEconomy.buy_life()
	if not ok:
		push_warning("FailScreen._on_buy_life_pressed: buy_life() returned false.")
	# UI refreshes via lives_changed / seeds_changed signals.


func _on_level_select_pressed() -> void:
	ScreenRouter.go_level_select()


# ── Signal callbacks ──────────────────────────────────────────────────────────

func _on_lives_changed(_new_count: int) -> void:
	_refresh_lives_display()
	_refresh_button_states()


func _on_seeds_changed(_new_balance: int) -> void:
	_refresh_seed_balance()
	_refresh_button_states()

func _process(_delta: float) -> void:
	if _regen_label and _regen_label.visible:
		_refresh_lives_display()
