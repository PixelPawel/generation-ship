class_name SaveLoad
extends RefCounted

## Trivial by design: the same to_dict()/from_dict() round trip used for
## network sync doubles as the save-file format.

const SAVE_DIR := "user://saves/"


static func save_game(state: GameState, slot_name: String) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f: FileAccess = FileAccess.open(SAVE_DIR + slot_name + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(state.to_dict()))
	f.close()
	return OK


static func load_game(slot_name: String) -> GameState:
	var path: String = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return null
	return GameState.from_dict(parsed)


static func list_saves() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			out.append(name.get_basename())
		name = dir.get_next()
	dir.list_dir_end()
	return out
