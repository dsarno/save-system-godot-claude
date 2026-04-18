## In-game HUD — clock, per-block HP bars, winner overlay.
##
## Wired to an Arena via `bind_arena(arena)` by the parent scene. Keeps no
## state of its own — always re-reads from Arena each frame so loading a save
## "just works" (the Arena's load_data replaces its blocks and the HUD
## rediscovers them).
extends Control

@onready var _time_label: Label = $TimeLabel
@onready var _block_stats: VBoxContainer = $BlockStats
@onready var _winner_panel: Panel = $WinnerPanel
@onready var _winner_title: Label = $WinnerPanel/Margin/VBox/Title
@onready var _winner_subtitle: Label = $WinnerPanel/Margin/VBox/Subtitle

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
	_winner_panel.visible = false


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
		var row = _row_by_block.get(b, null)
		if row == null:
			continue
		var name_label: Label = row.find_child("Name", true, false)
		var hp_label: Label = row.find_child("Hp", true, false)
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
	_winner_panel.visible = true
	if block == null:
		_winner_title.text = "DRAW"
		_winner_title.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
		_winner_subtitle.text = "no survivors"
	else:
		_winner_title.text = "VICTORY" if block.is_player else "KO"
		_winner_title.add_theme_color_override("font_color", block.block_color)
		_winner_subtitle.text = block.block_name


func _on_game_reset() -> void:
	_winner_panel.visible = false
	_rebuild_rows()


func _rebuild_rows() -> void:
	for child in _block_stats.get_children():
		child.queue_free()
	_row_by_block.clear()
	if _arena == null:
		return
	for b in _arena.blocks:
		if is_instance_valid(b):
			var row := _build_row(b)
			_block_stats.add_child(row)
			_row_by_block[b] = row


## One row per block: PanelContainer with subtle card styling, inside an
## HBoxContainer holding a colored Name label + white HP label. The Hp
## label is looked up by name from _process to avoid holding extra refs.
func _build_row(b: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _row_stylebox(b.block_color))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	row.add_child(_styled_label("Name", b.block_name, b.block_color, 20, true))
	row.add_child(_styled_label("Hp", "%d / %d" % [b.hp, b.max_hp], Color(1, 1, 1), 20, false))

	margin.add_child(row)
	panel.add_child(margin)
	return panel


func _styled_label(node_name: String, text: String, color: Color, size: int, bold: bool) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", size)
	if bold:
		# Fake bold via slight shadow offset — real bold requires a bold
		# font resource the project doesn't ship. Outline already gives weight.
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _row_stylebox(block_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.14, 0.55)
	sb.border_color = block_color
	sb.border_width_left = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	return sb


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	var mins := total / 60
	var secs := total % 60
	return "%02d:%02d" % [mins, secs]
