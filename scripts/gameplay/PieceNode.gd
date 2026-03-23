class_name PieceNode
extends Control

## PieceNode.gd
## Visual representation of one board piece.
## Pieces with a matching asset in assets/pieces/ show a sprite; others fall
## back to a plain colour block. Obstacle/special state is shown as a text
## glyph overlay on the Label child.
## All animations are Tween-based and return the Tween so callers can await.

# ── Piece → texture path ──────────────────────────────────────────────────────
const PIECE_TEXTURES: Dictionary = {
	"strawberry":    "res://assets/pieces/strawberry.png",
	"carrot":        "res://assets/pieces/carrot.png",
	"corn":          "res://assets/pieces/corn.png",
	"eggplant":      "res://assets/pieces/eggplant.png",
	"pumpkin":       "res://assets/pieces/pumpkin.png",
	"pumpkin-gold":  "res://assets/pieces/golden-pumpkin.png",
	"tomato":        "res://assets/pieces/tomato.png",
	"potato":        "res://assets/pieces/potato.png",
	"cabbage":       "res://assets/pieces/cabbage.png",
	"radish":        "res://assets/pieces/radish.png",
	"cucumber":      "res://assets/pieces/cucumber.png",
	"bushel_basket": "res://assets/pieces/basket.png",
	"scarecrow":     "res://assets/pieces/scarecrow.png",
	"watering_can":  "res://assets/pieces/wateringcan.png",
	"wheelbarrow":   "res://assets/pieces/wheelbarrow.png",
}

const OBSTACLE_TEXTURES: Dictionary = {
	"rock":   "res://assets/obstacles/rock.png",
	"flower": "res://assets/obstacles/sunflower.png",
}


# ── Piece → colour map ────────────────────────────────────────────────────────
# Used as fallback for pieces that have no texture asset.
const PIECE_COLORS: Dictionary = {
    "strawberry":    Color("E53935"),
    "carrot":        Color("FB8C00"),
    "corn":          Color("FDD835"),
    "eggplant":      Color("6A1B9A"),
    "pumpkin":       Color("EF6C00"),
    "tomato":        Color("E91E63"),
    "potato":        Color("A1887F"),
    "cabbage":       Color("66BB6A"),
    "bushel_basket": Color("42A5F5"),
    "scarecrow":     Color("AB47BC"),
    "watering_can":  Color("26C6DA"),
    "wheelbarrow":   Color("78909C"),
}

const OBSTACLE_COLORS: Dictionary = {
    "rock":   Color("607D8B"),
    "flower": Color("EC407A"),
}

const CROW_TEXTURE := "res://assets/obstacles/crow.png"

const EMPTY_COLOR    := Color("2A2A2A")
const NEUTRAL_COLOR  := Color("F5F0E8")  # soft parchment bg behind sprites
const CORNER_RADIUS := 6

# ── State ─────────────────────────────────────────────────────────────────────
var piece_id:   String = ""
var is_special: bool   = false
var obstacle:   String = "none"
var flower_hp:  int    = 0

var _hint_tween: Tween = null

# ── Child refs ────────────────────────────────────────────────────────────────
@onready var _panel:        Panel       = $Panel
@onready var _texture_rect: TextureRect = $Panel/TextureRect
@onready var _label:        Label       = $Panel/Label
@onready var _hp_label:     Label       = $Panel/HpLabel
@onready var _overlay_rect: TextureRect = $Panel/TextureRectOverlay

# ── Setup ─────────────────────────────────────────────────────────────────────

## Configures the visual for a given cell state. Call after adding to scene tree.
func setup(
        p_piece_id:   String,
        p_is_special: bool,
        p_obstacle:   String,
        p_flower_hp:  int
) -> void:
    piece_id   = p_piece_id
    is_special = p_is_special
    obstacle   = p_obstacle
    flower_hp  = p_flower_hp
    _refresh_visual()

# ── Visuals ───────────────────────────────────────────────────────────────────

