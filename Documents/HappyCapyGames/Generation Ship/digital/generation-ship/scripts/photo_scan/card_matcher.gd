class_name CardMatcher
extends RefCounted

const CardHashScript := preload("res://scripts/photo_scan/card_hash.gd")
const HASH_TABLE_PATH: String = "res://data/card_hashes.json"

var _table: Dictionary = {}

func _init() -> void:
	var file: FileAccess = FileAccess.open(HASH_TABLE_PATH, FileAccess.READ)
	if file == null:
		push_error("CardMatcher: could not open %s" % HASH_TABLE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_table = parsed

## Returns {"name": String, "distance": int} for the closest known card to
## the given image, or an empty Dictionary if the hash table failed to load.
## `distance` is out of 96 bits — the caller decides what counts as
## confident enough to accept without user confirmation.
##
## Tries the image both as given and rotated 180 degrees, keeping whichever
## matches better. A card's orientation (upright vs. upside-down) can't be
## recovered from its silhouette alone — CardDetector's moment-based angle
## finds the card's axis, not which end is "up" — so this is where that
## remaining ambiguity actually gets resolved, using the art content itself.
func match_card(card_image: Image) -> Dictionary:
	if _table.is_empty():
		return {}
	var flipped: Image = card_image.duplicate()
	flipped.flip_x()
	flipped.flip_y()
	var upright: Dictionary = _best_match(card_image)
	var upside_down: Dictionary = _best_match(flipped)
	return upright if upright["distance"] <= upside_down["distance"] else upside_down

func _best_match(card_image: Image) -> Dictionary:
	var query_hash: String = CardHashScript.compute_hash(card_image)
	var best_name: String = ""
	var best_distance: int = 999999
	for name: String in _table:
		var dist: int = CardHashScript.hamming_distance(_table[name], query_hash)
		if dist < best_distance:
			best_distance = dist
			best_name = name
	return {"name": best_name, "distance": best_distance}
