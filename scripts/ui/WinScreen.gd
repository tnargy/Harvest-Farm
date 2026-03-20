extends Control

## WinScreen.gd
## Layer 8 — Win Screen
##
## Displays the result of a won level: star rating, final score, seeds earned,
## and the list of completed goals. Provides Next Level and Level Select buttons.
##
## Reads all display data from ScreenData.consume() (written by WinFailResolver)
## and from SaveData. Performs NO game logic and NO mutations beyond navigation.

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _level_label:       Label         = $ContentContainer/LevelLabel
@onready var _star1:             Label         = $ContentContainer/StarsContainer/Star1
@onready var _star2:             Label         = $ContentContainer/StarsContainer/Star2
@onready var _star3:             Label         = $ContentContainer/StarsContainer/Star3
@onready var _score_label:       Label         = $ContentContainer/ScoreLabel
@onready var _seeds_label:       Label         = $ContentContainer/SeedsEarnedLabel
@onready var _goals_container:   VBoxContainer = $ContentContainer/GoalsContainer
@onready var _next_level_button: Button        = $ButtonRow/NextLevelButton
@onready var _level_select_btn:  Button        = $ButtonRow/LevelSelectButton
@onready var _seed_balance_label: Label        = $SeedBalanceBar/SeedBalanceLabel

# ── Runtime data ──────────────────────────────────────────────────────────────

var _data: Dictionary = {}
var _stars_earned: int = 0

# ── Textures (set in editor or loaded here as fallback) ───────────────────────

const STAR_FILLED_COLOR  := Color(1.0, 0.85, 0.1, 1.0)
const STAR_EMPTY_COLOR   := Color(0.4, 0.4, 0.4, 0.5)
const STAR_STAGGER_SEC   := 0.35
const STAR_ANIM_DURATION := 0.25


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_data = ScreenData.consume()

	if _data.is_empty():
		push_error("WinScreen._ready: ScreenData payload is empty — arriving without WinFailResolver data.")
		_level_label.text = "Level ?"
		return

	_stars_earned = _data.get("stars", 1)
	var level_id: int    = _data.get("level_id", 1)
	var final_score: int = _data.get("final_score", 0)
	var seeds_run: int   = _data.get("seeds_this_run", 0)
	var bonus_seeds: int = _data.get("bonus_seeds", 0)
	var total_seeds: int = seeds_run + bonus_seeds

	# ── Level title ───────────────────────────────────────────────────────────
	_level_label.text = "Level %d Complete!" % level_id

	# ── Score ─────────────────────────────────────────────────────────────────
	_score_label.text = "Score: %s" % GoalFormatter.format_number(final_score)

	# ── Seeds earned this run ─────────────────────────────────────────────────
	if total_seeds > 0:
		_seeds_label.text    = "+%d seeds" % total_seeds
		_seeds_label.visible = true
	else:
		_seeds_label.visible = false

	# ── Goal list (all completed) ─────────────────────────────────────────────
	_build_goal_list(level_id)

	# ── Stars (start dimmed, animate in) ─────────────────────────────────────
	_set_star_color(_star1, false)
	_set_star_color(_star2, false)
	_set_star_color(_star3, false)
	_animate_stars(_stars_earned)

	# ── Next Level button ─────────────────────────────────────────────────────
	_refresh_next_level_button(level_id)

	# ── Seed balance display ──────────────────────────────────────────────────
	_refresh_seed_balance()
	SaveData.seeds_changed.connect(_refresh_seed_balance)

	_next_level_button.pressed.connect(_on_next_level_button_pressed)
	_level_select_btn.pressed.connect(_on_level_select_button_pressed)


# ── Goal list ─────────────────────────────────────────────────────────────────

func _build_goal_list(level_id: int) -> void:
	for child in _goals_container.get_children():
		child.queue_free()

	var path := "res://resources/levels/level_%02d.tres" % level_id
	var level_data := load(path) as LevelData
	if level_data == null:
		return

	for goal in level_data.goals:
		var lbl := Label.new()
		lbl.text     = "✓  " + GoalFormatter.format_goal(goal)
		lbl.modulate = Color("88FF88")
		lbl.add_theme_font_size_override("font_size", 15)
		_goals_container.add_child(lbl)


# ── Star animation ────────────────────────────────────────────────────────────

func _animate_stars(count: int) -> void:
	var stars: Array[Label] = [_star1, _star2, _star3]
	for i in range(count):
		var star: Label = stars[i]
		var delay: float      = i * STAR_STAGGER_SEC
		_tween_star_in(star, delay)


func _tween_star_in(star: Label, delay: float) -> void:
	star.scale   = Vector2(0.5, 0.5)
	star.pivot_offset = star.size * 0.5

	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): _set_star_color(star, true))
	tw.tween_property(star, "scale", Vector2(1.3, 1.3), STAR_ANIM_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(star, "scale", Vector2(1.0, 1.0), STAR_ANIM_DURATION * 0.5) \
		.set_ease(Tween.EASE_IN_OUT)


func _set_star_color(star: Label, filled: bool) -> void:
	star.modulate = STAR_FILLED_COLOR if filled else STAR_EMPTY_COLOR


# ── Next Level button state ───────────────────────────────────────────────────

func _refresh_next_level_button(level_id: int) -> void:
	if level_id >= 50:
		_next_level_button.visible = false
		return

	_next_level_button.visible  = true
	_next_level_button.disabled = not SaveData.is_level_unlocked(level_id + 1)


# ── Seed balance ──────────────────────────────────────────────────────────────

func _refresh_seed_balance(_new_balance: int = 0) -> void:
	_seed_balance_label.text = str(SaveData.get_seeds())


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_next_level_button_pressed() -> void:
	var level_id: int = _data.get("level_id", 1)
	if level_id >= 50:
		return
	ScreenRouter.go_level_intro(level_id + 1)


func _on_level_select_button_pressed() -> void:
	ScreenRouter.go_level_select()
