extends Control
# The "do this here" marker for a 2D slot (the market screen's
# sector and expedition slots): a glowing gold outline that pulses, a soft
# breathing fill and four corner brackets that move in and out — readable at
# a glance on the small in-world screen, unlike the old flat tint. Fills its
# parent; ignores the mouse. Only animates while visible.

const GOLD: Color = Color(1.0, 0.82, 0.3)
const PEAK: Color = Color(1.0, 0.97, 0.85)
# The game's own "pick a slot" prompts (revealing a sector or expedition) use it
# too, in green: set tint before it's shown.
var tint: Color = GOLD
const PULSE_SPEED: float = 3.2      # radians per second
const BORDER: float = 4.0
const GLOW_RINGS: int = 3           # soft rings outside the outline
const CORNER_LEN: float = 0.22      # bracket arm, share of the shorter side
const BRACKET_TRAVEL: float = 6.0   # px the brackets breathe outward

var _t: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func() -> void:
		set_process(visible)
		_t = 0.0)
	set_process(visible)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_t * PULSE_SPEED)
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	# breathing fill
	draw_rect(r, Color(tint.r, tint.g, tint.b, lerpf(0.06, 0.18, pulse)))
	# glow rings, fading outward
	for i: int in GLOW_RINGS:
		var grow: float = BORDER + 3.0 * float(i + 1)
		var a: float = lerpf(0.10, 0.28, pulse) * (1.0 - float(i) / float(GLOW_RINGS))
		draw_rect(r.grow(grow), Color(tint.r, tint.g, tint.b, a), false, 3.0)
	# the outline itself, flaring towards white at the peak
	var peak: Color = tint.lerp(Color.WHITE, 0.8)
	draw_rect(r.grow(BORDER * 0.5), tint.lerp(peak, pulse * 0.6), false, BORDER)
	# corner brackets
	var arm: float = minf(size.x, size.y) * CORNER_LEN
	var out: float = BORDER + 4.0 + BRACKET_TRAVEL * pulse
	var col: Color = peak.lerp(tint, pulse)
	var w: float = BORDER + 1.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var sx: float = -1.0 if corner.x == 0.0 else 1.0
		var sy: float = -1.0 if corner.y == 0.0 else 1.0
		var p: Vector2 = Vector2(corner.x * size.x, corner.y * size.y) + Vector2(sx, sy) * out
		draw_line(p, p - Vector2(sx * arm, 0.0), col, w, true)
		draw_line(p, p - Vector2(0.0, sy * arm), col, w, true)
