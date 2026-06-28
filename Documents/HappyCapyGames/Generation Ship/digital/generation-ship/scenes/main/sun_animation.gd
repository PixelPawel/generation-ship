extends Sprite3D

const FRAME_COUNT: int = 310
const FPS: float = 12.0

var _frame: int = 0
var _elapsed: float = 0.0

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	no_depth_test = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pixel_size = 0.0072
	texture = _load_frame(0)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0 / FPS:
		_elapsed -= 1.0 / FPS
		_frame = (_frame + 1) % FRAME_COUNT
		texture = _load_frame(_frame)

func _load_frame(idx: int) -> Texture2D:
	return ResourceLoader.load(
		"res://assets/sun/%04d.png" % (idx + 1),
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
