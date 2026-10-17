extends Node3D

## Draws the live GameState as a real tabletop: the printed board lying in a
## frozen tundra under falling snow, the hex tiles with their card art, and
## every piece from the extracted models - Units per type, Garrison stacks
## by level, Skeletons, Curses, Havens with Wall/Tower, Heroes, Legions and
## Hordes (with a Threat badge). Attached to PlayBoard's "Board" node;
## play_board.gd feeds it apply_state() and the camera yaw.
##
## Layout: each hex holds a piece group that turns with the camera, so its
## two lanes always read front-to-back from the player's view - every tall
## piece side by side at the back (Garrison, Haven, Legion / Horde, Hero,
## Curse), Units and Skeletons in front. A lane that overflows squeezes and
## staggers instead of letting pieces cut through each other. Heroes,
## Legions and Hordes keep their node between updates and walk (hop) to
## their new hex.

const PieceLibrary := preload("res://scripts/ui/board/piece_library.gd")

const HEX_MESH_PATH := "res://assets/images/3d/hex.obj"
const BOARD_TEXTURE := "res://assets/art/board/game_board_4k.jpg"
const TUNDRA_SHADER := "res://scripts/ui/shaders/tundra_ground.gdshader"
const TUNDRA_DIR := "res://assets/art/tundra/"
const BADGE_TEXTURE := "res://assets/art/board/threat_badge.png"
const BADGE_FONT := "res://assets/art/fonts/BarlowCondensed-SemiBold.ttf"
const CURSE_SHADER := "res://scripts/ui/shaders/curse_overlay.gdshader"

## Printed board: 7208 px, centred on The Capital, 269.315 px per world unit
## (least-squares fit of 35 printed hex centres; Render/lib/uprising_assets.py).
const BOARD_WORLD_SIZE: float = 7208.0 / 269.31542306
const TILE_TOP: float = 0.2
const SQRT3: float = 1.7320508

const ROW_BACK_Z: float = -0.5
const ROW_FRONT_Z: float = 0.8
const ROW_MARGIN: float = 0.28
const ROW_GAP: float = 0.05
const STAGGER: float = 0.24

const EMPIRE_COLOR := Color(0.69, 0.043, 0.58)
const CHAOS_COLOR := Color(0.776, 0.812, 0.224)
const SELECT_COLOR := Color(0.875, 0.745, 0.424)
const HOVER_COLOR := Color(0.5, 0.86, 0.9)

const FALLBACK_COLORS: Dictionary = {
	"capital": Color(0.55, 0.16, 0.45),
	"home": Color(0.3, 0.45, 0.55),
	"sea_tower": Color(0.2, 0.5, 0.58),
	"interior": Color(0.16, 0.26, 0.3),
}

var camera_yaw: float = 0.0

var _tile_root: Node3D
var _piece_root: Node3D
var _overlay_root: Node3D
var _hex_mesh: Mesh
var _hex_fill: ArrayMesh
var _tiles: Dictionary = {}          # Vector2i -> MeshInstance3D (child of a per-hex Node3D)
var _tile_keys: Dictionary = {}      # Vector2i -> String (material key)
var _tile_explored: Dictionary = {}  # Vector2i -> bool
var _tile_rotation: Dictionary = {}  # Vector2i -> int
var _groups: Dictionary = {}         # Vector2i -> Node3D piece group
var _group_sigs: Dictionary = {}     # Vector2i -> String
var _group_keys: Dictionary = {}     # Vector2i -> Dictionary(key -> true) built last time
var _movers: Dictionary = {}         # mover key -> Node3D
var _mover_coord: Dictionary = {}    # mover key -> Vector2i
var _badges: Dictionary = {}         # mover key -> Label3D
var _curses: Dictionary = {}         # Vector2i -> MeshInstance3D overlay
var _materials: Dictionary = {}      # tile material cache
var _select_ring: MeshInstance3D
var _hover_ring: MeshInstance3D
var _has_built: bool = false
var _capital_flipped: bool = false
var _snow: GPUParticles3D
var _tops: Dictionary = {}           # Vector2i -> float (surface height pieces stand on)


