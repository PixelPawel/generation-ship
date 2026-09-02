@tool
extends Node3D

## Milestone 1: builds a real, editable 2-player/Normal-difficulty board
## from GameSetup.build_2p_normal_layout(), as genuine scene nodes rather
## than a runtime-only procedural scene.
##
## Runs in BOTH the editor (@tool + Engine.is_editor_hint()) and at play
## time, guarded so re-opening the scene doesn't duplicate content. Every
## node this builds gets `.owner` set explicitly - add_child() alone makes
## a node visible in the 3D viewport but NOT selectable/draggable in the
## Scene dock or via click-to-select; only nodes with `.owner` set to the
## edited scene root are treated as real, saveable scene content. Once the
## user saves the scene from the editor after this runs, these become
## permanent nodes in the .tscn and this script's own guard (below) means
## further edits won't be clobbered by a rebuild.

const HEX_MESH_PATH := "res://assets/images/3d/hex.obj"
const GARRISON_BOTTOM := "res://assets/models/Empire/garrison_bottom/Garrison_Bottom.obj"
const GARRISON_MIDDLE := "res://assets/models/Empire/garrison_middle/Garrison_Middle.obj"
const GARRISON_TOP := "res://assets/models/Empire/garrison_top/Garrison_Top.obj"
const CURSE_MODEL := "res://assets/models/Chaos/curse/Curse1.obj"
const SKELETON_MODEL := "res://assets/models/Chaos/skeletons/Skeletons.obj"

## Verified in two passes with tools/rotation_probe.gd. The first pass used
## a downward-tilted camera and wrongly concluded (0,0,0) was correct - a
## flat-lying card viewed from a shallow angle still looks plausible. The
## Hanzo mesh's own AABB at identity rotation ([P (-2.6,-0.95,0.0) S (5.70,
## 1.90,6.76)]) makes this unambiguous: Y (the "up" extent) is only 1.90 -
## the same flat plastic-clip thickness noted in the old project's own
## standee gotcha - while X/Z are 5.70/6.76, so identity rotation IS lying
## flat. A second pass with a strictly level (pitch 0) camera showed (0,0,0)
## and (180,0,0) as thin edge-on slivers (confirming flat), (90,0,0)
## standing upright with the nameplate correctly right-side up, and
## (-90,0,0) upside down. (90,0,0) is therefore correct - and differs from
## BOTH the old project's own -90 X fix AND this file's own first-pass
## guess, so don't trust either without a level-camera render like this.
const STANDEE_UPRIGHT_ROTATION := Vector3(90, 0, 0)

const ROLE_COLORS := {
	"capital": Color(0.85, 0.7, 0.2),
	"home": Color(0.3, 0.55, 0.85),
	"sea_tower": Color(0.2, 0.65, 0.75),
	"interior": Color(0.35, 0.35, 0.38),
}


func _ready() -> void:
	if has_node("Hexes"):
		return  # already built (and possibly hand-edited since) - don't rebuild.
	if not Engine.is_editor_hint() and not _autoloads_ready():
		# At runtime (not in-editor), autoloads may not be in the tree yet
		# on the very first frame - defer one frame rather than fail silently.
		call_deferred("_ready")
		return
	_build()


func _autoloads_ready() -> bool:
	return get_node_or_null("/root/CardDatabase") != null


