## Root scene controller: wires Arena + Hud + SlotMenu and routes input.
##
## F5 → quick save, F9 → quick load, ESC → slot menu, R → reset game.
extends Node

@onready var _arena: Node = $Arena
@onready var _hud: Control = $UiLayer/Hud
@onready var _slot_menu: Control = $UiLayer/SlotMenu


func _ready() -> void:
	_hud.bind_arena(_arena)
	_slot_menu.new_game_requested.connect(_on_new_game)
	_slot_menu.load_requested.connect(_on_load_requested)
	SaveSystem.loaded.connect(_on_slot_loaded)
	_arena.winner_determined.connect(_on_winner_determined)


func _on_winner_determined(winner_block) -> void:
	var player = _find_player_block()
	GameStats.record_game_end(winner_block, player)


func _find_player_block() -> Node:
	for b in _arena.blocks:
		if is_instance_valid(b) and b.is_player:
			return b
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu"):
		if _slot_menu.visible:
			_slot_menu.close()
		else:
			_slot_menu.open()
		get_viewport().set_input_as_handled()
		return

	if _slot_menu.visible:
		return

	if event.is_action_pressed("quick_save"):
		SaveSystem.save_to_slot(SaveSystem.last_used_slot, "arena", _arena.elapsed_seconds)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		SaveSystem.quick_load()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_game"):
		_arena.spawn_new_game()
		get_viewport().set_input_as_handled()


func _on_new_game() -> void:
	_arena.spawn_new_game()


func _on_load_requested(slot_id: int) -> void:
	SaveSystem.load_from_slot(slot_id)


func _on_slot_loaded(_slot_id: int) -> void:
	# Rebuild HUD rows against the new block list.
	_hud.bind_arena(_arena)
