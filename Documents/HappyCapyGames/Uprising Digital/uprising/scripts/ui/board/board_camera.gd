extends Camera3D

## Orbit camera for the play board. Right-drag (or Q / E) turns around the
## table, middle-drag or WASD / arrow keys pan, the wheel zooms, F or Home
## reframes the whole board. Left click is left alone for selecting hexes.
## Every move eases toward its target; shake() adds a short tremor for big
## board events (vfx_effect.gd calls it).

@export var target: Vector3 = Vector3(0.0, 0.0, 1.6)
@export var yaw_deg: float = 0.0
@export var pitch_deg: float = 54.0
@export var distance: float = 28.0
@export var min_distance: float = 7.0
@export var max_distance: float = 44.0
@export var min_pitch: float = 28.0
@export var max_pitch: float = 82.0
@export var board_limit: float = 12.0
## Fraction of the screen width the board is pushed right so it clears the
## HUD panel on the left.
@export var hud_clearance: float = 0.12
@export var smoothing: float = 9.0

var _goal_target: Vector3
var _goal_yaw: float
var _goal_pitch: float
var _goal_distance: float
var _home_target: Vector3
var _home_yaw: float
var _home_pitch: float
var _home_distance: float
var _orbiting: bool = false
var _panning: bool = false
var _shake: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	fov = 36.0
	near = 0.3
	far = 220.0
	_home_target = target
	_home_yaw = yaw_deg
	_home_pitch = pitch_deg
	_home_distance = distance
	_goal_target = target
	_goal_yaw = yaw_deg
	_goal_pitch = pitch_deg
	_goal_distance = distance
	_rng.randomize()
	_apply()


## Azimuth (radians) the board's standees turn to face.
func get_yaw() -> float:
	return deg_to_rad(yaw_deg)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func reframe() -> void:
	_goal_target = _home_target
	_goal_yaw = _home_yaw
	_goal_pitch = _home_pitch
	_goal_distance = _home_distance


func focus_on(world_pos: Vector3) -> void:
	_goal_target = Vector3(world_pos.x, 0.0, world_pos.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_goal_distance = clampf(_goal_distance * 0.88, min_distance, max_distance)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_goal_distance = clampf(_goal_distance / 0.88, min_distance, max_distance)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _orbiting:
			_goal_yaw -= mm.relative.x * 0.3
			_goal_pitch = clampf(_goal_pitch + mm.relative.y * 0.2, min_pitch, max_pitch)
		if _panning:
			var k: float = _goal_distance * 0.0017
			_pan(Vector2(-mm.relative.x, -mm.relative.y) * k)
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_F or key.keycode == KEY_HOME):
			reframe()


## Pan in the screen's directions projected onto the table.
func _pan(screen_delta: Vector2) -> void:
	var yaw: float = deg_to_rad(_goal_yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_goal_target += right * screen_delta.x - forward * screen_delta.y


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	if move != Vector2.ZERO:
		_pan(move.normalized() * _goal_distance * 0.7 * delta)
	if Input.is_key_pressed(KEY_Q):
		_goal_yaw += 70.0 * delta
	if Input.is_key_pressed(KEY_E):
		_goal_yaw -= 70.0 * delta

	var flat := Vector2(_goal_target.x, _goal_target.z)
	if flat.length() > board_limit:
		flat = flat.normalized() * board_limit
		_goal_target = Vector3(flat.x, 0.0, flat.y)

	var k: float = 1.0 - exp(-smoothing * delta)
	target = target.lerp(_goal_target, k)
	yaw_deg = lerpf(yaw_deg, _goal_yaw, k)
	pitch_deg = lerpf(pitch_deg, _goal_pitch, k)
	distance = lerpf(distance, _goal_distance, k)
	_shake = maxf(_shake - delta * 2.2, 0.0)
	_apply()


func _apply() -> void:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var look: Vector3 = target
	if _shake > 0.0:
		var s: float = _shake * _shake * 0.5
		look += Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s) * 0.5, _rng.randf_range(-s, s))
	global_transform = Transform3D(Basis(), target + offset).looking_at(look, Vector3.UP)
	var vp: Viewport = get_viewport()
	var aspect: float = 16.0 / 9.0
	if vp != null:
		var vs: Vector2 = vp.get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	var half_w: float = distance * tan(deg_to_rad(fov) * 0.5) * aspect
	h_offset = -hud_clearance * 2.0 * half_w
