extends Node3D

# Decorative control panels on the cockpit's side ledges and walls
# (assets/3d/cockpit_panel_kit.glb, built by Render/cockpit_panels/make_kit.py):
# indicator LEDs, toggle switches, lit push buttons, a knob, square indicators
# and twin level meters, all idly alive. Mounted only left/right of the desk —
# the desk itself is where the sector row and tech stacks go.
# The parked menu cockpit runs it fully; the game sets `calm` for a quieter,
# slower version behind the table.

const KIT: PackedScene = preload("res://assets/3d/cockpit_panel_kit.glb")

# Mounting frames fitted to the cockpit surfaces seen from the game camera
# (Render/cockpit_panels/fit_anchors.py): X across, Y = surface normal,
# Z = along the ledge toward the player / down the wall.
const ANCHORS: Dictionary = {
	"LedgeTop": [
		Transform3D(Vector3(0.9999, 0.0128, 0.0), Vector3(-0.0127, 0.9963, -0.0845), Vector3(-0.0011, 0.0844, 0.9964), Vector3(-0.7105, 0.4813, 0.1759)),
		Transform3D(Vector3(0.9999, -0.0127, 0.0), Vector3(0.0127, 0.9963, -0.0846), Vector3(0.0011, 0.0846, 0.9964), Vector3(0.711, 0.4814, 0.177)),
	],
	"LedgeLower": [
		Transform3D(Vector3(1.0, 0.0073, 0.0), Vector3(-0.0073, 0.9956, -0.0932), Vector3(-0.0007, 0.0932, 0.9956), Vector3(-0.7116, 0.4973, 0.3497)),
		Transform3D(Vector3(1.0, -0.0073, 0.0), Vector3(0.0073, 0.9956, -0.0932), Vector3(0.0007, 0.0932, 0.9956), Vector3(0.7113, 0.4972, 0.3492)),
	],
	"WallMeter": [
		Transform3D(Vector3(-0.1403, 0.0, -0.9901), Vector3(0.9857, 0.0945, -0.1397), Vector3(0.0936, -0.9955, -0.0133), Vector3(-0.767, 0.5829, 0.3278)),
		Transform3D(Vector3(-0.1402, 0.0, 0.9901), Vector3(-0.9858, 0.0929, -0.1396), Vector3(-0.092, -0.9957, -0.013), Vector3(0.7623, 0.5836, 0.3273)),
	],
}
const LIFT: float = 0.0006            # off the surface, against z-fighting

const C_GREEN: Color = Color(0.25, 1.0, 0.45)
const C_AMBER: Color = Color(1.0, 0.62, 0.12)
const C_RED: Color = Color(1.0, 0.18, 0.12)
const C_CYAN: Color = Color(0.2, 0.8, 1.0)
const GLOW_ENERGY: float = 2.2
const OFF_LEVEL: float = 0.06         # an unlit lamp still shows its colour faintly
const LEVER_DEG: float = 24.0

var calm: bool = false                # the game's quieter version
# the game's cockpit model rumbles (CockpitRig); following it keeps the
# panels on its ledges instead of floating off while it shakes
var follow: Node3D = null
var _follow_rest_inv: Transform3D = Transform3D.IDENTITY
var _next_calm_event: float = 0.0
var _power: float = 1.0               # overall brightness (the parked menu runs dim)
var _t: float = 0.0
# every lamp: {mat, color, level (0..1 target), shown (smoothed)}
var _lamps: Dictionary = {}           # name -> Dictionary, per side: "L:glow_led_1"
var _levers: Array[Node3D] = []
var _lever_up: Array[bool] = []
var _knobs: Array[Node3D] = []
var _buttons: Array[String] = []
var _blinkers: Array[Dictionary] = [] # {lamp, period, phase, duty}
var _meter: Array[float] = [0.0, 0.0, 0.0, 0.0]   # L-a, L-b, R-a, R-b
var _meter_target: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	var kit: Node3D = KIT.instantiate() as Node3D
	var side_names: Array[String] = ["L", "R"]
	for cluster: String in ANCHORS:
		var src: Node3D = kit.get_node_or_null(cluster) as Node3D
		if src == null:
			push_warning("cockpit_panel_kit.glb has no %s" % cluster)
			continue
		var frames: Array = ANCHORS[cluster]
		for i: int in frames.size():
			var inst: Node3D = src.duplicate() as Node3D
			var xf: Transform3D = frames[i]
			inst.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * LIFT)
			inst.name = "%s_%s" % [cluster, side_names[i]]
			add_child(inst)
			_wire(inst, side_names[i])
	kit.free()
	_set_initial_state()
	if follow:
		_follow_rest_inv = follow.global_transform.affine_inverse()
	_next_calm_event = randf_range(12.0, 30.0)

