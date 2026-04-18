## Central configuration for the save system.
##
## All knobs live here so the rest of the library has no magic numbers.
## When dropping this folder into another project, change ENCRYPTION_PASSWORD
## and optionally SAVES_DIR / SCHEMA_VERSION.
class_name SaveConfig
extends RefCounted

const SCHEMA_VERSION := 1
const GAME_VERSION := "0.1.0"

const SAVES_DIR := "user://saves"
const SAVE_EXTENSION := ".save"
const META_EXTENSION := ".meta.tres"

## Hardcoded password for FileAccess.open_encrypted_with_pass.
## NOT real security — deters casual save-editing. Change per-project.
const ENCRYPTION_PASSWORD := "save-system-godot-claude-v1-KG9z2p"

const SAVEABLE_GROUP := "saveable"
