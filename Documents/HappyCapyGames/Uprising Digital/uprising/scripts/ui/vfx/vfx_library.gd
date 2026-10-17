extends RefCounted

## Board event -> effect scene (assets/vfx/scenes, each a vfx_effect.gd
## with its own inspector values). Use via preload (no class_name):
##   const VfxLibrary := preload("res://scripts/ui/vfx/vfx_library.gd")
##   VfxLibrary.spawn("curse", self, board.hex_surface(coord))

const SCENES: Dictionary = {
	"curse": "res://assets/vfx/scenes/vfx_curse.tscn",
	"curse_lifted": "res://assets/vfx/scenes/vfx_curse_lifted.tscn",
	"skeleton": "res://assets/vfx/scenes/vfx_skeleton_rise.tscn",
	"horde_arrival": "res://assets/vfx/scenes/vfx_horde_arrival.tscn",
	"legion_arrival": "res://assets/vfx/scenes/vfx_legion_arrival.tscn",
	"garrison": "res://assets/vfx/scenes/vfx_garrison_placed.tscn",
	"explore": "res://assets/vfx/scenes/vfx_explore.tscn",
	"haven": "res://assets/vfx/scenes/vfx_haven_built.tscn",
	"defense": "res://assets/vfx/scenes/vfx_garrison_placed.tscn",
	"clash": "res://assets/vfx/scenes/vfx_combat_clash.tscn",
	"capital_uprising": "res://assets/vfx/scenes/vfx_capital_uprising.tscn",
	"nemesis_destroyed": "res://assets/vfx/scenes/vfx_destroyed.tscn",
	"garrison_lost": "res://assets/vfx/scenes/vfx_destroyed.tscn",
	"haven_lost": "res://assets/vfx/scenes/vfx_destroyed.tscn",
	"units_lost": "res://assets/vfx/scenes/vfx_destroyed.tscn",
	"units_arrive": "res://assets/vfx/scenes/vfx_units_arrive.tscn",
}

## Per-kind size tweaks on top of each scene's own size (a lost Unit is a
## smaller puff than a destroyed Legion).
const SIZE: Dictionary = {
	"units_lost": 0.6,
	"garrison_lost": 0.8,
	"haven_lost": 0.9,
	"defense": 0.75,
}

static var _cache: Dictionary = {}


static func has_effect(kind: String) -> bool:
	return SCENES.has(kind)


static func spawn(kind: String, parent: Node, world_pos: Vector3, size_mult: float = 1.0) -> Node3D:
	var path: String = str(SCENES.get(kind, ""))
	if path.is_empty() or parent == null:
		return null
	var packed: PackedScene = _cache.get(path)
	if packed == null:
		if not ResourceLoader.exists(path):
			return null
		packed = load(path) as PackedScene
		_cache[path] = packed
	if packed == null:
		return null
	var fx: Node3D = packed.instantiate() as Node3D
	if fx == null:
		return null
	var mult: float = size_mult * float(SIZE.get(kind, 1.0))
	if mult != 1.0:
		fx.set("size_scale", float(fx.get("size_scale")) * mult)
	parent.add_child(fx)
	fx.global_position = world_pos
	return fx
