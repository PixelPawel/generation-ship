class_name DiceMesh
extends RefCounted
## Builds a plain cube MeshInstance3D wearing one of the extracted TTS dice
## textures (assets/images/Uprising+Final+EN/CORE_BOX_EN/DICE) -- a simple
## textured-cube visual, not tied to DiceModel's roll logic yet.
##
## Every one of those textures packs its 6 face symbols into a 3-column x
## 2-row grid on a square image (confirmed by inspecting the grid lines
## against d6_black.png, d6_blue.png and new_gold-die.jpg). That happens to
## be exactly BoxMesh's own default per-face UV layout (confirmed by
## dumping BoxMesh.get_mesh_arrays(): each of its 6 faces already occupies
## a distinct 1/3 x 1/2 rect), so a stock BoxMesh with the texture as
## albedo needs no custom UVs at all -- verified by rendering it face-on
## and isometric and checking each visible face shows a different symbol.


static func build(texture: Texture2D, size: float = 1.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(size, size, size)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.6

	var inst := MeshInstance3D.new()
	inst.mesh = box
	inst.set_surface_override_material(0, mat)
	return inst
