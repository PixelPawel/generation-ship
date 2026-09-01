class_name OrbitCamera
extends Node3D
## Mouse-driven orbit camera for inspecting the board: right-click-drag to
## orbit around this node's position, wheel to zoom. The actual Camera3D is
## a child node repositioned every update; this node itself stays put as the
## pivot (move IT to pan the view to a different part of the board).

@export var min_distance: float = 8.0
@export var max_distance: float = 90.0
@export var zoom_speed: float = 3.0
@export var orbit_speed: float = 0.01
@export var min_pitch: float = deg_to_rad(20.0)
@export var max_pitch: float = deg_to_rad(85.0)

var camera: Camera3D
var distance: float = 35.0
var yaw: float = 0.0
var pitch: float = deg_to_rad(55.0)
var _dragging: bool = false


func _ready() -> void:
	camera = _find_camera()
	update_camera_transform()


func _find_camera() -> Camera3D:
	for c in get_children():
		if c is Camera3D:
			return c
	var cam := Camera3D.new()
	add_child(cam)
	return cam


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - zoom_speed, min_distance, max_distance)
			update_camera_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + zoom_speed, min_distance, max_distance)
			update_camera_transform()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * orbit_speed
		pitch = clampf(pitch - mm.relative.y * orbit_speed, min_pitch, max_pitch)
		update_camera_transform()


func update_camera_transform() -> void:
	if camera == null:
		return
	var dir := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	)
	camera.position = dir * distance
	camera.look_at(global_position, Vector3.UP)
