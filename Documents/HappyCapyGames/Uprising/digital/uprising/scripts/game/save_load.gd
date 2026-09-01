class_name SaveLoad
extends RefCounted
## Thin file-I/O wrapper around GameState.to_dict()/from_dict() -- the same
## serialization already used for network transport doubles as the save
## format for free, per the original design intent in game_state.gd.

const SAVE_DIR := "user://saves/"


static func save_game(state: GameState, slot_name: String) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + slot_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state.to_dict()))
	file.close()
	return OK


static func load_game(slot_name: String) -> GameState:
	var path := SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return null
	return GameState.from_dict(parsed)


static func list_saves() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			result.append(name.trim_suffix(".json"))
		name = dir.get_next()
	dir.list_dir_end()
	return result


static func delete_save(slot_name: String) -> bool:
	var path := SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK
