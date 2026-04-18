@tool
extends McpTestSuite

## Schema-compat tests — we promise old saves keep loading as the game evolves.
## That promise has two mechanisms:
##   1. Saveables use `d.get(key, default)` so missing keys yield defaults.
##   2. The library-level schema_version gate rejects saves from the future.

const SLOT := 921

var _sys: Node


## Subclass of FakeSaveable that uses .get(…, default) to demonstrate the
## backward-compat contract (old saves load with defaults for missing keys).
class DefaultingSaveable:
	extends FakeSaveable

	func load_data(d: Dictionary) -> void:
		loaded = {
			"hp": d.get("hp", 100),
			"name": d.get("name", "default_name"),
			"new_field": d.get("new_field", "default_new"),
		}
		load_count += 1


func suite_name() -> String:
	return "save_system_schema_compat"


func suite_setup(_ctx: Dictionary) -> void:
	var script := load("res://save_system/save_system.gd")
	_sys = script.new()


func suite_teardown() -> void:
	_sys.delete_slot(SLOT)
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_sys.delete_slot(SLOT)
	_sys.clear_registered()


# ----- missing keys get defaults -----

func test_missing_key_yields_default() -> void:
	# Simulate an "old" save that doesn't include `new_field`.
	var fake := DefaultingSaveable.new()
	fake.save_id = "schema_fake"
	fake.captured = {"hp": 42, "name": "hero"}
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	fake.loaded = {}
	_sys.load_from_slot(SLOT)
	assert_eq(fake.loaded.hp, 42)
	assert_eq(fake.loaded.name, "hero")
	assert_eq(fake.loaded.new_field, "default_new", "missing key should come back as default")
	fake.free()


# ----- unknown schema version refuses cleanly -----

func test_future_schema_version_refused() -> void:
	# Hand-write an encrypted save with a future schema_version to confirm the
	# library gate rejects rather than partially apply.
	var path := "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, SLOT, SaveConfig.SAVE_EXTENSION]
	DirAccess.make_dir_recursive_absolute(SaveConfig.SAVES_DIR)
	var payload := {
		"schema_version": 9999,
		"game_version": "?",
		"saved_at_unix": 1,
		"play_time_seconds": 0.0,
		"level_name": "",
		"saveables": {"schema_fake": {"hp": 1}},
	}
	SaveAtomicWrite.write_encrypted_json(path, payload, SaveConfig.ENCRYPTION_PASSWORD)

	var fake := DefaultingSaveable.new()
	fake.save_id = "schema_fake"
	fake.loaded = {"hp": 999}
	_sys.register(fake)

	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA, "unsupported schema_version must be rejected")
	assert_eq(fake.loaded.hp, 999, "load_data must not be called on rejected loads")
	fake.free()


func test_missing_schema_version_refused() -> void:
	# A save with schema_version=0 or missing should also be rejected.
	var path := "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, SLOT, SaveConfig.SAVE_EXTENSION]
	DirAccess.make_dir_recursive_absolute(SaveConfig.SAVES_DIR)
	SaveAtomicWrite.write_encrypted_json(path, {"saveables": {}}, SaveConfig.ENCRYPTION_PASSWORD)

	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA, "missing schema_version must be rejected")


# ----- saveables absent in save aren't disturbed -----

func test_saveable_not_in_save_is_untouched() -> void:
	# Save with one saveable; load with two registered. The second should not
	# receive load_data (it wasn't in the save).
	var a := DefaultingSaveable.new()
	a.save_id = "present"
	a.captured = {"hp": 7}
	_sys.register(a)
	_sys.save_to_slot(SLOT)
	_sys.clear_registered()

	var a2 := DefaultingSaveable.new()
	a2.save_id = "present"
	a2.loaded = {"hp": 0, "name": "before", "new_field": "before"}
	var b := DefaultingSaveable.new()
	b.save_id = "absent"
	b.loaded = {"hp": 0, "name": "before_b", "new_field": "before_b"}
	_sys.register(a2)
	_sys.register(b)

	_sys.load_from_slot(SLOT)
	assert_eq(a2.loaded.hp, 7, "present saveable should load")
	assert_eq(b.loaded.name, "before_b", "absent saveable should keep prior state")

	a.free()
	a2.free()
	b.free()