# Give every glow_* part its own emissive material and remember the movers.
func _wire(cluster: Node3D, side: String) -> void:
	for n: Node in cluster.find_children("*", "", true, false):
		var nm: String = String(n.name)
		if n is MeshInstance3D and nm.begins_with("glow_"):
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.emission_enabled = true
			mat.roughness = 0.35
			var col: Color = _lamp_color(nm)
			mat.albedo_color = col * 0.18
			mat.emission = col
			(n as MeshInstance3D).material_override = mat
			_lamps[side + ":" + nm] = {"mat": mat, "color": col, "level": 0.0, "shown": 0.0}
			if nm.begins_with("glow_btn_"):
				_buttons.append(side + ":" + nm)
		elif nm.begins_with("lever_") and not nm.contains("_stem") and not nm.contains("_tip") and n is Node3D:
			_levers.append(n as Node3D)
			_lever_up.append(randf() < 0.5)
			(n as Node3D).rotation.x = deg_to_rad(LEVER_DEG if _lever_up[-1] else -LEVER_DEG)
		elif nm.begins_with("knob_") and not nm.contains("_body") and n is Node3D:
			_knobs.append(n as Node3D)
			(n as Node3D).rotation.y = randf_range(-2.0, 2.0)

func _lamp_color(nm: String) -> Color:
	if nm.begins_with("glow_meter_"):
		var seg: int = int(nm.get_slice("_", 3))
		return C_GREEN if seg <= 5 else (C_AMBER if seg <= 7 else C_RED)
	if nm.begins_with("glow_btn_"):
		return [C_RED, C_AMBER, C_GREEN][(int(nm.get_slice("_", 2)) - 1) % 3]
	if nm.begins_with("glow_ind_"):
		return [C_CYAN, C_GREEN, C_AMBER, C_CYAN][(int(nm.get_slice("_", 2)) - 1) % 4]
	if nm.begins_with("glow_led_"):
		return [C_GREEN, C_AMBER, C_CYAN, C_RED][(int(nm.get_slice("_", 2)) - 1) % 4]
	if nm.begins_with("glow_knob"):
		return C_AMBER
	return C_GREEN   # toggle status LEDs

func _set_initial_state() -> void:
	for key: String in _lamps:
		var nm: String = key.get_slice(":", 1)
		var lamp: Dictionary = _lamps[key]
		if nm.begins_with("glow_led_") or nm.begins_with("glow_ind_"):
			# blink on their own clocks; the game keeps most of them steady
			if calm and randf() < 0.6:
				lamp["level"] = 1.0 if randf() < 0.7 else 0.0
			else:
				_blinkers.append({"key": key, "period": randf_range(0.8, 3.5) * (2.0 if calm else 1.0),
						"phase": randf(), "duty": randf_range(0.3, 0.8)})
		elif nm.begins_with("glow_btn_") or nm.begins_with("glow_knob"):
			lamp["level"] = 1.0 if randf() < 0.6 else 0.25
		elif nm.contains("tog"):
			lamp["level"] = 1.0
		lamp["shown"] = lamp["level"]
	_sync_toggle_leds()

