extends Control
## The studio intro right after Godot's boot splash, before the main menu (flows into its cockpit):
## the Happy Capy Games capybara (Art/Logo/CapySnapy.png, redrawn sharp from its vector) sits on
## the page while "Happy Capy Games" writes itself in underneath, letter by letter (each fades in
## and settles from a little below). A tap, click or key skips it. Calm on purpose (the user,
## 2026-11-04: the bouncing first version was "a bit too silly"). Colours and font as on
## happycapygames.com: cream #FEF5E7 page (Godot's boot splash too, see project.godot),
## ink #26303C, Fraunces 600 (only the rendered letters ship, not the font).

const NEXT_SCENE: String = "res://scenes/main_menu/main_menu.tscn"
const IntroVeil: GDScript = preload("res://scenes/intro/intro_veil.gd")
const BG: Color = Color8(254, 245, 231)
const LOGO: Texture2D = preload("res://assets/ui/studio/capy_logo.png")
const LETTERS: Array[Texture2D] = [
	preload("res://assets/ui/studio/letter_00.png"), preload("res://assets/ui/studio/letter_01.png"),
	preload("res://assets/ui/studio/letter_02.png"), preload("res://assets/ui/studio/letter_03.png"),
	preload("res://assets/ui/studio/letter_04.png"), preload("res://assets/ui/studio/letter_05.png"),
	preload("res://assets/ui/studio/letter_06.png"), preload("res://assets/ui/studio/letter_07.png"),
	preload("res://assets/ui/studio/letter_08.png"), preload("res://assets/ui/studio/letter_09.png"),
	preload("res://assets/ui/studio/letter_10.png"), preload("res://assets/ui/studio/letter_11.png"),
	preload("res://assets/ui/studio/letter_12.png"), preload("res://assets/ui/studio/letter_13.png"),
]
# where each letter starts in the set line "Happy Capy Games", in the letter images' pixels
# (Fraunces at 180 px, kerning as in the whole line; images 247 px high), and the line's width
const LETTER_X: Array[float] = [-12.0, 125.0, 207.0, 300.0, 391.0, 505.0, 620.0, 702.0, 793.0, 907.0, 1031.0, 1113.0, 1256.0, 1334.0]
const LINE_W: float = 1416.0
const LETTER_IMAGE_H: float = 247.0
const LOGO_HEIGHT: float = 440.0      # canvas px (the layout is 1080 high)
const TEXT_HEIGHT: float = 104.0      # the letters' image height on screen
const TEXT_GAP: float = 34.0          # logo → letters
const LOGO_IN: float = 0.45           # the capybara fades in from the boot splash
const LETTERS_AT: float = 0.45        # s after start
const LETTER_STAGGER: float = 0.055
const LETTER_TIME: float = 0.5
const LETTER_RISE: float = 22.0       # canvas px each letter settles from
const LEAVE_AT: float = 2.9
const SKIP_AFTER: float = 0.3
# the hand-over (2026-11-04, "flow into the cockpit"): the name and the capybara fade out on the
# page, the menu loads underneath, then the cream page dissolves onto its cockpit
const OUT_PAUSE: float = 0.1          # a frame or two: the menu's first frame is drawn
const OUT_CONTENT: float = 0.4
const OUT_PAGE: float = 0.9
const MAX_STEP: float = 1.0 / 30.0    # a long frame (the first one) slows the animation, no jump

var _logo: TextureRect = null
var _letters: Array[TextureRect] = []
var _letter_rest_y: float = 0.0
var _started_ms: int = 0
var _leaving: bool = false
var _tweens: Array[Tween] = []        # stepped by _process, see MAX_STEP

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg: ColorRect = ColorRect.new()
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_started_ms = Time.get_ticks_msec()
	_play()