func _ready() -> void:
	PieceLibrary.setup(get_node_or_null("/root/ModelManifest"))
	_hex_mesh = load(HEX_MESH_PATH) as Mesh
	_hex_fill = _make_hex_fill(1.97)
	_tile_root = _add_root("Tiles")
	_overlay_root = _add_root("Overlays")
	_piece_root = _add_root("Pieces")
	_build_table()
	_select_ring = _make_ring(SELECT_COLOR, 1.98, 1.78, 2.2)
	_hover_ring = _make_ring(HOVER_COLOR, 1.98, 1.86, 1.2)


func _add_root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


func _process(_delta: float) -> void:
	for g: Variant in _groups.values():
		var group: Node3D = g as Node3D
		group.rotation.y = camera_yaw
	if _select_ring.visible:
		var ring_mat: StandardMaterial3D = _select_ring.material_override as StandardMaterial3D
		var c: Color = ring_mat.albedo_color
		c.a = 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.004)
		ring_mat.albedo_color = c


## World position of a hex centre at the height pieces stand on.
func hex_surface(coord: Vector2i) -> Vector3:
	var p: Vector3 = HexMath.to_world(coord)
	p.y = float(_tops.get(coord, TILE_TOP))
	return p


## Keep the snowfall centred on what the camera looks at.
func set_snow_center(world_pos: Vector3) -> void:
	if _snow != null:
		_snow.position = Vector3(world_pos.x, _snow.position.y, world_pos.z)


# ======================================================================= state

func apply_state(state: GameState) -> void:
	if state == null:
		return
	var first: bool = not _has_built
	_has_built = true
	# GameState.capital_flipped: The Capital turned to "Uprising in the Capital"
	_capital_flipped = state.get("capital_flipped") == true
	var present: Dictionary = {}
	for coord: Vector2i in state.hexes.keys():
		present[coord] = true
		_update_tile(coord, state.hexes[coord], first)
	for coord: Variant in _tiles.keys():
		if not present.has(coord):
			_remove_tile(coord as Vector2i)

	# Heroes, Legions and Hordes: persistent standees that move.
	var wanted: Dictionary = {}   # key -> Dictionary
	for p: PlayerFactionState in state.players:
		wanted["hero:" + p.faction] = {"coord": p.hero_coord, "kind": "hero", "path": PieceLibrary.hero_model(p.faction, p.hero_name), "scale": PieceLibrary.TTS_HERO}
	for l: LegionInstance in state.legions:
		wanted["legion:%d" % l.id] = {"coord": l.coord, "kind": "legion", "path": PieceLibrary.legion_model(l.card_name), "scale": PieceLibrary.TTS_NEMESIS, "threat": l.threat}
	for h: HordeInstance in state.hordes:
		wanted["horde:%d" % h.id] = {"coord": h.coord, "kind": "horde", "path": PieceLibrary.horde_model(h.card_name), "scale": PieceLibrary.TTS_NEMESIS, "threat": h.threat}
	for key: Variant in _movers.keys():
		if not wanted.has(key):
			_remove_mover(str(key))
	var movers_at: Dictionary = {}  # Vector2i -> Array[String]
	for key: Variant in wanted.keys():
		var info: Dictionary = wanted[key]
		var c: Vector2i = info["coord"]
		if not movers_at.has(c):
			movers_at[c] = []
		(movers_at[c] as Array).append(str(key))

	# Rebuild the piece groups whose contents changed.
	for coord: Vector2i in state.hexes.keys():
		var tile: HexTileState = state.hexes[coord]
		var here: Array = movers_at.get(coord, [])
		here.sort()
		var items: Array[Dictionary] = _items_for(tile)
		var sig: String = _signature(items, here)
		if sig == str(_group_sigs.get(coord, "")):
			continue
		_group_sigs[coord] = sig
		_rebuild_group(coord, items, here, wanted, first)
	for coord: Variant in _groups.keys():
		if not present.has(coord):
			var stale: Node3D = _groups[coord]
			stale.queue_free()
			_groups.erase(coord)
			_group_sigs.erase(coord)
			_group_keys.erase(coord)

	# Threat badges follow the live numbers without rebuilding anything.
	for key: Variant in wanted.keys():
		var info: Dictionary = wanted[key]
		if info.has("threat") and _badges.has(key):
			var badge: Label3D = _badges[key]
			badge.text = str(int(info["threat"]))


