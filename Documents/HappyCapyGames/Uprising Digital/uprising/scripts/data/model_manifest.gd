extends Node

## Autoload. Loads assets/data/_model_manifest.csv: one row per already-
## extracted 3D unit, mapping its folder to the primary .obj to instance.

const MANIFEST_PATH := "res://assets/data/_model_manifest.csv"

## Known spelling mismatch between the CSV/playerboard faction name and the
## folder the .unity3d extraction actually produced. Add more here if other
## mismatches turn up rather than fuzzy-matching folder names.
const FACTION_FOLDER_ALIASES := {
	"Mohyar": "Moyhar",
}

## folder (res:// path, e.g. "res://assets/models/Chaos/lichqueen") -> primary_obj path.
var folder_to_obj: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	folder_to_obj.clear()
	var split: Dictionary = CsvParser.parse_file_split(MANIFEST_PATH)
	for row: PackedStringArray in split["rows"]:
		var folder: String = CsvParser.field(row, 0)
		var primary_obj: String = CsvParser.field(row, 1)
		if folder.is_empty():
			continue
		folder_to_obj[folder] = primary_obj


## Resolves a CSV/rulebook faction name to the folder name actually used
## under assets/models/, applying the known alias table.
func resolve_faction_folder(faction_name: String) -> String:
	return FACTION_FOLDER_ALIASES.get(faction_name, faction_name)


## Best-effort: find a folder under assets/models/<faction>/ whose name
## normalizes (lowercase, spaces/underscores/hyphens stripped) to match
## unit_name, and return its primary .obj path, or "" if none found.
func find_model_path(faction_name: String, unit_name: String) -> String:
	var faction_folder: String = resolve_faction_folder(faction_name)
	var target: String = _normalize(unit_name)
	for folder: String in folder_to_obj.keys():
		if not folder.begins_with("res://assets/models/%s/" % faction_folder):
			continue
		var last_segment: String = folder.get_file()
		if _normalize(last_segment) == target:
			return folder_to_obj[folder]
	return ""


func _normalize(s: String) -> String:
	return s.to_lower().replace(" ", "").replace("_", "").replace("-", "").replace("'", "")
