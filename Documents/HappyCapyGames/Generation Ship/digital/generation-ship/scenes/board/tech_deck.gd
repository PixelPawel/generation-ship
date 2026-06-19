extends Node3D

const CARD_W := 0.63
const CARD_H := 0.88

var _cards: Array[CardData] = []
var _count_label: Label3D = null
var _mat: StandardMaterial3D = null
var _back_url: String = ""

func _ready() -> void:
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(CARD_W, CARD_H)
	mesh_inst.mesh = quad
	mesh_inst.rotation_degrees.x = -90
	mesh_inst.position.y = 0.02
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.12, 0.28)
	_mat.emission_enabled = true
	_mat.emission = Color(0.04, 0.06, 0.18)
	_mat.emission_energy_multiplier = 0.6
	mesh_inst.set_surface_override_material(0, _mat)
	add_child(mesh_inst)

	_count_label = Label3D.new()
	_count_label.font_size = 48
	_count_label.modulate = Color(0.8, 0.85, 1.0)
	_count_label.position = Vector3(0, 0.03, 0)
	_count_label.rotation_degrees.x = -90
	_count_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_count_label.text = "0"
	add_child(_count_label)

func setup(cards: Array[CardData], back_url: String = "") -> void:
	_cards = cards.duplicate()
	_cards.shuffle()
	_update_label()
	_apply_back_url(back_url)

func _on_cache_loaded() -> void:
	var tex: ImageTexture = ImageCache.get_texture(_back_url)
	if tex:
		_apply_back_texture(tex)

func _apply_back_texture(tex: ImageTexture) -> void:
	if _mat:
		_mat.albedo_texture = tex
		_mat.albedo_color = Color.WHITE
		_mat.emission_enabled = false

func setup_ordered(cards: Array[CardData], order: Array, back_url: String = "") -> void:
	_cards = []
	for idx: Variant in order:
		var i: int = int(idx)
		if i >= 0 and i < cards.size():
			_cards.append(cards[i])
	_update_label()
	_apply_back_url(back_url)

func _apply_back_url(url: String) -> void:
	if url.is_empty():
		return
	_back_url = url
	var cached: ImageTexture = ImageCache.get_texture(url)
	if cached:
		_apply_back_texture(cached)
	else:
		ImageCache.all_loaded.connect(_on_cache_loaded, CONNECT_ONE_SHOT)

func refill(cards: Array[CardData]) -> void:
	_cards = cards.duplicate()
	_cards.shuffle()
	_update_label()

func draw_card() -> CardData:
	if _cards.is_empty():
		return null
	var card: CardData = _cards.pop_back()
	_update_label()
	return card

func shuffle_in(data: CardData) -> int:
	var idx: int = randi() % (_cards.size() + 1)
	_cards.insert(idx, data)
	_update_label()
	return idx

func insert_at(data: CardData, idx: int) -> void:
	_cards.insert(clampi(idx, 0, _cards.size()), data)
	_update_label()

func remaining() -> int:
	return _cards.size()

func _update_label() -> void:
	if _count_label:
		_count_label.text = str(_cards.size())