func _build() -> void:
	var view: Vector2 = get_viewport_rect().size
	var logo_size: Vector2 = Vector2(LOGO_HEIGHT * LOGO.get_width() / LOGO.get_height(), LOGO_HEIGHT)
	var top: float = (view.y - (LOGO_HEIGHT + TEXT_GAP + TEXT_HEIGHT)) / 2.0
	_logo = _make_picture(LOGO, logo_size)
	_logo.position = Vector2((view.x - logo_size.x) / 2.0, top)
	_logo.pivot_offset = logo_size / 2.0
	_logo.modulate.a = 0.0
	var k: float = TEXT_HEIGHT / LETTER_IMAGE_H
	var line_left: float = (view.x - LINE_W * k) / 2.0
	_letter_rest_y = top + LOGO_HEIGHT + TEXT_GAP
	for i: int in LETTERS.size():
		var tex: Texture2D = LETTERS[i]
		var letter: TextureRect = _make_picture(tex, Vector2(tex.get_width(), tex.get_height()) * k)
		letter.position = Vector2(line_left + LETTER_X[i] * k, _letter_rest_y + LETTER_RISE)
		letter.modulate.a = 0.0
		_letters.append(letter)

func _make_picture(tex: Texture2D, picture_size: Vector2) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # drawn well below its size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	r.size = picture_size                       # after add_child, so layout can't override it
	return r

func _tween() -> Tween:
	var t: Tween = create_tween()
	t.pause()
	_tweens.append(t)
	return t

func _process(delta: float) -> void:
	var step: float = minf(delta, MAX_STEP)
	for t: Tween in _tweens.duplicate():
		if not t.custom_step(step):
			_tweens.erase(t)

func _play() -> void:
	UIAudio.play_sfx("intro_chime")
	_tween().tween_property(_logo, "modulate:a", 1.0, LOGO_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i: int in _letters.size():
		var letter: TextureRect = _letters[i]
		var t: Tween = _tween().set_parallel(true)
		var at: float = LETTERS_AT + LETTER_STAGGER * i
		t.tween_property(letter, "modulate:a", 1.0, LETTER_TIME * 0.8).set_delay(at).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(letter, "position:y", _letter_rest_y, LETTER_TIME).set_delay(at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var leave: Tween = _tween()
	leave.tween_interval(LEAVE_AT)
	leave.tween_callback(_leave)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skip()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_skip()

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
		_skip()

func _skip() -> void:
	if Time.get_ticks_msec() - _started_ms >= int(SKIP_AFTER * 1000.0):
		_leave()

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	# The intro's pictures move onto a veil above everything, which outlives this scene: the
	# menu loads underneath (the veil shows meanwhile, no black), then the veil hands over.
	# (No background preload of the menu: it left 9 objects leaked at exit, 2026-11-04.)
	var layer: CanvasLayer = IntroVeil.new() as CanvasLayer
	layer.layer = 90                                # under SceneTransition's own layer (128)
	get_tree().root.add_child(layer)
	var veil: Control = Control.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page: Array[CanvasItem] = []
	var content: Array[CanvasItem] = []
	for child: Node in get_children():
		var item: CanvasItem = child as CanvasItem
		if item == null:
			continue
		item.reparent(veil)
		if item is ColorRect:
			page.append(item)
		else:
			content.append(item)
	var tw: Tween = layer.create_tween()
	tw.pause()                                      # the veil steps it, with the same MAX_STEP
	tw.tween_interval(OUT_PAUSE)
	# first the capybara and the name go, softly shrinking a touch
	for item: CanvasItem in content:
		tw.parallel().tween_property(item, "modulate:a", 0.0, OUT_CONTENT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_logo, "scale", Vector2(0.97, 0.97), OUT_CONTENT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# then the page opens onto the cockpit
	for item: CanvasItem in page:
		tw.chain().tween_property(item, "modulate:a", 0.0, OUT_PAGE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	layer.set("tween", tw)                          # it frees itself once this has run
	get_tree().change_scene_to_file(NEXT_SCENE)     # this (now empty) intro goes
