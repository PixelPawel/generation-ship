extends CanvasLayer
## The studio intro's last picture, laid over the main menu while that loads and then dissolved
## onto its cockpit (studio_intro.gd fills it and hands it the tween). Outlives the intro scene
## and frees itself. The tween steps by at most a 30 fps frame: the long frames of the hand-over
## (the menu loading, the cockpit's shaders compiling) slow it down instead of making it jump.

const MAX_STEP: float = 1.0 / 30.0

var tween: Tween = null

func _process(delta: float) -> void:
	if tween != null and not tween.custom_step(minf(delta, MAX_STEP)):
		queue_free()
