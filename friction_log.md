# godot-ai MCP Friction Log

Running notes on pain points hit while building this project with the godot-ai MCP tools. Each entry is a concrete thing that felt worse than it should. Goal: drive tool improvements in the godot-ai repo.

Project: `save-system-godot-claude`
Plugin version at start: 0.4.3
Build started: 2026-04-17

---

## 2026-04-17 — `parent_path` convention: `/root/Foo` fails silently-ish

**Tried:** `node_create(type="MeshInstance3D", name="Mesh", parent_path="/root/Block")` right after `scene_create(root_name="Block")`.
**Happened:** `INVALID_PARAMS: Parent not found: /root/Block`. My mental model was "the scene is running under /root like SceneTree", so `/root/Block` felt right.
**Wanted:** either (a) accept `/root/<root>` as an alias for the edited scene root, or (b) make the error message name the actual path convention ("paths are relative to the edited scene root, use `/Block` or empty").
**Workaround:** omit `parent_path` (empty = scene root), or use `/<RootName>`.

## 2026-04-17 — `editor_screenshot` source="game" returns the editor viewport on macOS separate-window play

**Tried:** After `project_run`, took `editor_screenshot(source="game")` expecting the running game window.
**Happened:** Got the editor UI (viewport + dock panels), not the game window. Verified the game was actually playing via `play_state_changed -> playing` events. Happens on macOS with a standalone game window — the plugin can't reach into another OS window.
**Wanted:** source="game" to capture the actual game window (separate OS window on macOS) — or to clearly error/warn if the editor is in separate-window play mode, rather than silently returning editor imagery.
**Workaround:** Switch Godot's **Editor Settings → Run → Game Embed Mode** to **Embed Game** so the game runs in a SubViewport inside the editor. Then `source="game"` (or even `source="viewport"` on the Game workspace tab) can capture it. But this setting is buried — some users have it on "Use Per-Project Configuration" or "Make Game Workspace Floating" and won't discover the fix without prompting.

## 2026-04-17 — `logs_read` doesn't surface game-side `print()` output

**Tried:** Expected runtime `print("spawned %d blocks" % count)` to appear in `logs_read` output during a playing session.
**Happened:** `logs_read` only shows the MCP plugin's internal log (recv/send/events), not the Godot Output panel / stdout from the running game.
**Wanted:** a way to tail game-side stdout + stderr via MCP so runtime verification doesn't require human eyes on the Output dock. Especially important when screenshots of the game viewport also can't be captured (macOS separate-window play).
**Workaround:** trust lack-of-error as success, or add an on-screen Label that mirrors runtime state. For this project I relied on user-provided screenshots to catch runtime bugs (blocks-were-white, HP-label-clipped).

## 2026-04-17 — Edited-scene state drift between MCP calls

**Tried:** `scene_create("game_main.tscn")` → `node_create(...)` for several children → at some point the edited scene silently switched to `hud.tscn` or `slot_menu.tscn`, so `node_create(parent_path="/GameMain/UiLayer")` landed under `/Hud/UiLayer` instead. Later `script_attach(path="/GameMain", ...)` failed with "Node not found: /GameMain" even though I thought the GameMain scene was active.
**Happened:** `editor_state` returned `current_scene="res://game/slot_menu.tscn"` when I expected game_main. My mental model was "scene_create opens the new scene and subsequent node ops target it", but that wasn't reliably true — opening other scenes mid-session (including via instancing scenes as nodes) seems to switch the active edited scene without obvious signal.
**Wanted:** (a) make the edited-scene target explicit on every scene-mutating call (`node_create(scene_file="res://game/game_main.tscn", parent_path="...")`), OR (b) emit an error if the parent_path is unresolvable instead of silently routing to whatever scene happens to be edited.
**Workaround:** call `scene_open(path)` defensively before any batch of scene edits, and `editor_state` to verify.

## 2026-04-17 — `project_stop` and `editor_state.is_playing` can disagree

**Tried:** `project_stop` → got `{stopped: true}`. Immediately `editor_state` returned `is_playing: true`.
**Happened:** transient state where stop was accepted but the editor hadn't propagated it yet. Subsequent `scene_open` failed with "Editor is in play mode — stop the game first" until a ~2s wait.
**Wanted:** either block `project_stop` until state has actually transitioned, or provide a synchronous `wait_until_stopped` helper. The current behavior makes scripted sequences fragile.
**Workaround:** sleep + retry. Crude.

## 2026-04-17 — `@tool` test suites with inner classes extending Node3D can't load via `set_script` / `load.instantiate()` in the editor context

**Tried:** Wrote `test_arena_saveable.gd` (`@tool extends McpTestSuite`) that built an `Arena` instance two ways: (a) `Node3D.new(); set_script(load("res://game/arena.gd"))`, (b) `load("res://game/arena.tscn").instantiate()`. The test ran, but every `test_*` method reported "Test completed with 0 assertions" — setup() was throwing silently before any assert ran.
**Happened:** Silent failure. Likely because `arena.gd` has `class_name Arena`, typed arrays of `Array[Block]`, and physics-body children (RigidBody3D) that don't initialize cleanly in `@tool` scope during editor tests. Zero-assertion guardrail caught it; no stack trace surfaced.
**Wanted:** a way to run integration-style tests that use the real game scripts inside the test runner, OR at least a clearer error when set_script / scene instantiate fails in @tool scope. Right now the failure mode (silent zero-assertion) tells you *something* is wrong but nothing about *what*.
**Workaround:** deleted the integration test. Unit tests (the 6 suites in place) cover the save_system library thoroughly; runtime Arena roundtrip is verified manually by playing the game and hitting F5/F9.

