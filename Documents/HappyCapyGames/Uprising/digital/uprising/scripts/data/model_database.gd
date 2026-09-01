class_name ModelDatabase
extends RefCounted
## Looks up the extracted 3D standee model (tools/extract_unity3d.py output,
## see assets/data/_model_manifest.csv) for a named entity by normalized
## name match against the model's folder name (e.g. "fhayanor" for
## res://assets/models/Druwhn/fhayanor/Fhayanor.obj). Built for Heroes
## first, but the manifest covers Legions/Hordes/Units/Garrisons the same
## way, so this same lookup works for those later.

const MANIFEST_PATH := "res://assets/data/_model_manifest.csv"

static var _cache: Dictionary = {}  # normalized name -> res:// .obj path
static var _loaded: bool = false


## Returns the res:// path to the entity's primary .obj, or "" if no model
## folder's name normalizes to match `entity_name` (e.g. an entity that
## simply has no extracted standee).
static func find_model_path(entity_name: String) -> String:
	_ensure_loaded()
	return _cache.get(_normalize(entity_name), "")


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for row in CsvParser.parse_file_as_dicts(MANIFEST_PATH):
		var folder: String = row.get("folder", "")
		var obj_path: String = row.get("primary_obj", "")
		if folder == "" or obj_path == "":
			continue
		_cache[_normalize(folder.get_file())] = obj_path


## Lowercases and strips everything but letters/digits, so e.g. "Kha'al"
## (CardDatabase) matches the "khaal" model folder name (apostrophes and
## casing don't survive into a folder name).
static func _normalize(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]")
	return regex.sub(name.to_lower(), "", true)
