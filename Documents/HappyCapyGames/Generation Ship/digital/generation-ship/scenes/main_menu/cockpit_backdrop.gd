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

# ── Life while parked ────────────────────────────────────────────────────────
# A slow camera sway, dust in the light, a low hum, and every few seconds a
# small random event: a console blip, a screen waking with static, a hull
# creak, the lights stuttering on a relay, now and then a spark.
const SFX_DIR: String = "res://assets/effects/menu/"
const HUM_DB: float = -18.0
const SWAY_ROT_DEG: float = 0.35      # how far the view drifts
const SWAY_POS: float = 0.004
const EVENT_GAP: Vector2 = Vector2(3.5, 8.0)   # seconds between random events
var _cam: Camera3D = null
var _cam_rest: Transform3D = Transform3D.IDENTITY
var _sway: float = 1.0                # fades to 0 as the ship wakes (the game's camera is still)
var _t: float = 0.0
var _hum: AudioStreamPlayer = null
var _sfx: Dictionary = {}             # name -> AudioStreamPlayer
var _screens: Array[MeshInstance3D] = []
var _awake: bool = false

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
		# the parked ship looks out at a busier sky than the game's
		_star_mat.set_shader_parameter("twinkle", 0.75)
		_star_mat.set_shader_parameter("nebula_str", 0.9)
		_star_mat.set_shader_parameter("galaxy_str", 0.85)
		_star_mat.set_shader_parameter("shooting_rate", 0.55)

	var cam: Camera3D = Camera3D.new()
	cam.transform = str_to_var(CAMERA_XFORM) as Transform3D
	cam.fov = 45.0
	add_child(cam)
	cam.make_current()
	_cam = cam
	_cam_rest = cam.transform

	for m: Array in MODELS:
		var model: Node3D = (m[0] as PackedScene).instantiate()
		model.transform = str_to_var(str(m[1])) as Transform3D
		add_child(model)
		for mesh: Node in model.find_children("*screen*", "MeshInstance3D", true, false):
			_screens.append(mesh as MeshInstance3D)

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
	_add_dust()
	_setup_audio()
	_schedule_event()

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

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		return
	# two slow, unrelated sines: the drift never quite repeats
	var a: float = sin(_t * 0.31) * 0.6 + sin(_t * 0.17 + 1.3) * 0.4
	var b: float = sin(_t * 0.23 + 0.7) * 0.6 + sin(_t * 0.11 + 2.1) * 0.4
	var rot: Basis = Basis(Vector3.RIGHT, deg_to_rad(SWAY_ROT_DEG) * a * _sway) * Basis(Vector3.FORWARD, deg_to_rad(SWAY_ROT_DEG) * b * 0.6 * _sway)
	_cam.transform = Transform3D(_cam_rest.basis * rot, _cam_rest.origin + Vector3(b, 0.0, a) * SWAY_POS * _sway)

# Faint dust motes drifting through the cockpit light.
func _add_dust() -> void:
	var dust: CPUParticles3D = CPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.1, 0.3, 0.7)
	dust.position = Vector3(0.0, 1.25, 0.0)
	dust.direction = Vector3(0.2, 0.05, 0.1)
	dust.spread = 180.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.004
	dust.initial_velocity_max = 0.018
	dust.scale_amount_min = 0.002
	dust.scale_amount_max = 0.005
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.7, 0.85, 1.0, 0.0))
	ramp.add_point(0.3, Color(0.7, 0.85, 1.0, 0.35))
	ramp.add_point(0.7, Color(0.7, 0.85, 1.0, 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.7, 0.85, 1.0, 0.0))
	dust.color_ramp = ramp
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	dust.mesh = quad
	add_child(dust)

func _setup_audio() -> void:
	for n: String in ["ship_hum_loop", "ship_power_up", "console_blip_1", "console_blip_2", "console_blip_3",
			"relay_click", "hull_creak", "screen_static", "spark"]:
		var path: String = SFX_DIR + n + ".wav"
		if not ResourceLoader.exists(path):
			continue
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = load(path) as AudioStream
		player.bus = &"SFX"
		add_child(player)
		_sfx[n] = player
	_hum = _sfx.get("ship_hum_loop") as AudioStreamPlayer
	if _hum:
		var wav: AudioStreamWAV = _hum.stream as AudioStreamWAV
		if wav:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
		_hum.volume_db = HUM_DB
		_hum.play()