func _process(delta: float) -> void:
	_t += delta
	if follow and is_instance_valid(follow):
		global_transform = follow.global_transform * _follow_rest_inv
	if calm and _t >= _next_calm_event:
		# now and then, quietly: a switch flips or a button blinks
		_next_calm_event = _t + randf_range(15.0, 35.0)
		if randf() < 0.5:
			flip_random_switch()
		else:
			press_random_button()
	var speed: float = 0.45 if calm else 1.0
	for b: Dictionary in _blinkers:
		var ph: float = fmod(_t / float(b["period"]) + float(b["phase"]), 1.0)
		(_lamps[b["key"]] as Dictionary)["level"] = 1.0 if ph < float(b["duty"]) else 0.0
	# level meters: wander toward new random targets, a little jumpy
	for i: int in 4:
		if randf() < delta * (3.0 if calm else 7.0):
			_meter_target[i] = randf_range(0.15, 0.7 if calm else 1.0)
		_meter[i] = lerpf(_meter[i], _meter_target[i], 1.0 - exp(-delta * 9.0 * speed))
	for side: String in ["L", "R"]:
		for m: int in 2:
			var v: float = _meter[(0 if side == "L" else 2) + m]
			var tag: String = "a" if m == 0 else "b"
			for seg: int in range(1, 9):
				var key: String = "%s:glow_meter_%s_%d" % [side, tag, seg]
				if _lamps.has(key):
					(_lamps[key] as Dictionary)["level"] = 1.0 if v * 8.0 >= float(seg) - 0.5 else 0.0
	# ease every lamp toward its level, scaled by power
	var k: float = 1.0 - exp(-delta * 18.0)
	for key: String in _lamps:
		var lamp: Dictionary = _lamps[key]
		var shown: float = lerpf(float(lamp["shown"]), float(lamp["level"]), k)
		lamp["shown"] = shown
		var mat: StandardMaterial3D = lamp["mat"] as StandardMaterial3D
		mat.emission_energy_multiplier = GLOW_ENERGY * _power * maxf(shown, OFF_LEVEL)

## 0 = dark, 1 = full (the parked menu cockpit runs lower; wake_up raises it).
func set_power(p: float) -> void:
	_power = clampf(p, 0.0, 1.0)

## A random toggle flips (the caller plays the click).
func flip_random_switch() -> void:
	if _levers.is_empty():
		return
	var i: int = randi() % _levers.size()
	_lever_up[i] = not _lever_up[i]
	var t: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_levers[i], "rotation:x", deg_to_rad(LEVER_DEG if _lever_up[i] else -LEVER_DEG), 0.12)
	_sync_toggle_leds()

## A random push button blinks as if pressed, and a knob may turn a little.
func press_random_button() -> void:
	if not _buttons.is_empty():
		var key: String = _buttons[randi() % _buttons.size()]
		var lamp: Dictionary = _lamps[key]
		var was: float = float(lamp["level"])
		lamp["level"] = 1.0
		lamp["shown"] = 1.6   # a bright flash that eases back
		# tweens die with this node; a SceneTree timer could fire after it's freed
		create_tween().tween_callback(func() -> void:
			lamp["level"] = 0.25 if was >= 0.99 else 1.0).set_delay(0.35)
	if not _knobs.is_empty() and randf() < 0.5:
		var knob: Node3D = _knobs[randi() % _knobs.size()]
		create_tween().set_trans(Tween.TRANS_SINE).tween_property(knob, "rotation:y", knob.rotation.y + randf_range(-1.2, 1.2), 0.5)

## Every lamp lights in a quick cascade from the back of the ledge forward
## (the wake-up), over `sec` seconds.
func power_on_cascade(sec: float) -> void:
	var keys: Array = _lamps.keys()
	keys.shuffle()
	for key: String in keys:
		var lamp: Dictionary = _lamps[key]
		lamp["shown"] = 0.0
		var flash_at: float = randf() * sec
		create_tween().tween_callback(func() -> void:
			lamp["shown"] = 1.5).set_delay(flash_at)

func _sync_toggle_leds() -> void:
	# toggle 1/2's status LED follows its lever (per side, in wiring order)
	var idx: int = 0
	for side: String in ["L", "R"]:
		for n: int in [1, 2]:
			var key: String = "%s:glow_tog%d_led" % [side, n]
			if _lamps.has(key) and idx < _lever_up.size():
				(_lamps[key] as Dictionary)["level"] = 1.0 if _lever_up[idx] else 0.0
			idx += 1
