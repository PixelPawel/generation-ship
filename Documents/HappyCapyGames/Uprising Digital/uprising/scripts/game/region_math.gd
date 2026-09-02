class_name RegionMath
extends RefCounted

## The 3 named Regions (rulebook p6-7,14,44): pre-explored Ice-Waste-type
## ring hexes surrounding the main 37-hex board, split into 3 wedges. Event/
## Quest/Hex effect text can target a hex "in the Fog Grave" etc.
##
## STUB: which exact coords belong to which wedge, and which of the 3 names
## goes with which wedge, is NOT yet determined for this project - it needs
## the same TTS-coordinate ground-truthing done for board setup in
## Milestone 1 (the old project got the wedge SPLIT right from a verbal
## description but had the 3 NAMES rotated one wedge off from the real
## printed board until it rendered a calibration overlay against the actual
## board art and compared - don't re-guess the name assignment, verify it
## visually against real board/map art before shipping this).
const REGIONS: Array[String] = ["Howling White", "Fog Grave", "Screaming Sea"]


## Placeholder - always returns "" until Milestone 1 supplies real geometry.
## Replace with a real wedge-membership + name calculation once the board
## radius/shape and a labeled reference image are available to calibrate
## against.
static func region_for(_coord: Vector2i) -> String:
	push_warning("RegionMath.region_for() not yet implemented - pending Milestone 1 board geometry")
	return ""