func _play(n: String, db: float = -6.0, pitch_spread: float = 0.08) -> void:
	var player: AudioStreamPlayer = _sfx.get(n) as AudioStreamPlayer
	if player:
		player.volume_db = db
		player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
		player.play()

func _schedule_event() -> void:
	get_tree().create_timer(randf_range(EVENT_GAP.x, EVENT_GAP.y)).timeout.connect(func() -> void:
		if not is_inside_tree() or _awake:
			return
		_random_event()
		_schedule_event())

func _random_event() -> void:
	match randi() % 9:
		0, 1, 2:
			_event_blip()
		3, 4:
			_event_screen_static()
		5:
			_event_creak()
		6, 7:
			_event_light_stutter()
		8:
			_event_spark()

# a console blip; one panel light answers with a double blink
func _event_blip() -> void:
	_play("console_blip_%d" % (randi() % 3 + 1), -14.0, 0.03)
	if _glows.is_empty():
		return
	var g: OmniLight3D = _glows[randi() % _glows.size()]
	var base: float = g.light_energy
	var t: Tween = create_tween()
	for i: int in 2:
		t.tween_property(g, "light_energy", base * 4.0, 0.04)
		t.tween_property(g, "light_energy", base, 0.08)

# a monitor flickers awake with static, then goes dark again
func _event_screen_static() -> void:
	if _screens.is_empty():
		return
	var screen: MeshInstance3D = _screens[randi() % _screens.size()]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.55, 0.75)
	screen.material_overlay = mat
	_play("screen_static", -16.0)
	var t: Tween = create_tween()
	for i: int in 6:
		t.tween_property(mat, "albedo_color:a", randf_range(0.05, 0.6), 0.05)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	t.tween_callback(func() -> void:
		if is_instance_valid(screen):
			screen.material_overlay = null)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

# the hull settles: a creak and the faintest jolt of the view
func _event_creak() -> void:
	_play("hull_creak", -18.0, 0.15)
	var t: Tween = create_tween()
	t.tween_property(self, "_sway", 2.2, 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "_sway", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

# a relay clicks and the cockpit light stutters
func _event_light_stutter() -> void:
	_play("relay_click", -14.0)
	var base: float = _fill.light_energy
	var t: Tween = create_tween()
	for v: float in [0.3, 1.6, 0.5, 1.2]:
		t.tween_property(_fill, "light_energy", base * v, 0.05)
	t.tween_property(_fill, "light_energy", base, 0.2)

# sparks from somewhere on the console, with a flash
func _event_spark() -> void:
	_play("spark", -12.0)
	var at: Vector3 = Vector3(randf_range(-0.7, 0.7), 0.75, randf_range(-0.25, 0.25))
	var burst: CPUParticles3D = CPUParticles3D.new()
	burst.one_shot = true
	burst.amount = 24
	burst.lifetime = 0.5
	burst.explosiveness = 0.95
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 70.0
	burst.initial_velocity_min = 0.3
	burst.initial_velocity_max = 0.9
	burst.gravity = Vector3(0, -2.5, 0)
	burst.scale_amount_min = 0.004
	burst.scale_amount_max = 0.008
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	sm.material = mat
	burst.mesh = sm
	burst.position = at
	add_child(burst)
	burst.emitting = true
	var flash: OmniLight3D = OmniLight3D.new()
	flash.position = at + Vector3(0, 0.05, 0)
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.omni_range = 0.6
	flash.light_energy = 2.5
	add_child(flash)
	var t: Tween = create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.35)
	t.tween_callback(func() -> void:
		flash.queue_free()
		burst.queue_free())

## Power up to the game's levels: a flicker, then lights, ambient and stars
## rise together. Await the returned signal before switching to the game.
func wake_up() -> Signal:
	_awake = true
	if has_meta(&"_idle"):
		(get_meta(&"_idle") as Tween).kill()
	# the power-up outlasts the menu (its thump lands as the game appears): it
	# moves up to the scene tree's root, so the scene change doesn't cut it off
	var power: AudioStreamPlayer = _sfx.get("ship_power_up") as AudioStreamPlayer
	if power:
		power.reparent(get_tree().root)
		power.volume_db = -4.0
		power.play()
		power.finished.connect(power.queue_free)
	if _hum:
		create_tween().tween_property(_hum, "volume_db", HUM_DB + 8.0, WAKE_SEC)
	create_tween().tween_property(self, "_sway", 0.0, WAKE_SEC).set_trans(Tween.TRANS_SINE)
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
