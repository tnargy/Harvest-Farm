# Harvest Match — Game Specification

**Version 1.1 · Godot Engine · Match-3 Puzzle Game**

---

## 1. Overview

A casual match-3 puzzle game set on a farm. Players swap adjacent crop pieces on an 8×8 grid to form matches of 3 or more. Each level presents one or more goals that must all be achieved within a fixed turn limit. There is no time pressure. The game ships with 50 levels and persists all progress between sessions.

---

## 2. Balance Data File

A single `balance.tres` resource file contains all tunable constants. No balance value is hardcoded elsewhere in the codebase. The following constants must be defined there:

| Constant | Description |
|---|---|
| `SEED_COST_LIFE` | Seeds required to purchase one life |
| `SEED_REWARD_SPECIAL_BUSHEL` | Seeds dropped when Bushel Basket activates |
| `SEED_REWARD_SPECIAL_SCARECROW` | Seeds dropped when Scarecrow activates |
| `SEED_REWARD_SPECIAL_WATERING_CAN` | Seeds dropped when Watering Can activates |
| `SEED_REWARD_SPECIAL_WHEELBARROW` | Seeds dropped when Wheelbarrow activates |
| `CASCADE_MULTIPLIER_PER_LEVEL` | Fractional bonus added per cascade chain step (default suggestion: 0.5) |
| `CASCADE_MULTIPLIER_CAP` | Maximum total cascade multiplier regardless of chain length (default suggestion: 3.0) |
| `LIFE_REGEN_MINUTES` | Minutes per life regeneration (set to 15) |
| `MAX_LIVES` | Maximum lives a player can hold (set to 3) |

---

## 3. Grid & Board

### 3.1 Dimensions

Every level uses an 8×8 grid of cells. Each cell is either active or inactive. Inactive cells (holes) are dead space — they hold no piece, pieces cannot fall through them, and they cannot be targeted by any game mechanic.

### 3.2 Crop pieces

Standard interactable pieces. New crop types are introduced progressively across levels to increase difficulty. All crop types present on the board at any time are treated identically by match logic.

| Introduced at level | Crops |
|---|---|
| 1 | Strawberry, Carrot, Corn, Sunflower |
| Defined per level in level data | Additional crops added as the designer specifies |

### 3.3 Obstacle types

| Obstacle | Behavior | Removable? |
|---|---|---|
| Hole | Permanently inactive cell. No piece ever occupies it. | No |
| Rock | Occupies a cell. Cannot be swapped, matched, or targeted by any mechanic. Permanent for the level duration. | No |
| Dirt patch | Underlays a normal or special piece. Cleared when a match is made that includes or is orthogonally adjacent to that cell. A piece — including a special piece — sitting on top of dirt is unaffected by its own presence; dirt clears only via a match event. | Yes — 1 hit |
| Flower | Occupies a full cell. Cannot hold a piece on top. Has 3 HP. Each orthogonally adjacent match reduces HP by 1. Visual states: Wilted (3 HP) → Budding (2 HP) → Blooming (1 HP) → Cleared (0 HP). | Yes — 3 hits |

**Behavioral scenario — dirt patch with special piece on top**
> **Given** a Watering Can special piece has fallen via gravity onto a dirt patch cell at (3,4),
> **when** no match has yet been made adjacent to (3,4),
> **then** the dirt patch remains. It clears only when a match is made that includes or is orthogonally adjacent to (3,4).

**Behavioral scenario — flower hit progression**
> **Given** a Wilted flower at (5,2),
> **when** a match is made at (5,3) — orthogonally adjacent,
> **then** the flower transitions to Budding state. Two more adjacent matches are required to clear it.

---

## 4. Match Rules

### 4.1 Valid match shapes

| Shape | Minimum pieces | Special piece spawned |
|---|---|---|
| Straight (row or column) — 3 | 3 | None |
| Straight — 4 in a line | 4 | Wheelbarrow |
| Straight — 5 in a line | 5 | Bushel Basket |
| L-shape (3 + 2 at corner) | 5 | Watering Can |
| T-shape (3 + 2 crossing) | 5 | Scarecrow |

