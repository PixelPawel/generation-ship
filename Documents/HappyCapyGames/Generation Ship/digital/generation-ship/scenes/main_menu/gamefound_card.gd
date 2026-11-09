extends Button
## The Gamefound card on the main menu, left of the buttons (it replaced the bare
## Gamefound logo in the corner). It shows:
## - the boxed game, in the player's language, slowly zooming in and out;
## - the Gamefound logo;
## - a headline, a line of pitch and a gold line with the offer;
## - a Gamefound-green call to action.
## The whole card is one button that opens the campaign page.
## main_menu.gd places it: _add_gamefound_card.

const URL: String = "https://gamefound.com/en/projects/happy-capy-games/generation-ship#/section/project-story"
## Before the launch the card asks for a follow, with the Follower Gift wording Gamefound
## approved for the ads. Set this to true when the campaign goes live, and the card
## asks for a pledge instead. Both sets of texts are translated in UI Strings.csv.
const CAMPAIGN_LIVE: bool = false
const TEXTS_SOON: Array[String] = ["Coming to your table", "The tabletop game launches soon on Gamefound.",
		"Follow now and unlock a Follower Gift!", "Follow on Gamefound"]
const TEXTS_LIVE: Array[String] = ["Now on Gamefound", "The tabletop game is live on Gamefound.",
		"Back it now and bring it to your table!", "Back on Gamefound"]

const ART: String = "res://assets/ui/gamefound/box_%s.jpg"   # tools/menu_gamefound_art.py
const LOGO: String = "res://assets/ui/gamefound_logo_white.png"
const MYRIAD: String = "res://assets/fonts/Myriad Variable Concept.ttf"
const ETHNO: String = "res://assets/fonts/Ethnocentric-Regular.otf"   # the theme's face (assets/ui/theme.tres)
const GREEN: Color = Color(0.18, 0.89, 0.56)        # Gamefound's green (#2EE48F, from its logo)
const GOLD: Color = Color(1.0, 0.85, 0.4)           # the menu's gold, as on "Recommended for your first game"
const BODY_COLOR: Color = Color(0.80, 0.87, 0.96)
const INK: Color = Color(0.02, 0.13, 0.08)          # text on the green button

# Sizes on the 1920x1080 layout; the card is built k times this (see _init)
const W: float = 400.0
const H: float = 486.0
const PAD: float = 14.0
const LOGO_H: float = 30.0
const CTA_H: float = 54.0
const HEAD_FONT: int = 24
const BODY_FONT: int = 23
const BODY_FONT_WIDE: int = 17  # Polish: the body is Ethnocentric, much wider and heavier than Myriad
const CTA_FONT: int = 19
const MIN_FONT: int = 13
const GAP: float = 8.0          # between headline, pitch and offer
const ZOOM: float = 1.09        # the picture drifts between 1.0 and this...
const ZOOM_SEC: float = 9.0     # ...this long each way

var k: float = 1.0
var _pic_h: float = 0.0
var _art: TextureRect = null
var _head: Label = null
var _pitch: Label = null
var _gift: Label = null
var _cta: Panel = null
var _cta_label: Label = null
var _cta_normal: StyleBoxFlat = null
var _cta_hover: StyleBoxFlat = null
var _myriad: FontFile = null
var _ethno: FontFile = null
var _body_font: FontVariation = null   # Myriad semibold; Polish: the theme's Ethnocentric (_pick_body_font)

func _init(ui_scale: float = 1.0) -> void:
	k = ui_scale
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(W, H) * k
	_myriad = load(MYRIAD) as FontFile
	_ethno = load(ETHNO) as FontFile
	_body_font = FontVariation.new()
	_pick_body_font()
	_style()
	_build()
	_layout()
	pressed.connect(func() -> void: OS.shell_open(URL))
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))

func _ready() -> void:
	# the slow drift: the only motion on the card, so the box catches the eye without nagging
	var tw: Tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_art, "scale", Vector2.ONE * ZOOM, ZOOM_SEC)
	tw.tween_property(_art, "scale", Vector2.ONE, ZOOM_SEC)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _art != null:
		_pick_body_font()
		_art.texture = _art_texture()
		_layout()

