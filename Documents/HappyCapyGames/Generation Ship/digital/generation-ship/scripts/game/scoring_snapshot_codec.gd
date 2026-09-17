class_name ScoringSnapshotCodec
# Packs a player's end-of-game scoring breakdown (the same Array[Dictionary]
# of {label, vp} that Scoring.calculate() returns and Scoreboard already
# displays) into the 64 int32 slots Steam's leaderboard "details" field
# allows (k_cLeaderboardDetailsMax = 64, confirmed live). Replaces the
# earlier card-art-thumbnail snapshot approach — same 64-int budget, but
# text instead of card refs.
#
# A scoring line's label is either one of a handful of fixed strings
# (scoring.gd's own constants, hardcoded here too since they're not tr()'d
# at the source either — see scoreboard.gd's show_scores()), or a tech/
# expedition card's card_name (scoring.gd uses the card as its own label
# for per-card conditional/expedition scoring). Encoding by CardData.id
# rather than storing the name as text means decoding re-resolves the
# CURRENT locale's name at display time, not whatever locale was active
# when the game was played.
#
# One ref = category*1_000_000 + subcode*1000 + vp (vp clamped to
# 0-999 — generous for any single scoring line in this game).
#   category 1: subcode = index into FIXED_LABELS
#   category 2: subcode = a TECH card's id
#   category 3: subcode = an EXPEDITION card's id
# 0 means "no line here". Up to 64 lines fit; a real game has maybe a
# dozen, so no line is ever expected to be dropped for space.

const TOTAL_SIZE: int = 64

const FIXED_LABELS: Array[String] = [
	"Faceup tucked (⭐)",
	"Facedown tucked (1 VP each)",
	"Stored supply (1 VP each)",
	"Stars (⭐)",
	"Greenhouses (Liquids bonus)",
	"Astra Cultura (Thrust bonus)",
]

static func encode_line(label: String, vp: int) -> int:
	var clamped_vp: int = clampi(vp, 0, 999)
	var fixed_idx: int = FIXED_LABELS.find(label)
	if fixed_idx >= 0:
		return 1_000_000 + fixed_idx * 1000 + clamped_vp
	for cd: CardData in CardDatabase.techs:
		if cd.card_name == label:
			return 2_000_000 + cd.id * 1000 + clamped_vp
	for cd: CardData in CardDatabase.expeditions:
		if cd.card_name == label:
			return 3_000_000 + cd.id * 1000 + clamped_vp
	return 0

# Returns {} for an unrecognized/empty ref, else {label: String, vp: int}.
static func decode_line(packed: int) -> Dictionary:
	if packed <= 0:
		return {}
	var vp: int = packed % 1000
	var rest: int = packed / 1000
	var category: int = rest / 1000
	var subcode: int = rest % 1000
	match category:
		1:
			if subcode < 0 or subcode >= FIXED_LABELS.size():
				return {}
			return {"label": FIXED_LABELS[subcode], "vp": vp}
		2:
			for cd: CardData in CardDatabase.techs:
				if cd.id == subcode:
					return {"label": cd.card_name, "vp": vp}
		3:
			for cd: CardData in CardDatabase.expeditions:
				if cd.id == subcode:
					return {"label": cd.card_name, "vp": vp}
	return {}

static func encode_lines(lines: Array[Dictionary]) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(TOTAL_SIZE)
	var i: int = 0
	for line: Dictionary in lines:
		if i >= TOTAL_SIZE:
			break
		var packed: int = encode_line(String(line.get("label", "")), int(line.get("vp", 0)))
		if packed > 0:
			out[i] = packed
			i += 1
	return out

static func decode_lines(details: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in details.size():
		var decoded: Dictionary = decode_line(details[i])
		if not decoded.is_empty():
			out.append(decoded)
	return out
