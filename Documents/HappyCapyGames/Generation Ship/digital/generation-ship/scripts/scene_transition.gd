extends CanvasLayer

const FADE_DURATION: float = 0.25
const SLIDE_DURATION: float = 0.5

var _overlay: ColorRect

func _ready() -> void:
	layer = 128
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.modulate.a = 0.0
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

func change_scene(path: String) -> void:
	var t: Tween = create_tween()
	t.tween_property(_overlay, "modulate:a", 1.0, FADE_DURATION).set_ease(Tween.EASE_IN)
	await t.finished
	get_tree().change_scene_to_file(path)
	t = create_tween()
	t.tween_property(_overlay, "modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_OUT)

func slide_change_scene(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	var snapshot: TextureRect = TextureRect.new()
	snapshot.texture = tex
	snapshot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(snapshot)

	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame

	var vp_w: float = get_viewport().get_visible_rect().size.x
	var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(snapshot, "position:x", -vp_w, SLIDE_DURATION)
	await tw.finished
	remove_child(snapshot)
