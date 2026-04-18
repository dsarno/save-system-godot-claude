## Slot metadata resource.
##
## Written unencrypted as a sidecar (.meta.tres) so slot menus can list N
## slots with previews without touching the encrypted main save.
class_name SaveSlotMeta
extends Resource

@export var slot_id: int = 0
@export var display_name: String = ""
@export var saved_at_unix: int = 0
@export var play_time_seconds: float = 0.0
@export var level_name: String = ""
@export var game_version: String = ""
@export var thumbnail: Texture2D = null


## Returns a human-readable "saved at" string like "2026-04-17 14:05".
func saved_at_text() -> String:
	if saved_at_unix <= 0:
		return "never"
	var dt := Time.get_datetime_dict_from_unix_time(saved_at_unix)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]


## Returns a human-readable "play time" string like "1h 23m" or "45s".
func play_time_text() -> String:
	var total := int(play_time_seconds)
	if total < 60:
		return "%ds" % total
	var mins := total / 60
	var secs := total % 60
	if mins < 60:
		return "%dm %02ds" % [mins, secs]
	var hours := mins / 60
	mins = mins % 60
	return "%dh %02dm" % [hours, mins]
