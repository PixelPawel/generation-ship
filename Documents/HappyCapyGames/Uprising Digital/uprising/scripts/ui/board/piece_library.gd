extends RefCounted

## Builds board pieces from the extracted TTS models at the real game's
## relative scale. Use via preload (no class_name):
##   const PieceLibrary := preload("res://scripts/ui/board/piece_library.gd")
##
## Scale: every piece = TTS object scale x TTS_TO_WORLD x PIECE_SCALE. The
## TTS scales were read from the mod save (Documents/My Games/Tabletop
## Simulator/Mods/Workshop/2092091239.json): hex tiles 1.8, Heroes /
## Legions / Hordes / Skeletons 0.6, basic Units 0.425, elite Units 0.55
## (Trolls, Koloth 0.6), Curses 0.55, Garrisons 0.8, Havens 0.7, Walls
## 0.725, Towers 0.75. hex.obj is already world size (circumradius 2.0),
## so TTS_TO_WORLD = 1 / 1.8 keeps every piece in proportion to the tiles.
##
## Orientation: the standee OBJs ship Z-up (base at z = 0, card rising
## along +Z, printed front at y = -0.1; checked by rendering them in
## Blender), so they need -90 degrees about X to stand on the board with
## the art facing +Z. Garrisons, Havens, Walls and Towers ship Y-up.

const TTS_TO_WORLD: float = 1.0 / 1.8
const PIECE_SCALE: float = 1.12   # a touch over physical size so pieces read on screen
const STANDEE_ROTATION := Vector3(-90.0, 0.0, 0.0)

const TTS_HERO: float = 0.6
const TTS_NEMESIS: float = 0.6
const TTS_SKELETON: float = 0.6
const TTS_CURSE: float = 0.55
const TTS_BASIC: float = 0.425
const TTS_ELITE: float = 0.55
const TTS_BIG_ELITE: float = 0.6
const TTS_GARRISON: float = 0.8
const TTS_HAVEN: float = 0.7
const TTS_WALL: float = 0.725
const TTS_TOWER: float = 0.75

const MODELS := "res://assets/models/"
const GARRISON_PARTS: Array[String] = [
	MODELS + "Empire/garrison_bottom/Garrison_Bottom.obj",
	MODELS + "Empire/garrison_middle/Garrison_Middle.obj",
	MODELS + "Empire/garrison_top/Garrison_Top.obj",
]
const CURSE_MODEL := MODELS + "Chaos/curse/Curse1.obj"
const SKELETON_MODEL := MODELS + "Chaos/skeletons/Skeletons.obj"
const WALL_MODEL := MODELS + "walls/Haven_Walls.obj"
const TOWER_MODEL := MODELS + "tower/Haven_Tower.obj"

const HAVEN_MODELS: Dictionary = {
	"Druwhn": MODELS + "Druwhn/haven_bone/Haven_Bottom_Bone.obj",
	"Duerkhar": MODELS + "Duerkhar/haven_blue/Haven_Bottom_Blue.obj",
	"Krowh": MODELS + "Krowh/haven_red/Haven_Bottom_Red.obj",
	"Mohyar": MODELS + "Moyhar/haven_yellow/Haven_Bottom_Yellow.obj",
}

## Core factions' Unit standees by PlayerboardTable unit name. Explicit
## because the folder names don't follow the unit names (Vargs -> wargs,
## Sellswords -> sellsword, Trolls -> troll ...).
const UNIT_MODELS: Dictionary = {
	"Druwhn": {
		"Swordsisters": MODELS + "Druwhn/swordsisters/Swordsisters.obj",
		"Sons of the Bow": MODELS + "Druwhn/sonsofthebow/Sons_of_the_Bow.obj",
		"Beastmasters": MODELS + "Druwhn/beastmasters/Beastmasters.obj",
		"Rangers": MODELS + "Druwhn/rangers/Rangers.obj",
	},
	"Duerkhar": {
		"Younglings": MODELS + "Duerkhar/younglings/Younglings.obj",
		"Spearsingers": MODELS + "Duerkhar/spearsingers/Spearsingers.obj",
		"Oathsworn": MODELS + "Duerkhar/oathsworn/Oathsworn.obj",
		"Koloth": MODELS + "Duerkhar/koloth/Koloth.obj",
	},
	"Krowh": {
		"Tribesmen": MODELS + "Krowh/tribesmen/Tribesmen.obj",
		"Deadeyes": MODELS + "Krowh/deadeyes/Deadeyes.obj",
		"Vargs": MODELS + "Krowh/wargs/Wargs.obj",
		"Trolls": MODELS + "Krowh/troll/Trolls.obj",
	},
	"Mohyar": {
		"Sellswords": MODELS + "Moyhar/sellsword/Sellswords.obj",
		"Hunters": MODELS + "Moyhar/hunter/Hunters.obj",
		"Berserkers": MODELS + "Moyhar/berserker/Berserkers.obj",
		"Slavers": MODELS + "Moyhar/slaver/Slavers.obj",
	},
}
const BIG_ELITES: Array[String] = ["Trolls", "Koloth"]

