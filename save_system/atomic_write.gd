## Atomic file replace helpers for the save system.
##
## Pattern: write to `<path>.tmp`, flush/close, then swap into place via a
## rename. If the existing file exists we first rotate it to `<path>.backup`
## so a mid-swap crash leaves a recoverable file behind.
##
## All functions return a Godot Error code (OK == 0 on success).
class_name SaveAtomicWrite
extends RefCounted


## Write a Dictionary as JSON into `path`, encrypted with `password`,
## using the atomic-replace pattern.
static func write_encrypted_json(path: String, data: Dictionary, password: String) -> Error:
	var tmp_path := path + ".tmp"
	var f := FileAccess.open_encrypted_with_pass(tmp_path, FileAccess.WRITE, password)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data))
	f.close()
	return _swap_into_place(tmp_path, path)


## Read and decrypt an encrypted JSON file.
## Returns null on any failure (missing file, wrong password, malformed JSON).
static func read_encrypted_json(path: String, password: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, password)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	if text.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(text)
	return parsed


## Delete a file if it exists. Returns OK whether or not it existed.
static func safe_delete(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


static func _swap_into_place(tmp_path: String, final_path: String) -> Error:
	var dir := final_path.get_base_dir()
	var da := DirAccess.open(dir)
	if da == null:
		return ERR_FILE_CANT_OPEN
	var final_name := final_path.get_file()
	var tmp_name := tmp_path.get_file()
	var backup_name := final_name + ".backup"
	# Rotate existing file out of the way so rename(tmp -> final) can succeed
	# on platforms where rename refuses to overwrite.
	if da.file_exists(final_name):
		if da.file_exists(backup_name):
			da.remove(backup_name)
		var rot_err := da.rename(final_name, backup_name)
		if rot_err != OK:
			return rot_err
	var swap_err := da.rename(tmp_name, final_name)
	if swap_err != OK:
		# Roll back the rotated backup if we moved it.
		if da.file_exists(backup_name) and not da.file_exists(final_name):
			da.rename(backup_name, final_name)
		return swap_err
	# Successful swap — clean up stale backup.
	if da.file_exists(backup_name):
		da.remove(backup_name)
	return OK