func _build() -> void:
	var card_db: Node = get_node("/root/CardDatabase")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1  # deterministic for this milestone's first pass - remove once this is a real game setup entry point.
	var layout: BoardLayout = GameSetup.build_2p_normal_layout(card_db, rng)

	var hex_mesh: Mesh = load(HEX_MESH_PATH)
	if hex_mesh == null:
		push_error("GameBoardSetup: could not load hex mesh at %s" % HEX_MESH_PATH)
		return

	var hexes_root := Node3D.new()
	hexes_root.name = "Hexes"
	_add_owned(self, hexes_root)

	_add_hex(hexes_root, hex_mesh, layout.capital_coord, "Capital", "capital")
	for coord: Vector2i in layout.home_coords:
		var faction: String = layout.home_factions.get(coord, "?")
		_add_hex(hexes_root, hex_mesh, coord, "Home_%s" % faction, "home")
	for coord: Vector2i in layout.sea_tower_coords:
		_add_hex(hexes_root, hex_mesh, coord, "SeaTower_%d_%d" % [coord.x, coord.y], "sea_tower")
	for coord: Vector2i in layout.interior_coords:
		_add_hex(hexes_root, hex_mesh, coord, "Interior_%d_%d" % [coord.x, coord.y], "interior")

	var pieces_root := Node3D.new()
	pieces_root.name = "Pieces"
	_add_owned(self, pieces_root)

	_add_garrison(pieces_root, layout.capital_coord, layout.capital_garrison_count)
	for coord: Vector2i in layout.garrison_counts.keys():
		_add_garrison(pieces_root, coord, layout.garrison_counts[coord])
	for coord: Vector2i in layout.curse_coords:
		_add_simple_piece(pieces_root, CURSE_MODEL, coord, "Curse", Vector3.ZERO)
	for coord: Vector2i in layout.skeleton_counts.keys():
		var count: int = layout.skeleton_counts[coord]
		for i: int in range(count):
			var offset := Vector3(0.3 * i, 0.0, 0.0)
			_add_simple_piece(pieces_root, SKELETON_MODEL, coord, "Skeleton_%d" % i, offset)

	var standees_root := Node3D.new()
	standees_root.name = "Standees"
	_add_owned(self, standees_root)
	_add_home_hero_standees(standees_root, layout, card_db)


func _add_hex(parent: Node3D, mesh: Mesh, coord: Vector2i, node_name: String, role: String) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = node_name
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROLE_COLORS.get(role, Color.WHITE)
	inst.material_override = mat
	_add_owned(parent, inst)
	inst.position = HexMath.to_world(coord)


func _add_garrison(parent: Node3D, coord: Vector2i, level: int) -> void:
	if level <= 0:
		return
	var paths: Array[String] = [GARRISON_BOTTOM]
	if level >= 2:
		paths.append(GARRISON_MIDDLE)
	if level >= 3:
		paths.append(GARRISON_TOP)
	var group := Node3D.new()
	group.name = "Garrison_%d_%d" % [coord.x, coord.y]
	_add_owned(parent, group)
	group.position = HexMath.to_world(coord)
	# The 3 garrison pieces (bottom/middle/top) are separate same-footprint
	# models meant to physically stack, not overlap in place - offset each
	# by the previous piece's own measured height so a 3-stack reads as a
	# visible tower rather than a Z-fighting blob.
	var y_offset := 0.0
	for path: String in paths:
		var mesh: Mesh = load(path)
		if mesh == null:
			continue
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.name = path.get_file().get_basename()
		_add_owned(group, inst)
		inst.position = Vector3(0, y_offset, 0)
		y_offset += mesh.get_aabb().size.y


func _add_simple_piece(parent: Node3D, model_path: String, coord: Vector2i, node_name: String, local_offset: Vector3) -> void:
	var mesh: Mesh = load(model_path)
	if mesh == null:
		push_warning("GameBoardSetup: could not load %s" % model_path)
		return
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = node_name
	_add_owned(parent, inst)
	inst.position = HexMath.to_world(coord) + local_offset


func _add_home_hero_standees(parent: Node3D, layout: BoardLayout, card_db: Node) -> void:
	var model_manifest: Node = get_node_or_null("/root/ModelManifest")
	if model_manifest == null:
		return
	for coord: Vector2i in layout.home_coords:
		var faction: String = layout.home_factions.get(coord, "")
		var hero: HeroCard = _first_hero_for_faction(card_db, faction)
		if hero == null:
			continue
		var model_path: String = model_manifest.find_model_path(faction, hero.card_name)
		if model_path.is_empty():
			push_warning("GameBoardSetup: no model found for hero '%s' (%s)" % [hero.card_name, faction])
			continue
		var mesh: Mesh = load(model_path)
		if mesh == null:
			continue
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.name = "Hero_%s" % hero.card_name
		_add_owned(parent, inst)
		inst.position = HexMath.to_world(coord) + Vector3(0, 0.2, 0)
		inst.rotation_degrees = STANDEE_UPRIGHT_ROTATION


func _first_hero_for_faction(card_db: Node, faction: String) -> HeroCard:
	for h: HeroCard in card_db.heroes:
		if h.faction == faction:
			return h
	return null


## add_child() alone leaves a node visible but not selectable/draggable in
## the editor - .owner must also be set to the scene root that will
## actually be saved.
func _add_owned(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else self
