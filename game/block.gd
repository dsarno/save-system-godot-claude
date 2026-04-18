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

## Minimum relative impact speed before damage applies. Below this the blocks
## just bump harmlessly.
@export var impact_threshold: float = 2.0
## Damage per unit of impact speed above the threshold.
@export var damage_per_impact_unit: float = 10.0
## Force applied toward the current wander target each physics step.
@export var steer_force: float = 4.0
## Interval between picking new wander targets.
@export var wander_interval: float = 2.5
## Half-size of the wander region (square around origin). Keeps targets
## comfortably inside a 20×20 arena.
@export var wander_half_extent: float = 8.0

var alive: bool = true

var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _material: StandardMaterial3D = null

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_ensure_material()
	_apply_hp_tint()
	_pick_new_target()


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_target()
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.04:
		return
	apply_central_force(to_target.normalized() * steer_force)


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
