@tool
extends McpTestSuite

## Roundtrip tests — save a fake Node's state, mutate it, load, confirm the
## loaded value matches the saved value exactly. Uses a fresh SaveSystem
## instance (not the real autoload) so editor tests don't depend on runtime.

const TEST_SLOT := 901
const TEST_SLOT_2 := 902

var _sys: Node


## Minimal fake saveable used throughout the suite. Not a production pattern —
## real saveables mix save_data with the node's own logic.
class FakeSaveable:
	extends Node
	var save_id: String = "fake"
	var captured: Dictionary = {}
	var load_arg: Dictionary = {}
	var load_count: int = 0

	func save_data() -> Dictionary:
		return captured.duplicate(true)

	func load_data(d: Dictionary) -> void:
		load_arg = d
		load_count += 1


func suite_name() -> String:
	return "save_system_roundtrip"


func suite_setup(_ctx: Dictionary) -> void:
	var script := load("res://save_system/save_system.gd")
	_sys = script.new()


func suite_teardown() -> void:
	_sys.delete_slot(TEST_SLOT)
	_sys.delete_slot(TEST_SLOT_2)
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_sys.delete_slot(TEST_SLOT)
	_sys.delete_slot(TEST_SLOT_2)
	_sys._registered.clear()


func _mk(save_id: String, captured: Dictionary) -> FakeSaveable:
	var f := FakeSaveable.new()
	f.save_id = save_id
	f.captured = captured
	return f


# ----- roundtrip -----

func test_roundtrip_primitives() -> void:
	var fake := _mk("primitives", {
		"hp": 42,
		"pos": {"x": 1.5, "y": 2.5, "z": 3.5},
		"flags": [true, false, true],
		"name": "hero",
		"rate": 0.75,
	})
	_sys.register(fake)

	var err: int = _sys.save_to_slot(TEST_SLOT, "arena", 12.3)
	assert_eq(err, OK)

	# Mutate state before load to prove we actually loaded from disk
	fake.captured = {"hp": 0}

	err = _sys.load_from_slot(TEST_SLOT)
	assert_eq(err, OK)
	assert_eq(fake.load_count, 1, "load_data should be called once")
	assert_eq(fake.load_arg.hp, 42)
	assert_eq(fake.load_arg.pos.x, 1.5)
	assert_eq(fake.load_arg.pos.z, 3.5)
	assert_eq(fake.load_arg.flags.size(), 3)
	assert_eq(fake.load_arg.name, "hero")
	assert_eq(fake.load_arg.rate, 0.75)

	fake.free()


func test_multiple_saveables_get_distinct_payloads() -> void:
	var a := _mk("a", {"v": 1, "label": "alpha"})
	var b := _mk("b", {"v": 2, "label": "beta"})
	_sys.register(a)
	_sys.register(b)

	assert_eq(_sys.save_to_slot(TEST_SLOT), OK)

	# Swap state so a load that misroutes would be detectable
	a.captured = {}
	b.captured = {}

	assert_eq(_sys.load_from_slot(TEST_SLOT), OK)
	assert_eq(a.load_arg.v, 1)
	assert_eq(a.load_arg.label, "alpha")
	assert_eq(b.load_arg.v, 2)
	assert_eq(b.load_arg.label, "beta")

	a.free()
	b.free()


func test_save_files_appear_on_disk() -> void:
	var fake := _mk("disk", {"hp": 7})
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(TEST_SLOT), OK)

	var save_path := "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, TEST_SLOT, SaveConfig.SAVE_EXTENSION]
	var meta_path := "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, TEST_SLOT, SaveConfig.META_EXTENSION]
	assert_true(FileAccess.file_exists(save_path), "main .save should exist")
	assert_true(FileAccess.file_exists(meta_path), "sidecar .meta.tres should exist")

	fake.free()


func test_saveable_without_save_data_method_is_skipped() -> void:
	# A node in the registry that has save_id but no save_data method should
	# not crash the save pipeline.
	var plain := Node.new()
	plain.set_meta("save_id_like", "ignored")
	_sys.register(plain)

	var fake := _mk("real", {"ok": true})
	_sys.register(fake)

	assert_eq(_sys.save_to_slot(TEST_SLOT), OK, "save should skip the plain Node cleanly")
	fake.captured = {}
	assert_eq(_sys.load_from_slot(TEST_SLOT), OK)
	assert_eq(fake.load_arg.ok, true)

	plain.free()
	fake.free()


func test_empty_save_id_still_roundtrips_via_fallback() -> void:
	# Exercise the fallback branch in _saveable_id when save_id is empty.
	var noid := _mk("", {"tag": "no_id"})
	_sys.register(noid)

	assert_eq(_sys.save_to_slot(TEST_SLOT), OK)
	noid.captured = {}
	assert_eq(_sys.load_from_slot(TEST_SLOT), OK)
	assert_eq(noid.load_arg.tag, "no_id", "empty save_id should still roundtrip via fallback id")

	noid.free()
