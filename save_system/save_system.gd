## Save system autoload — the whole public API for saving / loading game state.
##
## Usage (see save_system/README.md for the drop-in guide):
##   1. Register this script as an autoload named "SaveSystem".
##   2. Mark any node that needs to persist by adding it to group "saveable"
##      and implementing `save_data() -> Dictionary` and
##      `load_data(d: Dictionary) -> void`.
##   3. Call SaveSystem.save_to_slot(1) or SaveSystem.quick_save().
##
## Dynamic collections (e.g. a spawner that owns a list of enemies) should be
## handled by the OWNER node rather than by each member — the owner becomes the
## saveable, serializes its children, and rebuilds them in load_data. This keeps
## the library free of collection-management special cases.
extends Node

signal saved(slot_id: int)
signal load_started(slot_id: int)
signal loaded(slot_id: int)
signal save_failed(slot_id: int, reason: String)
signal load_failed(slot_id: int, reason: String)

var last_used_slot: int = 1

# Explicit registry for saveables that can't use the group convention
# (e.g. non-Node RefCounteds held by some controller).
var _registered: Array = []


func _ready() -> void:
	_ensure_saves_dir()


## Explicit registration. Most users should add nodes to group "saveable"
## instead — this is for edge cases where the group approach doesn't fit.
func register(node: Object) -> void:
	if node != null and not _registered.has(node):
		_registered.append(node)


func unregister(node: Object) -> void:
	_registered.erase(node)


## Clear every explicitly-registered saveable. Mostly useful for tests that
## rebuild their fixture between cases without needing a full editor reload.
func clear_registered() -> void:
	_registered.clear()


## Save the current state of all saveables to the given slot.
##
## File format (decrypted): {"schema_version": 2, "hmac": "<hex>",
## "body": "<json string of inner payload>"}. The body is JSON-stringified
## before hashing so the HMAC is computed over the exact bytes that land
## on disk — no dictionary-ordering drift.
func save_to_slot(slot_id: int, level_name: String = "", play_time_seconds: float = 0.0) -> Error:
	_ensure_saves_dir()
	var inner: Dictionary = {
		"game_version": SaveConfig.GAME_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"play_time_seconds": play_time_seconds,
		"level_name": level_name,
		"saveables": {},
	}
	for node in _collect_saveables():
		if not _has_method(node, "save_data"):
			continue
		var sid := _saveable_id(node)
		inner.saveables[sid] = node.call("save_data")

	var body_json: String = JSON.stringify(inner)
	var envelope: Dictionary = {
		"schema_version": SaveConfig.SCHEMA_VERSION,
		"hmac": _compute_hmac(body_json),
		"body": body_json,
	}

	var save_path := _slot_save_path(slot_id)
	var err := SaveAtomicWrite.write_encrypted_json(save_path, envelope, SaveConfig.ENCRYPTION_PASSWORD)
	if err != OK:
		save_failed.emit(slot_id, "write failed: " + error_string(err))
		return err

	var meta := SaveSlotMeta.new()
	meta.slot_id = slot_id
	meta.display_name = "Slot %d" % slot_id
	meta.saved_at_unix = inner.saved_at_unix
	meta.play_time_seconds = play_time_seconds
	meta.level_name = level_name
	meta.game_version = SaveConfig.GAME_VERSION
	var meta_err := ResourceSaver.save(meta, _slot_meta_path(slot_id))
	if meta_err != OK:
		save_failed.emit(slot_id, "meta save failed: " + error_string(meta_err))
		return meta_err

	last_used_slot = slot_id
	saved.emit(slot_id)
	return OK


## Load the slot and apply it to all matching saveables.
##
## Two integrity gates run before any saveable sees the data:
##   1. HMAC over the body JSON must match (detects tampering / corruption
##      that slipped through encryption).
##   2. Every saveable with a `validate_data(dict) -> String` method runs
##      first; if any returns a non-empty reason, load aborts *before* any
##      `load_data` is called so the in-memory world stays consistent.
func load_from_slot(slot_id: int) -> Error:
	var save_path := _slot_save_path(slot_id)
	if not FileAccess.file_exists(save_path):
		load_failed.emit(slot_id, "no save at slot %d" % slot_id)
		return ERR_FILE_NOT_FOUND
	load_started.emit(slot_id)
	var envelope: Variant = SaveAtomicWrite.read_encrypted_json(save_path, SaveConfig.ENCRYPTION_PASSWORD)
	if envelope == null or typeof(envelope) != TYPE_DICTIONARY:
		load_failed.emit(slot_id, "decrypt or parse failed")
		return ERR_PARSE_ERROR

	var env_dict: Dictionary = envelope
	var ver: int = int(env_dict.get("schema_version", 0))
	if ver <= 0 or ver > SaveConfig.SCHEMA_VERSION:
		load_failed.emit(slot_id, "unsupported schema_version: %d" % ver)
		return ERR_INVALID_DATA

	# Verify HMAC before trusting the body.
	var body_json: String = String(env_dict.get("body", ""))
	var stored_hmac: String = String(env_dict.get("hmac", ""))
	if body_json == "" or stored_hmac == "":
		load_failed.emit(slot_id, "malformed envelope (missing body or hmac)")
		return ERR_INVALID_DATA
	if _compute_hmac(body_json) != stored_hmac:
		load_failed.emit(slot_id, "hmac mismatch — save may be tampered or corrupted")
		return ERR_INVALID_DATA

	var inner_parsed: Variant = JSON.parse_string(body_json)
	if typeof(inner_parsed) != TYPE_DICTIONARY:
		load_failed.emit(slot_id, "body JSON parse failed")
		return ERR_PARSE_ERROR
	var inner: Dictionary = _migrate(inner_parsed)

	var saveables_data: Dictionary = inner.get("saveables", {})
	var saveables := _collect_saveables()

	# Validation pass — before applying anything. A single failure aborts
	# the whole load so partial application can't leave a broken world.
	for node in saveables:
		if not _has_method(node, "validate_data"):
			continue
		var sid := _saveable_id(node)
		if not saveables_data.has(sid):
			continue
		var reason: String = String(node.call("validate_data", saveables_data[sid]))
		if reason != "":
			load_failed.emit(slot_id, "validation failed for '%s': %s" % [sid, reason])
			return ERR_INVALID_DATA

	# Apply pass.
	for node in saveables:
		if not _has_method(node, "load_data"):
			continue
		var sid := _saveable_id(node)
		if saveables_data.has(sid):
			node.call("load_data", saveables_data[sid])

	last_used_slot = slot_id
	loaded.emit(slot_id)
	return OK