A swap is only permitted if it results in a valid match of 3 or more for at least one of the swapped pieces. Only orthogonal swaps are permitted (no diagonal). Invalid swap attempts are rejected — the pieces animate back to their original positions and no turn is consumed.

**Behavioral scenario — invalid swap**
> **Given** no valid match would result from swapping pieces at (2,2) and (2,3),
> **when** the player attempts that swap,
> **then** the pieces animate toward each other and return to their starting positions. No turn is consumed.

---

## 5. Special Pieces

### 5.1 Creation

When a qualifying match completes, a special piece spawns in the cell where the player initiated the swap. If that cell is not clean (has a dirt patch underneath), the special piece still spawns there — it sits on top of the dirt, which is not cleared by the spawn event. Special pieces only fail to spawn if the swap-origin cell is a flower or rock cell, which cannot occur under normal play rules.

Special pieces cannot be combined. Swapping two special pieces together is an invalid move — it is rejected, the pieces animate back, and no turn is consumed.

### 5.2 Special piece catalog

| Name | Trigger | Activation effect | Seeds dropped |
|---|---|---|---|
| Wheelbarrow | 4 in a line | Clears the entire row AND entire column it occupies at activation (full cross pattern). | `SEED_REWARD_SPECIAL_WHEELBARROW` |
| Bushel Basket | 5 in a line | Clears all pieces in either the row or the column it occupies, determined by match orientation: horizontal match → clears row; vertical match → clears column. | `SEED_REWARD_SPECIAL_BUSHEL` |
| Watering Can | L-shape | Clears all pieces in the 3×3 area centered on the cell it occupies at activation. | `SEED_REWARD_SPECIAL_WATERING_CAN` |
| Scarecrow | T-shape | Clears all pieces on the board that share the same crop type as the piece it was swapped with. | `SEED_REWARD_SPECIAL_SCARECROW` |

Activation occurs when a special piece is included in a valid swap. The effect resolves before gravity and refill run. Cleared cells from special piece effects count as adjacent to neighboring obstacles for the purpose of clearing dirt patches and damaging flowers.

**Behavioral scenario — Bushel Basket orientation**
> **Given** a Bushel Basket was created from a horizontal 5-in-a-line match and sits at (4,4),
> **when** the player activates it,
> **then** all pieces in row 4 are cleared. The column is not affected.

**Behavioral scenario — Scarecrow activation**
> **Given** a Scarecrow at (4,4) and 7 Strawberry pieces scattered across the board,
> **when** the player swaps the Scarecrow with an adjacent Strawberry,
> **then** all 7 Strawberry pieces on the board are removed simultaneously. The Scarecrow is consumed. All cleared Strawberries count toward any active Strawberry collection goal.

---

## 6. Gravity & Refill

### 6.1 Gravity

After any pieces are cleared, remaining pieces fall straight down to fill empty active cells in their column. Holes block falling — pieces settle at the lowest available active cell above a hole.

### 6.2 Special pieces under gravity

Special pieces fall and settle identically to normal crop pieces. Landing on a dirt patch cell does not clear the dirt. The special piece sits on top of the dirt and awaits activation normally.

### 6.3 Refill

Once all pieces have settled, new pieces fall from above the topmost active cell in each column to fill remaining empty active cells. New pieces are selected using weighted random: each crop type in the level's `crop_set` has a base weight of 1. If the level has an active "Collect X of crop Y" goal that is not yet met, crop Y has its weight increased to 2. Weights reset to 1 for all crops once that goal is satisfied.

### 6.4 Cascade

After refill settles, if new valid matches form automatically, they resolve without consuming a turn. Each cascade chain level applies a bonus multiplier to that cascade's points: `1 + (CASCADE_MULTIPLIER_PER_LEVEL × chain_level)`, capped at `CASCADE_MULTIPLIER_CAP`. Cascades count toward all goals normally.

