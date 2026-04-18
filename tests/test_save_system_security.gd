@tool
extends McpTestSuite

## Security posture tests — "security" here means the hardcoded encryption
## deters casual save-editing, not that it's cryptographically strong. We
## just verify the file isn't plain-text JSON on disk and that wrong-password
## reads fail cleanly.

const SLOT := 931

var _sys: Node


class FakeSaveable:
	extends Node
	var save_id: String = "sec_fake"
	var captured: Dictionary = {"hp": 42, "secret": "you_should_not_read_me"}
	var loaded: Dictionary = {}

	func save_data() -> Dictionary:
		return captured.duplicate(true)

	func load_data(d: Dictionary) -> void:
		loaded = d


func suite_name() -> String:
	return "save_system_security"


func suite_setup(_ctx: Dictionary) -> void:
	var script := load("res://save_system/save_system.gd")
	_sys = script.new()


func suite_teardown() -> void:
	_sys.delete_slot(SLOT)
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_sys.delete_slot(SLOT)
	_sys._registered.clear()


func _save_path() -> String:
	return "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, SLOT, SaveConfig.SAVE_EXTENSION]


# ----- file contents are not plain text -----

func test_save_file_is_not_plain_text_json() -> void:
	var fake := FakeSaveable.new()
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	# Read raw bytes (bypassing decryption) and confirm we can't parse the
	# secret back. An unencrypted file would show "you_should_not_read_me".
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	assert_true(f != null, "should be able to open for reading")
	var raw := f.get_as_text()
	f.close()
	assert_false(raw.contains("you_should_not_read_me"),
		"plaintext secret must not appear in encrypted save bytes")
	assert_false(raw.contains("\"hp\""), "JSON structure must not appear plainly")

	# And JSON.parse_string on the raw bytes fails or yields non-dict.
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed == null or not (parsed is Dictionary),
		"raw save bytes must not parse as JSON dict")
	fake.free()


# ----- wrong password fails cleanly -----

func test_wrong_password_load_fails() -> void:
	var fake := FakeSaveable.new()
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	# Decrypt with wrong password through the helper directly.
	var out: Variant = SaveAtomicWrite.read_encrypted_json(_save_path(), "wrong-password")
	assert_true(out == null, "wrong password should yield null, not a partial dict")
	fake.free()


func test_load_emits_load_failed_on_corruption() -> void:
	# Write garbage to the slot file directly and attempt to load.
	DirAccess.make_dir_recursive_absolute(SaveConfig.SAVES_DIR)
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	assert_true(f != null)
	f.store_string("not an encrypted file at all, just raw bytes")
	f.close()

	var fail_reason := [""]
	var cb := func(_slot, reason): fail_reason[0] = reason
	_sys.load_failed.connect(cb)

	var fake := FakeSaveable.new()
	fake.loaded = {"hp": 999}
	_sys.register(fake)

	var err: int = _sys.load_from_slot(SLOT)
	assert_true(err != OK, "corrupt file should fail to load")
	assert_true(fail_reason[0] != "", "load_failed signal should fire with a reason")
	assert_eq(fake.loaded.hp, 999, "load_data must not be called on failed loads")

	_sys.load_failed.disconnect(cb)
	fake.free()
