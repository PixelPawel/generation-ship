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

# No black between scenes: the current frame stays up as a still while the next
# scene loads (from the background preload if one was started, see
# preload_scene), then fades away over the new scene. The menu → game start
# uses it: the still is the powered-up cockpit, which is what the game shows.
const SNAPSHOT_FADE: float = 0.45

func preload_scene(path: String) -> void:
	if not ResourceLoader.has_cached(path):
		ResourceLoader.load_threaded_request(path)

func snapshot_change_scene(path: String) -> void:
	var tex: ImageTexture = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	var snapshot: TextureRect = TextureRect.new()
	snapshot.texture = tex
	snapshot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	snapshot.stretch_mode = TextureRect.STRETCH_SCALE
	snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(snapshot)
	await get_tree().process_frame   # the still is on screen before the load stalls
	var packed: PackedScene = null
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(path) as PackedScene   # waits if still loading
	if packed:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw: Tween = create_tween().set_ease(Tween.EASE_OUT)
	tw.tween_property(snapshot, "modulate:a", 0.0, SNAPSHOT_FADE)
	await tw.finished
	snapshot.queue_free()