## Where Walls and a Tower seat on a Haven, in the Haven model's own units
## (measured from the OBJ profile): the palisade ring sits on the camp's
## lower platform around the tents, the Tower on top of the tents.
const HAVEN_RAW_HEIGHT: float = 1.178
const HAVEN_WALL_SEAT: float = 0.385
const HAVEN_TOWER_SEAT: float = 1.1

static var _meshes: Dictionary = {}       # path -> Mesh (or null when missing)
static var _finish: Dictionary = {}       # "path#surface" -> Material
static var _folder_to_obj: Dictionary = {}  # from ModelManifest, for Heroes / Legions / Hordes
static var _resolved: Dictionary = {}     # cache of name lookups


## Hand over ModelManifest's folder -> primary .obj table (call once with
## the autoload node; it is optional - the explicit tables above work
## without it).
static func setup(model_manifest: Node) -> void:
	if model_manifest == null:
		return
	var table: Variant = model_manifest.get("folder_to_obj")
	if table is Dictionary:
		_folder_to_obj = table


static func mesh(path: String) -> Mesh:
	if path.is_empty():
		return null
	if _meshes.has(path):
		return _meshes[path]
	var m: Mesh = null
	if ResourceLoader.exists(path):
		m = load(path) as Mesh
	_meshes[path] = m
	return m


# --------------------------------------------------------------- resolving

static func unit_model(faction: String, unit_name: String) -> String:
	var table: Dictionary = UNIT_MODELS.get(faction, {})
	if table.has(unit_name):
		return str(table[unit_name])
	return _find_in_folder(_faction_folder(faction), unit_name)


static func unit_tts_scale(faction: String, unit_name: String) -> float:
	if BIG_ELITES.has(unit_name):
		return TTS_BIG_ELITE
	var entry: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, unit_name)
	if entry != null and not entry.is_basic():
		return TTS_ELITE
	return TTS_BASIC


static func hero_model(faction: String, hero_name: String) -> String:
	return _find_in_folder(_faction_folder(faction), hero_name)


static func legion_model(card_name: String) -> String:
	return _find_in_folder("Empire", card_name)


static func horde_model(card_name: String) -> String:
	return _find_in_folder("Chaos", card_name)


static func haven_model(faction: String) -> String:
	return str(HAVEN_MODELS.get(faction, HAVEN_MODELS["Druwhn"]))


static func _faction_folder(faction: String) -> String:
	return "Moyhar" if faction == "Mohyar" else faction


## Folder under assets/models/<group>/ whose name matches `wanted` once
## both are normalised (case, spaces, apostrophes, a leading "The ", a
## "titans_" folder prefix and a plural "s" are ignored).
static func _find_in_folder(group: String, wanted: String) -> String:
	var key: String = group + "|" + wanted
	if _resolved.has(key):
		return _resolved[key]
	var target: String = _norm(wanted)
	var found: String = ""
	var prefix: String = MODELS + group + "/"
	for folder: Variant in _folder_to_obj.keys():
		var f: String = str(folder)
		if not f.begins_with(prefix):
			continue
		var leaf: String = _norm(f.get_file().trim_prefix("titans_"))
		if leaf == target or leaf + "s" == target or leaf == target + "s":
			found = str(_folder_to_obj[folder])
			break
	_resolved[key] = found
	return found


static func _norm(s: String) -> String:
	var t: String = s.to_lower().strip_edges()
	if t.begins_with("the "):
		t = t.substr(4)
	for ch: String in [" ", "_", "-", "'", "’"]:
		t = t.replace(ch, "")
	return t


# --------------------------------------------------------------- building

