extends SceneTree

## One-off visual probe: renders the hex mesh with uv1_offset.y=0.0 next to
## uv1_offset.y=0.5, using Bruthgaard.png (already confirmed by direct
## image read: TOP half = teal "UNEXPLORED" art, BOTTOM half = red
## "BRUTHGAARD" explored art) - so whichever offset shows the red
## volcano is EXPLORED_V_OFFSET.
## Run (NOT headless): godot --path . --script res://tools/hex_texture_probe.gd --rendering-driver d3d12

const HEX_MESH_PATH := "res://assets/images/3d/hex.obj"
const TEX_PATH := "res://assets/images/Uprising+Final+EN/CORE_BOX_EN/HEXES_EN_TTS/Regular/Bruthgaard.png"

func _initialize() -> void:
	await process_frame
	await process_frame

	var mesh: Mesh = load(HEX_MESH_PATH)
	var tex: Texture2D = load(TEX_PATH)
	if mesh == null or tex == null:
		printerr("hex_texture_probe: failed to load mesh or texture")
		quit(1)
		return

	var world := Node3D.new()
	root.add_child(world)

	var offsets: Array[float] = [0.0, 0.5]
	for i: int in range(offsets.size()):
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		world.add_child(inst)
		inst.position = Vector3(i * 5.0, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(1, 0.5, 1)
		mat.uv1_offset = Vector3(0, offsets[i], 0)
		inst.material_override = mat

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(light)

	var cam := Camera3D.new()
	cam.position = Vector3(2.5, 8, 0.1)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	world.add_child(cam)

	for i: int in range(10):
		await process_frame

	var img: Image = root.get_texture().get_image()
	img.save_png("user://hex_texture_probe.png")
	print("saved user://hex_texture_probe.png - left = offset 0.0, right = offset 0.5")
	quit(0)
