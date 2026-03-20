extends CanvasLayer

## NoLivesOverlay.gd
## Layer 8 — No-Lives Overlay
##
## Displayed as a modal overlay when the player attempts to start a level
## with 0 lives. Shows a countdown to the next life regeneration and offers
## the option to purchase a life with seeds.
##
## Instantiated on-demand by ScreenRouter.show_no_lives_overlay(parent).
## Automatically dismissed when the player gains a life (regen or purchase).
## Emits `dismissed` which ScreenRouter connects to queue_free().
##
## Contains NO game logic. Reads state from SaveData, LivesManager, and
## Balance. The only write is SeedEconomy.buy_life() on button press.

# ── Signal ────────────────────────────────────────────────────────────────────

## Emitted when the overlay should close (dismiss button, backdrop tap,
## or automatic dismiss when lives > 0).
signal dismissed

# ── Child refs ────────────────────────────────────────────────────────────────

@onready var _title_label:     Label  = $Backdrop/Panel/ContentContainer/TitleLabel
@onready var _countdown_label: Label  = $Backdrop/Panel/ContentContainer/CountdownLabel
@onready var _balance_label:   Label  = $Backdrop/Panel/ContentContainer/BalanceLabel
@onready var _cost_label:      Label  = $Backdrop/Panel/ContentContainer/CostLabel
@onready var _buy_button:      Button = $Backdrop/Panel/ContentContainer/BuyLifeButton
@onready var _dismiss_button:  Button = $Backdrop/Panel/DismissButton
@onready var _countdown_timer: Timer  = $Backdrop/CountdownTimer

# ── Data ──────────────────────────────────────────────────────────────────────

var _balance: Balance = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_balance = load("res://resources/balance.tres") as Balance
	if _balance == null:
		push_error("NoLivesOverlay._ready: failed to load balance.tres.")

	# Initial display pass.
	_refresh_countdown()
	_refresh_seed_display()
	_refresh_buy_button()

	# Wire countdown timer (ticks every second to update the label).
	_countdown_timer.wait_time = 1.0
	_countdown_timer.one_shot  = false
	_countdown_timer.autostart = false
	_countdown_timer.timeout.connect(_on_countdown_tick)
	_countdown_timer.start()

	# Wire buttons.
	_buy_button.pressed.connect(_on_buy_pressed)
	_dismiss_button.pressed.connect(_on_dismiss_pressed)

	# Auto-dismiss if a life arrives (regen while overlay is open, or purchase).
	SaveData.lives_changed.connect(_on_lives_changed)
	SaveData.seeds_changed.connect(_on_seeds_changed)


func _exit_tree() -> void:
	if SaveData.lives_changed.is_connected(_on_lives_changed):
		SaveData.lives_changed.disconnect(_on_lives_changed)
	if SaveData.seeds_changed.is_connected(_on_seeds_changed):
		SaveData.seeds_changed.disconnect(_on_seeds_changed)


# ── Display refresh ───────────────────────────────────────────────────────────

func _refresh_countdown() -> void:
	var secs: int = LivesManager.get_seconds_until_next_life()
	if secs <= 0:
		_countdown_label.text = "Regenerating… 0:00"
	else:
		var mm: int = secs / 60
		var ss: int = secs % 60
		_countdown_label.text = "Regenerating… %d:%02d" % [mm, ss]


func _refresh_seed_display() -> void:
	_balance_label.text = "Your seeds: %d" % SaveData.get_seeds()

	if _balance != null:
		_cost_label.text = "Buy life: %d 🌱" % int(_balance.SEED_COST_LIFE)
	else:
		_cost_label.text = "Buy life: — 🌱"


func _refresh_buy_button() -> void:
	if _balance == null:
		_buy_button.disabled = true
		return
	var seeds: int = SaveData.get_seeds()
	var cost:  int = int(_balance.SEED_COST_LIFE)
	_buy_button.disabled = (seeds < cost)


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	var ok := SeedEconomy.buy_life()
	if not ok:
		push_warning("NoLivesOverlay._on_buy_pressed: buy_life() returned false.")
		return
	# Dismiss directly on success — don't rely solely on the signal chain.
	_emit_dismissed()


func _on_dismiss_pressed() -> void:
	_emit_dismissed()


# ── Timer callback ────────────────────────────────────────────────────────────

func _on_countdown_tick() -> void:
	_refresh_countdown()


# ── Signal callbacks ──────────────────────────────────────────────────────────

func _on_lives_changed(_new_count: int) -> void:
	# Auto-dismiss as soon as the player has at least 1 life (covers regen case).
	if SaveData.get_lives() > 0:
		_emit_dismissed()


func _on_seeds_changed(_new_balance: int) -> void:
	_refresh_seed_display()
	_refresh_buy_button()


# ── Dismiss helper ────────────────────────────────────────────────────────────

func _emit_dismissed() -> void:
	_countdown_timer.stop()
	emit_signal("dismissed")
