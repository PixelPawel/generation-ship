extends Node3D

## One-shot board effect, configured entirely from the inspector so each
## assets/vfx/scenes/*.tscn is just this script plus numbers: a Mantaflow
## flipbook (Blender-rendered, see Render/vfx), a ground shockwave ring, a
## light-ray burst, sparks or embers (GPUParticles3D), a light flash and an
## optional camera shake. Every part is optional; the node frees itself
## after `duration`. Spawn through vfx_library.gd.

const FLIPBOOK_SHADER := "res://scripts/ui/shaders/vfx_flipbook.gdshader"
const RING_SHADER := "res://scripts/ui/shaders/vfx_ring.gdshader"
const RAYS_SHADER := "res://scripts/ui/shaders/vfx_rays.gdshader"

@export var duration: float = 2.0
@export var size_scale: float = 1.0

@export_group("Flipbook")
@export var sheet: Texture2D
@export var sheet_height: float = 3.0
@export var sheet_time: float = 1.8
@export var sheet_delay: float = 0.0
@export var smoke_color: Color = Color(0.78, 0.8, 0.84)
@export var glow_color: Color = Color(0.6, 1.0, 0.2)
@export var glow_energy: float = 0.0
@export var smoke_opacity: float = 0.9

@export_group("Ring")
@export var ring_radius: float = 0.0
@export var ring_color: Color = Color(1.0, 0.3, 0.8)
@export var ring_energy: float = 3.0
@export var ring_time: float = 0.7

@export_group("Rays")
@export var rays_size: float = 0.0
@export var rays_color: Color = Color(1.0, 0.85, 0.5)
@export var rays_energy: float = 2.5
@export var rays_time: float = 1.0
@export var rays_height: float = 1.0

@export_group("Sparks")
@export var spark_count: int = 0
@export var spark_color: Color = Color(1.0, 0.85, 0.55)
@export var spark_energy: float = 4.0
@export var spark_size: float = 0.06
@export var spark_speed: float = 4.0
@export var spark_spread: float = 70.0
@export var spark_gravity: float = -7.0
@export var spark_lifetime: float = 0.9
@export var spark_height: float = 0.4

@export_group("Light")
@export var light_energy: float = 0.0
@export var light_color: Color = Color(1.0, 0.6, 0.9)
@export var light_range: float = 6.0
@export var light_time: float = 0.8

@export_group("Camera")
@export var shake: float = 0.0

var _t: float = 0.0
var _flipbook: MeshInstance3D
var _ring: MeshInstance3D
var _rays: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	var s: float = size_scale
	if sheet != null:
		_flipbook = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		q.center_offset = Vector3(0.0, 0.5, 0.0)
		_flipbook.mesh = q
		_flipbook.scale = Vector3.ONE * sheet_height * s
		_flipbook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fm := ShaderMaterial.new()
		fm.shader = load(FLIPBOOK_SHADER) as Shader
		fm.set_shader_parameter("sheet", sheet)
		fm.set_shader_parameter("smoke_color", smoke_color)
		fm.set_shader_parameter("glow_color", glow_color)
		fm.set_shader_parameter("glow_energy", glow_energy)
		fm.set_shader_parameter("opacity", smoke_opacity)
		_flipbook.material_override = fm
		_flipbook.visible = sheet_delay <= 0.0
		add_child(_flipbook)
	if ring_radius > 0.0:
		_ring = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0) * ring_radius * s
		_ring.mesh = pm
		_ring.position.y = 0.02
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var rm := ShaderMaterial.new()
		rm.shader = load(RING_SHADER) as Shader
		rm.set_shader_parameter("ring_color", ring_color)
		rm.set_shader_parameter("energy", ring_energy)
		_ring.material_override = rm
		add_child(_ring)
	if rays_size > 0.0:
		_rays = MeshInstance3D.new()
		var rq := QuadMesh.new()
		rq.size = Vector2(1.0, 1.0)
		_rays.mesh = rq
		_rays.scale = Vector3.ONE * rays_size * s
		_rays.position.y = rays_height * s
		_rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ym := ShaderMaterial.new()
		ym.shader = load(RAYS_SHADER) as Shader
		ym.set_shader_parameter("ray_color", rays_color)
		ym.set_shader_parameter("energy", rays_energy)
		_rays.material_override = ym
		add_child(_rays)
	if spark_count > 0:
		add_child(_make_sparks(s))
	if light_energy > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = light_color
		_light.light_energy = light_energy
		_light.omni_range = light_range * s
		_light.position.y = 1.0 * s
		_light.shadow_enabled = false
		add_child(_light)
	if shake > 0.0:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null and cam.has_method("shake"):
			cam.call("shake", shake)
	_update(0.0)


func _process(delta: float) -> void:
	_t += delta
	_update(_t)
	if _t >= duration:
		queue_free()


func _update(t: float) -> void:
	if _flipbook != null:
		var local: float = t - sheet_delay
		_flipbook.visible = local >= 0.0 and local <= sheet_time
		_flipbook.set_instance_shader_parameter("progress", clampf(local / maxf(sheet_time, 0.01), 0.0, 1.0))
	if _ring != null:
		_ring.visible = t <= ring_time
		_ring.set_instance_shader_parameter("progress", clampf(t / maxf(ring_time, 0.01), 0.0, 1.0))
	if _rays != null:
		_rays.visible = t <= rays_time
		_rays.set_instance_shader_parameter("progress", clampf(t / maxf(rays_time, 0.01), 0.0, 1.0))
	if _light != null:
		var k: float = clampf(t / maxf(light_time, 0.01), 0.0, 1.0)
		# fast attack, slow decay
		var env: float = minf(k * 8.0, 1.0) * (1.0 - k) * (1.0 - k)
		_light.light_energy = light_energy * env
		_light.visible = k < 1.0


func _make_sparks(s: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = spark_count
	p.lifetime = spark_lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.4
	p.local_coords = false
	p.position.y = spark_height * s
	p.visibility_aabb = AABB(Vector3(-6, -1, -6) * s, Vector3(12, 10, 12) * s)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25 * s
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = spark_spread
	pm.initial_velocity_min = spark_speed * 0.45 * s
	pm.initial_velocity_max = spark_speed * s
	pm.gravity = Vector3(0.0, spark_gravity * s, 0.0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.6, Color(1, 1, 1, 0.85))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	pm.turbulence_enabled = spark_gravity > 0.0
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(spark_size, spark_size) * s
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(spark_color.r * spark_energy, spark_color.g * spark_energy, spark_color.b * spark_energy, 1.0)
	dm.albedo_texture = _dot_texture()
	quad.material = dm
	p.draw_pass_1 = quad
	p.emitting = true
	return p


static var _dot: GradientTexture2D = null


static func _dot_texture() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.9))
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.width = 32
		_dot.height = 32
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(0.5, 0.0)
	return _dot
