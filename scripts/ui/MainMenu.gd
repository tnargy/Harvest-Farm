extends Control

## MainMenu.gd
## Layer 8 — Main Menu Screen
##
## Top-level entry point of the game. Displays the Play and Settings buttons
## and a live seed balance. Contains NO game logic — read-only except for
## navigation calls through ScreenRouter.

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _play_button:        Button = $ButtonContainer/PlayButton
@onready var _settings_button:    Button = $ButtonContainer/SettingsButton
@onready var _seed_balance_label: Label  = $SeedBalanceBar/SeedBalanceLabel
@onready var _lives_label:        Label  = $SeedBalanceBar/LivesLabel


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_refresh_seed_balance()
	_refresh_lives()
	SaveData.seeds_changed.connect(_refresh_seed_balance)
	SaveData.lives_changed.connect(_refresh_lives)

	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)


func _exit_tree() -> void:
	if SaveData.seeds_changed.is_connected(_refresh_seed_balance):
		SaveData.seeds_changed.disconnect(_refresh_seed_balance)
	if SaveData.lives_changed.is_connected(_refresh_lives):
		SaveData.lives_changed.disconnect(_refresh_lives)


# ── Resource displays ─────────────────────────────────────────────────────────

func _refresh_seed_balance(_new_balance: int = 0) -> void:
	_seed_balance_label.text = str(SaveData.get_seeds())


func _refresh_lives(_new_count: int = 0) -> void:
	_lives_label.text = str(SaveData.get_lives())


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	ScreenRouter.go_level_select()


func _on_settings_pressed() -> void:
	ScreenRouter.go_settings()
