class_name CardRef

# Converts a CardData object to a lightweight {t, i} dict that can be sent
# over an RPC. t = CardType int, i = index in the relevant CardDatabase array.
static func to_ref(cd: CardData) -> Dictionary:
	if not cd:
		return {t = -1, i = -1}
	var idx: int = -1
	match cd.card_type:
		CardData.CardType.SECTOR:
			idx = CardDatabase.sectors.find(cd)
		CardData.CardType.TECH:
			idx = CardDatabase.techs.find(cd)
		CardData.CardType.EXPEDITION:
			idx = CardDatabase.expeditions.find(cd)
	return {t = int(cd.card_type), i = idx}

# Reconstructs a CardData from a {t, i} dict produced by to_ref().
# Returns null if the ref is invalid.
static func from_ref(ref: Dictionary) -> CardData:
	var idx: int = ref.get("i", -1)
	if idx < 0:
		return null
	match ref.get("t", -1):
		CardData.CardType.SECTOR:
			if idx < CardDatabase.sectors.size():
				return CardDatabase.sectors[idx]
		CardData.CardType.TECH:
			if idx < CardDatabase.techs.size():
				return CardDatabase.techs[idx]
		CardData.CardType.EXPEDITION:
			if idx < CardDatabase.expeditions.size():
				return CardDatabase.expeditions[idx]
	return null
