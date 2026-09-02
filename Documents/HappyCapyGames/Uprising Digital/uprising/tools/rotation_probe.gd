extends SceneTree

## One-off visual probe: renders the same standee mesh with several
## candidate rotations side by side from a strictly LEVEL camera (pitch 0)
## so a card lying flat on the ground reads as a near-invisible sliver and
## a genuinely upright card reads as a full clear profile - the first probe
## used a downward-tilted camera, which made a flat-lying card look
## deceptively "upright enough" and gave a wrong answer.
## Run (NOT headless): godot --path . --script res://tools/rotation_probe.gd --rendering-driver d3d12

const MODEL_PATH := "res://assets/models/Moyhar/hanzo/Hanzo.obj"

func _initialize() -> void:
	await process_frame
	await process_frame

	var mesh: Mesh = load(MODEL_PATH)
	if mesh == null:
		printerr("rotation_probe: could not load %s" % MODEL_PATH)
		quit(1)
		return
	print("mesh AABB: %s" % mesh.get_aabb())

	var world := Node3D.new()
	root.add_child(world)

	var candidates: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(180, 0, 0),
		Vector3(90, 0, 180), Vector3(-90, 0, 180), Vector3(0, 0, 90), Vector3(0, 0, -90),
	]
	var spacing := 3.5
	for i: int in range(candidates.size()):
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		world.add_child(inst)
		inst.position = Vector3((i - (candidates.size() - 1) / 2.0) * spacing, 0, 0)
		inst.rotation_degrees = candidates[i]

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(32, 8)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.18)
	ground.material_override = mat
	ground.position = Vector3(0, -0.05, 0)
	world.add_child(ground)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -20, 0)
	world.add_child(light)
	var light2 := OmniLight3D.new()
	light2.position = Vector3(0, 3, 6)
	light2.omni_range = 40
	world.add_child(light2)

	# Strictly level (pitch 0), positioned at roughly standee eye-height,
	# far enough back to see the full 32-unit-wide row.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 16)
	cam.rotation_degrees = Vector3(0, 0, 0)
	cam.fov = 55
	cam.current = true
	world.add_child(cam)

	for i: int in range(10):
		await process_frame

	var img: Image = root.get_texture().get_image()
	img.save_png("user://rotation_probe2.png")
	print("rotation_probe: saved user://rotation_probe2.png")
	print("labels left-to-right: %s" % [candidates])
	quit(0)