func _refresh_visual() -> void:
    modulate = Color.WHITE
    scale    = Vector2.ONE

    var color: Color = _resolve_color()
    var style := StyleBoxFlat.new()
    style.bg_color                = color
    style.corner_radius_top_left  = CORNER_RADIUS
    style.corner_radius_top_right = CORNER_RADIUS
    style.corner_radius_bottom_left  = CORNER_RADIUS
    style.corner_radius_bottom_right = CORNER_RADIUS

    _panel.add_theme_stylebox_override("panel", style)
    _label.text = _resolve_glyph()
    _apply_texture()

    # HP label: only visible on flower cells.
    if obstacle == "flower":
        _hp_label.text = str(flower_hp)
        _hp_label.show()
    else:
        _hp_label.hide()


func _apply_texture() -> void:
    # Obstacles that occupy the full cell (rock, flower) replace the piece texture.
    var obs_path: String = OBSTACLE_TEXTURES.get(obstacle, "")
    if obs_path != "":
        _texture_rect.texture = load(obs_path)
        _texture_rect.show()
        _overlay_rect.hide()
        return

    # Show the piece texture (if any) in the base layer.
    var tex_path: String = PIECE_TEXTURES.get(piece_id, "")
    if tex_path != "":
        _texture_rect.texture = load(tex_path)
        _texture_rect.show()
    else:
        _texture_rect.texture = null
        _texture_rect.hide()

    # Dirt: render crow on top of the piece.
    if obstacle == "dirt":
        _overlay_rect.texture = load(CROW_TEXTURE)
        _overlay_rect.show()
    else:
        _overlay_rect.hide()


func _resolve_color() -> Color:
    match obstacle:
        "rock":   return Color.TRANSPARENT
        "flower": return Color.TRANSPARENT
    if piece_id != "":
        # Pieces with a sprite asset get a transparent background so the
        # PNG's own transparent areas show through cleanly.
        if piece_id in PIECE_TEXTURES:
            return Color.TRANSPARENT
        return PIECE_COLORS.get(piece_id, Color("888888"))
    return EMPTY_COLOR


func _resolve_glyph() -> String:
    if is_special:
        return "★"
    return ""

# ── Animations ────────────────────────────────────────────────────────────────

## Tweens this node to target_pos (local coordinates) over dur seconds.
func animate_move_to(target_pos: Vector2, dur: float) -> Tween:
    var tw := create_tween()
    tw.tween_property(self, "position", target_pos, dur)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    return tw


## Scales down to zero and fades out (used for matched/cleared pieces).
func animate_clear() -> Tween:
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.18)\
        .set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
    tw.tween_property(self, "modulate:a", 0.0, 0.18)
    return tw


## Drops in from above: node starts at position.y - from_y_offset and tweens
## down to its current position. Call AFTER the node has been positioned.
func animate_drop_in(from_y_offset: float) -> Tween:
    position.y -= from_y_offset
    modulate.a  = 0.0
    var tw := create_tween()
    tw.set_parallel(true)
    tw.tween_property(self, "position:y", position.y + from_y_offset, 0.30)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
    tw.tween_property(self, "modulate:a", 1.0, 0.20)
    return tw


## Nudges the node in direction then springs back (invalid-swap bounce).
## direction should be a unit vector toward the attempted swap target.
func animate_bounce(direction: Vector2) -> Tween:
    var origin  := position
    var nudge   := origin + direction * 8.0
    var tw := create_tween()
    tw.tween_property(self, "position", nudge, 0.08)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    tw.tween_property(self, "position", origin, 0.12)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
    return tw


# ── Hint ──────────────────────────────────────────────────────────────────────

## Starts a looping scale pulse to signal a valid swap hint.
## Safe to call repeatedly — clears any existing hint tween first.
func show_hint() -> void:
    clear_hint()
    pivot_offset = size / 2.0
    _hint_tween = create_tween().set_loops()
    _hint_tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.45)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
    _hint_tween.tween_property(self, "scale", Vector2.ONE, 0.45)\
        .set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)


## Stops the hint pulse and restores normal appearance.
func clear_hint() -> void:
    if _hint_tween != null and _hint_tween.is_valid():
        _hint_tween.kill()
    _hint_tween = null
    scale    = Vector2.ONE
    modulate = Color.WHITE
