extends CanvasLayer

const FADE_DURATION: float = 0.25

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
