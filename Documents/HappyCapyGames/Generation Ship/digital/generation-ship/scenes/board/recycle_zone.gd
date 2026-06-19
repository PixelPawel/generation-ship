extends Node3D

const CARD_W := 0.63
const CARD_H := 0.88

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _title_label: Label3D
var _count_label: Label3D
var _discard_count: int = 0
var _has_texture: bool = false
var _discarded_cards: Array[CardData] = []

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_W, CARD_H)
	_mesh.mesh = quad
	_mesh.position.y = 0.02
	_mesh.rotation_degrees.x = -90
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(0.12, 0.06, 0.06, 1.0)
	_mesh.set_surface_override_material(0, _mat)
	add_child(_mesh)

	_title_label = Label3D.new()
	_title_label.visible = false
	add_child(_title_label)

	_count_label = Label3D.new()
	_count_label.font_size = 52
	_count_label.modulate = Color(0.9, 0.6, 0.55)
	_count_label.position = Vector3(0, 0.03, 0.05)
	_count_label.rotation_degrees.x = -90
	_count_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_count_label.text = "0"
	add_child(_count_label)

func add_discard(card_data: CardData = null) -> void:
	_discard_count += 1
	_count_label.text = str(_discard_count)
	if card_data == null:
		return
	_discarded_cards.append(card_data)
	var url: String = card_data.image_url
	if url.is_empty():
		return
	var tex: ImageTexture = ImageCache.get_texture(url)
	if tex:
		_apply_texture(tex)

func take_all_cards() -> Array[CardData]:
	var result: Array[CardData] = _discarded_cards.duplicate()
	_discarded_cards.clear()
	_discard_count = 0
	_count_label.text = "0"
	_count_label.font_size = 52
	_count_label.modulate = Color(0.9, 0.6, 0.55)
	_count_label.position = Vector3(0, 0.03, 0.05)
	_has_texture = false
	_mat.albedo_texture = null
	_mat.albedo_color = Color(0.12, 0.06, 0.06, 1.0)
	return result

func _apply_texture(tex: ImageTexture) -> void:
	_has_texture = true
	_mat.albedo_texture = tex
	_mat.albedo_color = Color.WHITE
	_title_label.visible = false
	_count_label.font_size = 28
	_count_label.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_count_label.position = Vector3(0, 0.035, 0.36)

func highlight(on: bool) -> void:
	if on:
		_mat.albedo_color = Color(1.0, 0.5, 0.5) if _has_texture else Color(1.0, 0.25, 0.15)
	else:
		_mat.albedo_color = Color.WHITE if _has_texture else Color(0.12, 0.06, 0.06)
