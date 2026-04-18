# Save System

Drop-in save system for Godot 4. One folder, one autoload, zero dependencies on any game code.

## Install in another project

1. Copy the entire `save_system/` folder into your project.
2. Project Settings → Autoload → add `res://save_system/save_system.gd` with name `SaveSystem`.
3. Edit `save_system/save_config.gd` and change `ENCRYPTION_PASSWORD` to a project-specific value.

That's it. The `SaveSystem` singleton is now globally available.

## Making something saveable

1. Add the node to group `saveable` (in the editor's Node panel → Groups, or via `add_to_group("saveable")`).
2. Implement two methods:

```gdscript
func save_data() -> Dictionary:
    return {"hp": hp, "position": {"x": position.x, "y": position.y, "z": position.z}}

func load_data(d: Dictionary) -> void:
    hp = d.get("hp", 100)
    var p = d.get("position", {"x": 0, "y": 0, "z": 0})
    position = Vector3(p.x, p.y, p.z)
```

Always use `d.get(key, default)` — when you add a new field later, old saves still load with the default.

## Save & load

```gdscript
SaveSystem.save_to_slot(1, "level_name", play_time_seconds)
SaveSystem.load_from_slot(1)
SaveSystem.quick_save()              # last-used slot
SaveSystem.quick_load()
SaveSystem.list_slots()              # Array[SaveSlotMeta]
SaveSystem.has_slot(1)
SaveSystem.delete_slot(1)
```

## Signals

```gdscript
SaveSystem.saved.connect(func(slot_id): ...)
SaveSystem.loaded.connect(func(slot_id): ...)
SaveSystem.save_failed.connect(func(slot_id, reason): ...)
SaveSystem.load_failed.connect(func(slot_id, reason): ...)
```

## Dynamic collections

If you have a controller that spawns children (enemies, items, projectiles), make the *controller* saveable, not each child. The controller's `save_data` serializes the full list including the child scene paths + per-child state; `load_data` clears existing children, re-instantiates from the saved list, and calls `load_data` on each new child. This keeps the library free of collection-management special cases.

```gdscript
# spawner.gd — in group "saveable", save_id="spawner"
func save_data() -> Dictionary:
    var children_data := []
    for child in $Spawned.get_children():
        children_data.append({
            "scene": child.scene_file_path,
            "state": child.save_data(),
        })
    return {"children": children_data}

func load_data(d: Dictionary) -> void:
    for child in $Spawned.get_children():
        child.queue_free()
    for entry in d.get("children", []):
        var packed: PackedScene = load(entry.scene)
        var child = packed.instantiate()
        $Spawned.add_child(child)
        child.load_data(entry.state)
```

## File layout on disk

```
user://saves/
  slot_1.save          # encrypted binary (JSON inside)
  slot_1.meta.tres     # unencrypted Resource sidecar (fast to read for slot pickers)
  slot_2.save
  slot_2.meta.tres
```

Atomic writes use `<path>.tmp` + rename with a `.backup` rotation, so a mid-write crash leaves a recoverable file.

## Security caveat

`ENCRYPTION_PASSWORD` is hardcoded. Determined users can extract it from the compiled binary and edit saves. This is deterrent, not cryptographic security. For real security you'd need a per-user derived key (outside this library's scope).

## Schema evolution

- The save dict has a `schema_version` field. Bump `SaveConfig.SCHEMA_VERSION` when the *library-level* schema changes and add migrations in `SaveSystem._migrate`.
- Individual saveables evolve their own format by always reading fields with `.get(key, default)`. Add new fields freely — old saves load with defaults.
