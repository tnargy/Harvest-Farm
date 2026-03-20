extends Control

## SettingsScreen.gd
## Layer 8 — Settings Screen
##
## Provides sound toggle, music toggle, and a two-step Reset Progress dialog.
## Reads initial toggle states from SaveData. Writes only to SaveData audio
## preferences and calls SaveData.reset() on confirmed reset.
##
## Contains NO game logic. All mutations are settings/navigation only.

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _back_button:        Button       = $Header/BackButton
@onready var _sound_toggle:       CheckButton  = $ContentContainer/SoundRow/SoundToggle
@onready var _music_toggle:       CheckButton  = $ContentContainer/MusicRow/MusicToggle
@onready var _reset_button:       Button       = $ContentContainer/ResetRow/ResetButton
@onready var _confirm_container:  HBoxContainer = $ContentContainer/ResetRow/ConfirmContainer
@onready var _confirm_yes_button: Button       = $ContentContainer/ResetRow/ConfirmContainer/ConfirmYesButton
@onready var _confirm_no_button:  Button       = $ContentContainer/ResetRow/ConfirmContainer/ConfirmNoButton


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# ── Initialise toggle states BEFORE connecting signals to prevent
	#    spurious save writes during setup.
	_sound_toggle.set_pressed_no_signal(SaveData.is_sound_enabled())
	_music_toggle.set_pressed_no_signal(SaveData.is_music_enabled())

	# ── Hide confirmation dialog initially.
	_confirm_container.visible = false
	_reset_button.disabled     = false

	# ── Wire up signals.
	_back_button.pressed.connect(_on_back_pressed)
	_sound_toggle.toggled.connect(_on_sound_toggled)
	_music_toggle.toggled.connect(_on_music_toggled)
	_reset_button.pressed.connect(_on_reset_pressed)
	_confirm_yes_button.pressed.connect(_on_confirm_yes_pressed)
	_confirm_no_button.pressed.connect(_on_confirm_no_pressed)


# ── Button / toggle handlers ──────────────────────────────────────────────────

func _on_back_pressed() -> void:
	ScreenRouter.go_main_menu()


func _on_sound_toggled(pressed: bool) -> void:
	SaveData.set_sound_enabled(pressed)


func _on_music_toggled(pressed: bool) -> void:
	SaveData.set_music_enabled(pressed)


func _on_reset_pressed() -> void:
	# First press: reveal the confirmation row and disable the reset button
	# so a second tap cannot stack another dialog.
	_confirm_container.visible = true
	_reset_button.disabled     = true


func _on_confirm_no_pressed() -> void:
	# Cancel: hide the confirmation row and re-enable the reset button.
	_confirm_container.visible = false
	_reset_button.disabled     = false


func _on_confirm_yes_pressed() -> void:
	# Confirmed: wipe all save data and return to the main menu.
	SaveData.reset()
	ScreenRouter.go_main_menu()
