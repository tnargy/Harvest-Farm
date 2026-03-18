**Version used**
Godot 4.6.1

**Prevent assumption-making**

- Never infer missing values — reference balance.tres constants only, never hardcode a number
- If a behavior is ambiguous, stop and surface the ambiguity rather than picking one interpretation

**Enforce architecture boundaries**

- All tunable values live in balance.tres — no exceptions
- Level data lives in LevelData.tres resources — no level logic in code
- No game logic in UI nodes; UI only reads state, never mutates it

**Keep changes contained**

- Only modify files relevant to the current task
- Do not refactor code outside the scope of the current instruction

**Maintain spec fidelity**

- The spec is the source of truth — if the spec and the code conflict, fix the code
- Do not add features not described in the spec without explicit instruction

**Testing discipline**

- After implementing each system, verify it against the behavioral scenarios in the spec before moving to the next layer
- A system is not complete until every behavioral scenario for that system produces the described outcome
- Use godot-mcp tools to run in-editor verification: use `play_scene` to launch the game, `get_hierarchy` and `get_object_properties` to inspect runtime state, and `stop_scene` when done
- Use `find_objects_by_name` and `get_object_properties` to assert node state matches expected outcomes from the spec
- Use `diagnostics` after every script change to catch errors before running the scene
- Never mark a behavioral scenario as passing based on code review alone — confirm it by running the scene via godot-mcp
