extends Node3D
# The main menu's background: the game's own cockpit, parked — the same
# models, camera and starfield as the game scene (main.tscn), but with the
# lights low and the stars barely drifting. wake_up() brings everything up to
# the game's levels just before the game scene loads, whose own screen
# boot-up then carries on from there: the ship "starts up" instead of cutting.
#
# Built in code from main.tscn's values (transforms, light energies) so the
# menu and the game line up exactly; keep them in sync if the cockpit moves.

const UI_CONTROL: PackedScene = preload("res://assets/3d/gs_ui_control.glb")
const UI_INFO: PackedScene = preload("res://assets/3d/gs_ui_info.glb")
const UI_COCKPIT: PackedScene = preload("res://assets/3d/gs_ui_cockpit.glb")
const UI_LOG: PackedScene = preload("res://assets/3d/gs_ui_log.glb")
const STARFIELD: Script = preload("res://scripts/starfield.gd")

# transforms exactly as main.tscn stores them (parsed with str_to_var)
const CAMERA_XFORM: String = "Transform3D(1, 0, 0, 0, -4.371139e-08, 1, 0, -1, -4.371139e-08, 0, 1.772, 0.056)"
const SUN_XFORM: String = "Transform3D(1, 0, 0, 0, 0.342, -0.94, 0, 0.94, 0.342, 0, 3, 0)"
const MODELS: Array = [
	[UI_CONTROL, "Transform3D(3.2208035, 0.011242848, 1.3697807, -1.3697723, -0.004781525, 3.220823, 0.012217389, -3.4999788, -5.987502e-08, -0.6467306, 1.1118473, -0.22355545)"],
	[UI_INFO, "Transform3D(3.799994, 0.006632248, 2.8990477e-10, 0, -1.6610328e-07, 3.8, 0.006632248, -3.799994, -1.6610302e-07, 0.74006987, 0.9406268, -0.28849393)"],
	[UI_COCKPIT, "Transform3D(2.5, 0, 0, 0, 0.88841176, 1.8694555, 0, -2.3368194, 0.7107294, -0.0023359656, 0.9999999, -0.119951665)"],
	[UI_LOG, "Transform3D(-7.86805e-08, -3, -8.742278e-08, 0, -1.3113416e-07, 2, -1.8, 1.3113416e-07, 3.821371e-15, -0.33061832, 0.8986856, -0.36365524)"],
]
# main.tscn's CockpitPanelGlow chain: [parent index (-1 = root), local position]
const GLOWS: Array = [
	[-1, Vector3(-0.4310641, 0.49116862, 0.013363868)],
	[0, Vector3(0.7827995, -0.00016492605, -0.009)],
	[0, Vector3(-0.4310641, 0.47997022, 0.28677505)],
	[2, Vector3(0.8734183, -0.07851958, 0.0075092018)],
	[2, Vector3(1.44297, 0.08542335, 0.14597967)],
	[4, Vector3(0.7827995, -0.00016492605, -0.009)],
]
# [game energy, parked share] per light; the wake-up tweens to the game value
const SUN_ENERGY: float = 0.9
const FILL_ENERGY: float = 0.7
const GLOW_ENERGY: float = 0.35
const AMBIENT_ENERGY: float = 0.35
const PARKED: float = 0.25            # lights at a quarter while parked
const STAR_SPEED_GAME: float = 0.018  # starfield.gd's cruising speed
const STAR_SPEED_PARKED: float = 0.003
const WAKE_SEC: float = 1.3

var _env: Environment = null
var _sun: DirectionalLight3D = null
var _fill: OmniLight3D = null
var _glows: Array[OmniLight3D] = []
var _star_mat: ShaderMaterial = null

