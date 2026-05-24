extends CPUParticles3D

var particle_color: Color = Color(1.0, 0.85, 0.05)

func _ready() -> void:
	one_shot      = true
	explosiveness = 0.92
	amount        = 55
	lifetime      = 0.7
	randomness    = 0.4

	emission_shape         = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.12

	direction = Vector3(0.0, 1.0, 0.0)
	spread    = 120.0
	flatness  = 0.0
	gravity   = Vector3(0.0, -6.0, 0.0)

	initial_velocity_min = 2.5
	initial_velocity_max = 5.5

	damping_min = 2.0
	damping_max = 4.0

	scale_amount_min = 0.02
	scale_amount_max = 0.055

	var c0: Color = particle_color.lightened(0.35)
	c0.a = 1.0
	var c2: Color = particle_color.darkened(0.25)
	c2.a = 0.8
	var c3: Color = Color(c2.r * 0.5, c2.g * 0.3, c2.b * 0.2, 0.0)
	var gradient := Gradient.new()
	gradient.set_color(0, c0)
	gradient.add_point(0.15, particle_color)
	gradient.add_point(0.55, c2)
	gradient.add_point(1.00, c3)
	color_ramp = gradient

	var mesh := CapsuleMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.9
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = particle_color
	mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	self.mesh = mesh

	emitting = true
	get_tree().create_timer(lifetime + 0.3).timeout.connect(queue_free)
