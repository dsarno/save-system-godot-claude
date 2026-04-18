@tool
extends McpTestSuite

## Signal tests — `saved`, `loaded`, `save_failed`, `load_failed` must fire
## with correct payloads at the right time.

const SLOT := 941
const MISSING_SLOT := 942

var _sys: Node


func _new_fake() -> FakeSaveable:
	var f := FakeSaveable.new()
	f.save_id = "signal_fake"
	f.captured = {"v": 1}
	return f


func suite_name() -> String:
	return "save_system_signals"


func suite_setup(_ctx: Dictionary) -> void:
	var script := load("res://save_system/save_system.gd")
	_sys = script.new()


func suite_teardown() -> void:
	_sys.delete_slot(SLOT)
	_sys.delete_slot(MISSING_SLOT)
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_sys.delete_slot(SLOT)
	_sys.delete_slot(MISSING_SLOT)
	_sys.clear_registered()


# ----- saved -----

func test_saved_signal_fires_with_slot_id() -> void:
	var got := [-1]
	var cb := func(slot): got[0] = slot
	_sys.saved.connect(cb)

	var fake := FakeSaveable.new()
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(SLOT), OK)
	assert_eq(got[0], SLOT, "saved should emit with slot_id")

	_sys.saved.disconnect(cb)
	fake.free()


# ----- loaded -----

func test_loaded_signal_fires_with_slot_id() -> void:
	var fake := FakeSaveable.new()
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	var got := [-1]
	var cb := func(slot): got[0] = slot
	_sys.loaded.connect(cb)

	assert_eq(_sys.load_from_slot(SLOT), OK)
	assert_eq(got[0], SLOT, "loaded should emit with slot_id")

	_sys.loaded.disconnect(cb)
	fake.free()


# ----- load_started fires before loaded -----

func test_load_started_fires_before_loaded() -> void:
	var fake := FakeSaveable.new()
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	var order: Array = []
	var on_start := func(_slot): order.append("started")
	var on_done := func(_slot): order.append("loaded")
	_sys.load_started.connect(on_start)
	_sys.loaded.connect(on_done)

	_sys.load_from_slot(SLOT)
	assert_eq(order.size(), 2)
	assert_eq(order[0], "started")
	assert_eq(order[1], "loaded")

	_sys.load_started.disconnect(on_start)
	_sys.loaded.disconnect(on_done)
	fake.free()


# ----- load_failed fires on missing slot -----

func test_load_failed_fires_on_missing_slot() -> void:
	var got_slot := [-1]
	var got_reason := [""]
	var cb := func(slot, reason):
		got_slot[0] = slot
		got_reason[0] = reason
	_sys.load_failed.connect(cb)

	var err: int = _sys.load_from_slot(MISSING_SLOT)
	assert_eq(err, ERR_FILE_NOT_FOUND)
	assert_eq(got_slot[0], MISSING_SLOT)
	assert_true(got_reason[0] != "", "reason must be non-empty")

	_sys.load_failed.disconnect(cb)


# ----- save emits nothing on failure-less success -----

func test_saved_emits_only_once_per_save() -> void:
	var fake := FakeSaveable.new()
	_sys.register(fake)

	var count := [0]
	var cb := func(_slot): count[0] += 1
	_sys.saved.connect(cb)
	_sys.save_to_slot(SLOT)
	assert_eq(count[0], 1, "saved should emit exactly once per successful save")

	_sys.saved.disconnect(cb)
	fake.free()
