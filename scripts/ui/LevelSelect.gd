extends Control

## LevelSelect.gd
## Layer 8 — Level Select Screen
##
## Displays all 50 levels as a scrollable grid of LevelCell buttons.
## Each cell shows the level number, best star rating, and locked/unlocked state.
## Tapping an unlocked cell with lives available navigates to LevelIntro.
## Tapping an unlocked cell with 0 lives shows the NoLivesOverlay.
## Locked cells are disabled and cannot be interacted with.
##
## Reads all state from SaveData. Performs no mutations beyond navigation.

# ── Constants ─────────────────────────────────────────────────────────────────

const LEVEL_CELL_SCENE := preload("res://scenes/ui/components/LevelCell.tscn")
const TOTAL_LEVELS     := 50

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _back_button:        Button        = $Header/BackButton
@onready var _seed_balance_label: Label         = $Header/SeedBalanceBar/SeedBalanceLabel
@onready var _lives_label:        Label         = $Header/SeedBalanceBar/LivesLabel
@onready var _level_grid:         GridContainer = $ScrollContainer/LevelGrid

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_grid()
	_refresh_seed_balance()
	_refresh_lives()

	_back_button.pressed.connect(_on_back_pressed)
	SaveData.seeds_changed.connect(_refresh_seed_balance)
	SaveData.lives_changed.connect(_refresh_lives)


func _exit_tree() -> void:
	if SaveData.seeds_changed.is_connected(_refresh_seed_balance):
		SaveData.seeds_changed.disconnect(_refresh_seed_balance)
	if SaveData.lives_changed.is_connected(_refresh_lives):
		SaveData.lives_changed.disconnect(_refresh_lives)


# ── Grid construction ─────────────────────────────────────────────────────────

func _build_grid() -> void:
	# Clear any existing cells (e.g. on re-enter).
	for child in _level_grid.get_children():
		child.queue_free()

	for i in range(1, TOTAL_LEVELS + 1):
		var stars:     int  = SaveData.get_stars(i)
		var unlocked:  bool = SaveData.is_level_unlocked(i)
		var cell: LevelCell = LEVEL_CELL_SCENE.instantiate() as LevelCell
		cell.setup(i, stars, unlocked)
		cell.cell_pressed.connect(_on_cell_pressed)
		_level_grid.add_child(cell)


# ── Seed balance ──────────────────────────────────────────────────────────────

func _refresh_seed_balance(_new_balance: int = 0) -> void:
	_seed_balance_label.text = str(SaveData.get_seeds())


func _refresh_lives(_new_count: int = 0) -> void:
	_lives_label.text = str(SaveData.get_lives())


# ── Button / cell handlers ────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	ScreenRouter.go_main_menu()


func _on_cell_pressed(level_id: int) -> void:
	# Guard: level must be unlocked (cell should already be disabled if locked,
	# but double-check here for safety).
	if not SaveData.is_level_unlocked(level_id):
		return

	# If the player has no lives, show the overlay instead of navigating.
	if SaveData.get_lives() == 0:
		ScreenRouter.show_no_lives_overlay(self)
		return

	ScreenRouter.go_level_intro(level_id)
