## Career stats — a second saveable that lives alongside the Arena.
##
## Demonstrates adding a brand-new persisted record without touching the
## save_system library: drop the autoload, add it to the saveable group,
## implement save_data / load_data, done. Old saves missing these keys
## load with zeroed stats via the .get(…, default) convention.
extends Node

const SAVE_ID := "game_stats"
var save_id: String = SAVE_ID

var games_played: int = 0
var wins: int = 0
var total_jumps: int = 0
var total_walls_bumped: int = 0


func _ready() -> void:
	add_to_group(SaveConfig.SAVEABLE_GROUP)


## Called by GameMain when a game ends (winner determined, even if it's a
## draw). Folds the round's per-block numbers into the career totals.
func record_game_end(winner_block, player_block) -> void:
	games_played += 1
	if winner_block != null and winner_block == player_block:
		wins += 1
	if player_block != null and is_instance_valid(player_block):
		total_jumps += int(player_block.jumps)
		total_walls_bumped += int(player_block.walls_bumped)


func save_data() -> Dictionary:
	return {
		"games_played": games_played,
		"wins": wins,
		"total_jumps": total_jumps,
		"total_walls_bumped": total_walls_bumped,
	}


func load_data(d: Dictionary) -> void:
	games_played = int(d.get("games_played", 0))
	wins = int(d.get("wins", 0))
	total_jumps = int(d.get("total_jumps", 0))
	total_walls_bumped = int(d.get("total_walls_bumped", 0))
