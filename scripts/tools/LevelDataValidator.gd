@tool
extends EditorScript

## LevelDataValidator.gd
## Run this from the Godot editor via: Script Editor → File → Run (Ctrl+Shift+X)
## Validates all LevelData.tres files under res://resources/levels/ and
## validates balance.tres under res://resources/.
## Prints a full report to the Output panel. No errors = schema is sound.

const BALANCE_PATH := "res://resources/balance.tres"
const LEVELS_DIR   := "res://resources/levels/"

func _run() -> void:
	print("=" .repeat(64))
	print("Harvest Match — Level Data & Balance Validator")
	print("=".repeat(64))

	var total_errors   := 0
	var total_warnings := 0

	# ── 1. Validate balance.tres ──────────────────────────────────────────────
	print("\n[Balance] Checking %s …" % BALANCE_PATH)

	var balance = load(BALANCE_PATH)
	if balance == null:
		print("  ERROR: Could not load balance.tres at '%s'." % BALANCE_PATH)
		print("         Ensure the file exists and the script path is correct.")
		total_errors += 1
	else:
		var balance_errors: Array[String] = balance.validate()
		if balance_errors.is_empty():
			print("  OK — balance.tres passed all checks.")
		else:
			for err in balance_errors:
				print("  ERROR: %s" % err)
				total_errors += 1

	# ── 2. Discover LevelData.tres files ─────────────────────────────────────
	print("\n[Levels] Scanning '%s' …" % LEVELS_DIR)

	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		print("  ERROR: Could not open levels directory '%s'." % LEVELS_DIR)
		print("         Create the directory and add at least one LevelData.tres file.")
		total_errors += 1
		_print_summary(total_errors, total_warnings)
		return

	var level_files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			level_files.append(LEVELS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if level_files.is_empty():
		print("  WARNING: No .tres files found in '%s'." % LEVELS_DIR)
		total_warnings += 1
	else:
		level_files.sort()
		print("  Found %d file(s)." % level_files.size())

	# ── 3. Validate each level file ───────────────────────────────────────────
	var seen_ids: Dictionary = {}  # level_id → file path, for duplicate detection

	for path in level_files:
		print("\n[Level] %s" % path)

		var resource = load(path)
		if resource == null:
			print("  ERROR: Could not load resource. Check script path and file format.")
			total_errors += 1
			continue

		# Confirm this is actually a LevelData resource.
		if not resource.has_method("validate"):
			print("  ERROR: Resource does not have a validate() method.")
			print("         Ensure the file's script is set to LevelData.gd.")
			total_errors += 1
			continue

		# Run LevelData's own structural validator.
		var errors: Array[String] = resource.validate()
		if errors.is_empty():
			print("  OK — structural validation passed.")
		else:
			for err in errors:
				print("  ERROR: %s" % err)
				total_errors += 1

		# ── Duplicate level_id check ──
		var lid: int = resource.level_id
		if seen_ids.has(lid):
			print(
				"  ERROR: Duplicate level_id %d also found in '%s'." \
				% [lid, seen_ids[lid]]
			)
			total_errors += 1
		else:
			seen_ids[lid] = path

		# ── Cross-check score_overrides keys against balance scoring keys ──
		# (balance.tres is the source of truth; overrides must name known keys)
		const VALID_OVERRIDE_KEYS := [
			"match_3", "match_4", "match_5", "match_l", "match_t", "special_activation"
		]
		for key in resource.score_overrides.keys():
			if key not in VALID_OVERRIDE_KEYS:
				print(
					"  ERROR: score_overrides key '%s' is not a recognised balance scoring key." % key
				)
				total_errors += 1

		# ── Warn if seed_reward_3star is 0 (likely unset, not a hard error) ──
		if resource.seed_reward_3star == 0:
			print(
				"  WARNING: seed_reward_3star is 0. " +
				"Intentional? Set a positive value if seeds should be awarded on 3-star completion."
			)
			total_warnings += 1

		# ── Warn if meta is empty ──
		if resource.meta.is_empty():
			print("  WARNING: meta dictionary is empty. Consider adding author/version/notes.")
			total_warnings += 1

		# ── Active cell count info ──
		var active_count := _count_active_cells(resource.grid_layout)
		if active_count < 64:
			print(
				"  INFO: %d / 64 cells are active (%d holes)." \
				% [active_count, 64 - active_count]
			)

		# ── Warn if no crop_set member appears in a collect_crop goal ──
		# (harmless, but may indicate a typo)
		for goal in resource.goals:
			if goal.get("type", "") == "collect_crop":
				var crop: String = goal.get("crop", "")
				if crop != "" and crop not in resource.crop_set:
					# LevelData.validate() already errors on this; add INFO so it's visible here too.
					print(
						"  INFO: collect_crop goal references crop '%s' not found in crop_set." % crop
					)

	# ── 4. Level sequence continuity check ───────────────────────────────────
	print("\n[Sequence] Checking level_id continuity …")
	if seen_ids.is_empty():
		print("  SKIP — no valid level files loaded.")
	else:
		var sorted_ids: Array = seen_ids.keys()
		sorted_ids.sort()

		var expected := 1
		for lid in sorted_ids:
			if lid != expected:
				print(
					"  WARNING: Expected level_id %d but found %d ('%s'). " \
					% [expected, lid, seen_ids[lid]] +
					"Levels must be numbered 1–50 in strict sequence for linear unlock to work."
				)
				total_warnings += 1
				expected = lid + 1
			else:
				expected += 1

		if sorted_ids[-1] > 50:
			print("  WARNING: level_id %d exceeds maximum of 50." % sorted_ids[-1])
			total_warnings += 1
		else:
			print("  OK — IDs are sequential with no gaps up to level %d." % sorted_ids[-1])

	# ── 5. Summary ────────────────────────────────────────────────────────────
	_print_summary(total_errors, total_warnings)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _count_active_cells(grid_layout: Array) -> int:
	var count := 0
	for row in grid_layout:
		if row is Array:
			for cell in row:
				if cell is Dictionary and cell.get("active", false):
					count += 1
	return count


func _print_summary(errors: int, warnings: int) -> void:
	print("\n" + "=".repeat(64))
	if errors == 0 and warnings == 0:
		print("RESULT: ALL CHECKS PASSED — no errors, no warnings.")
	elif errors == 0:
		print("RESULT: PASSED with %d warning(s). Review warnings above." % warnings)
	else:
		print(
			"RESULT: FAILED — %d error(s), %d warning(s). Fix errors before proceeding." \
			% [errors, warnings]
		)
	print("=".repeat(64))
