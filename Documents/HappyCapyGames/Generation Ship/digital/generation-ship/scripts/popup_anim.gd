# Opening and closing a full-screen popup (Rule Book, Collection, Leaderboard,
# Scan Tableau): a quick fade with a slight zoom from the centre, instead of
# popping in and out.

const OPEN_SEC: float = 0.2
const CLOSE_SEC: float = 0.14
const START_SCALE: float = 0.96
const TWEEN_META: StringName = &"_popup_anim_tween"

static func open(c: Control) -> void:
	_kill(c)
	c.visible = true
	c.pivot_offset = c.size / 2.0
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * START_SCALE
	var t: Tween = c.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(c, "modulate:a", 1.0, OPEN_SEC)
	t.tween_property(c, "scale", Vector2.ONE, OPEN_SEC)
	c.set_meta(TWEEN_META, t)

static func close(c: Control) -> void:
	if not c.visible:
		return
	_kill(c)
	c.pivot_offset = c.size / 2.0
	var t: Tween = c.create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(c, "modulate:a", 0.0, CLOSE_SEC)
	t.tween_property(c, "scale", Vector2.ONE * START_SCALE, CLOSE_SEC)
	t.chain().tween_callback(func() -> void:
		c.visible = false
		c.modulate.a = 1.0
		c.scale = Vector2.ONE)
	c.set_meta(TWEEN_META, t)

static func _kill(c: Control) -> void:
	if c.has_meta(TWEEN_META):
		var old: Tween = c.get_meta(TWEEN_META) as Tween
		if old and old.is_valid():
			old.kill()
	c.modulate.a = 1.0
	c.scale = Vector2.ONE
