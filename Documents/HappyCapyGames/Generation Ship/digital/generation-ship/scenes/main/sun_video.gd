extends VideoPlayback

# Hand-tuned to sit centered on the cockpit's "porthole" glow at the 16:9
# aspect ratio this whole rig was laid out against (see
# CockpitRig.setup_responsive_screen_positions for the same problem applied
# to the control/info/log screens). Camera3D defaults to KEEP_HEIGHT, so a
# wider aspect ratio (e.g. phone landscape) reveals extra horizontal FOV the
# video's old hardcoded CanvasLayer offset/scale never accounted for,
# drifting it visibly left of center. Repositioned from this fixed reference
# NDC point every time the viewport resizes instead.
const _REFERENCE_ASPECT := 16.0 / 9.0
const _REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const _REFERENCE_SCREEN_CENTER := Vector2(958.15, 398.495)  # at _REFERENCE_SIZE
const _SCREEN_SIZE := Vector2(120.0, 90.0)  # 400x300 at the old 0.3 CanvasLayer scale

var _cam: Camera3D

func _ready() -> void:
	super._ready()
	_shader_material.shader = load("res://shaders/yuv_to_rgb_additive.gdshader")
	size = _SCREEN_SIZE
	_cam = get_viewport().get_camera_3d()
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _reposition() -> void:
	if not _cam:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var ndc_ref: Vector2 = (_REFERENCE_SCREEN_CENTER / _REFERENCE_SIZE) * 2.0 - Vector2.ONE
	var half_vfov: float = deg_to_rad(_cam.fov) * 0.5
	var half_hfov_ref: float = atan(tan(half_vfov) * _REFERENCE_ASPECT)
	var half_hfov_cur: float = atan(tan(half_vfov) * (vp_size.x / vp_size.y))
	var ndc_x_cur: float = ndc_ref.x * tan(half_hfov_ref) / tan(half_hfov_cur)
	var target: Vector2 = (Vector2(ndc_x_cur, ndc_ref.y) + Vector2.ONE) * 0.5 * vp_size
	position = target - size / 2.0
