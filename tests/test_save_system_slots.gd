@tool
extends McpTestSuite

## Slot management tests — list_slots, has_slot, delete_slot,
## quick_save/quick_load, last_used_slot tracking.

const S1 := 911
const S2 := 912
const S3 := 913

var _sys: Node


class FakeSaveable:
	extends Node
	var save_id: String = "slot_fake"
	var captured: Dictionary = {}
	var load_arg: Dictionary = {}

	func save_data() -> Dictionary:
		return captured.duplicate(true)

	func load_data(d: Dictionary) -> void:
		load_arg = d


func suite_name() -> String:
	return "save_system_slots"


func suite_setup(_ctx: Dictionary) -> void:
	var script := load("res://save_system/save_system.gd")
	_sys = script.new()


func suite_teardown() -> void:
	_wipe_all()
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_wipe_all()
	_sys._registered.clear()
	_sys.last_used_slot = 1


func _wipe_all() -> void:
	for s in [S1, S2, S3]:
		_sys.delete_slot(s)


func _mk_fake(captured: Dictionary) -> FakeSaveable:
	var f := FakeSaveable.new()
	f.captured = captured
	return f


# ----- has_slot -----

func test_has_slot_false_when_no_save() -> void:
	assert_false(_sys.has_slot(S1))


func test_has_slot_true_after_save() -> void:
	var fake := _mk_fake({"v": 1})
	_sys.register(fake)
	_sys.save_to_slot(S1)
	assert_true(_sys.has_slot(S1))
	fake.free()


# ----- list_slots -----

func test_list_slots_empty_when_no_saves() -> void:
	var slots: Array = _sys.list_slots()
	# Filter to just our test slot IDs so real saves don't pollute
	var ours := slots.filter(func(m): return m.slot_id in [S1, S2, S3])
	assert_eq(ours.size(), 0)


func test_list_slots_returns_all_saved_sorted() -> void:
	var fake := _mk_fake({"v": 1})
	_sys.register(fake)
	# Save out of order to check sorting
	_sys.save_to_slot(S3, "level_c")
	_sys.save_to_slot(S1, "level_a")
	_sys.save_to_slot(S2, "level_b")

	var slots: Array = _sys.list_slots()
	var ours := slots.filter(func(m): return m.slot_id in [S1, S2, S3])
	assert_eq(ours.size(), 3)
	assert_eq(ours[0].slot_id, S1)
	assert_eq(ours[1].slot_id, S2)
	assert_eq(ours[2].slot_id, S3)
	assert_eq(ours[0].level_name, "level_a")
	assert_eq(ours[1].level_name, "level_b")
	assert_eq(ours[2].level_name, "level_c")
	fake.free()


func test_list_slots_metadata_fields_populated() -> void:
	var fake := _mk_fake({"v": 1})
	_sys.register(fake)
	_sys.save_to_slot(S1, "arena", 123.4)

	var slots: Array = _sys.list_slots()
	var ours := slots.filter(func(m): return m.slot_id == S1)
	assert_eq(ours.size(), 1)
	var meta = ours[0]
	assert_eq(meta.slot_id, S1)
	assert_eq(meta.level_name, "arena")
	assert_eq(meta.play_time_seconds, 123.4)
	assert_gt(meta.saved_at_unix, 0)
	assert_eq(meta.game_version, SaveConfig.GAME_VERSION)
	fake.free()


# ----- delete_slot -----

func test_delete_slot_removes_both_files() -> void:
	var fake := _mk_fake({"v": 1})
	_sys.register(fake)
	_sys.save_to_slot(S1)
	assert_true(_sys.has_slot(S1))

	var err: int = _sys.delete_slot(S1)
	assert_eq(err, OK)
	assert_false(_sys.has_slot(S1), ".save should be gone")

	var meta_path := "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, S1, SaveConfig.META_EXTENSION]
	assert_false(FileAccess.file_exists(meta_path), ".meta.tres should be gone")
	fake.free()


func test_delete_missing_slot_returns_ok() -> void:
	var err: int = _sys.delete_slot(S1)
	assert_eq(err, OK, "delete_slot on missing slot should be a no-op success")


# ----- quick_save / quick_load -----

func test_quick_save_uses_slot_1_by_default() -> void:
	var fake := _mk_fake({"v": 10})
	_sys.register(fake)
	# Default last_used_slot == 1 after setup
	var err: int = _sys.quick_save()
	# Slot 1 is a real slot, clean it up after
	assert_eq(err, OK)
	assert_true(_sys.has_slot(1))
	_sys.delete_slot(1)
	fake.free()


func test_quick_save_remembers_last_slot() -> void:
	var fake := _mk_fake({"v": 10})
	_sys.register(fake)
	_sys.save_to_slot(S2)
	assert_eq(_sys.last_used_slot, S2)

	fake.captured = {"v": 20}
	_sys.quick_save()
	fake.captured = {}
	_sys.quick_load()
	assert_eq(fake.load_arg.v, 20, "quick_load should pull from last-used slot")
	fake.free()


func test_load_missing_slot_returns_error() -> void:
	var fake := _mk_fake({"v": 1})
	_sys.register(fake)
	var err: int = _sys.load_from_slot(S3)
	assert_eq(err, ERR_FILE_NOT_FOUND, "loading a nonexistent slot must return ERR_FILE_NOT_FOUND")
	fake.free()
