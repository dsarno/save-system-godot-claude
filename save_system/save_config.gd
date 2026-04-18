## Central configuration for the save system.
##
## All knobs live here so the rest of the library has no magic numbers.
## When dropping this folder into another project, change ENCRYPTION_PASSWORD
## and optionally SAVES_DIR / SCHEMA_VERSION.
class_name SaveConfig
extends RefCounted

const SCHEMA_VERSION := 2
const GAME_VERSION := "0.1.0"

const SAVES_DIR := "user://saves"
const SAVE_EXTENSION := ".save"
const META_EXTENSION := ".meta.tres"

## Hardcoded password for FileAccess.open_encrypted_with_pass.
## NOT real security — deters casual save-editing. Change per-project.
const ENCRYPTION_PASSWORD := "save-system-godot-claude-v1-KG9z2p"

## HMAC key for the integrity signature computed over the JSON payload.
## Separate from ENCRYPTION_PASSWORD so a compromise of one doesn't hand
## over the other. Still shipped in the binary — not crypto-grade secrecy,
## but catches tampering by anyone who doesn't extract both secrets.
const HMAC_KEY := "save-system-godot-claude-hmac-v1-qw7P"

const SAVEABLE_GROUP := "saveable"
