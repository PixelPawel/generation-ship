extends Control

## Main menu over the Blender-rendered tabletop backdrop
## (assets/art/menu/menu_backdrop.jpg, built by
## Render/menu_bg/build_menu_scene.py from the real game models and card
## art). Ambient life is all cheap: the backdrop shader's slow push-in,
## mist and breathing glows, two GPUParticles2D snow layers, and a short
## intro fade. The hovered / focused button turns rivet gold and gets a
## small gold rivet beside it (the logo's riveted letters).

const NEXT_SCENE := "res://scenes/Lobby.tscn"

const PUSH_IN_PERIOD := 48.0   # seconds for one slow in-and-out of the backdrop
const PUSH_IN_AMOUNT := 0.035  # extra zoom at the deepest point
const RIVET_INSET := 5.0   # rivet centre, from the button's left edge

@onready var backdrop: ColorRect = $Backdrop
@onready var snow_far: GPUParticles2D = $SnowFar
@onready var snow_near: GPUParticles2D = $SnowNear
@onready var logo: TextureRect = $Content/Column/Logo
@onready var subtitle: Label = $Content/Column/Subtitle
@onready var edition_label: Label = $Content/Column/Edition
@onready var buttons_box: VBoxContainer = $Content/Column/Buttons
@onready var start_button: Button = $Content/Column/Buttons/StartButton
@onready var quit_button: Button = $Content/Column/Buttons/QuitButton
@onready var hover_marker: ColorRect = $HoverMarker
@onready var fader: ColorRect = $Fader

var _bg_mat: ShaderMaterial
var _time: float = 0.0
var _hovered: Button = null
var _leaving: bool = false


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_bg_mat = backdrop.material as ShaderMaterial
	resized.connect(_on_resized)
	_on_resized()

	var menu_buttons: Array[Button] = [start_button, quit_button]
	for b: Button in menu_buttons:
		b.mouse_entered.connect(_on_button_hovered.bind(b))
		b.focus_entered.connect(_on_button_hovered.bind(b))
		b.mouse_exited.connect(_on_button_unhovered.bind(b))
		b.resized.connect(_update_pivot.bind(b))
		_update_pivot(b)
	hover_marker.modulate.a = 0.0
	_play_intro()
	# keyboard / gamepad focus once the buttons have faded in
	get_tree().create_timer(1.7).timeout.connect(_focus_first)


func _process(delta: float) -> void:
	_time += delta
	if _bg_mat != null:
		# Slow, almost subliminal push-in towards the Capital.
		var phase: float = 0.5 - 0.5 * cos(TAU * _time / PUSH_IN_PERIOD)
		_bg_mat.set_shader_parameter("zoom", 1.0 + PUSH_IN_AMOUNT * phase)
		_bg_mat.set_shader_parameter("pan", Vector2(0.012, -0.004) * phase)
	if _hovered != null and is_instance_valid(_hovered):
		_place_marker(_hovered, false)


func _on_resized() -> void:
	if _bg_mat != null:
		_bg_mat.set_shader_parameter("rect_size", size)
	# Snow spawns in a strip just above the screen, as wide as the window.
	var half_w: float = size.x * 0.5 + 160.0
	for p: GPUParticles2D in [snow_far, snow_near]:
		p.position = Vector2(size.x * 0.5 - 80.0, -40.0)
		var mat: ParticleProcessMaterial = p.process_material as ParticleProcessMaterial
		if mat != null:
			mat.emission_box_extents = Vector3(half_w, 30.0, 1.0)
		p.visibility_rect = Rect2(-half_w - 400.0, -100.0, half_w * 2.0 + 800.0, size.y + 400.0)


func _focus_first() -> void:
	if is_inside_tree() and not _leaving and get_viewport().gui_get_focus_owner() == null:
		start_button.grab_focus()


func _update_pivot(b: Button) -> void:
	b.pivot_offset = Vector2(0.0, b.size.y * 0.5)


func _play_intro() -> void:
	fader.color.a = 1.0
	logo.modulate.a = 0.0
	logo.pivot_offset = logo.custom_minimum_size * Vector2(0.0, 0.5)
	logo.scale = Vector2(0.96, 0.96)
	subtitle.modulate.a = 0.0
	edition_label.modulate.a = 0.0
	buttons_box.modulate.a = 0.0

	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(fader, "color:a", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(logo, "modulate:a", 1.0, 1.4).set_delay(0.35)
	tw.tween_property(logo, "scale", Vector2.ONE, 2.2).set_delay(0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(subtitle, "modulate:a", 1.0, 1.0).set_delay(0.9)
	tw.tween_property(edition_label, "modulate:a", 1.0, 1.0).set_delay(1.1)
	tw.tween_property(buttons_box, "modulate:a", 1.0, 0.9).set_delay(1.25)


func _on_button_hovered(b: Button) -> void:
	if _leaving:
		return
	var first: bool = _hovered == null
	_hovered = b
	_place_marker(b, first)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(hover_marker, "modulate:a", 1.0, 0.18)
	tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.16).set_trans(Tween.TRANS_SINE)
	var menu_buttons: Array[Button] = [start_button, quit_button]
	for other: Button in menu_buttons:
		if other != b:
			tw.tween_property(other, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)


func _on_button_unhovered(b: Button) -> void:
	# Keyboard/gamepad focus keeps the marker; a plain mouse-out just eases
	# the scale back.
	if b.has_focus():
		return
	create_tween().tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


func _place_marker(b: Button, snap: bool) -> void:
	var r: Rect2 = b.get_global_rect()
	var half: Vector2 = hover_marker.size * 0.5
	var target := Vector2(r.position.x + RIVET_INSET, r.position.y + r.size.y * 0.52) - half
	if snap:
		hover_marker.global_position = target
	else:
		hover_marker.global_position = hover_marker.global_position.lerp(target, 0.25)


func _on_start_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	var tw: Tween = create_tween()
	tw.tween_property(fader, "color:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(NEXT_SCENE))


func _on_quit_pressed() -> void:
	get_tree().quit()
