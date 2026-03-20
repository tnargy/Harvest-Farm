# Autoloaded singleton — intentionally no class_name to avoid autoload name conflict
extends Node

## ScreenRouter.gd
## Centralised scene navigation for Harvest Match.
##
## All scene path constants live here. No other file calls
## get_tree().change_scene_to_file() directly — every navigation goes through
## this autoload so paths are a single source of truth.
##
## Navigation methods that carry data write to the ScreenData autoload before
## changing scenes. The incoming scene reads ScreenData.consume() in _ready().

# ── Scene path constants ──────────────────────────────────────────────────────

const MAIN_MENU    := "res://scenes/ui/MainMenu.tscn"
const LEVEL_SELECT := "res://scenes/ui/LevelSelect.tscn"
const LEVEL_INTRO  := "res://scenes/ui/LevelIntro.tscn"
const GAMEPLAY     := "res://scenes/gameplay/GameplayScene.tscn"
const WIN_SCREEN   := "res://scenes/ui/WinScreen.tscn"
const FAIL_SCREEN  := "res://scenes/ui/FailScreen.tscn"
const SETTINGS     := "res://scenes/ui/SettingsScreen.tscn"
const NO_LIVES_OVR := "res://scenes/ui/NoLivesOverlay.tscn"


# ── Navigation methods ────────────────────────────────────────────────────────

## Navigate to the main menu.
func go_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


## Navigate to the level select screen.
func go_level_select() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)


## Navigate to the level intro screen for the given level.
## Stores the level id in SaveData so GameplayScene can read it on start.
func go_level_intro(level_id: int) -> void:
	SaveData.set_current_level(level_id)
	get_tree().change_scene_to_file(LEVEL_INTRO)


## Navigate directly into gameplay (called from LevelIntro's Start button).
## SaveData.get_current_level() must already be set before calling this.
func go_gameplay() -> void:
	get_tree().change_scene_to_file(GAMEPLAY)


## Navigate to the win screen, carrying a result payload.
## Expected payload keys:
##   "outcome"         : "win"
##   "level_id"        : int
##   "stars"           : int   (1–3)
##   "turns_remaining" : int
##   "final_score"     : int
##   "seeds_this_run"  : int
##   "bonus_seeds"     : int
func go_win(payload: Dictionary) -> void:
	ScreenData.set_payload(payload)
	get_tree().change_scene_to_file(WIN_SCREEN)


## Navigate to the fail screen, carrying a result payload.
## Expected payload keys:
##   "outcome"          : "fail"
##   "level_id"         : int
##   "lives_remaining"  : int
##   "incomplete_goals" : Array[Dictionary]
func go_fail(payload: Dictionary) -> void:
	ScreenData.set_payload(payload)
	get_tree().change_scene_to_file(FAIL_SCREEN)


## Navigate to the settings screen.
func go_settings() -> void:
	get_tree().change_scene_to_file(SETTINGS)


## Instantiate and display the no-lives overlay as a child of `parent`.
## The overlay emits a `dismissed` signal when the player dismisses it or
## a life is regenerated. This method connects that signal to queue_free the
## overlay automatically.
##
## parent – the Node that will own the overlay (typically the current screen root)
func show_no_lives_overlay(parent: Node) -> void:
	var packed: PackedScene = load(NO_LIVES_OVR)
	if packed == null:
		push_error("ScreenRouter.show_no_lives_overlay: could not load '%s'." % NO_LIVES_OVR)
		return
	var overlay: Node = packed.instantiate()
	parent.add_child(overlay)
	# Connect dismissed → queue_free so the overlay cleans itself up.
	if overlay.has_signal("dismissed"):
		overlay.dismissed.connect(overlay.queue_free)
