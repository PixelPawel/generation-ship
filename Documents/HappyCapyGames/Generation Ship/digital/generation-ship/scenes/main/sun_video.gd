extends VideoPlayback

func _ready() -> void:
	super._ready()
	_shader_material.shader = load("res://shaders/yuv_to_rgb_additive.gdshader")
