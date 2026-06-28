extends MeshInstance3D

const FRAME_COUNT: int = 310
const FPS: float = 12.0

var _frame: int = 0
var _elapsed: float = 0.0
var _mat: StandardMaterial3D = null

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 3.0)
	mesh = quad

	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.no_depth_test = false
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_surface_override_material(0, _mat)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_advance_frame()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0 / FPS:
		_elapsed -= 1.0 / FPS
		_frame = (_frame + 1) % FRAME_COUNT
		_advance_frame()

func _advance_frame() -> void:
	_mat.albedo_texture = ResourceLoader.load(
		"res://assets/sun/%04d.png" % (_frame + 1),
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
