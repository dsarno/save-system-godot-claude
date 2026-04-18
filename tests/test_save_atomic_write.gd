@tool
extends McpTestSuite

## Regression tests for SaveAtomicWrite — the encrypted atomic-replace layer
## underneath the save system. Kept in its own suite so failures here isolate
## to the I/O helper, not the higher-level library.

const PASSWORD := "test-password-xyz"
const TEST_DIR := "user://save_system_tests/atomic"


func suite_name() -> String:
	return "save_atomic_write"


func suite_setup(_ctx: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func suite_teardown() -> void:
	_wipe()


func setup() -> void:
	_wipe()


func _wipe() -> void:
	var da := DirAccess.open(TEST_DIR)
	if da == null:
		return
	da.list_dir_begin()
	while true:
		var entry := da.get_next()
		if entry == "":
			break
		if not da.current_is_dir():
			da.remove(entry)
	da.list_dir_end()


func _path(name: String) -> String:
	return TEST_DIR + "/" + name


# ----- roundtrip -----

func test_encrypted_roundtrip() -> void:
	var path := _path("roundtrip.save")
	var payload := {"hello": "world", "n": 42, "nested": {"a": [1, 2, 3]}}
	var err := SaveAtomicWrite.write_encrypted_json(path, payload, PASSWORD)
	assert_eq(err, OK, "write_encrypted_json should succeed")
	assert_true(FileAccess.file_exists(path), "save file must exist after write")
	var out: Variant = SaveAtomicWrite.read_encrypted_json(path, PASSWORD)
	assert_true(out is Dictionary, "read_encrypted_json should return Dictionary")
	assert_eq(out.hello, "world")
	assert_eq(out.n, 42)
	assert_eq(out.nested.a.size(), 3)


func test_overwrite_replaces_cleanly() -> void:
	var path := _path("overwrite.save")
	SaveAtomicWrite.write_encrypted_json(path, {"v": 1}, PASSWORD)
	SaveAtomicWrite.write_encrypted_json(path, {"v": 2}, PASSWORD)
	var out: Variant = SaveAtomicWrite.read_encrypted_json(path, PASSWORD)
	assert_eq(out.v, 2, "second write must fully replace the first")


# ----- failure modes -----

func test_wrong_password_returns_null() -> void:
	var path := _path("pw.save")
	SaveAtomicWrite.write_encrypted_json(path, {"v": 1}, PASSWORD)
	var out: Variant = SaveAtomicWrite.read_encrypted_json(path, "different-password")
	assert_true(out == null, "wrong password must yield null, not a partial dict")


func test_missing_file_returns_null() -> void:
	var out: Variant = SaveAtomicWrite.read_encrypted_json(_path("nope.save"), PASSWORD)
	assert_true(out == null)


# ----- safe_delete -----

func test_safe_delete_missing_returns_ok() -> void:
	var err := SaveAtomicWrite.safe_delete(_path("ghost.save"))
	assert_eq(err, OK, "safe_delete must tolerate missing files")


func test_safe_delete_existing_removes_file() -> void:
	var path := _path("exists.save")
	SaveAtomicWrite.write_encrypted_json(path, {"v": 1}, PASSWORD)
	assert_true(FileAccess.file_exists(path))
	var err := SaveAtomicWrite.safe_delete(path)
	assert_eq(err, OK)
	assert_false(FileAccess.file_exists(path), "file should be gone after safe_delete")


# ----- no residue -----

func test_no_tmp_or_backup_after_successful_write() -> void:
	var path := _path("clean.save")
	# Two writes to force the rotation path (first creates, second triggers .backup rotate).
	SaveAtomicWrite.write_encrypted_json(path, {"v": 1}, PASSWORD)
	SaveAtomicWrite.write_encrypted_json(path, {"v": 2}, PASSWORD)
	assert_false(FileAccess.file_exists(path + ".tmp"), ".tmp must be renamed into place")
	assert_false(FileAccess.file_exists(path + ".backup"), ".backup must be cleaned up after success")
	assert_true(FileAccess.file_exists(path), "final file must exist")
