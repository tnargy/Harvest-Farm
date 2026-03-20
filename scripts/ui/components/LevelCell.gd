class_name LevelCell
extends Button

## LevelCell.gd
## Layer 8 — Level Select cell component
##
## A self-contained Button that displays one level's number, star rating,
## and lock state. Emits cell_pressed(level_id) when the player taps an
## unlocked cell. Locked cells have disabled = true so no signal fires.
##
## Call setup() once after instantiation to configure the cell.
## Values are stored and applied in _ready() so @onready refs are guaranteed
## to exist when they are first written to.

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when the player presses this cell (only fires when unlocked).
signal cell_pressed(level_id: int)

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _number_label: Label       = $LevelNumberLabel
@onready var _star1:        Label = $StarsContainer/Star1
@onready var _star2:        Label = $StarsContainer/Star2
@onready var _star3:        Label = $StarsContainer/Star3
@onready var _lock_icon:    Label = $LockIcon

# ── Constants ─────────────────────────────────────────────────────────────────

const STAR_FILLED_COLOR := Color(1.0, 0.85, 0.1, 1.0)
const STAR_EMPTY_COLOR  := Color(0.35, 0.35, 0.35, 0.5)

# ── Pending setup data (stored until _ready fires) ────────────────────────────

var _pending_level_id: int  = 0
var _pending_stars:    int  = 0
var _pending_unlocked: bool = false
var _setup_called:     bool = false

# ── Public API ────────────────────────────────────────────────────────────────

## Configure this cell for the given level.
## level_id  – integer 1–50
## stars     – best star rating earned (0 = never completed, 1–3)
## unlocked  – whether the player may enter this level
##
## Safe to call before the node enters the scene tree; values are latched
## and applied in _ready() once @onready refs are available.
func setup(level_id: int, stars: int, unlocked: bool) -> void:
	_pending_level_id = level_id
	_pending_stars    = stars
	_pending_unlocked = unlocked
	_setup_called     = true

	# If _ready has already run (e.g. setup called after add_child), apply now.
	if is_node_ready():
		_apply_setup()


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if _setup_called:
		_apply_setup()

	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


# ── Private helpers ───────────────────────────────────────────────────────────

func _apply_setup() -> void:
	_number_label.text = str(_pending_level_id)

	# Star display — filled up to `_pending_stars`, empty beyond.
	_set_star(0, _pending_stars >= 1)
	_set_star(1, _pending_stars >= 2)
	_set_star(2, _pending_stars >= 3)

	if _pending_unlocked:
		disabled                   = false
		_lock_icon.visible         = false
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_star1.visible             = true
		_star2.visible             = true
		_star3.visible             = true
	else:
		disabled                   = true
		_lock_icon.visible         = true
		# Hide star slots on locked cells — the player hasn't seen this level.
		_star1.visible             = false
		_star2.visible             = false
		_star3.visible             = false
		mouse_default_cursor_shape = Control.CURSOR_ARROW


func _set_star(index: int, filled: bool) -> void:
	var stars: Array[Label] = [_star1, _star2, _star3]
	if index < 0 or index >= stars.size():
		return
	stars[index].modulate = STAR_FILLED_COLOR if filled else STAR_EMPTY_COLOR


# ── Button handler ────────────────────────────────────────────────────────────

func _on_pressed() -> void:
	emit_signal("cell_pressed", _pending_level_id)
