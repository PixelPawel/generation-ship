class_name ScifiPanel
extends PanelContainer

const CLIP_SZ := 10.0
const COL_BG  := Color(0.03, 0.04, 0.09, 0.93)

var _style: StyleBoxFlat = null

func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color.TRANSPARENT
	_style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", _style)
	resized.connect(queue_redraw)
	theme = GameTheme.get_theme()

func set_content_margin(m: int) -> void:
	if _style:
		_style.set_content_margin_all(m)

func _draw() -> void:
	var sz := size
	if sz.x < 1 or sz.y < 1:
		return
	var cs := CLIP_SZ

	draw_colored_polygon(PackedVector2Array([
		Vector2(cs, 0),           Vector2(sz.x - cs, 0),
		Vector2(sz.x, cs),        Vector2(sz.x, sz.y - cs),
		Vector2(sz.x - cs, sz.y), Vector2(cs, sz.y),
		Vector2(0, sz.y - cs),    Vector2(0, cs),
	]), COL_BG)