func quick_save(level_name: String = "", play_time_seconds: float = 0.0) -> Error:
	return save_to_slot(last_used_slot, level_name, play_time_seconds)


func quick_load() -> Error:
	return load_from_slot(last_used_slot)


## List all existing save slots by reading the unencrypted .meta.tres sidecars.
## Sorted by slot_id ascending. Returns Array[SaveSlotMeta].
func list_slots() -> Array:
	var slots: Array = []
	_ensure_saves_dir()
	var da := DirAccess.open(SaveConfig.SAVES_DIR)
	if da == null:
		return slots
	da.list_dir_begin()
	while true:
		var entry := da.get_next()
		if entry == "":
			break
		if entry.ends_with(SaveConfig.META_EXTENSION):
			var meta_path := SaveConfig.SAVES_DIR + "/" + entry
			var meta = ResourceLoader.load(meta_path, "SaveSlotMeta", ResourceLoader.CACHE_MODE_IGNORE)
			if meta is SaveSlotMeta:
				slots.append(meta)
	da.list_dir_end()
	slots.sort_custom(func(a, b): return int(a.slot_id) < int(b.slot_id))
	return slots


func has_slot(slot_id: int) -> bool:
	return FileAccess.file_exists(_slot_save_path(slot_id))


func delete_slot(slot_id: int) -> Error:
	var err1 := SaveAtomicWrite.safe_delete(_slot_save_path(slot_id))
	var err2 := SaveAtomicWrite.safe_delete(_slot_meta_path(slot_id))
	# Also wipe any stale .tmp or .backup the crash-recovery path could leave.
	SaveAtomicWrite.safe_delete(_slot_save_path(slot_id) + ".tmp")
	SaveAtomicWrite.safe_delete(_slot_save_path(slot_id) + ".backup")
	if err1 != OK:
		return err1
	if err2 != OK:
		return err2
	return OK


# --- internals ---------------------------------------------------------------


func _collect_saveables() -> Array:
	# Snapshot the saveable set so in-flight mutations inside save_data /
	# load_data can't affect iteration.
	var result: Array = []
	var seen: Dictionary = {}
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(SaveConfig.SAVEABLE_GROUP):
			if is_instance_valid(node) and not seen.has(node):
				result.append(node)
				seen[node] = true
	for node in _registered:
		if is_instance_valid(node) and not seen.has(node):
			result.append(node)
			seen[node] = true
	return result


func _saveable_id(node: Object) -> String:
	# Prefer an explicit `save_id` property (StringName or String). Falls back
	# to the scene-tree path for scene-baked Nodes.
	if "save_id" in node:
		var sid: String = String(node.get("save_id"))
		if sid != "":
			return sid
	if node is Node:
		return str((node as Node).get_path())
	return str(node.get_instance_id())


func _has_method(obj: Object, method: String) -> bool:
	return obj != null and obj.has_method(method)


func _ensure_saves_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SaveConfig.SAVES_DIR)


func _slot_save_path(slot_id: int) -> String:
	return "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, slot_id, SaveConfig.SAVE_EXTENSION]


func _slot_meta_path(slot_id: int) -> String:
	return "%s/slot_%d%s" % [SaveConfig.SAVES_DIR, slot_id, SaveConfig.META_EXTENSION]


func _migrate(data: Dictionary) -> Dictionary:
	# Inner payload migrations go here when v3+ arrives. v2 carries no
	# migration debt yet — the envelope change alone bumped the version.
	return data


func _compute_hmac(body: String) -> String:
	var crypto := Crypto.new()
	var digest := crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		SaveConfig.HMAC_KEY.to_utf8_buffer(),
		body.to_utf8_buffer(),
	)
	return digest.hex_encode()
