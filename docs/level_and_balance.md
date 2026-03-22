# Level & Balance Authoring Guide

**Harvest Match · Godot 4.6**

---

## Table of Contents

1. [Overview](#overview)
2. [balance.tres — Tunable Constants](#balancetres--tunable-constants)
   - [Where it lives](#where-it-lives)
   - [All constants defined](#all-constants-defined)
   - [How to add a new constant](#how-to-add-a-new-constant)
   - [Rules](#rules)
3. [LevelData.tres — Per-Level Configuration](#leveldatatres--per-level-configuration)
   - [Where files live](#where-files-live)
   - [Field reference](#field-reference)
   - [Goal types](#goal-types)
   - [Grid layout schema](#grid-layout-schema)
   - [Score overrides](#score-overrides)
   - [How to author a new level](#how-to-author-a-new-level)
4. [Running the Validator](#running-the-validator)
   - [How to run](#how-to-run)
   - [Understanding output](#understanding-output)
   - [Common errors and fixes](#common-errors-and-fixes)
5. [Example Levels](#example-levels)
6. [Checklist Before Committing](#checklist-before-committing)

---

## Overview

This game uses two categories of data files that must be kept in sync:

| File | Purpose |
|---|---|
| `resources/balance.tres` | Single source of truth for every tunable gameplay constant |
| `resources/levels/level_NN.tres` | Per-level configuration (goals, grid, crops, thresholds) |

**The golden rule:** No numeric gameplay constant is ever hardcoded in a `.gd` script or scene file. Every tunable value lives in `balance.tres`. Level data may specify its own per-level values (e.g. `turn_limit`, `seed_reward_3star`) but must never duplicate or shadow a constant that belongs in balance.

---

## balance.tres — Tunable Constants

### Where it lives

```
res://resources/balance.tres
```

It is loaded as a `Balance` resource (see `scripts/resources/Balance.gd`).

### All constants defined

| Constant | Type | Spec-mandated value | Description |
|---|---|---|---|
| `SEED_COST_LIFE` | int | designer-set | Seeds required to purchase one life (only when player has 0 lives) |
| `SEED_REWARD_SPECIAL_BUSHEL` | int | designer-set | Seeds dropped on Bushel Basket activation |
| `SEED_REWARD_SPECIAL_SCARECROW` | int | designer-set | Seeds dropped on Scarecrow activation |
| `SEED_REWARD_SPECIAL_WATERING_CAN` | int | designer-set | Seeds dropped on Watering Can activation |
| `SEED_REWARD_SPECIAL_WHEELBARROW` | int | designer-set | Seeds dropped on Wheelbarrow activation |
| `CASCADE_MULTIPLIER_PER_LEVEL` | float | 0.5 | Fractional bonus added per cascade chain step |
| `CASCADE_MULTIPLIER_CAP` | float | 3.0 | Maximum total cascade multiplier |
| `LIFE_REGEN_MINUTES` | int | 15 | Real-world minutes between life regeneration ticks |
| `MAX_LIVES` | int | 3 | Maximum lives a player can hold |
| `SCORE_MATCH_3_PER_PIECE` | int | 50 | Points per piece in a 3-piece match |
| `SCORE_MATCH_4_PER_PIECE` | int | 100 | Points per piece in a 4-piece match |
| `SCORE_MATCH_5_PER_PIECE` | int | 150 | Points per piece in a 5-piece match |
| `SCORE_MATCH_L_PER_PIECE` | int | 100 | Points per piece in an L-shape match |
| `SCORE_MATCH_T_PER_PIECE` | int | 120 | Points per piece in a T-shape match |
| `SCORE_SPECIAL_ACTIVATION_BONUS` | int | 200 | Flat bonus on any special piece activation |

#### Cascade multiplier formula

```
multiplier = min(1.0 + CASCADE_MULTIPLIER_PER_LEVEL × chain_level, CASCADE_MULTIPLIER_CAP)
```

Example with defaults (`CASCADE_MULTIPLIER_PER_LEVEL = 0.5`, `CASCADE_MULTIPLIER_CAP = 3.0`):

| Chain level | Multiplier |
|---|---|
| 1 | 1.5× |
| 2 | 2.0× |
| 3 | 2.5× |
| 4 | 3.0× (capped) |
| 5+ | 3.0× (capped) |

### How to add a new constant

1. Open `scripts/resources/Balance.gd`.
2. Add a new `@export var MY_NEW_CONSTANT: int = 0` (or `float`) with a doc comment explaining what it controls.
3. Add a corresponding validation check inside `Balance.validate()` if the constant must be non-zero or within a range.
4. Open `resources/balance.tres` in the Godot Inspector and set the value in the Inspector panel — do **not** edit the `.tres` file by hand unless you are certain of the format.
5. Run the validator (see below) to confirm no errors.

### Rules

- **Never** hardcode a number in a `.gd` file that represents a gameplay tunable. Always read from the loaded `Balance` resource.
- **Never** duplicate a balance constant inside a `LevelData.tres`. Level data references balance at runtime via the game systems.
- If you are unsure whether a value belongs in `balance.tres` or in a level file, ask: *does this value affect more than one level or more than one system?* If yes, it belongs in balance.

---

## LevelData.tres — Per-Level Configuration

### Where files live

```
res://resources/levels/level_01.tres
res://resources/levels/level_02.tres
…
res://resources/levels/level_50.tres
```

Files must be named `level_NN.tres` where `NN` is the zero-padded level number. The `level_id` field inside the file must match the number in the filename.

### Field reference

| Field | Type | Required | Description |
|---|---|---|---|
| `level_id` | int | Yes | Integer 1–50. Must be unique across all level files. |
| `turn_limit` | int | Yes | Total player turns allowed. Must be > 0. |
| `star_threshold_2` | int | Yes | Turns remaining needed for 2 stars. Must be < `turn_limit`. |
| `star_threshold_3` | int | Yes | Turns remaining needed for 3 stars. Must be < `star_threshold_2`. |
| `crop_set` | Array[String] | Yes | Crop identifiers active on this level. At least one required. |
| `goals` | Array[Dictionary] | Yes | One or more goal objects. All must be met to win. |
| `grid_layout` | Array[Array] | Yes | 8×8 array of cell Dictionaries. See Grid layout schema. |
| `seed_reward_3star` | int | Yes | Seeds awarded on 3-star completion. May be 0. |
| `score_overrides` | Dictionary | No | Per-level overrides for default point values. May be empty `{}`. |
| `meta` | Dictionary | No | Authoring notes. Not used at runtime. Suggested keys: `author`, `version`, `notes`. |

#### Star threshold ordering rule

```
0 < star_threshold_3 < star_threshold_2 < turn_limit
```

Example for a 25-turn level:

```
turn_limit       = 25
star_threshold_2 = 10   → earn 2 stars with 10+ turns remaining
star_threshold_3 = 16   → earn 3 stars with 16+ turns remaining
```

#### Crop identifiers

Crop identifiers are plain lowercase strings. The spec defines the following progression:

| Introduced at level | Crops |
|---|---|
| 1 | `strawberry`, `carrot`, `corn`, `eggplant` |
| Designer-defined | Additional crops added as specified in level data |

You may introduce any new identifier string in any level's `crop_set`. The validator checks that `collect_crop` goals do not reference a crop absent from `crop_set`.

### Goal types

Each entry in `goals` is a Dictionary with at minimum a `"type"` key.

#### Score goal

```
{ "type": "score", "target": 3000 }
```

| Key | Type | Required | Description |
|---|---|---|---|
| `type` | String | Yes | Must be `"score"` |
| `target` | int | Yes | Score the player must reach or exceed |

#### Clear all dirt goal

```
{ "type": "clear_dirt" }
```

No additional keys. Satisfied when every `dirt` obstacle cell on the board has been cleared.

#### Clear all flowers goal

```
{ "type": "clear_flowers" }
```

No additional keys. Satisfied when every `flower` cell on the board has been reduced to 0 HP.

#### Collect crop goal

```
{ "type": "collect_crop", "crop": "strawberry", "target": 12 }
```

| Key | Type | Required | Description |
|---|---|---|---|
| `type` | String | Yes | Must be `"collect_crop"` |
| `crop` | String | Yes | Crop identifier. Must appear in this level's `crop_set`. |
| `target` | int | Yes | Number of that crop to remove from the board by any means |

#### Multi-goal levels

A level may declare any combination of goal types simultaneously:

```
goals = [
    { "type": "score", "target": 3000 },
    { "type": "clear_dirt" },
    { "type": "clear_flowers" },
    { "type": "collect_crop", "crop": "pumpkin", "target": 10 }
]
```

All goals must be satisfied on or before the final turn. The level does **not** end early when the first goal is met — play continues until all are complete or turns run out.

### Grid layout schema

`grid_layout` is an 8×8 array. The outer array contains 8 row arrays (index 0 = top row). Each row contains 8 cell Dictionaries (index 0 = leftmost column).

#### Cell keys

| Key | Type | Required | Description |
|---|---|---|---|
| `active` | bool | Yes | `false` = hole (dead space). No piece ever occupies a hole. |
| `obstacle` | String | No | One of: `"none"`, `"rock"`, `"dirt"`, `"flower"`. Defaults to `"none"` if omitted. |
| `flower_hp` | int | If obstacle is `"flower"` | Initial HP of the flower, 1–3. Defaults to 3 if omitted. |
| `starting_piece` | String | No | Crop or special piece identifier placed here at level start. Omit or leave `""` for random fill. |

#### Obstacle behaviour summary

| Obstacle | Behaviour | Removable? |
|---|---|---|
| `none` | Normal active cell. | — |
| `hole` (`active: false`) | Permanently inactive. Pieces cannot fall through or target it. | No |
| `rock` | Occupies a cell. Cannot be swapped, matched, or targeted. Permanent. | No |
| `dirt` | Underlays a piece. Cleared when a match is made that includes or is orthogonally adjacent to that cell. | Yes — 1 hit |
| `flower` | Occupies a full cell. Cannot hold a piece on top. Damaged by orthogonally adjacent matches. | Yes — 3 hits |

#### Hole rules

Inactive cells (`active: false`) must **not** declare an obstacle or `starting_piece`. The validator will error if they do.

#### Example cell declarations

```
# Normal active cell
{ "active": true, "obstacle": "none" }

# Hole (dead space)
{ "active": false }

# Dirt patch
{ "active": true, "obstacle": "dirt" }

# Rock
{ "active": true, "obstacle": "rock" }

# Wilted flower (full HP)
{ "active": true, "obstacle": "flower", "flower_hp": 3 }

# Pre-damaged flower
{ "active": true, "obstacle": "flower", "flower_hp": 1 }

# Cell with a forced starting piece
{ "active": true, "obstacle": "none", "starting_piece": "strawberry" }

# Dirt patch with a special piece forced on top at level start
{ "active": true, "obstacle": "dirt", "starting_piece": "watering_can" }
```

### Score overrides

`score_overrides` is an optional Dictionary that replaces default point values from `balance.tres` for this level only. Only the keys you specify are overridden; all others fall back to balance defaults.

| Key | Overrides balance constant |
|---|---|
| `"match_3"` | `SCORE_MATCH_3_PER_PIECE` |
| `"match_4"` | `SCORE_MATCH_4_PER_PIECE` |
| `"match_5"` | `SCORE_MATCH_5_PER_PIECE` |
| `"match_l"` | `SCORE_MATCH_L_PER_PIECE` |
| `"match_t"` | `SCORE_MATCH_T_PER_PIECE` |
| `"special_activation"` | `SCORE_SPECIAL_ACTIVATION_BONUS` |

All override values must be positive integers. The validator will error on unknown keys or non-positive values.

Example — boost match scores on a level with many holes (fewer active cells):

```
score_overrides = {
    "match_3": 60,
    "match_4": 120,
    "special_activation": 300
}
```

### How to author a new level

1. Duplicate the closest example level file from `resources/levels/`.
2. Rename it to match the intended level number (e.g. `level_15.tres`).
3. Open the file in the Godot Inspector (or a text editor) and update every field:
   - Set `level_id` to the correct integer.
   - Set `turn_limit`, `star_threshold_2`, `star_threshold_3` following the ordering rule above.
   - Update `crop_set` — add any new crops this level introduces.
   - Define `goals` using the supported goal types above.
   - Lay out the 8×8 `grid_layout` — every row must have exactly 8 cell Dictionaries.
   - Set `seed_reward_3star`.
   - Add `score_overrides` only if you need to deviate from balance defaults.
   - Fill in `meta` with your name, version, and a short note.
4. Run the validator (see below) and fix all reported errors before committing.

---

## Running the Validator

The validator is an editor tool that scans all level files and `balance.tres`, then prints a full report to the Output panel.

### How to run

1. Open the Godot Editor.
2. In the **FileSystem** panel, navigate to `scripts/tools/LevelDataValidator.gd` and double-click to open it in the Script Editor.
3. With the script open and focused, press **Ctrl+Shift+X** (or go to **File → Run**).
4. Check the **Output** panel at the bottom of the editor for the report.

### Understanding output

```
================================================================
Harvest Match — Level Data & Balance Validator
================================================================

[Balance] Checking res://resources/balance.tres …
  OK — balance.tres passed all checks.

[Levels] Scanning 'res://resources/levels/' …
  Found 3 file(s).

[Level] res://resources/levels/level_01.tres
  OK — structural validation passed.
  INFO: 64 / 64 cells are active (0 holes).

[Level] res://resources/levels/level_08.tres
  OK — structural validation passed.
  INFO: 64 / 64 cells are active (0 holes).

[Level] res://resources/levels/level_20.tres
  OK — structural validation passed.
  INFO: 60 / 64 cells are active (4 holes).

[Sequence] Checking level_id continuity …
  OK — IDs are sequential with no gaps up to level 20.

================================================================
RESULT: PASSED with 0 warning(s).
================================================================
```

| Prefix | Meaning |
|---|---|
| `OK` | Check passed. No action needed. |
| `INFO` | Informational note. Not an error. Review at your discretion. |
| `WARNING` | Non-blocking issue. Should be reviewed before shipping. |
| `ERROR` | Blocking issue. Must be fixed before this data is considered valid. |

### Common errors and fixes

| Error message | Likely cause | Fix |
|---|---|---|
| `Could not load balance.tres` | File missing or wrong path | Ensure `resources/balance.tres` exists and `Balance.gd` script path is correct |
| `SEED_COST_LIFE must be greater than 0` | balance.tres field left at default 0 | Open `balance.tres` in Inspector and set a positive value |
| `level_id must be between 1 and 50` | Wrong `level_id` value | Correct the field to match the filename |
| `star_threshold_2 must be less than turn_limit` | Thresholds not ordered correctly | Review the ordering rule: `star_threshold_3 < star_threshold_2 < turn_limit` |
| `goals[N] is missing required key 'type'` | Goal Dictionary incomplete | Add a `"type"` key to the goal |
| `goals[N] references crop 'X' not in crop_set` | Typo in goal crop name or crop missing from set | Fix the crop identifier or add it to `crop_set` |
| `grid_layout must have exactly 8 rows` | Row count wrong | Ensure the outer array has exactly 8 entries |
| `grid_layout[R][C] must have exactly 8 columns` | Column count wrong in a row | Ensure every row array has exactly 8 cell Dictionaries |
| `grid_layout[R][C] is inactive but declares obstacle` | Hole cell has an obstacle set | Remove `obstacle` and `starting_piece` from hole cells |
| `Duplicate level_id N` | Two files share the same `level_id` | Correct one file's `level_id` |
| `score_overrides contains unknown key 'X'` | Typo in override key name | Check the valid key list in the Score overrides section above |

---

## Example Levels

Three example levels are provided as references:

| File | Level | Description |
|---|---|---|
| `resources/levels/level_01.tres` | Tutorial | Full 8×8 active grid, no obstacles, single score goal, 4 base crops |
| `resources/levels/level_08.tres` | Standard | Introduces a 5th crop (`tomato`), adds dirt patches, uses a multi-goal (collect + clear dirt) |
| `resources/levels/level_20.tres` | Challenge | Uses all obstacle types (holes, rocks, dirt, flowers), 4 simultaneous goals, score overrides, 6 crops |

Study `level_20.tres` to see how `score_overrides` compensate for reduced active cell count, and how holes are declared with only `{ "active": false }`.

---

## Checklist Before Committing

Before opening a PR that adds or modifies level data or balance:

- [ ] Ran the validator — zero errors reported
- [ ] All new balance constants added to both `Balance.gd` (export + validate) and `balance.tres` (Inspector value set)
- [ ] No numeric gameplay constants hardcoded in any `.gd` file or scene
- [ ] `level_id` matches the filename number
- [ ] `star_threshold_3 < star_threshold_2 < turn_limit` holds
- [ ] Every `collect_crop` goal crop exists in `crop_set`
- [ ] All `flower` cells have `flower_hp` in range 1–3
- [ ] No obstacle or `starting_piece` declared on hole cells (`active: false`)
- [ ] `score_overrides` keys are all from the valid key list
- [ ] `meta` filled in with at minimum `author` and `notes`
- [ ] Validator sequence check shows no gaps in level numbering

---

*This guide reflects Harvest Match spec v1.1. If the spec and this guide conflict, the spec is the source of truth — update this guide to match.*