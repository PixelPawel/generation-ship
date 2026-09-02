class_name HexTextureLibrary
extends RefCounted

## Maps HexTileState role/card-name to the real card-art texture, from
## assets/images/Uprising+Final+EN/CORE_BOX_EN/HEXES_EN_TTS/
## {Capitals,Home,Regular,SeaTowers}/*.png. Each file is a single 1900x1900
## atlas: TOP half = face-down "unexplored" art, BOTTOM half = the actual
## explored card front - confirmed by reading the raw pixels directly
## (Regular/Bruthgaard.png, Regular/Rhun.png, Home/Moyhar.png all read and
## visually cross-checked against their real card names before trusting
## this), not assumed from a filename pattern alone.
##
## Filename -> real card name mapping (verified against 3 direct reads,
## not blindly trusted from filenames): most Regular/ filenames are a
## recognizable abbreviation of the real Core hex name (e.g. "Rhun.png" ->
## "Plains of Rhun", "Slavemines.png" -> "Imperial Slave Mines"). 6 of the
## 25 Regular/ files are OUT of V1 scope and deliberately not mapped here:
## "Maelstrom"/"NewWinterholm" are Titans-expansion Normal hexes (their
## CSV rows are Box=Titans, confirmed against the Hexes CSV, not V1
## Core), and "Abyssal"/"Depths"/"Graveyard"/"Omeido" are the 4 Core
## "Advanced" (Red-Skull) hexes - excluded from standard-difficulty V1
## play per the rulebook's own Setup step 4, and also the exact filenames
## the OLD project flagged as actively misleading (e.g. "Abyssal.png" is
## really "Haunted Hollows") - since they're out of scope, that mismatch
## doesn't need resolving here, just noting why they're absent.
##
## Similarly, only 5 of Home/'s 10 files and 5 of SeaTowers/'s 7 files are
## Core-box factions/hexes; the rest are Arch-Nemesis/Titans-expansion
## content, out of V1 scope. Capitals/ has 3 "Advanced Capitals" variants
## beyond the 1 Core Capital.png, also out of scope.

const DIR := "res://assets/images/Uprising+Final+EN/CORE_BOX_EN/HEXES_EN_TTS/"

const CAPITAL_PATH := DIR + "Capitals/Capital.png"

## Faction name -> Home hex art. Folder spells the 3rd faction "Moyhar" -
## same mismatch vs. the CSV's "Mohyar" that ModelManifest already has an
## alias table for; reused here rather than adding a second alias table.
const HOME: Dictionary = {
	"Druwhn": DIR + "Home/Druwhn.png",
	"Duerkhar": DIR + "Home/Duerkhar.png",
	"Krowh": DIR + "Home/Krowh.png",
	"Mohyar": DIR + "Home/Moyhar.png",
}

## Core Hex card_name (from CardDatabase/HexCard) -> Regular/ art.
const REGULAR: Dictionary = {
	"Bruthgaard": DIR + "Regular/Bruthgaard.png",
	"Golgardei": DIR + "Regular/Golgardei.png",
	"Plains of Rhun": DIR + "Regular/Rhun.png",
	"Frosthold Pass": DIR + "Regular/Frosthold.png",
	"Imperial Slave Mines": DIR + "Regular/Slavemines.png",
	"Tomb of the Elder Kings": DIR + "Regular/tomboftheelder.png",
	"Black Ice": DIR + "Regular/Blackice.png",
	"Grim Fangs": DIR + "Regular/Grimfangs.png",
	"Raufrost": DIR + "Regular/Raufrost.png",
	"Shadowdawn": DIR + "Regular/Shadowdawn.png",
	"Taurel Caravan Passage": DIR + "Regular/Taurel.png",
	"Torment": DIR + "Regular/Torment.png",
	"Fyrnhalla": DIR + "Regular/Fyrnhalla.png",
	"Kyushis Tavern": DIR + "Regular/Tavern.png",
	"Rigga": DIR + "Regular/Rigga.png",
	"Dunkelholm": DIR + "Regular/Dunkelholm.png",
	"Fjoelja Stone Circle": DIR + "Regular/Fjoelja.png",
	"Trollward": DIR + "Regular/Trollward.png",
	"Netherwood": DIR + "Regular/Netherwood.png",
}

## Core Sea Tower card_name -> SeaTowers/ art.
const SEA_TOWER: Dictionary = {
	"Dawngaard": DIR + "SeaTowers/Dawngaard.png",
	"Guragi Tower": DIR + "SeaTowers/Guragi.png",
	"Hellhound Tower": DIR + "SeaTowers/Hellhound.png",
	"Zeegard": DIR + "SeaTowers/Zeegaard.png",
	"Midnight Tower": DIR + "SeaTowers/Midnight.png",
}


## Resolves the texture path from plain parameters (not a HexTileState) so
## both Milestone 1's BoardLayout-driven scene and Milestone 5's
## GameState/HexTileState-driven scene can share this lookup without one
## needing to fake the other's data shape. Returns "" if nothing is
## mapped (e.g. an out-of-scope card name, or an "outer" role tile with
## no specific art - callers should fall back to a flat color then).
static func get_texture_path(role: String, card_name: String, faction: String) -> String:
	match role:
		"capital":
			return CAPITAL_PATH
		"home":
			return str(HOME.get(faction, ""))
		"sea_tower":
			return str(SEA_TOWER.get(card_name, ""))
		"interior":
			return str(REGULAR.get(card_name, ""))
	return ""


## Determines the DEFAULT explored/unexplored atlas-half a role starts on
## when its card_name (or faction) isn't resolvable to art yet - Capital
## and Home hexes are always face-up per GameSetup, Sea Tower and interior
## hexes start face-down until Explored.
static func default_explored(role: String) -> bool:
	return role == "capital" or role == "home"


## StandardMaterial3D.albedo_texture ignores AtlasTexture.region entirely
## on 3D surfaces (that crop is 2D-canvas-only) - uv1_offset/uv1_scale is
## the fix that actually works in 3D, verified by rendering both atlas
## halves and checking which one is upright/readable (tools/hex_texture_probe.gd),
## not assumed. EXPLORED_V_OFFSET is the y offset that selects the bottom
## (explored/front) half; the top (unexplored/back) half is offset 0.
const EXPLORED_V_OFFSET := 0.5

## Applies the correct card-art material to a hex MeshInstance3D, or a
## flat placeholder color if no art is mapped (out-of-scope card, or a
## bare "outer" role tile with no card at all). `tint` multiplies the
## texture's albedo (Godot's normal albedo_color-as-tint behavior) - lets
## callers overlay a curse/selection tint on top of REAL art rather than
## only being able to tint the flat-color fallback.
static func apply_material(mesh_instance: MeshInstance3D, role: String, card_name: String, faction: String, explored_flag: bool, fallback_color: Color, tint: Color = Color.WHITE) -> void:
	var path: String = get_texture_path(role, card_name, faction)
	var explored: bool = explored_flag or default_explored(role)
	if path.is_empty():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = fallback_color * tint
		mesh_instance.material_override = mat
		return
	var tex: Texture2D = load(path)
	if tex == null:
		var mat_fallback := StandardMaterial3D.new()
		mat_fallback.albedo_color = fallback_color * tint
		mesh_instance.material_override = mat_fallback
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.uv1_scale = Vector3(1, 0.5, 1)
	mat.uv1_offset = Vector3(0, EXPLORED_V_OFFSET if explored else 0.0, 0)
	mesh_instance.material_override = mat
