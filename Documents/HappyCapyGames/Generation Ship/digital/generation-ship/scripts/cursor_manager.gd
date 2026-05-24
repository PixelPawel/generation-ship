extends Node

# Procedurally generated sci-fi arrow cursors.
# Shape: right-angle triangle, tip at top-left (hotspot 0,0), opens toward bottom-right.

const _SIZE    := 20
const _N       := 14   # rows of shape; bottom edge is row _N

const _FILL_DEFAULT    := Color(0.40, 0.62, 0.95, 0.90)
const _OUTLINE_DEFAULT := Color(0.92, 0.96, 1.00, 1.00)
const _FILL_HOVER      := Color(0.22, 0.88, 0.55, 0.90)
const _OUTLINE_HOVER   := Color(0.80, 1.00, 0.88, 1.00)

var _default_tex: ImageTexture = null
var _hover_tex:   ImageTexture = null

func _ready() -> void:
	_default_tex = _build(_FILL_DEFAULT, _OUTLINE_DEFAULT)
	_hover_tex   = _build(_FILL_HOVER,   _OUTLINE_HOVER)
	set_default()

func set_default() -> void:
	Input.set_custom_mouse_cursor(_default_tex, Input.CURSOR_ARROW, Vector2.ZERO)

func set_hover() -> void:
	Input.set_custom_mouse_cursor(_hover_tex, Input.CURSOR_ARROW, Vector2.ZERO)

func _build(fill: Color, outline: Color) -> ImageTexture:
	var img := Image.create(_SIZE, _SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(_N + 1):
		if y < _N:
			img.set_pixel(0, y, outline)
			for x: int in range(1, y + 1):
				img.set_pixel(x, y, fill)
			img.set_pixel(y + 1, y, outline)
		else:
			for x: int in range(_N + 2):
				img.set_pixel(x, y, outline)
	return ImageTexture.create_from_image(img)
