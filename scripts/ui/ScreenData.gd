# Autoloaded singleton — intentionally no class_name to avoid autoload name conflict
extends Node

## ScreenData.gd
## One-shot payload scratchpad for passing data between scenes.
##
## Usage pattern:
##   1. Writer calls set_payload(data) immediately before changing scenes.
##   2. The incoming scene calls consume() in _ready() to retrieve and clear
##      the payload in a single atomic step.
##
## consume() always clears the stored payload, so stale data never bleeds into
## a second navigation. If no payload was set, consume() returns an empty Dict.

var _payload: Dictionary = {}


## Store a payload for the next scene to consume.
## Duplicated to prevent the caller from mutating it after storing.
func set_payload(data: Dictionary) -> void:
	_payload = data.duplicate(true)


## Retrieve and clear the stored payload.
## Returns a duplicate of the stored data and immediately clears the store.
## Guaranteed to return an empty Dictionary when nothing was set.
func consume() -> Dictionary:
	var result := _payload.duplicate(true)
	_payload = {}
	return result


## Returns true when a payload is currently waiting to be consumed.
## Useful for defensive checks in _ready() if a scene can be entered
## both with and without data.
func has_payload() -> bool:
	return not _payload.is_empty()
