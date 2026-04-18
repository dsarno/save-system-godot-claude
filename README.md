# Save System + Blocks Demo

A drop-in save system for Godot 4, plus a small 3D demo that exercises it.

Four cubes wander a neon-grid arena, bump each other, and lose HP on impact. You control one of them with **WASD + Space**. Whoever's left standing wins. Save/load at any moment via F5/F9 or the ESC slot menu — positions, velocities, HP, kill/jump counts, the player designation, career totals across sessions, and the event log all restore exactly.

## How to run

1. **Install Godot 4.6** (the `.mono` build is fine; the project has no C# code — the `[dotnet]` section in `project.godot` is just leftover from scaffolding).
   macOS download: <https://godotengine.org/download/macos/>

2. **Clone the repo:**
   ```bash
   git clone https://github.com/dsarno/save-system-godot-claude.git
   cd save-system-godot-claude
   ```

3. **Open the project:**
   ```bash
   /Applications/Godot_mono.app/Contents/MacOS/Godot --editor --path .
   ```
   Or: launch Godot → Project Manager → Import → pick this folder's `project.godot`.

4. **Play:** press `F5` in the editor (or the Play button in the top-right toolbar).
   The main scene (`game/game_main.tscn`) runs by default.

5. **First-time note**: if you see broken shader errors on first import, close the project and reopen it — Godot sometimes needs a second pass to resolve `.gdshader` references.

No external dependencies, no package manager, no build step.

## Controls

| Key | Action |
|-----|--------|
| WASD | Move the player block (Block 1 — it has a pulsing glow) |
| Space | Jump (if grounded) |
| F5 | Quick-save to the last-used slot |
| F9 | Quick-load from the last-used slot |
| ESC | Open / close the save-slot menu (shows career stats at the bottom) |
| R | Respawn all blocks |

## Why the save system is "sophisticated"

Save systems are often a `var my_state = {}` + `JSON.stringify` + `FileAccess.open`, which breaks the moment you need more than one save, schema changes, or crash resilience. This one tries to do better without ballooning into something you'd be afraid to touch:

- **Decoupled library.** `save_system/` has zero dependencies on the game. Drop the folder into any Godot 4 project, register one autoload, done. No base classes to inherit; any node in group `saveable` that implements `save_data()` / `load_data()` participates.

- **Atomic writes, won't half-save.** Writes go to `<slot>.save.tmp`, then `rename()` into place, with a `.backup` rotation in between. A crash mid-save leaves you with either the old file or the new one — never a torn byte stream.

- **Encrypted on disk, readable after decrypt.** Save payload is JSON wrapped in `FileAccess.open_encrypted_with_pass`. Deters casual save-editing, but when debugging you can run a one-liner with the project password and get readable JSON back.

- **Separate metadata sidecar.** Each slot has a `.save` (encrypted) and a `.meta.tres` (plain Godot Resource). The slot picker reads sidecars — no decryption — so listing 100 slots with timestamps, play-time, and level names is cheap.

- **Schema versioning at two levels.** A top-level `schema_version` lets the library reject or migrate saves from the future. Individual saveables evolve independently by reading every field with `.get(key, default)` — add a new field tomorrow, old saves still load.

- **Collections through ownership, not magic.** Instead of a "saveable collection" concept with special cases, dynamic entities (like the spawned blocks) are owned by a saveable controller (Arena) that serializes them in its own `save_data`. The library stays unaware of collection semantics; the pattern scales to any kind of spawned entity.

- **Signals for every outcome.** `saved`, `loaded`, `load_started`, `save_failed`, `load_failed` — so HUDs, menus, or analytics can react without polling.

- **HMAC-SHA256 integrity signature** on every save. The JSON payload is hashed with a project-specific key and the signature is verified before any saveable sees the data. Catches tampering and corruption that slipped past encryption.

- **Two-phase load with per-saveable validation.** Saveables may implement `validate_data(dict) -> String` (empty string = OK, otherwise a failure reason). The library runs every saveable's validator *before* any `load_data` fires — a single rejection aborts the whole load, so a bad save can't leave the world in a partially-applied state. Example checks in the demo: `hp > max_hp`, NaN positions, `winner_index` out of range, negative counters.

- **41 unit tests across 7 suites** covering roundtrip, slot management, schema compatibility (forward & backward), encryption posture (wrong password → clean failure), signals, atomic writes, and HMAC/validation gates. Every change runs them.

### Demos of the extensibility story

- `Block.save_data` grew `jumps` and `walls_bumped` late in development; old saves still load with 0 defaults.
- `GameStats` is a completely separate saveable added as an autoload — career totals persist across games and slots without the library knowing it exists.
- `Arena.event_log` is an array-of-dicts (`{t, kind, block}`) that shows structured collection data round-tripping cleanly.

## What it's lacking (honest list)

- **The "encryption" is not real security.** The password is hardcoded in `save_config.gd`. A determined user can dump the binary and decrypt saves. It stops a player from opening the `.save` in a text editor and editing their HP to 9999 — nothing more. For real security you'd derive a key from the user's OS account or a server.

- **Still no migration code written.** `SaveSystem._migrate()` is a stub. The infrastructure (envelope-level `schema_version`, inner-payload `_migrate` function) is in place, but the first real migration transform (e.g. v2 → v3) hasn't been needed yet.

- **HMAC key lives next to the encryption key.** Both are constants in `save_config.gd`, so the integrity signature is only as strong as the binary's secrecy. A defender who can extract one secret gets the other. Still catches casual tampering, random corruption, and bit-flips — it doesn't resist an attacker who has reverse-engineered the game.

- **No thumbnails.** `SaveSlotMeta.thumbnail` is a field but the game never populates it. Slot pickers could show the last viewport frame; that plumbing isn't built.

- **No async / threaded saves.** Everything runs on the main thread. Fine for this demo (a few kilobytes), annoying for a hundred-MB open-world save.

- **No cloud / sync.** No Steam Cloud, no iCloud, no custom server. Saves live in `user://saves/` on the local machine.

- **Group-based discovery has a race.** If a node emits `add_to_group("saveable")` during a save's `_collect_saveables` iteration, behavior is undefined. In practice saveable membership is set up in `_ready` long before saves happen, so it hasn't bit us — but the guarantee isn't formal.

- **No "cloud of saves" UI.** The slot picker lists exactly N numbered slots. No "auto-save" rotation, no named saves, no folder view.

## What's in here

```
save_system/              drop-in library (GDScript, zero game dependencies)
  save_system.gd          autoload, whole public API (~220 lines)
  save_slot_meta.gd       Resource class for the .meta.tres sidecar
  save_config.gd          one-file knobs (password, paths, constants)
  atomic_write.gd         encrypted write helper with .tmp+rename + .backup
  README.md               drop-in instructions

game/                     the demo — scenes, scripts, Tron-ish visuals
  game_main.tscn + .gd    root scene, input routing
  arena.tscn + .gd        floor, walls, camera, spawns blocks, event log
  block.tscn + .gd        RigidBody3D with player + AI control
  hud.tscn + .gd          timer, per-block stat cards, victory panel
  slot_menu.tscn + .gd    ESC slot picker with career stats footer
  game_stats.gd           career-wide autoload (games, wins, totals)
  ui_theme.tres           synthwave theme
  tron_grid.gdshader      emissive grid floor shader
  floor_material.tres     shader material for the floor
  wall_material.tres      neon cyan material for arena rails
  slick.tres              low-friction PhysicsMaterial

tests/                    6 test suites, 34 tests for the save_system library
friction_log.md           running notes on godot-ai MCP pain points hit
```

## Credits

Built live with Claude Code + the [godot-ai](https://github.com/davidsarno/godot-ai) MCP plugin. Every scene, script, shader, and theme was created via MCP tool calls; see [friction_log.md](friction_log.md) for what worked and what didn't.