# The card itself: the menu's dark panel with its blue edge; hovered, the edge
# turns Gamefound green and glows.
func _style() -> void:
	var normal: StyleBoxFlat = _box(Color(0.05, 0.08, 0.14, 0.92), Color(0.22, 0.40, 0.65, 0.60), 1)
	var hover: StyleBoxFlat = _box(Color(0.07, 0.11, 0.18, 0.95), Color(GREEN, 0.85), 2)
	hover.shadow_color = Color(GREEN, 0.30)
	hover.shadow_size = 10
	var down: StyleBoxFlat = _box(Color(0.03, 0.05, 0.09, 1.0), Color(GREEN, 0.65), 2)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", down)
	add_theme_stylebox_override("hover_pressed", down)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_cta_normal = _box(GREEN, GREEN, 0)
	_cta_hover = _box(GREEN.lightened(0.22), GREEN.lightened(0.22), 0)

func _build() -> void:
	var inner_w: float = (W - 2.0 * PAD) * k
	_pic_h = roundf(inner_w * 9.0 / 16.0)
	# the picture, in a frame that crops the zoom
	var frame: Control = Control.new()
	frame.clip_contents = true
	_quiet(frame)
	add_child(frame)
	frame.position = Vector2(PAD, PAD) * k
	frame.size = Vector2(inner_w, _pic_h)
	_art = TextureRect.new()
	_art.texture = _art_texture()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # drawn ~2.5x smaller than the file
	_quiet(_art)
	frame.add_child(_art)
	_art.position = Vector2.ZERO
	_art.size = frame.size
	_art.pivot_offset = frame.size * Vector2(0.5, 0.45)   # between the two boxes
	# a dark corner behind the logo, so it reads over the bright cards
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.82))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var corner: GradientTexture2D = GradientTexture2D.new()
	corner.gradient = grad
	corner.fill = GradientTexture2D.FILL_RADIAL
	corner.fill_from = Vector2(0.0, 1.0)
	corner.fill_to = Vector2(0.62, 0.30)
	corner.width = 128
	corner.height = 72
	var shade: TextureRect = TextureRect.new()
	shade.texture = corner
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_quiet(shade)
	frame.add_child(shade)
	shade.position = Vector2.ZERO
	shade.size = frame.size
	var logo_tex: Texture2D = load(LOGO) as Texture2D
	if logo_tex:
		var logo: TextureRect = TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_quiet(logo)
		frame.add_child(logo)
		var lh: float = LOGO_H * k
		logo.size = Vector2(lh * float(logo_tex.get_width()) / float(logo_tex.get_height()), lh)
		logo.position = Vector2(12.0 * k, _pic_h - lh - 10.0 * k)
	# a hairline round the picture, so it sits in the card like a screen
	var rim: Panel = Panel.new()
	var rim_box: StyleBoxFlat = StyleBoxFlat.new()
	rim_box.draw_center = false
	rim_box.border_color = Color(1.0, 1.0, 1.0, 0.14)
	rim_box.set_border_width_all(1)
	rim.add_theme_stylebox_override("panel", rim_box)
	_quiet(rim)
	add_child(rim)
	rim.position = frame.position
	rim.size = frame.size

	_head = _label(TEXTS_LIVE[0] if CAMPAIGN_LIVE else TEXTS_SOON[0], Color.WHITE)
	_pitch = _label(TEXTS_LIVE[1] if CAMPAIGN_LIVE else TEXTS_SOON[1], BODY_COLOR)
	_gift = _label(TEXTS_LIVE[2] if CAMPAIGN_LIVE else TEXTS_SOON[2], GOLD)
	_head.add_theme_font_override("font", _ethno)
	for lbl: Label in [_pitch, _gift]:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_override("font", _body_font)

	_cta = Panel.new()
	_cta.add_theme_stylebox_override("panel", _cta_normal)
	_quiet(_cta)
	add_child(_cta)
	_cta.position = Vector2(PAD, H - PAD - CTA_H) * k
	_cta.size = Vector2(inner_w, CTA_H * k)
	_cta_label = Label.new()
	_cta_label.text = TEXTS_LIVE[3] if CAMPAIGN_LIVE else TEXTS_SOON[3]
	_cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cta_label.add_theme_color_override("font_color", INK)
	_cta_label.add_theme_font_override("font", _ethno)
	_quiet(_cta_label)
	_cta.add_child(_cta_label)
	_cta_label.position = Vector2.ZERO
	_cta_label.size = _cta.size

