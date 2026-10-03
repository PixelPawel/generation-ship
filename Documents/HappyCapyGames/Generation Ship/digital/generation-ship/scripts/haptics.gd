class_name Haptics
# Short vibrations on phones for the moments that should be felt: a card
# snapping onto a slot, supply coming in, a won bid or a fully optimized
# sector. Does nothing on desktop. Toggled in Settings ("Vibration", saved as
# display/vibration — see pause_menu.gd / main_menu.gd).

static var enabled: bool = true

const TICK_MS: int = 12          # snap / small gain: barely there
const TICK_AMPLITUDE: float = 0.35
const THUMP_MS: int = 40         # a card placed, a bid won
const THUMP_AMPLITUDE: float = 0.8
const CELEBRATE_MS: int = 90     # a sector fully optimized
const CELEBRATE_AMPLITUDE: float = 1.0

static func available() -> bool:
	return OS.has_feature("mobile")

static func tick() -> void:
	_vibrate(TICK_MS, TICK_AMPLITUDE)

static func thump() -> void:
	_vibrate(THUMP_MS, THUMP_AMPLITUDE)

static func celebrate() -> void:
	_vibrate(CELEBRATE_MS, CELEBRATE_AMPLITUDE)

static func _vibrate(ms: int, amplitude: float) -> void:
	if enabled and available():
		Input.vibrate_handheld(ms, amplitude)
