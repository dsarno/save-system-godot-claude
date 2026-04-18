# Save System + Blocks Demo

A drop-in save system for Godot 4, plus a small 3D demo that exercises it.

Four cubes wander a neon-grid arena, bump each other, and lose HP on impact. You control one of them with **WASD + Space**. Whoever's left standing wins. Save/load at any moment via F5/F9 or the ESC slot menu — positions, velocities, HP, kill/jump counts, and the player designation all restore exactly.

## Getting started

1. Open the project in Godot 4.6+.
2. Play (F5 in the editor, or Play button).

## Controls

| Key | Action |
|-----|--------|
| WASD | Move the player block (Block 1 — it has a pulsing glow) |
| Space | Jump (if grounded) |
| F5 | Quick-save to the last-used slot |
| F9 | Quick-load from the last-used slot |
| ESC | Open / close the save-slot menu |
| R | Respawn all blocks |

## Save system (library)

The save system lives in [save_system/](save_system/) and is intentionally decoupled from this game — drop the folder into any Godot 4 project, register one autoload, and any node in group `saveable` that implements `save_data()`/`load_data()` gets persisted.

See [save_system/README.md](save_system/README.md) for the drop-in guide and API.

Highlights:
- **Encrypted atomic writes** (`FileAccess.open_encrypted_with_pass` + `.tmp` rename + `.backup` rotation)
- **JSON payload inside the encrypted blob** — readable after decryption for debugging
- **Unencrypted `.meta.tres` sidecar** per slot for fast slot-picker listing
- **Schema versioning** and `.get(key, default)` convention for backward-compat
- **6 test suites, 34 tests** — round-trip, slot management, schema compatibility, security posture, signals, atomic writes

Run the regression suite:

```
test_run   (via the godot-ai MCP plugin)
```

## What's in here

```
save_system/              drop-in library (GDScript, zero game dependencies)
  save_system.gd          autoload, whole public API (~220 lines)
  save_slot_meta.gd       Resource class for the .meta.tres sidecar
  save_config.gd          one-file knobs (password, paths, constants)
  atomic_write.gd         encrypted write helper with .tmp+rename + .backup
  README.md               drop-in instructions

game/                     the demo — scenes, scripts, Tron-ish visuals
  arena.tscn + .gd        floor, walls, camera, spawns blocks
  block.tscn + .gd        RigidBody3D with player + AI control
  hud.tscn + .gd          timer, HP readouts, winner overlay
  slot_menu.tscn + .gd    ESC slot picker
  game_main.tscn + .gd    root scene, input routing
  ui_theme.tres           synthwave theme
  tron_grid.gdshader      emissive grid floor
  floor_material.tres     shader material for the floor
  wall_material.tres      neon cyan material for arena rails
  slick.tres              low-friction PhysicsMaterial

tests/                    6 test suites for the save_system library
friction_log.md           running notes on godot-ai MCP pain points hit
```

## Credits

Built live with Claude Code + the [godot-ai](https://github.com/davidsarno/godot-ai) MCP plugin. Every scene, script, shader, and theme was created via MCP tool calls; see [friction_log.md](friction_log.md) for what worked and what didn't.
