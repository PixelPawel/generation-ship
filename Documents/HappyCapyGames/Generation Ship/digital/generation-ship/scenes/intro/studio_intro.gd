extends Control
## The studio intro right after Godot's boot splash, before the main menu (loaded meanwhile):
## the Happy Capy Games capybara (Art/Logo/CapySnapy.png, redrawn sharp from its vector) drops
## onto the screen, squashes as it lands and tips its hat; "Happy Capy Games" pops up word by
## word underneath; a little bob, then the menu. A tap, click or key skips it. Brand colours and
## font as on happycapygames.com: ink #26303C, cream #FEF5E7, accent #F5BE33, Fraunces.

const NEXT_SCENE: String = "res://scenes/main_menu/main_menu.tscn"
const BG: Color = Color8(38, 48, 60)
const LOGO: Texture2D = preload("res://assets/ui/studio/capy_logo.png")
const WORD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/ui/studio/word_happy.png"),
	preload("res://assets/ui/studio/word_capy.png"),
	preload("res://assets/ui/studio/word_games.png"),
]
const LOGO_HEIGHT: float = 440.0      # canvas px (the layout is 1080 high)
const WORD_HEIGHT: float = 104.0
const WORD_GAP: float = 10.0          # between the words (their images carry some margin already)
const TEXT_GAP: float = 34.0          # logo → words
const DROP_AT: float = 0.15           # s after start
const DROP_TIME: float = 0.42
const WORDS_AT: float = 0.9
const WORD_STAGGER: float = 0.16
const LEAVE_AT: float = 2.75
const SKIP_AFTER: float = 0.3

var _logo: TextureRect = null
var _words: Array[TextureRect] = []
var _logo_rest: Vector2 = Vector2.ZERO
var _started_ms: int = 0
var _leaving: bool = false

func _ready() -> void:
	SceneTransition.preload_scene(NEXT_SCENE)
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
	var block: float = LOGO_HEIGHT + TEXT_GAP + WORD_HEIGHT
	var top: float = (view.y - block) / 2.0
	_logo = _make_picture(LOGO, logo_size)
	_logo_rest = Vector2((view.x - logo_size.x) / 2.0, top)
	_logo.position = _logo_rest
	_logo.pivot_offset = Vector2(logo_size.x / 2.0, logo_size.y)   # squash and nod from its feet
	var sizes: Array[Vector2] = []
	var row: float = 0.0
	for tex: Texture2D in WORD_TEXTURES:
		var s: Vector2 = Vector2(WORD_HEIGHT * tex.get_width() / tex.get_height(), WORD_HEIGHT)
		sizes.append(s)
		row += s.x
	row += WORD_GAP * (WORD_TEXTURES.size() - 1)
	var x: float = (view.x - row) / 2.0
	for i: int in WORD_TEXTURES.size():
		var word: TextureRect = _make_picture(WORD_TEXTURES[i], sizes[i])
		word.position = Vector2(x, top + LOGO_HEIGHT + TEXT_GAP)
		word.pivot_offset = sizes[i] / 2.0
		word.scale = Vector2.ZERO
		_words.append(word)
		x += sizes[i].x + WORD_GAP

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

func _play() -> void:
	# the drop: from above the screen, speeding up like a real fall
	_logo.position.y = -_logo.size.y - 40.0
	var drop: Tween = create_tween()
	drop.tween_interval(DROP_AT)
	drop.tween_property(_logo, "position:y", _logo_rest.y, DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# the landing: squash, stretch back, settle
	drop.tween_property(_logo, "scale", Vector2(1.16, 0.84), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drop.tween_property(_logo, "scale", Vector2(0.95, 1.06), 0.11).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drop.tween_property(_logo, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# howdy: a hat-tipping nod from its feet
	drop.tween_property(_logo, "rotation", deg_to_rad(-9.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	drop.tween_property(_logo, "rotation", deg_to_rad(5.0), 0.17).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drop.tween_property(_logo, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# then a gentle bob while the name is read
	drop.tween_property(_logo, "position:y", _logo_rest.y - 10.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drop.tween_property(_logo, "position:y", _logo_rest.y, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# the name, word by word: pop past full size, settle; "Capy" with a little wobble
	for i: int in _words.size():
		var word: TextureRect = _words[i]
		var t: Tween = create_tween()
		t.tween_interval(WORDS_AT + WORD_STAGGER * i)
		t.tween_property(word, "scale", Vector2(1.18, 1.18), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(word, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if i == 1:
			word.rotation = deg_to_rad(-12.0)
			t.parallel().tween_property(word, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var leave: Tween = create_tween()
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
	SceneTransition.change_scene(NEXT_SCENE)
