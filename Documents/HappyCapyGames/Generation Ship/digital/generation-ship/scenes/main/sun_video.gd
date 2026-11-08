extends VideoPlayback

# Hand-tuned to sit centered on the cockpit's "porthole" glow at the 16:9
# aspect ratio this whole rig was laid out against (see
# CockpitRig.setup_responsive_screen_positions for the same problem applied
# to the control/info/log screens). Camera3D defaults to KEEP_HEIGHT, so a
# wider aspect ratio (e.g. phone landscape) reveals extra horizontal FOV the
# video's old hardcoded CanvasLayer offset/scale never accounted for,
# drifting it visibly left of center. Repositioned from this fixed reference
# NDC point every time the viewport resizes instead.
# Narrower than 16:9, CockpitRig widens the camera's vertical FOV so the 16:9
# width stays in view: the same formula here keeps the sun on the porthole
# (it had sat over the market screen at 16:10 and 4:3).
const _REFERENCE_ASPECT := 16.0 / 9.0
const _REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const _REFERENCE_SCREEN_CENTER := Vector2(958.15, 398.495)  # at _REFERENCE_SIZE
const _SCREEN_SIZE := Vector2(120.0, 90.0)  # 400x300 at the old 0.3 CanvasLayer scale

var _cam: Camera3D
var _base_fov: float = 45.0   # the scene's camera FOV, before CockpitRig changes it
var _layer: CanvasLayer = null

func _ready() -> void:
	super._ready()
	_shader_material.shader = load("res://shaders/yuv_to_rgb_additive.gdshader")
	size = _SCREEN_SIZE
	_cam = get_viewport().get_camera_3d()
	if _cam:
		_base_fov = _cam.fov
	get_viewport().size_changed.connect(_reposition)
	_reposition()
	# hidden (a card held up to the camera): stop decoding frames nobody sees
	_layer = get_parent() as CanvasLayer
	if _layer:
		_layer.visibility_changed.connect(_on_layer_visibility_changed)
		playback_started.connect(func() -> void:
			if not _layer.visible:
				pause())   # (auto-play once loaded, while hidden)

func _on_layer_visibility_changed() -> void:
	if _layer.visible:
		if is_open():
			play()
	else:
		pause()

func _reposition() -> void:
	if not _cam:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var aspect: float = vp_size.x / vp_size.y
	var ndc_ref: Vector2 = (_REFERENCE_SCREEN_CENTER / _REFERENCE_SIZE) * 2.0 - Vector2.ONE
	var half_vfov_ref: float = deg_to_rad(_base_fov) * 0.5
	var half_vfov_cur: float = half_vfov_ref
	if aspect < _REFERENCE_ASPECT:
		half_vfov_cur = atan(tan(half_vfov_ref) * _REFERENCE_ASPECT / aspect)
	var half_hfov_ref: float = atan(tan(half_vfov_ref) * _REFERENCE_ASPECT)
	var half_hfov_cur: float = atan(tan(half_vfov_cur) * aspect)
	var ndc_x_cur: float = ndc_ref.x * tan(half_hfov_ref) / tan(half_hfov_cur)
	var ndc_y_cur: float = ndc_ref.y * tan(half_vfov_ref) / tan(half_vfov_cur)
	var target: Vector2 = (Vector2(ndc_x_cur, ndc_y_cur) + Vector2.ONE) * 0.5 * vp_size
	position = target - size / 2.0
