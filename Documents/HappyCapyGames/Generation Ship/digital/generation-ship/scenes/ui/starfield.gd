extends Control

const STAR_COUNT  := 220
const SEED        := 7391
const LAYER_SPEED: Array = [0.010, 0.030, 0.080]

var _stars: Array = []
var _time: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -100
	_generate()

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_stars.clear()
	for _i: int in STAR_COUNT:
		var layer: int = rng.randi_range(0, 2)
		_stars.append({
			"nx":      rng.randf(),
			"ny":      rng.randf(),
			"layer":   layer,
			"radius":  [0.55, 1.1, 1.8][layer],
			"base_a":  [0.35, 0.55, 0.85][layer],
			"twinkle": rng.randf_range(0.4, 1.6),
			"phase":   rng.randf_range(0.0, TAU),
			"warm":    rng.randf() < 0.12,
		})


func _process(delta: float) -> void:
	_time += delta
	for s: Dictionary in _stars:
		s.nx += LAYER_SPEED[s.layer] * delta
		if s.nx > 1.06:
			s.nx = -0.06
	queue_redraw()

func _draw() -> void:
	var sz := size
	if sz.x < 1 or sz.y < 1:
		return

	for s: Dictionary in _stars:
		var t: float = sin(_time * s.twinkle + s.phase) * 0.5 + 0.5
		var alpha: float = lerpf(s.base_a * 0.55, s.base_a, t)
		var col: Color
		if s.warm:
			col = Color(1.0, 0.92, 0.78, alpha)
		else:
			col = Color(0.82, 0.90, 1.00, alpha)
		var pos := Vector2(s.nx * sz.x, s.ny * sz.y)
		var r: float = s.radius
		if s.layer >= 1:
			var tail_len: float = r * (3.0 if s.layer == 2 else 1.5)
			var tail: Vector2 = pos - Vector2(tail_len, 0.0)
			var streak_col: Color = col
			streak_col.a *= 0.4
			draw_line(tail, pos, streak_col, r * 0.6)
		if r < 1.0:
			draw_rect(Rect2(pos, Vector2.ONE), col)
		else:
			draw_circle(pos, r, col)