**Behavioral scenario — cascade chain**
> **Given** `CASCADE_MULTIPLIER_PER_LEVEL = 0.5` and `CASCADE_MULTIPLIER_CAP = 3.0`,
> **when** a player match triggers two cascades in sequence,
> **then** cascade 1 applies a 1.5× multiplier and cascade 2 applies a 2.0× multiplier. No turn is consumed for either cascade.

---

## 7. Scoring

| Event | Points |
|---|---|
| 3-piece match | 50 per piece (150 total) |
| 4-piece match | 100 per piece (400 total) |
| 5-piece match | 150 per piece (750 total) |
| L-shape match | 100 per piece (500 total) |
| T-shape match | 120 per piece (600 total) |
| Special piece activation | 200 flat bonus |
| Cascade | Match points × cascade multiplier (see 6.4) |

All point values above are defaults. Each level's data file may override them via `score_overrides` to tune difficulty and star thresholds.

---

## 8. Level Goals

Each level defines one or more simultaneous goals. All goals must be satisfied before or on the final turn for the player to win. A level does not end when the first goal is met — play continues until all goals are complete or turns run out.

| Goal type | Definition |
|---|---|
| Reach target score | Score ≥ defined threshold by end of turn limit. |
| Clear all dirt | Every dirt patch cell on the board is cleared. |
| Clear all flowers | Every flower on the board is reduced to 0 HP. |
| Collect crop | A defined quantity of a specific crop is removed from the board by any means — matches, cascades, or special piece effects. |

**Behavioral scenario — multi-goal level, first goal met early**
> **Given** a level with goals "Score 800 points" and "Clear all dirt," and the score goal is met on turn 10 of 20 while 3 dirt patches remain,
> **when** turn 10 resolves,
> **then** the level continues. The score goal is marked complete in the UI. Play proceeds until all dirt is cleared (win) or turn 20 expires (fail).

---

## 9. Win & Fail Conditions

**Win:** All defined goals are satisfied on or before the final turn. Star rating is calculated and the win screen is shown.

**Fail:** Turn counter reaches 0 with at least one goal unsatisfied. One life is deducted and the fail screen is shown.

| Stars | Condition |
|---|---|
| ⭐ | All goals met, any turns remaining (including exactly 0 on final move) |
| ⭐⭐ | All goals met with ≥ `star_threshold_2` turns remaining (defined per level) |
| ⭐⭐⭐ | All goals met with ≥ `star_threshold_3` turns remaining (defined per level) |

The best star rating ever earned for a level is stored. Replaying a level cannot decrease a previously earned star rating.

---

## 10. Lives System

Maximum 3 lives (`MAX_LIVES`). One life is consumed on each level failure. Lives regenerate at one per `LIFE_REGEN_MINUTES` (15) minutes in real-world time, regardless of whether the app is open.

The save file stores the UTC timestamp of when the next life regeneration is due. On app launch, the game calculates elapsed intervals since that timestamp, grants that many lives (capped at `MAX_LIVES`), and advances the timestamp accordingly.

With 0 lives, the player may browse the main menu and level select screen freely but cannot enter any level. A "no lives" overlay is shown when the player attempts to start a level, displaying time until next regeneration and the option to purchase a life with seeds.

**Behavioral scenario — life regeneration while app closed**
> **Given** the player has 1 life and closes the app at 10:00 AM,
> **when** the player reopens the app at 11:00 AM (60 minutes later),
> **then** 2 lives are granted (4 intervals elapsed, capped at `MAX_LIVES` − 1 = 2 addable). Player now has 3 lives.

**Behavioral scenario — 0 lives, browse attempt**
> **Given** the player has 0 lives,
> **when** the player navigates to the level select screen and taps a level,
> **then** the no-lives overlay appears. The level does not launch. The player may dismiss the overlay or purchase a life.

---

## 11. Seed Economy

### 11.1 Earning seeds

