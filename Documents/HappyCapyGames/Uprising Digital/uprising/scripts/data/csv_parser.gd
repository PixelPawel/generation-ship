class_name CsvParser
extends RefCounted

## RFC4180-aware CSV parser. Godot's own CSV import treats every .csv as a
## localization table and breaks on embedded newlines inside quoted cells
## (both problems the game's data CSVs actually hit - see Heros/Hexes),
## so this parses the whole file as one character-by-character state
## machine instead of splitting by line first.

static func parse_file(path: String) -> Array[PackedStringArray]:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CsvParser: could not open %s (%s)" % [path, FileAccess.get_open_error()])
		return []
	var text: String = f.get_as_text()
	f.close()
	return parse_text(text)


static func parse_text(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var row: PackedStringArray = PackedStringArray()
	var field: String = ""
	var in_quotes: bool = false
	var i: int = 0
	var n: int = text.length()
	var row_has_content: bool = false

	while i < n:
		var c: String = text[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					field += "\""
					i += 2
				else:
					in_quotes = false
					i += 1
			else:
				field += c
				i += 1
			continue

		match c:
			"\"":
				in_quotes = true
				row_has_content = true
				i += 1
			",":
				row.append(field)
				field = ""
				row_has_content = true
				i += 1
			"\r":
				i += 1
			"\n":
				row.append(field)
				rows.append(row)
				row = PackedStringArray()
				field = ""
				row_has_content = false
				i += 1
			_:
				field += c
				row_has_content = true
				i += 1

	if row_has_content or field != "" or row.size() > 0:
		row.append(field)
		rows.append(row)

	return rows


## Convenience: parse a file and return the header row separately from the
## data rows, so callers with an unreliable/typo'd header (e.g. Quests.csv's
## first column is literally named "a", not "Lang") can still access columns
## positionally instead of by name.
static func parse_file_split(path: String) -> Dictionary:
	var rows: Array[PackedStringArray] = parse_file(path)
	if rows.is_empty():
		return {"header": PackedStringArray(), "rows": []}
	var header: PackedStringArray = rows[0]
	var data: Array[PackedStringArray] = rows.slice(1)
	return {"header": header, "rows": data}


## Safe positional field access - returns "" instead of erroring if a row is
## short a trailing empty column (CSV exporters sometimes drop a fully-empty
## trailing cell).
static func field(row: PackedStringArray, index: int) -> String:
	if index < 0 or index >= row.size():
		return ""
	return row[index]
