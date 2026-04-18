## In-game HUD — clock, per-block HP bars, winner overlay.
##
## Wired to an Arena via `bind_arena(arena)` by the parent scene. Keeps no
## state of its own — always re-reads from Arena each frame so loading a save
## "just works" (the Arena's load_data replaces its blocks and the HUD
## rediscovers them).
extends Control

@onready var _time_label: Label = $TimeLabel
@onready var _block_stats: VBoxContainer = $BlockStats
@onready var _winner_label: Label = $WinnerLabel

var _arena: Node = null
var _row_by_block: Dictionary = {}


func bind_arena(arena: Node) -> void:
	if _arena == arena:
		return
	if _arena != null:
		if _arena.winner_determined.is_connected(_on_winner):
			_arena.winner_determined.disconnect(_on_winner)
		if _arena.game_reset.is_connected(_on_game_reset):
			_arena.game_reset.disconnect(_on_game_reset)
	_arena = arena
	if _arena != null:
		_arena.winner_determined.connect(_on_winner)
		_arena.game_reset.connect(_on_game_reset)
	_rebuild_rows()
	_winner_label.visible = false


func _process(_delta: float) -> void:
	if _arena == null:
		return
	_time_label.text = _format_time(_arena.elapsed_seconds)
	# Rebuild if the block list changed (e.g. after a load).
	if _row_by_block.size() != _arena.blocks.size():
		_rebuild_rows()
	for b in _arena.blocks:
		if not is_instance_valid(b):
			continue
		var row: HBoxContainer = _row_by_block.get(b, null)
		if row == null:
			continue
		var name_label: Label = row.get_node_or_null("Name")
		var hp_label: Label = row.get_node_or_null("Hp")
		if name_label != null:
			name_label.text = b.block_name
			name_label.add_theme_color_override("font_color", b.block_color)
		if hp_label != null:
			if b.alive:
				var suffix := ""
				if b.is_player:
					# Surface player-only stats — demonstrates that the save
					# system preserves arbitrary fields added to Block.
					suffix = "  J:%d W:%d" % [b.jumps, b.walls_bumped]
				hp_label.text = "%d / %d%s" % [b.hp, b.max_hp, suffix]
			else:
				hp_label.text = "DEAD"


func _on_winner(block) -> void:
	_winner_label.visible = true
	if block == null:
		_winner_label.text = "DRAW"
		_winner_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	else:
		_winner_label.text = "WINNER: %s" % block.block_name
		_winner_label.add_theme_color_override("font_color", block.block_color)


func _on_game_reset() -> void:
	_winner_label.visible = false
	_rebuild_rows()


func _rebuild_rows() -> void:
	for child in _block_stats.get_children():
		child.queue_free()
	_row_by_block.clear()
	if _arena == null:
		return
	for b in _arena.blocks:
		if not is_instance_valid(b):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = b.block_name
		name_label.add_theme_color_override("font_color", b.block_color)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 4)
		name_label.add_theme_font_size_override("font_size", 22)
		var hp_label := Label.new()
		hp_label.name = "Hp"
		hp_label.text = "%d / %d" % [b.hp, b.max_hp]
		hp_label.add_theme_color_override("font_color", Color(1, 1, 1))
		hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
		hp_label.add_theme_constant_override("outline_size", 4)
		hp_label.add_theme_font_size_override("font_size", 22)
		row.add_child(name_label)
		row.add_child(hp_label)
		_block_stats.add_child(row)
		_row_by_block[b] = row


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	var mins := total / 60
	var secs := total % 60
	return "%02d:%02d" % [mins, secs]
