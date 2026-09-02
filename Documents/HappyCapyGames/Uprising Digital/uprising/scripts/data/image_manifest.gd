extends Node

## Autoload. Loads assets/data/_image_manifest.csv, which maps
## (sheet, lang, box, name, link_col) -> a res:// path for one of the
## ~2,100 downloaded card/board images, plus whether that particular link
## was actually downloaded (6 "Arch Nemesis Events" rows are known-missing,
## out of V1 scope anyway).
##
## The CSV's "sheet" values do NOT always match a CardDatabase category name
## 1:1 (e.g. the sheet is "Heros" with no trailing space, while the CSV file
## on disk is named "Heros .csv" with one - that's a filename quirk, not a
## sheet-name quirk). Lookups here use the sheet name as it appears in the
## manifest.

const MANIFEST_PATH := "res://assets/data/_image_manifest.csv"

## key = "sheet|lang|name|link_col" (box is informational only, not part of
## the key, since a given sheet/lang/name/link_col combination is unique on
## its own in the source data).
var _lookup: Dictionary = {}
var rows: Array[Dictionary] = []


func _ready() -> void:
	reload()


func reload() -> void:
	_lookup.clear()
	rows.clear()
	var split: Dictionary = CsvParser.parse_file_split(MANIFEST_PATH)
	for row: PackedStringArray in split["rows"]:
		var sheet: String = CsvParser.field(row, 0)
		var lang: String = CsvParser.field(row, 2)
		var box: String = CsvParser.field(row, 3)
		var name: String = CsvParser.field(row, 4)
		var link_col: String = CsvParser.field(row, 5)
		var res_path: String = CsvParser.field(row, 7)
		var downloaded: bool = CsvParser.field(row, 8).strip_edges() == "True"

		var entry: Dictionary = {
			"sheet": sheet, "lang": lang, "box": box, "name": name,
			"link_col": link_col, "res_path": res_path, "downloaded": downloaded,
		}
		rows.append(entry)
		_lookup[_key(sheet, lang, name, link_col)] = entry


func _key(sheet: String, lang: String, name: String, link_col: String) -> String:
	return "%s|%s|%s|%s" % [sheet, lang, name, link_col]


## Returns the res:// path for an image, or "" if not found / not actually
## downloaded. link_col defaults to "Front" since most single-image cards use
## that column name; multi-image cards (e.g. some Quests) may need "Name",
## "Back", etc. - pass the exact link_col value seen in the manifest.
## Named get_image_path (not get_path) - Node already defines get_path().
func get_image_path(sheet: String, lang: String, name: String, link_col: String = "Front") -> String:
	var entry: Variant = _lookup.get(_key(sheet, lang, name, link_col))
	if entry == null:
		return ""
	if not entry["downloaded"]:
		return ""
	return entry["res_path"]


## Every downloaded=False row - the known asset-pull gaps.
func missing_downloads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in rows:
		if not r["downloaded"]:
			out.append(r)
	return out
