extends Node3D

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 500.0
	sphere.height = 1000.0
	sphere.radial_segments = 64
	sphere.rings = 32

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/starfield.gdshader")
	mat.set_shader_parameter("speed", 0.012)
	mat.set_shader_parameter("emission_str", 22.0)
	mat.set_shader_parameter("star_density", 0.05)
	mat.set_shader_parameter("travel_dir", Vector3(0.0, -1.0, 0.0))

	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
