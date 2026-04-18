## Arena — spawns a fixed-size cast of Blocks, watches for a winner, and is
## itself the single saveable for the scene (owns Block serialization).
##
## Design: Blocks are NOT in group "saveable"; Arena serializes them as part of
## its own save_data. This keeps the save_system library free of collection
## special cases — the owner handles its dynamic children.
class_name Arena
extends Node3D

signal winner_determined(block)
signal game_reset

const BLOCK_SCENE_PATH := "res://game/block.tscn"

@export var num_blocks: int = 4
@export var block_colors: Array[Color] = [
	Color(1.00, 0.35, 0.35),
	Color(0.35, 0.80, 0.35),
	Color(0.35, 0.55, 1.00),
	Color(1.00, 0.85, 0.20),
	Color(0.85, 0.35, 0.90),
	Color(0.95, 0.55, 0.20),
]
@export var spawn_radius: float = 4.0
@export var spawn_speed: float = 3.0

## Stable save_id so the save system can round-trip even if the scene is
## renamed or reparented.
var save_id: String = "arena"

var blocks: Array[Block] = []
var elapsed_seconds: float = 0.0
var winner: Block = null

var _block_scene: PackedScene


func _ready() -> void:
	add_to_group(SaveConfig.SAVEABLE_GROUP)
	_block_scene = load(BLOCK_SCENE_PATH)
	spawn_new_game()


func _process(delta: float) -> void:
	if winner != null:
		return
	elapsed_seconds += delta
	_check_winner()


## Clear any existing blocks and spawn a fresh cast around the spawn ring.
func spawn_new_game() -> void:
	_clear_blocks()
	winner = null
	elapsed_seconds = 0.0
	for i in range(num_blocks):
		var b := _spawn_block(i)
		blocks.append(b)
	game_reset.emit()


func alive_blocks() -> Array:
	return blocks.filter(func(b): return is_instance_valid(b) and b.alive)


func _spawn_block(index: int) -> Block:
	var b: Block = _block_scene.instantiate()
	# Set @export properties BEFORE add_child so Block._ready sees the final
	# values when it builds its material. If we set them after, _ready has
	# already baked a material with the default (white) block_color.
	b.block_name = "Block %d" % (index + 1)
	b.block_color = block_colors[index % block_colors.size()]
	b.max_hp = 100
	b.hp = b.max_hp
	$Blocks.add_child(b)
	var angle := (float(index) / float(num_blocks)) * TAU
	b.global_position = Vector3(cos(angle) * spawn_radius, 0.6, sin(angle) * spawn_radius)
	b.linear_velocity = Vector3(-sin(angle), 0.0, cos(angle)) * spawn_speed
	b.died.connect(_on_block_died)
	return b


func _clear_blocks() -> void:
	for b in blocks:
		if is_instance_valid(b):
			b.queue_free()
	blocks.clear()


func _on_block_died(_block) -> void:
	# Actual winner resolution happens in _process so death-frame ordering
	# doesn't affect the outcome.
	pass


func _check_winner() -> void:
	var alive: Array = alive_blocks()
	if alive.size() == 1 and blocks.size() > 1:
		winner = alive[0]
		winner_determined.emit(winner)
	elif alive.size() == 0 and blocks.size() > 0:
		winner = null
		winner_determined.emit(null)  # draw


# -- Saveable contract --------------------------------------------------------

func save_data() -> Dictionary:
	var entries: Array = []
	for b in blocks:
		if is_instance_valid(b):
			entries.append({
				"scene": b.scene_file_path,
				"state": b.save_data(),
			})
	var winner_idx := -1
	if winner != null and winner in blocks:
		winner_idx = blocks.find(winner)
	return {
		"elapsed_seconds": elapsed_seconds,
		"num_blocks": num_blocks,
		"blocks": entries,
		"winner_index": winner_idx,
	}


func load_data(d: Dictionary) -> void:
	_clear_blocks()
	winner = null
	elapsed_seconds = float(d.get("elapsed_seconds", 0.0))
	num_blocks = int(d.get("num_blocks", num_blocks))

	var entries: Array = d.get("blocks", [])
	for entry in entries:
		var scene_path := String(entry.get("scene", BLOCK_SCENE_PATH))
		var state: Dictionary = entry.get("state", {})
		var packed: PackedScene = load(scene_path)
		var b: Block = packed.instantiate()
		$Blocks.add_child(b)
		b.died.connect(_on_block_died)
		b.load_data(state)
		blocks.append(b)

	var winner_idx := int(d.get("winner_index", -1))
	if winner_idx >= 0 and winner_idx < blocks.size():
		winner = blocks[winner_idx]
		winner_determined.emit(winner)
	else:
		game_reset.emit()
