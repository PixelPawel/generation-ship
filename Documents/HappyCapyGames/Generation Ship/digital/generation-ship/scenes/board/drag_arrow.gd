class_name DragArrow
extends Node2D

const _SEG: int = 30
const _DOT_BASE: float = 5.0
const _DOT_AMP: float = 3.5
const _SPEED: float = 2.0
const _ARROWHEAD: float = 22.0
const _COL_A: Color = Color(0.2, 0.72, 1.0, 0.9)
const _COL_B: Color = Color(0.45, 1.0, 0.88, 1.0)
const _COL_HEAD: Color = Color(0.3, 0.88, 1.0, 1.0)

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _active: bool = false
var _t: float = 0.0

func _process(delta: float) -> void:
	if _active:
		_t += delta
		queue_redraw()

func _draw() -> void:
	if not _active:
		return

	var span_y: float = absf(_to.y - _from.y)
	var ctrl: float = maxf(span_y * 0.5, 80.0)
	var p0: Vector2 = _from
	var p1: Vector2 = _from + Vector2(0.0, -ctrl)
	var p2: Vector2 = _to + Vector2(0.0, ctrl * 0.6)
	var p3: Vector2 = _to

	for i: int in _SEG:
		var t: float = float(i) / float(_SEG - 1)
		var pt: Vector2 = _cbez(p0, p1, p2, p3, t)
		var phase: float = fmod(t * 2.5 - _t * _SPEED * 0.2, 1.0)
		if phase < 0.0:
			phase += 1.0
		var pulse: float = sin(phase * PI)
		var r: float = _DOT_BASE + _DOT_AMP * pulse
		var col: Color = _COL_A.lerp(_COL_B, t)
		col.a = col.a * (0.4 + 0.6 * pulse)
		draw_circle(pt, r, col)

	var near: Vector2 = _cbez(p0, p1, p2, p3, 0.97)
	var dir: Vector2 = (p3 - near).normalized()
	if dir.length_squared() < 0.001:
		return
	var perp: Vector2 = dir.rotated(PI * 0.5)
	draw_colored_polygon(
		PackedVector2Array([
			p3,
			p3 - dir * _ARROWHEAD + perp * _ARROWHEAD * 0.5,
			p3 - dir * _ARROWHEAD - perp * _ARROWHEAD * 0.5,
		]),
		_COL_HEAD
	)

func _cbez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var m: float = 1.0 - t
	return m*m*m*p0 + 3.0*m*m*t*p1 + 3.0*m*t*t*p2 + t*t*t*p3

func show_arrow(from: Vector2, to: Vector2) -> void:
	_from = from
	_to = to
	_active = true

func update_to(to: Vector2) -> void:
	_to = to

func hide_arrow() -> void:
	_active = false
	queue_redraw()