| Source | Amount |
|---|---|
| Activating any special piece during play | Per-piece constant from `balance.tres` |
| Completing a level with 3 stars | `seed_reward_3star` defined per level in level data |

### 11.2 Spending seeds

| Purchase | Cost | Condition |
|---|---|---|
| +1 Life | `SEED_COST_LIFE` | Only available when player has 0 lives |

Seed balance persists between sessions and cannot go below 0. If a player has insufficient seeds, the purchase button is shown as disabled with a visual indicator.

---

## 12. Progression & Level Structure

### 12.1 Level select screen

Displays all 50 levels. Levels are unlocked in strict linear order — level N+1 unlocks only after level N is completed with at least 1 star. Each level cell displays: level number, best star rating (0 = not yet completed), and locked/unlocked state. No goal preview is shown on the level select screen — goals are revealed only on the level intro screen after tapping a level.

### 12.2 Level data schema

Each level is a Godot resource (`LevelData.tres`) with the following fields:

| Field | Type | Description |
|---|---|---|
| `level_id` | int | Integer 1–50 |
| `turn_limit` | int | Total player turns allowed |
| `star_threshold_2` | int | Turns remaining required for 2 stars |
| `star_threshold_3` | int | Turns remaining required for 3 stars |
| `crop_set` | Array | Crop type identifiers active in this level |
| `goals` | Array | Goal objects, each with a type identifier and type-specific parameters |
| `grid_layout` | Array[8][8] | Each cell defines: active state, obstacle type (none/rock/dirt/flower/hole), optional starting piece override |
| `seed_reward_3star` | int | Seeds awarded on 3-star completion |
| `score_overrides` | Dictionary | Optional overrides for default point values for this level |

---

## 13. Persistence & Save Data

All data below persists locally using Godot's `FileAccess`. The save file is written after every meaningful state change (level complete, life consumed, seeds earned or spent).

- Per-level: completion status, best star rating
- Highest unlocked level index
- Seed balance
- Current lives count
- UTC timestamp of next life regeneration
- Audio preferences (sound on/off, music on/off)

A reset option in the Settings screen clears all save data after a two-step confirmation dialog. After reset: lives = `MAX_LIVES`, seeds = 0, only level 1 unlocked, all star ratings cleared.

---

## 14. UI Screen Inventory

| Screen | Contents |
|---|---|
| Main menu | Play (→ level select), Settings, seed balance display |
| Level select | 50 level cells (number, stars, lock state), back button, seed balance display |
| Level intro | Level number, all goals listed, turn limit, Start button, back button |
| Gameplay | Board, goal list with live progress, turns remaining, current score, seed balance, pause button |
| Win screen | Stars earned, final score, goals achieved, seeds earned this run, Next Level button, Level Select button |
| Fail screen | Goals not met highlighted, Retry button (costs 1 life), Level Select button, Buy Life button if 0 lives |
| No lives overlay | Time until next life, Buy Life button (shows seed cost and player's current balance), dismiss button |
| Settings | Sound toggle, Music toggle, Reset Progress (confirmation dialog required) |

---

## 15. Audio

Sound effects and music are independently toggleable. Both default to on. Preferences persist between sessions.

| Event | Sound character |
|---|---|
| Valid swap | Soft rustle / thud |
| Invalid swap | Gentle negative tone |
| 3-piece match | Light pop / chime |
| 4+ or shape match | Richer ascending chime |
| Special piece spawned | Distinct sparkle tone |
| Special piece activated | Distinct harvest sound per piece type |
| Flower hit (stage change) | Soft bloom sound |
| Flower cleared | Bright pop + petal rustle |
| Dirt cleared | Earthy thud |
| Cascade (each chain level) | Layered match sound, escalating with chain depth |
| Goal completed mid-level | Short positive chime distinct from match sounds |
| Level win | Upbeat harvest fanfare |
| Level fail | Soft descending tone |
| Background music | Looping ambient farm/folk instrumental |

---

*End of specification — Harvest Match v1.1 · All ambiguities resolved*