## A standee standing on the local origin, art facing local +Z. Returns a
## plain Node3D holder (yaw it freely); `meta "height"` / `"width"` hold
## its world size. Falls back to a coloured peg if the model is missing.
static func make_standee(path: String, tts_scale: float, fallback: Color = Color(0.7, 0.7, 0.7)) -> Node3D:
	var holder := Node3D.new()
	var m: Mesh = mesh(path)
	var s: float = tts_scale * TTS_TO_WORLD * PIECE_SCALE
	if m == null:
		var peg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.26
		cyl.height = 0.9
		peg.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = fallback
		peg.material_override = mat
		peg.position.y = 0.45
		holder.add_child(peg)
		holder.set_meta("height", 0.9)
		holder.set_meta("width", 0.5)
		return holder
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.rotation_degrees = STANDEE_ROTATION
	inst.scale = Vector3(s, s, s)
	var aabb: AABB = m.get_aabb()
	# centre the card over the origin (some art is off-centre on its base)
	inst.position.x = -(aabb.position.x + aabb.size.x * 0.5) * s
	_apply_finish(inst, m, path)
	holder.add_child(inst)
	holder.set_meta("height", aabb.size.z * s)
	holder.set_meta("width", aabb.size.x * s)
	return holder


## Pieces that physically stack (the Garrison's three tiers): each sits
## on the previous one's measured height.
static func make_stack(parts: Array) -> Node3D:
	var holder := Node3D.new()
	var y: float = 0.0
	var width: float = 0.0
	for part: Variant in parts:
		var inst: MeshInstance3D = _part(str(part[0]), float(part[1]), y)
		if inst == null:
			continue
		holder.add_child(inst)
		y += float(inst.get_meta("height"))
		width = maxf(width, float(inst.get_meta("width")))
	holder.set_meta("height", y)
	holder.set_meta("width", width)
	return holder


## One Y-up model, centred on the origin, its base at height `y`.
static func _part(path: String, tts_scale: float, y: float) -> MeshInstance3D:
	var m: Mesh = mesh(path)
	if m == null:
		return null
	var s: float = tts_scale * TTS_TO_WORLD * PIECE_SCALE
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.scale = Vector3(s, s, s)
	var aabb: AABB = m.get_aabb()
	inst.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * s, y - aabb.position.y * s, -(aabb.position.z + aabb.size.z * 0.5) * s)
	_apply_finish(inst, m, path)
	inst.set_meta("height", aabb.size.y * s)
	inst.set_meta("width", aabb.size.x * s)
	return inst


static func make_garrison(level: int) -> Node3D:
	var parts: Array = []
	for i: int in range(clampi(level, 0, 3)):
		parts.append([GARRISON_PARTS[i], TTS_GARRISON])
	return make_stack(parts)


static func make_haven(faction: String, wall: bool, tower: bool) -> Node3D:
	var holder := Node3D.new()
	var hs: float = TTS_HAVEN * TTS_TO_WORLD * PIECE_SCALE
	var height: float = HAVEN_RAW_HEIGHT * hs
	var width: float = 0.9
	var camp: MeshInstance3D = _part(haven_model(faction), TTS_HAVEN, 0.0)
	if camp != null:
		holder.add_child(camp)
		width = float(camp.get_meta("width"))
	if wall:
		var ring: MeshInstance3D = _part(WALL_MODEL, TTS_WALL, HAVEN_WALL_SEAT * hs)
		if ring != null:
			holder.add_child(ring)
	if tower:
		var tw: MeshInstance3D = _part(TOWER_MODEL, TTS_TOWER, HAVEN_TOWER_SEAT * hs)
		if tw != null:
			holder.add_child(tw)
			height = HAVEN_TOWER_SEAT * hs + float(tw.get_meta("height"))
	holder.set_meta("height", height)
	holder.set_meta("width", width)
	return holder


## Imported MTL materials are fully matte. Printed card faces get a satin
## finish, flat plastic a glossier one, the Garrison's gold trim a metal.
static func _apply_finish(inst: MeshInstance3D, m: Mesh, path: String) -> void:
	for i: int in range(m.get_surface_count()):
		var key: String = "%s#%d" % [path, i]
		var mat: Material = _finish.get(key)
		if mat == null:
			var src: Material = m.surface_get_material(i)
			if src is StandardMaterial3D:
				var sm: StandardMaterial3D = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				var textured: bool = sm.albedo_texture != null
				sm.roughness = 0.62 if textured else 0.42
				sm.metallic_specular = 0.45
				sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if src.resource_name.findn("gold") != -1:
					sm.metallic = 0.75
					sm.roughness = 0.32
				mat = sm
			else:
				mat = src
			_finish[key] = mat
		if mat != null:
			inst.set_surface_override_material(i, mat)