func _ready() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.03, 0.08)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.08, 0.12, 0.28)
	_env.ambient_light_energy = AMBIENT_ENERGY * PARKED
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	for i: int in range(1, 6):
		_env.set_glow_level(i, 1.0)
	_env.glow_normalized = true
	_env.glow_intensity = 0.24
	_env.glow_strength = 0.2
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 0.65
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = _env
	add_child(world)

	var stars: Node3D = Node3D.new()
	stars.set_script(STARFIELD)
	add_child(stars)
	for child: Node in stars.get_children():
		if child is MeshInstance3D:
			_star_mat = (child as MeshInstance3D).material_override as ShaderMaterial
	if _star_mat:
		_star_mat.set_shader_parameter("speed", STAR_SPEED_PARKED)

	var cam: Camera3D = Camera3D.new()
	cam.transform = str_to_var(CAMERA_XFORM) as Transform3D
	cam.fov = 45.0
	add_child(cam)
	cam.make_current()

	for m: Array in MODELS:
		var model: Node3D = (m[0] as PackedScene).instantiate()
		model.transform = str_to_var(str(m[1])) as Transform3D
		add_child(model)

	_sun = DirectionalLight3D.new()
	_sun.transform = str_to_var(SUN_XFORM) as Transform3D
	_sun.light_energy = SUN_ENERGY * PARKED
	_sun.shadow_enabled = true
	add_child(_sun)
	_fill = OmniLight3D.new()
	_fill.position = Vector3(-0.037768304, 1.0892866, -0.05723527)
	_fill.light_color = Color(0.85, 0.92, 1.0)
	_fill.light_energy = FILL_ENERGY * PARKED
	_fill.light_indirect_energy = 0.5
	_fill.omni_range = 1.5
	add_child(_fill)
	# the console's blue panel glows, nested like main.tscn's CockpitPanelGlow chain
	for spec: Array in GLOWS:
		var g: OmniLight3D = OmniLight3D.new()
		g.position = spec[1]
		g.light_color = Color(0.55, 0.78, 1.0)
		g.light_energy = GLOW_ENERGY * PARKED
		g.omni_range = 0.8
		var parent_idx: int = int(spec[0])
		(self if parent_idx < 0 else _glows[parent_idx]).add_child(g)
		_glows.append(g)
	_idle_flicker()

# A parked ship isn't dead: the panel glows breathe slowly.
func _idle_flicker() -> void:
	var t: Tween = create_tween().set_loops()
	t.tween_method(func(v: float) -> void:
		for g: OmniLight3D in _glows:
			g.light_energy = GLOW_ENERGY * PARKED * v, 0.6, 1.0, 2.2).set_trans(Tween.TRANS_SINE)
	t.tween_method(func(v: float) -> void:
		for g: OmniLight3D in _glows:
			g.light_energy = GLOW_ENERGY * PARKED * v, 1.0, 0.6, 2.2).set_trans(Tween.TRANS_SINE)
	set_meta(&"_idle", t)

## Power up to the game's levels: a flicker, then lights, ambient and stars
## rise together. Await the returned signal before switching to the game.
func wake_up() -> Signal:
	if has_meta(&"_idle"):
		(get_meta(&"_idle") as Tween).kill()
	var t: Tween = create_tween()
	# a couple of quick flickers, like systems catching
	for v: float in [0.9, 0.2, 0.7, 0.35]:
		t.tween_callback(func() -> void: _set_power(v))
		t.tween_interval(0.07)
	t.tween_method(_set_power, 0.35, 1.0, WAKE_SEC).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	return t.finished

# 0 = parked, 1 = the game's levels
func _set_power(p: float) -> void:
	var k: float = lerpf(PARKED, 1.0, p)
	_sun.light_energy = SUN_ENERGY * k
	_fill.light_energy = FILL_ENERGY * k
	for g: OmniLight3D in _glows:
		g.light_energy = GLOW_ENERGY * k
	_env.ambient_light_energy = AMBIENT_ENERGY * k
	if _star_mat:
		_star_mat.set_shader_parameter("speed", lerpf(STAR_SPEED_PARKED, STAR_SPEED_GAME, p))