# Font sizes and the text block's place: the headline and the button text on one line
# each (smaller if a language needs it), the pitch and offer as big as fits between
# the picture and the button, the block centred in that gap. Again after a language switch.
func _layout() -> void:
	var inner_w: float = (W - 2.0 * PAD) * k
	var head_font: Font = _ethno
	var head_size: int = _fit_line(head_font, tr(_head.text), inner_w, roundi(HEAD_FONT * k))
	_head.add_theme_font_size_override("font_size", head_size)
	var cta_size: int = _fit_line(head_font, tr(_cta_label.text), inner_w - 24.0 * k, roundi(CTA_FONT * k))
	_cta_label.add_theme_font_size_override("font_size", cta_size)

	var top: float = PAD * k + _pic_h + 12.0 * k
	var bottom: float = (H - PAD - CTA_H) * k - 12.0 * k
	var gap: float = GAP * k
	var head_h: float = head_font.get_height(head_size)
	var body_size: int = roundi((BODY_FONT if _body_font.base_font == _myriad else BODY_FONT_WIDE) * k)
	var pitch_h: float = 0.0
	var gift_h: float = 0.0
	while true:
		pitch_h = _text_h(tr(_pitch.text), inner_w, body_size)
		gift_h = _text_h(tr(_gift.text), inner_w, body_size)
		if head_h + pitch_h + gift_h + 2.0 * gap <= bottom - top or body_size <= roundi(MIN_FONT * k):
			break
		body_size -= 1
	for lbl: Label in [_pitch, _gift]:
		lbl.add_theme_font_size_override("font_size", body_size)
	var y: float = top + maxf(0.0, (bottom - top - (head_h + pitch_h + gift_h + 2.0 * gap)) / 2.0)
	_place(_head, y, inner_w, head_h)
	y += head_h + gap
	_place(_pitch, y, inner_w, pitch_h)
	y += pitch_h + gap
	_place(_gift, y, inner_w, gift_h)

func _place(lbl: Label, y: float, w: float, h: float) -> void:
	lbl.position = Vector2(PAD * k, y)
	lbl.size = Vector2(w, h)

# Height of a wrapped paragraph in the body font, with the Label's own line spacing.
func _text_h(line: String, w: float, font_size: int) -> float:
	var line_h: float = _body_font.get_height(font_size)
	var block: Vector2 = _body_font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w, font_size)
	var n: int = maxi(1, roundi(block.y / line_h))
	var spacing: float = float(_pitch.get_theme_constant("line_spacing"))
	return float(n) * line_h + float(n - 1) * spacing

static func _fit_line(font: Font, line: String, max_w: float, base: int) -> int:
	var fs: int = base
	while fs > MIN_FONT and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	return fs

func _label(key: String, color: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = key
	lbl.add_theme_color_override("font_color", color)
	_quiet(lbl)
	add_child(lbl)
	return lbl

func _on_hover(on: bool) -> void:
	_cta.add_theme_stylebox_override("panel", _cta_hover if on else _cta_normal)

func _art_texture() -> Texture2D:
	var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
	var path: String = ART % lang
	if not ResourceLoader.exists(path):
		path = ART % "EN"
	return load(path) as Texture2D

# Myriad has no Polish ą ć ę ń ś ź ż: Polish keeps the theme's Ethnocentric (as photo_scan.gd does).
func _pick_body_font() -> void:
	if TranslationServer.get_locale().begins_with("pl") or _myriad == null:
		_body_font.base_font = _ethno
		_body_font.variation_opentype = {}
	else:
		# Semibold, normal width. The keys must be tag numbers: Godot 4.7 silently ignores the
		# 4-letter strings ({"wght": 600} measured the same as {}), and this font's defaults
		# are its thinnest, narrowest cut (wght 300, wdth 70).
		var ts: TextServer = TextServerManager.get_primary_interface()
		_body_font.base_font = _myriad
		_body_font.variation_opentype = {ts.name_to_tag("wght"): 600, ts.name_to_tag("wdth"): 100}

# Everything inside the card lets the clicks through to it.
static func _quiet(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(roundi(6.0 * k))
	return s
