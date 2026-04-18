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
func save_to_slot(slot_id: int, level_name: String = "", play_time_seconds: float = 0.0) -> Error:
	_ensure_saves_dir()
	var payload: Dictionary = {
		"schema_version": SaveConfig.SCHEMA_VERSION,
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
		payload.saveables[sid] = node.call("save_data")

	var save_path := _slot_save_path(slot_id)
	var err := SaveAtomicWrite.write_encrypted_json(save_path, payload, SaveConfig.ENCRYPTION_PASSWORD)
	if err != OK:
		save_failed.emit(slot_id, "write failed: " + error_string(err))
		return err

	var meta := SaveSlotMeta.new()
	meta.slot_id = slot_id
	meta.display_name = "Slot %d" % slot_id
	meta.saved_at_unix = payload.saved_at_unix
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
func load_from_slot(slot_id: int) -> Error:
	var save_path := _slot_save_path(slot_id)
	if not FileAccess.file_exists(save_path):
		load_failed.emit(slot_id, "no save at slot %d" % slot_id)
		return ERR_FILE_NOT_FOUND
	load_started.emit(slot_id)
	var data: Variant = SaveAtomicWrite.read_encrypted_json(save_path, SaveConfig.ENCRYPTION_PASSWORD)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		load_failed.emit(slot_id, "decrypt or parse failed")
		return ERR_PARSE_ERROR

	var ver: int = int((data as Dictionary).get("schema_version", 0))
	if ver <= 0 or ver > SaveConfig.SCHEMA_VERSION:
		load_failed.emit(slot_id, "unsupported schema_version: %d" % ver)
		return ERR_INVALID_DATA

	data = _migrate(data)

	var saveables_data: Dictionary = (data as Dictionary).get("saveables", {})
	for node in _collect_saveables():
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
	# Schema migrations live here when v2+ arrives. For now we only accept v1.
	return data
