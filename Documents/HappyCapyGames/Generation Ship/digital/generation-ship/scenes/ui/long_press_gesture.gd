class_name LongPressGesture
extends RefCounted

# Touch has no "right-click" — long-press is the standard mobile stand-in for
# it. One instance per interactive element (card, market slot, ...); drive it
# from that element's own press/move/release handling. Where a right-click
# handler had no competing left-click action at all (e.g. a popup's zoomed
# preview open/close), it's simpler to just accept the left click directly
# instead of using this — this is specifically for spots where left-click
# already does something else (buy, drag, select) that a long-press needs to
# NOT also trigger.

const HOLD_DURATION_SEC: float = 0.45
const MOVE_TOLERANCE_PX: float = 16.0

var _timer: SceneTreeTimer = null
var _press_pos: Vector2 = Vector2.ZERO
var _fired: bool = false
var _on_long_press: Callable = Callable()

## Call on press (left mouse button / touch down).
func begin(tree: SceneTree, at_pos: Vector2, on_long_press: Callable) -> void:
	cancel()
	_press_pos = at_pos
	_fired = false
	_on_long_press = on_long_press
	_timer = tree.create_timer(HOLD_DURATION_SEC)
	_timer.timeout.connect(_on_timeout)

## Call on move while pressed — cancels the long-press if it turns into a
## drag, so a dragged card/slot never also fires the long-press action.
func update_position(at_pos: Vector2) -> void:
	if _timer and at_pos.distance_to(_press_pos) > MOVE_TOLERANCE_PX:
		cancel()

## Call on release. Returns true if this should fire the normal tap/click
## action (i.e. no long-press fired first) — mirrors the old "if it wasn't a
## right-click, treat it as a left-click" branching these call sites had.
func end() -> bool:
	var was_tap: bool = _timer != null and not _fired
	cancel()
	return was_tap

func cancel() -> void:
	if _timer and _timer.timeout.is_connected(_on_timeout):
		_timer.timeout.disconnect(_on_timeout)
	_timer = null

func _on_timeout() -> void:
	_fired = true
	if _on_long_press.is_valid():
		_on_long_press.call()