func _items_for(tile: HexTileState) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if tile.garrison_level > 0:
		items.append({"key": "garrison:%d" % tile.garrison_level, "kind": "garrison", "row": 0, "level": tile.garrison_level})
	if not tile.haven_faction.is_empty():
		items.append({"key": "haven:%s:%s:%s" % [tile.haven_faction, tile.wall, tile.tower], "kind": "haven", "row": 0,
			"faction": tile.haven_faction, "wall": tile.wall, "tower": tile.tower})
	if tile.curse:
		items.append({"key": "curse", "kind": "curse", "row": 0})
	var faction: String = tile.player_faction_here()
	if not faction.is_empty():
		var stack: Dictionary = tile.unit_stack(faction)
		var names: Array = stack.keys()
		names.sort()
		for unit_name: Variant in names:
			for i: int in range(int(stack[unit_name])):
				items.append({"key": "unit:%s:%s:%d" % [faction, unit_name, i], "kind": "unit", "row": 1,
					"faction": faction, "unit": str(unit_name)})
	for i: int in range(tile.skeleton_count):
		items.append({"key": "skeleton:%d" % i, "kind": "skeleton", "row": 1})
	return items


func _signature(items: Array[Dictionary], movers: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for it: Dictionary in items:
		parts.append(str(it["key"]))
	for m: Variant in movers:
		parts.append(str(m))
	return "|".join(parts)


func _rebuild_group(coord: Vector2i, items: Array[Dictionary], movers_here: Array, wanted: Dictionary, first: bool) -> void:
	var group: Node3D = _groups.get(coord)
	if group == null:
		group = Node3D.new()
		group.name = "Hex_%d_%d" % [coord.x, coord.y]
		_piece_root.add_child(group)
		group.position = hex_surface(coord)
		group.rotation.y = camera_yaw
		_groups[coord] = group
	var old_keys: Dictionary = _group_keys.get(coord, {})
	var new_keys: Dictionary = {}
	for child: Node in group.get_children():
		if child.has_meta("item"):
			child.queue_free()

	var rows: Array = [[], []]   # back lane, front lane: Array of Node3D
	var spawned: Array[Node3D] = []
	var curse_nodes: Array[Node3D] = []
	for it: Dictionary in items:
		var node: Node3D = _build_item(it)
		if node == null:
			continue
		node.set_meta("item", true)
		group.add_child(node)
		if str(it["kind"]) == "curse":
			curse_nodes.append(node)   # goes last, after the standees
		else:
			(rows[int(it["row"])] as Array).append(node)
		var key: String = str(it["key"])
		new_keys[key] = true
		if not old_keys.has(key):
			spawned.append(node)
	for mkey: Variant in movers_here:
		var key: String = str(mkey)
		var info: Dictionary = wanted[key]
		var mover: Node3D = _ensure_mover(key, info, group, first)
		(rows[0] as Array).append(mover)
		new_keys[key] = true
	for cn: Node3D in curse_nodes:
		(rows[0] as Array).append(cn)
	_group_keys[coord] = new_keys

	_layout_row(rows[0], ROW_BACK_Z)
	_layout_row(rows[1], ROW_FRONT_Z)

	var delay: float = 0.0
	if first:
		delay = 0.35 + 0.09 * float(HexMath.distance(coord, Vector2i.ZERO))
	for i: int in range(spawned.size()):
		_drop_in(spawned[i], delay + 0.05 * float(i))


func _build_item(it: Dictionary) -> Node3D:
	match str(it["kind"]):
		"garrison":
			return PieceLibrary.make_garrison(int(it["level"]))
		"haven":
			return PieceLibrary.make_haven(str(it["faction"]), bool(it["wall"]), bool(it["tower"]))
		"curse":
			return PieceLibrary.make_standee(PieceLibrary.CURSE_MODEL, PieceLibrary.TTS_CURSE, CHAOS_COLOR)
		"skeleton":
			return PieceLibrary.make_standee(PieceLibrary.SKELETON_MODEL, PieceLibrary.TTS_SKELETON, CHAOS_COLOR)
		"unit":
			var f: String = str(it["faction"])
			var u: String = str(it["unit"])
			return PieceLibrary.make_standee(PieceLibrary.unit_model(f, u), PieceLibrary.unit_tts_scale(f, u))
	return null


## Spreads a row's pieces across the hex at depth `z`; overflowing rows
## squeeze together and every other piece steps back so cards never cut
## through each other.
func _layout_row(nodes: Array, z: float) -> void:
	var n: int = nodes.size()
	if n == 0:
		return
	var avail: float = 2.0 * (2.0 - absf(z) / SQRT3 - ROW_MARGIN)
	var widths: Array[float] = []
	var span: float = ROW_GAP * float(n - 1)
	for node: Variant in nodes:
		var w: float = float((node as Node3D).get_meta("width", 0.8)) * 0.86
		widths.append(w)
		span += w
	var squeeze: float = minf(1.0, avail / maxf(span, 0.001))
	var x: float = -span * squeeze * 0.5
	for i: int in range(n):
		var w: float = widths[i] * squeeze
		var zz: float = z
		if squeeze < 0.98 and i % 2 == 1:
			zz -= STAGGER
		var target := Vector3(x + w * 0.5, 0.0, zz)
		x += w + ROW_GAP * squeeze
		var node: Node3D = nodes[i]
		node.set_meta("slot", target)
		if node.has_meta("mover") and node.has_meta("arrived"):
			_walk_to(node, target)
		else:
			node.position = target
			if node.has_meta("mover"):
				node.set_meta("arrived", true)


func _drop_in(node: Node3D, delay: float) -> void:
	var rest: Vector3 = node.position
	node.position = rest + Vector3(0.0, 1.1, 0.0)
	node.scale = Vector3(0.85, 0.85, 0.85)
	var tw: Tween = node.create_tween().set_parallel(true)
	tw.tween_property(node, "position", rest, 0.34).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "scale", Vector3.ONE, 0.42).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ======================================================================= movers

