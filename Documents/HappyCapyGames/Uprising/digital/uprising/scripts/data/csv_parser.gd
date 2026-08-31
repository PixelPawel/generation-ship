class_name CsvParser
extends RefCounted
## RFC4180-ish CSV parser. Godot's FileAccess.get_csv_line() reads one physical
## line at a time, so it breaks on quoted fields that contain literal newlines
## (which every card-text CSV in this project has). This parses the whole
## file text as one state machine pass instead.


static func parse_file(path: String) -> Array[PackedStringArray]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CsvParser: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return []
	var text := file.get_as_text()
	file.close()
	return parse_text(text)


static func parse_text(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var field := ""
	var row: PackedStringArray = []
	var in_quotes := false
	var i := 0
	var length := text.length()

	while i < length:
		var ch := text[i]

		if in_quotes:
			if ch == "\"":
				if i + 1 < length and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					in_quotes = false
			else:
				field += ch
		else:
			if ch == "\"":
				in_quotes = true
			elif ch == ",":
				row.append(field)
				field = ""
			elif ch == "\r":
				pass
			elif ch == "\n":
				row.append(field)
				field = ""
				rows.append(row)
				row = []
			else:
				field += ch
		i += 1

	if field != "" or not row.is_empty():
		row.append(field)
		rows.append(row)

	return rows


## Parses a file into an Array of Dictionaries keyed by the header row.
static func parse_file_as_dicts(path: String) -> Array[Dictionary]:
	var rows := parse_file(path)
	return _rows_to_dicts(rows)


static func parse_text_as_dicts(text: String) -> Array[Dictionary]:
	var rows := parse_text(text)
	return _rows_to_dicts(rows)


static func _rows_to_dicts(rows: Array[PackedStringArray]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rows.is_empty():
		return result
	var headers := rows[0]
	for r in range(1, rows.size()):
		var row := rows[r]
		if row.size() == 1 and row[0].strip_edges() == "":
			continue
		var dict := {}
		for c in range(headers.size()):
			var key := headers[c]
			var value := row[c] if c < row.size() else ""
			dict[key] = value
		result.append(dict)
	return result
