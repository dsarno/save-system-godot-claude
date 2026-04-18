## Slot picker UI — lists N slots with metadata, Save/Load/Delete buttons
## per slot. Pauses the tree when open so physics freezes while the player
## browses.
extends Control

signal new_game_requested
signal load_requested(slot_id: int)

const SLOT_IDS: Array[int] = [1, 2, 3, 4, 5]

@onready var _rows: VBoxContainer = $Panel/Margin/VBox/RowsScroll/Rows
@onready var _close_btn: Button = $Panel/Margin/VBox/Footer/CloseBtn
@onready var _new_game_btn: Button = $Panel/Margin/VBox/Footer/NewGameBtn
@onready var _career_label: Label = $Panel/Margin/VBox/CareerStats


func _ready() -> void:
	_close_btn.pressed.connect(close)
	_new_game_btn.pressed.connect(_on_new_game)
	SaveSystem.saved.connect(_on_save_system_changed)
	SaveSystem.loaded.connect(_on_save_system_changed)
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	# SlotMenu runs in PROCESS_MODE_ALWAYS so it still receives input while
	# the tree is paused. GameMain's ESC handler only fires when unpaused —
	# once the menu is open we own the toggle.
	if visible and event.is_action_pressed("toggle_menu"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_rebuild()
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _on_new_game() -> void:
	close()
	new_game_requested.emit()


func _on_save_system_changed(_slot_id: int) -> void:
	# Auto-refresh when a save/load fires from anywhere.
	if visible:
		_rebuild()


func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var metas: Dictionary = {}
	for meta in SaveSystem.list_slots():
		metas[int(meta.slot_id)] = meta
	for slot_id in SLOT_IDS:
		_rows.add_child(_build_row(slot_id, metas.get(slot_id, null)))
	_career_label.text = "Career:  %d played   \u00b7   %d wins   \u00b7   %d jumps   \u00b7   %d wall bumps" % [
		GameStats.games_played,
		GameStats.wins,
		GameStats.total_jumps,
		GameStats.total_walls_bumped,
	]


func _build_row(slot_id: int, meta) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Slot %d" % slot_id
	title.add_theme_font_size_override("font_size", 20)
	info.add_child(title)

	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 14)
	if meta == null:
		detail.text = "Empty"
		detail.modulate = Color(0.7, 0.7, 0.7)
	else:
		detail.text = "%s   ·   %s   ·   %s" % [
			meta.level_name if meta.level_name != "" else "—",
			meta.saved_at_text(),
			meta.play_time_text(),
		]
	info.add_child(detail)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(func(): SaveSystem.save_to_slot(slot_id, "arena", _play_time()))

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.disabled = meta == null
	load_btn.pressed.connect(func(): _on_load_pressed(slot_id))

	var delete_btn := Button.new()
	delete_btn.text = "Delete"
	delete_btn.disabled = meta == null
	delete_btn.pressed.connect(func():
		SaveSystem.delete_slot(slot_id)
		_rebuild()
	)

	row.add_child(info)
	row.add_child(save_btn)
	row.add_child(load_btn)
	row.add_child(delete_btn)
	return row


func _on_load_pressed(slot_id: int) -> void:
	# Unpause before loading so physics state from the save takes effect
	# in a running tree.
	get_tree().paused = false
	visible = false
	load_requested.emit(slot_id)


func _play_time() -> float:
	# Arena's elapsed_seconds is the natural play-time proxy. Look it up
	# from the first saveable Arena in the tree.
	for n in get_tree().get_nodes_in_group(SaveConfig.SAVEABLE_GROUP):
		if "elapsed_seconds" in n:
			return float(n.elapsed_seconds)
	return 0.0