func _ensure_mover(key: String, info: Dictionary, group: Node3D, first: bool) -> Node3D:
	var mover: Node3D = _movers.get(key)
	var coord: Vector2i = info["coord"]
	if mover == null:
		mover = PieceLibrary.make_standee(str(info["path"]), float(info["scale"]))
		mover.name = key.replace(":", "_")
		mover.set_meta("mover", true)
		group.add_child(mover)
		_movers[key] = mover
		_mover_coord[key] = coord
		if info.has("threat"):
			_add_badge(key, mover, str(info["kind"]) == "legion", int(info["threat"]))
		# placed by the layout this frame, then falls in
		var delay: float = 0.0
		if first:
			delay = 0.6 + 0.09 * float(HexMath.distance(coord, Vector2i.ZERO))
		_drop_in_after_layout.call_deferred(mover, delay)
		return mover
	if mover.get_parent() != group:
		mover.reparent(group, true)
		mover.rotation = Vector3.ZERO
	_mover_coord[key] = coord
	return mover


func _drop_in_after_layout(node: Node3D, delay: float) -> void:
	if is_instance_valid(node):
		_drop_in(node, delay)


## Walk to `target` (group-local) with a little hop, like lifting a standee.
func _walk_to(node: Node3D, target: Vector3) -> void:
	var from: Vector3 = node.position
	if from.distance_to(target) < 0.01:
		return
	var dist: float = from.distance_to(target)
	var dur: float = clampf(0.25 + dist * 0.06, 0.3, 0.9)
	var tw: Tween = node.create_tween()
	tw.tween_method(_hop.bind(node, from, target, minf(0.35 + dist * 0.05, 1.2)), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _hop(t: float, node: Node3D, from: Vector3, to: Vector3, height: float) -> void:
	if not is_instance_valid(node):
		return
	var p: Vector3 = from.lerp(to, t)
	p.y += sin(t * PI) * height
	node.position = p


func _remove_mover(key: String) -> void:
	var mover: Node3D = _movers.get(key)
	_movers.erase(key)
	_mover_coord.erase(key)
	_badges.erase(key)
	if mover == null or not is_instance_valid(mover):
		return
	var tw: Tween = mover.create_tween().set_parallel(true)
	tw.tween_property(mover, "scale", Vector3(0.05, 0.05, 0.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mover.queue_free)


func _add_badge(key: String, mover: Node3D, legion: bool, threat: int) -> void:
	var h: float = float(mover.get_meta("height", 2.0))
	var badge := Sprite3D.new()
	badge.texture = load(BADGE_TEXTURE) as Texture2D
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.render_priority = 10
	badge.pixel_size = 0.0021
	badge.modulate = EMPIRE_COLOR.lightened(0.15) if legion else CHAOS_COLOR
	badge.position = Vector3(0.0, h + 0.32, 0.0)
	badge.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mover.add_child(badge)
	var label := Label3D.new()
	label.text = str(threat)
	label.font = load(BADGE_FONT) as Font
	label.font_size = 96
	label.pixel_size = 0.0034
	label.outline_size = 0
	label.modulate = Color(0.949, 0.91, 0.769)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 11
	label.outline_render_priority = 10
	label.position = Vector3(0.0, h + 0.32, 0.0)
	mover.add_child(label)
	_badges[key] = label


# ======================================================================= tiles

func _update_tile(coord: Vector2i, tile: HexTileState, first: bool) -> void:
	var has_tile: bool = tile.role != "outer"
	_tops[coord] = TILE_TOP if has_tile else 0.0
	_update_curse(coord, tile.curse, has_tile)
	if not has_tile:
		if _tiles.has(coord):
			_remove_tile(coord)
		return
	var holder: Node3D
	var inst: MeshInstance3D = _tiles.get(coord)
	if inst == null:
		holder = Node3D.new()
		holder.name = "Tile_%d_%d" % [coord.x, coord.y]
		_tile_root.add_child(holder)
		holder.position = HexMath.to_world(coord)
		inst = MeshInstance3D.new()
		inst.mesh = _hex_mesh
		holder.add_child(inst)
		_tiles[coord] = inst
		holder.rotation.y = deg_to_rad(-60.0 * float(tile.rotation))
		_tile_rotation[coord] = tile.rotation
		if first:
			_tile_intro(inst, 0.08 * float(HexMath.distance(coord, Vector2i.ZERO)))
	else:
		holder = inst.get_parent() as Node3D
		if int(_tile_rotation.get(coord, 0)) != tile.rotation:
			_tile_rotation[coord] = tile.rotation
			var target: float = deg_to_rad(-60.0 * float(tile.rotation))
			# turn the short way round
			var cur: float = holder.rotation.y
			while target - cur > PI:
				target -= TAU
			while cur - target > PI:
				target += TAU
			holder.create_tween().tween_property(holder, "rotation:y", target, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var path: String = HexTextureLibrary.get_texture_path(tile.role, tile.hex_card_name, tile.owning_faction)
	var explored: bool = tile.explored or HexTextureLibrary.default_explored(tile.role)
	if tile.role == "capital" and _capital_flipped:
		explored = false  # the atlas's other half is the "Uprising in the Capital" side
	var key: String = "%s|%s|%s|%s" % [path, explored, tile.curse, tile.role]
	if str(_tile_keys.get(coord, "")) == key:
		return
	var was_explored: bool = bool(_tile_explored.get(coord, explored))
	_tile_keys[coord] = key
	_tile_explored[coord] = explored
	var mat: Material = _tile_material(path, explored, tile.curse, tile.role)
	if explored != was_explored and not first:
		_flip_tile(inst, mat)
	else:
		inst.material_override = mat


func _remove_tile(coord: Vector2i) -> void:
	var inst: MeshInstance3D = _tiles.get(coord)
	if inst != null and is_instance_valid(inst):
		inst.get_parent().queue_free()
	_tiles.erase(coord)
	_tile_keys.erase(coord)
	_tile_explored.erase(coord)
	_tile_rotation.erase(coord)


func _tile_material(path: String, explored: bool, cursed: bool, role: String) -> Material:
	var key: String = "%s|%s|%s|%s" % [path, explored, cursed, role]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.6
	mat.metallic_specular = 0.38
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.uv1_offset = Vector3(0.0, HexTextureLibrary.EXPLORED_V_OFFSET if explored else 0.0, 0.0)
	else:
		mat.albedo_color = FALLBACK_COLORS.get(role, Color(0.2, 0.25, 0.28))
	if cursed:
		# the Curse drains the land: darker, greener, under the overlay
		mat.albedo_color *= Color(0.62, 0.74, 0.5)
	_materials[key] = mat
	return mat


## Explore: lift the tile, turn it over, and land it face up.
func _flip_tile(inst: MeshInstance3D, front: Material) -> void:
	var tw: Tween = inst.create_tween()
	tw.tween_property(inst, "position:y", 0.9, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(inst, "rotation:x", PI * 0.5, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_flip_swap.bind(inst, front))
	tw.tween_property(inst, "rotation:x", 0.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(inst, "position:y", 0.0, 0.26).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _flip_swap(inst: MeshInstance3D, front: Material) -> void:
	if is_instance_valid(inst):
		inst.material_override = front
		inst.rotation.x = -PI * 0.5


func _tile_intro(inst: MeshInstance3D, delay: float) -> void:
	inst.position.y = 1.6
	inst.transparency = 1.0
	var tw: Tween = inst.create_tween().set_parallel(true)
	tw.tween_property(inst, "position:y", 0.0, 0.4).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(inst, "transparency", 0.0, 0.25).set_delay(delay)


func _update_curse(coord: Vector2i, cursed: bool, has_tile: bool) -> void:
	var overlay: MeshInstance3D = _curses.get(coord)
	if not cursed:
		if overlay != null:
			var tw: Tween = overlay.create_tween()
			tw.tween_method(_set_curse_cover.bind(overlay), 0.62, 0.0, 0.6)
			tw.tween_callback(overlay.queue_free)
			_curses.erase(coord)
		return
	var y: float = (TILE_TOP if has_tile else 0.0) + 0.006
	if overlay != null:
		overlay.position.y = y
		return
	overlay = MeshInstance3D.new()
	overlay.mesh = _hex_fill
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load(CURSE_SHADER) as Shader
	var noise := NoiseTexture2D.new()
	noise.seamless = true
	noise.width = 256
	noise.height = 256
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.02
	fnl.seed = coord.x * 73 + coord.y * 19
	noise.noise = fnl
	mat.set_shader_parameter("noise_tex", noise)
	mat.set_shader_parameter("coverage", 0.0)
	overlay.material_override = mat
	_overlay_root.add_child(overlay)
	overlay.position = HexMath.to_world(coord) + Vector3(0.0, y, 0.0)
	_curses[coord] = overlay
	overlay.create_tween().tween_method(_set_curse_cover.bind(overlay), 0.0, 0.62, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_curse_cover(v: float, overlay: MeshInstance3D) -> void:
	if is_instance_valid(overlay) and overlay.material_override is ShaderMaterial:
		(overlay.material_override as ShaderMaterial).set_shader_parameter("coverage", v)


# ======================================================================= selection

func set_selected(coord: Vector2i, visible_flag: bool) -> void:
	_place_ring(_select_ring, coord, visible_flag, 0.012)


func set_hover(coord: Vector2i, visible_flag: bool) -> void:
	_place_ring(_hover_ring, coord, visible_flag, 0.009)


func _place_ring(ring: MeshInstance3D, coord: Vector2i, visible_flag: bool, lift: float) -> void:
	ring.visible = visible_flag
	if visible_flag:
		var p: Vector3 = HexMath.to_world(coord)
		p.y = float(_tops.get(coord, TILE_TOP)) + lift
		ring.position = p


func _make_ring(color: Color, r_out: float, r_in: float, energy: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(6):
		var a0: float = deg_to_rad(60.0 * float(i))
		var a1: float = deg_to_rad(60.0 * float(i + 1))
		var o0 := Vector3(cos(a0) * r_out, 0.0, sin(a0) * r_out)
		var o1 := Vector3(cos(a1) * r_out, 0.0, sin(a1) * r_out)
		var i0 := Vector3(cos(a0) * r_in, 0.0, sin(a0) * r_in)
		var i1 := Vector3(cos(a1) * r_in, 0.0, sin(a1) * r_in)
		for v: Vector3 in [o0, o1, i1, o0, i1, i0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var ring := MeshInstance3D.new()
	ring.mesh = st.commit()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	ring.material_override = mat
	ring.visible = false
	add_child(ring)
	return ring


func _make_hex_fill(radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(6):
		var a0: float = deg_to_rad(60.0 * float(i))
		var a1: float = deg_to_rad(60.0 * float(i + 1))
		var v0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var v1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		for v: Vector3 in [Vector3.ZERO, v0, v1]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z) / (radius * 2.0) + Vector2(0.5, 0.5))
			st.add_vertex(v)
	return st.commit()


# ======================================================================= table

func _build_table() -> void:
	var board := MeshInstance3D.new()
	board.name = "PrintedBoard"
	var pm := PlaneMesh.new()
	pm.size = Vector2(BOARD_WORLD_SIZE, BOARD_WORLD_SIZE)
	board.mesh = pm
	var bm := StandardMaterial3D.new()
	var btex: Texture2D = null
	if ResourceLoader.exists(BOARD_TEXTURE):
		btex = load(BOARD_TEXTURE) as Texture2D
	if btex != null:
		bm.albedo_texture = btex
		# the printed Region spaces are bright; let the tiles and pieces lead
		bm.albedo_color = Color(0.72, 0.77, 0.8)
	else:
		bm.albedo_color = Color(0.03, 0.25, 0.29)
	bm.roughness = 0.55
	bm.metallic_specular = 0.4
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	board.material_override = bm
	board.position.y = -0.002
	add_child(board)

	var edge := MeshInstance3D.new()
	edge.name = "BoardEdge"
	var bx := BoxMesh.new()
	bx.size = Vector3(BOARD_WORLD_SIZE, 0.09, BOARD_WORLD_SIZE)
	edge.mesh = bx
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.02, 0.05, 0.055)
	em.roughness = 0.8
	edge.material_override = em
	edge.position.y = -0.052  # top face sits under the printed board, no z-fighting
	add_child(edge)

	_build_tundra()


## The frozen tundra round the board: displaced, textured snow ground
## (tundra_ground.gdshader, flat right round the board so it lies on the
## snow) and snow falling over everything.
func _build_tundra() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(TUNDRA_SHADER) as Shader
	var maps: Dictionary = {
		"macro_albedo": "snow_field_aerial_col_2k.jpg",
		"macro_normal": "snow_field_aerial_nor_gl_1k.jpg",
		"macro_height": "snow_field_aerial_height_1k.jpg",
		"detail_albedo": "snow_02_diff_1k.jpg",
		"detail_normal": "snow_02_nor_gl_1k.jpg",
	}
	for param: Variant in maps.keys():
		var path: String = TUNDRA_DIR + str(maps[param])
		if ResourceLoader.exists(path):
			mat.set_shader_parameter(str(param), load(path) as Texture2D)
	mat.set_shader_parameter("board_half", BOARD_WORLD_SIZE * 0.5)

	var ground := MeshInstance3D.new()
	ground.name = "Tundra"
	var pm := PlaneMesh.new()
	pm.size = Vector2(220.0, 220.0)
	pm.subdivide_width = 140
	pm.subdivide_depth = 140
	ground.mesh = pm
	ground.material_override = mat
	ground.position.y = -0.1
	ground.extra_cull_margin = 4.0
	add_child(ground)

	_snow = _make_snowfall()
	add_child(_snow)


func _make_snowfall() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Snowfall"
	p.amount = 1600
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(0.0, 15.0, 0.0)
	p.visibility_aabb = AABB(Vector3(-45.0, -20.0, -45.0), Vector3(90.0, 40.0, 90.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(34.0, 0.5, 34.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 10.0
	pm.initial_velocity_min = 0.7
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.35, -0.2, 0.12)
	pm.scale_min = 0.6
	pm.scale_max = 1.25
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.08, Color(1, 1, 1, 1))
	fade.add_point(0.9, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.075)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.86, 0.92, 1.0, 0.8)
	var dot := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	dm.albedo_texture = dot
	# flakes right in front of the lens fade out instead of blotting the view
	dm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	dm.distance_fade_min_distance = 3.0
	dm.distance_fade_max_distance = 9.0
	quad.material = dm
	p.draw_pass_1 = quad
	return p
