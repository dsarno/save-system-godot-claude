## RigidBody3D block that wanders around the arena and loses HP on impact.
##
## Wander AI: every few seconds pick a random ground target and apply a small
## steering force toward it. Keeps collisions happening without a real combat AI.
##
## Not in the "saveable" group — the Arena owns blocks and serializes them in
## its own save_data. This file still exposes save_data/load_data so Arena can
## delegate per-block capture/restore. Library never sees blocks directly.
class_name Block
extends RigidBody3D

signal died(block)

@export var hp: int = 100
@export var max_hp: int = 100
@export var block_color: Color = Color.WHITE
@export var block_name: String = ""
## When true, this block is driven by player input (WASD + Space) instead of
## the wander AI. Saved so reloads restore which block the player controls.
@export var is_player: bool = false

## Gameplay stats — demonstrate the save-system's extensibility. Both
## persist through save/load; old saves lacking these keys default to 0
## via load_data's `.get(key, default)` pattern.
var jumps: int = 0
var walls_bumped: int = 0

## Minimum relative impact speed before damage applies. Below this the blocks
## just bump harmlessly.
@export var impact_threshold: float = 2.0
## Damage per unit of impact speed above the threshold.
@export var damage_per_impact_unit: float = 10.0
## Force applied toward the current wander target each physics step.
@export var steer_force: float = 14.0
## Interval between picking new wander targets.
@export var wander_interval: float = 2.5
## Half-size of the wander region (square around origin). Keeps targets
## comfortably inside a 20×20 arena.
@export var wander_half_extent: float = 8.0
## Force multiplier applied to the WASD vector for the player block.
## Higher than steer_force so input feels responsive against the AI jostling.
@export var player_move_force: float = 28.0
## Upward impulse applied on jump. Scaled roughly for mass=1.
@export var jump_impulse: float = 7.0
## How close to the floor we must be to re-jump. Small epsilon for physics jitter.
@export var ground_epsilon: float = 0.12

var alive: bool = true

var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _material: StandardMaterial3D = null
var _pulse_time: float = 0.0

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_ensure_material()
	_apply_hp_tint()
	_pick_new_target()


func _process(delta: float) -> void:
	# Pulsing emission glow on the player block so it's visually unmistakable
	# among the AI crowd. ~1.4 Hz, oscillating between dim and bright.
	if not is_player or not alive or _material == null:
		return
	_pulse_time += delta
	var phase: float = (sin(_pulse_time * TAU * 1.4) + 1.0) * 0.5  # 0..1
	_material.emission_energy_multiplier = lerp(0.4, 2.2, phase)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if is_player:
		_player_tick()
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_target()
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.04:
		return
	apply_central_force(to_target.normalized() * steer_force)


## Player-control tick — WASD nudges a horizontal force, Space triggers an
## upward impulse when the block is close to the floor. Camera is fixed on
## +Z looking down, so "forward" (W) is -Z (away from camera).
func _player_tick() -> void:
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vec != Vector2.ZERO:
		var force := Vector3(input_vec.x, 0.0, input_vec.y) * player_move_force
		apply_central_force(force)
	if Input.is_action_just_pressed("jump") and _is_on_ground():
		apply_central_impulse(Vector3(0, jump_impulse, 0))
		jumps += 1


## Treat the block as grounded if its Y velocity is basically zero and it's
## low to the floor. Simple heuristic — no raycast needed for a box on a plane.
func _is_on_ground() -> bool:
	return absf(linear_velocity.y) < 0.6 and global_position.y < 0.6 + ground_epsilon


func _pick_new_target() -> void:
	_wander_timer = wander_interval
	_wander_target = Vector3(
		randf_range(-wander_half_extent, wander_half_extent),
		global_position.y,
		randf_range(-wander_half_extent, wander_half_extent),
	)


func _on_body_entered(other: Node) -> void:
	if not alive:
		return
	if other.is_in_group("wall"):
		walls_bumped += 1
		return
	if not (other is Block):
		return
	var other_block := other as Block
	if not other_block.alive:
		return
	# Both blocks take damage proportional to relative impact speed.
	var rel := linear_velocity - other_block.linear_velocity
	var impact := rel.length()
	if impact < impact_threshold:
		return
	var dmg := int((impact - impact_threshold) * damage_per_impact_unit)
	if dmg <= 0:
		return
	apply_damage(dmg)


func apply_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	hp = max(0, hp - amount)
	_apply_hp_tint()
	if hp == 0:
		_die()


func _die() -> void:
	alive = false
	freeze = true
	died.emit(self)
	if _material != null:
		_material.emission_enabled = false
	if _mesh != null:
		var tween := create_tween()
		tween.tween_property(_mesh, "transparency", 1.0, 0.6)


func _ensure_material() -> void:
	if _mesh == null:
		return
	if not (_mesh.material_override is StandardMaterial3D):
		_material = StandardMaterial3D.new()
		_mesh.material_override = _material
	else:
		_material = _mesh.material_override
	_material.albedo_color = block_color
	_material.emission_enabled = is_player
	if is_player:
		_material.emission = block_color
		_material.emission_energy_multiplier = 0.5


func _apply_hp_tint() -> void:
	if _material == null:
		return
	var ratio: float = 1.0 if max_hp <= 0 else clamp(float(hp) / float(max_hp), 0.0, 1.0)
	var tinted := block_color * (0.3 + 0.7 * ratio)
	tinted.a = block_color.a
	_material.albedo_color = tinted


# -- Saveable contract (called by Arena) -------------------------------------

func save_data() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"color": [block_color.r, block_color.g, block_color.b, block_color.a],
		"name": block_name,
		"alive": alive,
		"is_player": is_player,
		"jumps": jumps,
		"walls_bumped": walls_bumped,
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": [rotation.x, rotation.y, rotation.z],
		"lv": [linear_velocity.x, linear_velocity.y, linear_velocity.z],
		"av": [angular_velocity.x, angular_velocity.y, angular_velocity.z],
	}


func load_data(d: Dictionary) -> void:
	hp = int(d.get("hp", max_hp))
	max_hp = int(d.get("max_hp", 100))
	var c: Array = d.get("color", [1.0, 1.0, 1.0, 1.0])
	var alpha: float = c[3] if c.size() > 3 else 1.0
	block_color = Color(float(c[0]), float(c[1]), float(c[2]), alpha)
	block_name = String(d.get("name", ""))
	alive = bool(d.get("alive", true))
	is_player = bool(d.get("is_player", false))
	jumps = int(d.get("jumps", 0))
	walls_bumped = int(d.get("walls_bumped", 0))

	var p: Array = d.get("pos", [0.0, 0.5, 0.0])
	var r: Array = d.get("rot", [0.0, 0.0, 0.0])
	var lv: Array = d.get("lv", [0.0, 0.0, 0.0])
	var av: Array = d.get("av", [0.0, 0.0, 0.0])

	# Teleport transform before restoring velocities; RigidBody3D picks up
	# both in the next physics step.
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
	linear_velocity = Vector3(float(lv[0]), float(lv[1]), float(lv[2]))
	angular_velocity = Vector3(float(av[0]), float(av[1]), float(av[2]))

	freeze = not alive
	_ensure_material()
	_apply_hp_tint()
	if _mesh != null:
		_mesh.transparency = 0.0 if alive else 1.0
	_pick_new_target()
