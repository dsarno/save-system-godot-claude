@tool
extends McpTestSuite

## Regression tests for the two new integrity gates on load:
##   1. HMAC signature over the payload body (detects tampering / corruption)
##   2. Per-saveable validate_data(dict) -> reason hook (detects logic-corrupt
##      state like hp > max_hp, NaN positions, etc.)
##
## Both gates run BEFORE any load_data fires so the live world stays
## consistent when a save is rejected.

const SLOT := 961


class ValidatingFake:
	extends FakeSaveable

	## Reject payloads where "hp" exceeds "max_hp".
	func validate_data(d: Dictionary) -> String:
		var hp: int = int(d.get("hp", 0))
		var mx: int = int(d.get("max_hp", 100))
		if hp > mx:
			return "hp %d > max_hp %d" % [hp, mx]
		return ""


var _sys


func suite_name() -> String:
	return "save_system_validation"


func suite_setup(_ctx: Dictionary) -> void:
	_sys = load("res://save_system/save_system.gd").new()


func suite_teardown() -> void:
	_sys.delete_slot(SLOT)
	if is_instance_valid(_sys):
		_sys.free()


func setup() -> void:
	_sys.delete_slot(SLOT)
	_sys.clear_registered()


func _save_path() -> String:
	return "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, SLOT, SaveConfig.SAVE_EXTENSION]


# ----- HMAC -----

func test_tampered_body_rejected() -> void:
	var fake := FakeSaveable.new()
	fake.save_id = "tamper"
	fake.captured = {"v": 1}
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(SLOT), OK)

	# Decrypt the saved file, mutate the body (keep HMAC the same), rewrite.
	var envelope = SaveAtomicWrite.read_encrypted_json(_save_path(), SaveConfig.ENCRYPTION_PASSWORD)
	assert_true(envelope is Dictionary, "saved envelope must be a Dictionary")
	var original_body: String = envelope.body
	envelope.body = original_body.replace("\"v\":1", "\"v\":999")
	assert_ne(envelope.body, original_body, "test precondition: body must have changed")
	SaveAtomicWrite.write_encrypted_json(_save_path(), envelope, SaveConfig.ENCRYPTION_PASSWORD)

	fake.loaded = {"sentinel": true}
	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA, "HMAC mismatch must reject with ERR_INVALID_DATA")
	assert_eq(fake.loaded.sentinel, true, "load_data must not be called on HMAC failure")
	fake.free()


func test_hmac_intact_roundtrip_ok() -> void:
	# Sanity: a normal save-then-load roundtrip passes HMAC.
	var fake := FakeSaveable.new()
	fake.save_id = "clean"
	fake.captured = {"v": 7}
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(SLOT), OK)

	fake.captured = {}
	assert_eq(_sys.load_from_slot(SLOT), OK)
	assert_eq(fake.loaded.v, 7)
	fake.free()


func test_missing_envelope_fields_rejected() -> void:
	# Simulate a malformed envelope with no body/hmac fields.
	DirAccess.make_dir_recursive_absolute(SaveConfig.SAVES_DIR)
	SaveAtomicWrite.write_encrypted_json(
		_save_path(),
		{"schema_version": SaveConfig.SCHEMA_VERSION},
		SaveConfig.ENCRYPTION_PASSWORD
	)
	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA, "missing hmac/body must be rejected")


# ----- validate_data -----

func test_validate_rejects_and_no_load_data_called() -> void:
	var fake := ValidatingFake.new()
	fake.save_id = "validated"
	fake.captured = {"hp": 200, "max_hp": 100}  # intentionally invalid
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(SLOT), OK)

	fake.loaded = {"sentinel": true}
	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA, "validate_data should reject invalid state")
	assert_eq(fake.loaded.sentinel, true, "load_data must not run on validation failure")
	fake.free()


func test_validate_accepts_and_load_data_called() -> void:
	var fake := ValidatingFake.new()
	fake.save_id = "ok"
	fake.captured = {"hp": 50, "max_hp": 100}
	_sys.register(fake)
	assert_eq(_sys.save_to_slot(SLOT), OK)

	fake.loaded = {}
	assert_eq(_sys.load_from_slot(SLOT), OK)
	assert_eq(fake.loaded.hp, 50, "load_data ran after validation passed")
	fake.free()


func test_validation_failure_aborts_whole_load() -> void:
	# One saveable is fine, the other invalid. Nothing should load.
	var ok := ValidatingFake.new()
	ok.save_id = "a"
	ok.captured = {"hp": 10, "max_hp": 100}

	var bad := ValidatingFake.new()
	bad.save_id = "b"
	bad.captured = {"hp": 500, "max_hp": 100}  # invalid

	_sys.register(ok)
	_sys.register(bad)
	assert_eq(_sys.save_to_slot(SLOT), OK)

	ok.loaded = {"sentinel": true}
	bad.loaded = {"sentinel": true}
	var err: int = _sys.load_from_slot(SLOT)
	assert_eq(err, ERR_INVALID_DATA)
	assert_eq(ok.loaded.sentinel, true, "valid saveable must NOT be loaded when a sibling fails validation")
	assert_eq(bad.loaded.sentinel, true, "invalid saveable must not be loaded either")

	ok.free()
	bad.free()


func test_validate_data_optional() -> void:
	# Plain FakeSaveable has no validate_data method — load still works.
	var fake := FakeSaveable.new()
	fake.save_id = "optional"
	fake.captured = {"v": 3}
	_sys.register(fake)
	_sys.save_to_slot(SLOT)

	fake.captured = {}
	assert_eq(_sys.load_from_slot(SLOT), OK)
	assert_eq(fake.loaded.v, 3)
	fake.free()
