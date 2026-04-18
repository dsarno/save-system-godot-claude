@tool
class_name FakeSaveable
extends Node

## Shared test fake: a Node implementing the saveable contract with enough
## instrumentation for assertions. Used by every save_system_* test suite.
## Not intended as a production pattern — real saveables mix the contract
## with their own logic.

var save_id: String = "fake"
var captured: Dictionary = {}
var loaded: Dictionary = {}
var load_count: int = 0


func save_data() -> Dictionary:
	return captured.duplicate(true)


func load_data(d: Dictionary) -> void:
	loaded = d
	load_count += 1
