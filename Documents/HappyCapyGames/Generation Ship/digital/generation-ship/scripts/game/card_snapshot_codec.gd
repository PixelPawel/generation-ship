class_name CardSnapshotCodec
# Packs a player's final board state into the PackedInt32Array Steam's
# leaderboard "details" field allows (hard cap: 64 int32s / 256 bytes,
# k_cLeaderboardDetailsMax — confirmed live against a real uploaded entry).
#
# Deliberately NOT the same encoding as CardRef (scripts/net/card_ref.gd):
# CardRef encodes an array INDEX into CardDatabase's session-local arrays,
# fine for same-session RPCs but unsafe here — a leaderboard entry uploaded
# today has to still decode correctly if the CSVs are ever reordered later.
# This encodes CardData.id (the CSV "No." column), which the game already
# treats as a card's permanent identity (see card_database.gd's art-path
# lookups keyed on id).
#
# Fixed-size layout, 64 ints total, no header (nothing to version yet):
#   [0..5]   6 sector refs, one per SectorSlot1-6, in board order
#            (flag = is_advanced face)
#   [6..35]  up to 30 tech/expedition refs, packed sequentially in board
#            order (NOT one fixed group of 5 per sector — a sector with
#            fewer than 5 placed doesn't waste slots, it just leaves more
#            room for other sectors) — so this only tells you "what was
#            played", not "which sector each tech sat on"
#   [36..63] up to 28 tucked-card refs, flat across the whole board,
#            packed the same way (flag = face_up)
# A ref is 0 for "nothing here". Boards can never fill more than 6 sectors /
# 30 tech-or-expedition slots, so those two ranges always fit exactly;
# tucked cards are unbounded in theory but capped at 28 here — any beyond
# that are silently dropped, which only affects the snapshot's
# completeness, not the score itself.

const TOTAL_SIZE: int = 64
const SECTORS_START: int = 0
const SECTORS_COUNT: int = 6
const TECHS_START: int = 6
const TECHS_COUNT: int = 30
const TUCKED_START: int = 36
const TUCKED_COUNT: int = 28

# One ref = (card_type + 1) * 1000 + id * 2 + (1 if flag else 0).
# +1 on card_type reserves 0 for "empty slot"; ids only ever reach 137 (see
# card_database.gd's loaded CSVs), so id*2+flag safely stays under 1000.
static func encode_ref(cd: CardData, flag: bool = false) -> int:
	if not cd:
		return 0
	return (int(cd.card_type) + 1) * 1000 + cd.id * 2 + (1 if flag else 0)

# Returns {} for an empty/invalid ref, else {card_type: int, id: int, flag: bool}.
static func decode_ref(packed: int) -> Dictionary:
	if packed <= 0:
		return {}
	var type_val: int = packed / 1000
	if type_val < 1 or type_val > 3:
		return {}
	var rest: int = packed % 1000
	return {
		"card_type": type_val - 1,
		"id": rest / 2,
		"flag": (rest % 2) == 1,
	}

static func resolve_card(card_type: int, id: int) -> CardData:
	var arr: Array[CardData]
	match card_type:
		CardData.CardType.SECTOR:
			arr = CardDatabase.sectors
		CardData.CardType.TECH:
			arr = CardDatabase.techs
		CardData.CardType.EXPEDITION:
			arr = CardDatabase.expeditions
		_:
			return null
	for cd: CardData in arr:
		if cd.id == id:
			return cd
	return null

# entries: Array of {cd: CardData, flag: bool} in encounter order, matching
# the layout comment above (sectors, then techs/expeditions, then tucked).
static func decode_details(details: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in details.size():
		var decoded: Dictionary = decode_ref(details[i])
		if decoded.is_empty():
			continue
		var cd: CardData = resolve_card(decoded["card_type"], decoded["id"])
		if not cd:
			continue
		out.append({"cd": cd, "flag": decoded["flag"], "slot_index": i})
	return out
