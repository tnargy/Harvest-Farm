# Harvest Match — Project Roadmap

**Last updated:** 2026-03-20  
**Engine:** Godot 4.6.1  
**Spec version:** 1.1

---

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Complete and fully tested |
| 🔲 | Not started |

---

## Layer 1 — Logic (Complete)

All core game logic is implemented, unit-tested, and passing 101/101 integration assertions in `TestBoardController`.

| System | File(s) | Status |
|--------|---------|--------|
| Board state | `scripts/board/BoardState.gd` | ✅ |
| Match detection | `scripts/board/MatchFinder.gd` | ✅ |
| Gravity & refill | `scripts/board/GravitySystem.gd` | ✅ |
| Score calculation | `scripts/board/ScoreCalculator.gd` | ✅ |
| Special piece effects | `scripts/board/SpecialPieceHandler.gd` | ✅ |
| Goal tracking | `scripts/board/GoalTracker.gd` | ✅ |
| Turn orchestration | `scripts/board/BoardController.gd` | ✅ |
| Balance constants | `resources/balance.tres` | ✅ |
| Level data schema | `scripts/resources/LevelData.gd` | ✅ |
| Level data validator | `scripts/tools/LevelDataValidator.gd` | ✅ |
| Authoring guide | `docs/level_and_balance.md` | ✅ |

---

## Layer 2 — Content

Level `.tres` files authored to the schema defined in `LevelData.gd`. The validator must pass with zero errors before a level is considered done.

| Levels | Status |
|--------|--------|
| Levels 1–20 | ✅ |
| Levels 21–50 | 🔲 |

**Dependency:** none — pure content work, no code changes required.

---

## Layer 3 — Persistence

A standalone `SaveData.gd` autoload with no UI dependency. Everything from lives to unlock state to seed balance is read and written here.

See spec §13 for the full field list, write-trigger rules, and reset behaviour.

**Dependency:** none.

**Status:** ✅ — Implementation complete and verified (116/116 tests passed).

---

## Layer 4 — Lives System

Reads and writes lives count through `SaveData`. Enforces the "0 lives = cannot start a level" rule.

See spec §10 for regeneration timing, the launch-time calculation, and the 0-lives browsing rules.

**Dependency:** Layer 3 (SaveData).

**Status:** ✅ — Implementation complete and verified (19/19 tests passed).


---

## Layer 5 — Seed Economy

Thin wrapper around `SaveData` enforcing the earn/spend rules.

See spec §11 for earn sources, spend conditions, and the disabled-button rule.

Note: `BoardController.TurnResult.seeds_earned` already tracks per-turn seed income — the economy layer only needs to flush that value into `SaveData` at turn resolution.

**Dependency:** Layer 3 (SaveData), Layer 4 (LivesManager).

**Status:** ✅ — Implementation complete and verified (13/13 tests passed).

| System | File(s) |
|--------|---------|
| Seed economy | `scripts/economy/SeedEconomy.gd` |
| Test suite | `scripts/tests/TestSeedEconomy.gd` |
| Test scene | `scenes/tests/TestSeedEconomy.tscn` |

---

## Layer 6 — Gameplay Scene

**Status:** ✅ — Implementation complete and verified (5/5 manual tests passed).

| System | File(s) |
|--------|---------|
| Piece visual | `scripts/gameplay/PieceNode.gd`, `scenes/gameplay/PieceNode.tscn` |
| Board grid | `scripts/gameplay/BoardGrid.gd`, `scenes/gameplay/BoardGrid.tscn` |
| HUD bar | `scripts/gameplay/HudBar.gd`, `scenes/gameplay/HudBar.tscn` |
| Gameplay scene | `scripts/gameplay/GameplayScene.gd`, `scenes/gameplay/GameplayScene.tscn` |

The board UI. Largest single piece of work.

### Responsibilities

- Render the 8×8 grid from `BoardState`
- Accept player swap input (touch/click drag between adjacent cells)
- Call `BoardController.attempt_swap()` and read `TurnResult`
- Animate: piece swap, invalid swap bounce-back, match clear, gravity fall, refill drop, special piece spawn, special piece activation effect
- Display live HUD: turns remaining, current score, goal progress list, seed balance
- On `TurnResult.win` → transition to Win screen
- On `TurnResult.fail` → transition to Fail screen

**Dependency:** Layers 3–5 (SaveData, Lives, Seeds).

---

## Layer 7 — Win / Fail Resolution

Reads `TurnResult` from `BoardController`, computes star rating, persists results, and gates the next action.

See spec §9 for star thresholds, the "never decrease a rating" rule, and win/fail screen triggers.

**Dependency:** Layer 6 (Gameplay scene).

---

## Layer 8 — UI Screens

Build in dependency order. Each screen reads state only — no game logic lives in UI nodes (per architecture rules).

| Screen | Key contents | Dependency |
|--------|-------------|------------|
| **Level intro** | Level number, all goals listed, turn limit, Start button, back button | Layer 6 |
| **Win screen** | Stars earned, final score, seeds earned this run, Next Level + Level Select buttons | Layer 7 |
| **Fail screen** | Incomplete goals highlighted, Retry button (costs 1 life), Level Select button, Buy Life button if 0 lives | Layer 7 |
| **Level select** | 50 level cells (number, stars, lock state), back button, seed balance display | Layer 3 |
| **Main menu** | Play → level select, Settings, seed balance display | Layer 8 (level select) |
| **No-lives overlay** | Time until next regen, Buy Life button (seed cost + current balance), dismiss button | Layer 4 |
| **Settings screen** | Sound toggle, music toggle, Reset Progress (two-step confirmation dialog) | Layer 3 |

---

## Layer 9 — Audio

Sound effects and music, independently toggleable. Both default to on. Preferences persisted in `SaveData`.

See spec §15 for the full event list and described sound characters.

**Dependency:** Layer 8 (all screens present before audio pass).

---

## Suggested Build Order

```
Layer 3 → Layer 4 → Layer 5 → Layer 6 → Layer 7 → Layer 8 → Layer 9
                                                    ↑
                                          Layer 2 (content) can proceed
                                          in parallel at any point
```

Start with **Layer 3 (SaveData)** — it has no dependencies, it unblocks everything above it, and it is straightforwardly testable in isolation.