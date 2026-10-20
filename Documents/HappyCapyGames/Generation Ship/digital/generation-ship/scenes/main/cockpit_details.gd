extends Node3D
# The cockpit's dash consoles, strut columns and running lights, laid on the old
# shell. Built and baked in Blender (Render/cockpit/build_cockpit.py → panels.py,
# export_details.py → gs_ui_cockpit_details.glb + assets/3d/cockpit_details/).
# A child of UiCockpit in its local space, so it rumbles with the shell; without
# this node the cockpit is the old plain one (main.tscn of 2026-10-20 is kept in
# digital/_backups/old_cockpit_2026-10-20). The lamps run in the shader on the
# loop baked into schedule.png — nothing ticks here.

const MODEL: PackedScene = preload("res://assets/3d/gs_ui_cockpit_details.glb")
const SHADER: Shader = preload("res://shaders/cockpit_details.gdshader")
const ALBEDO: Texture2D = preload("res://assets/3d/cockpit_details/albedo.png")
const RM: Texture2D = preload("res://assets/3d/cockpit_details/rm.png")
const EMIT: Texture2D = preload("res://assets/3d/cockpit_details/emit.png")
const SCHEDULE: Texture2D = preload("res://assets/3d/cockpit_details/schedule.png")
# glb mesh name -> shader mode (cockpit_details.gdshader)
const MODES: Dictionary = {"Panels": 0, "ScreenWave": 1, "ScreenRadar": 2, "Accents": 3}
const GLASS_COLOR: Color = Color(0.33, 0.31, 0.28, 0.12)   # dusty gauge / scope glass

## Blender emission strength → Godot emission energy (lamps, screens, light strips)
@export var glow: float = 0.45

func _ready() -> void:
	var model: Node3D = MODEL.instantiate() as Node3D
	add_child(model)
	var mats: Dictionary = {}
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var key: String = _mode_key(String(mi.name))
		if key.is_empty():
			mi.material_override = _glass_material()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if not mats.has(key):
			mats[key] = _panel_material(int(MODES[key]))
		mi.material_override = mats[key] as Material
		if key != "Panels":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# "Panels", "ScreenWave"... (import may add a suffix); "" = glass
static func _mode_key(mesh_name: String) -> String:
	for key: String in MODES:
		if mesh_name.begins_with(key):
			return key
	return ""

func _panel_material(mode: int) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("albedo_tex", ALBEDO)
	mat.set_shader_parameter("rm_tex", RM)
	mat.set_shader_parameter("emit_tex", EMIT)
	mat.set_shader_parameter("schedule_tex", SCHEDULE)
	mat.set_shader_parameter("glow", glow)
	return mat

static func _glass_material() -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = GLASS_COLOR
	mat.roughness = 0.15
	return mat
