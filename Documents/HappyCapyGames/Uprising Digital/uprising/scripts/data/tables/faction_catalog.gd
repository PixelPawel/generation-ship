extends RefCounted

## Every people of Uprising this project has cards and art for: the Core box
## (4), Arch-Nemesis (4) and Titans (2). The faction screen lists all ten;
## only PLAYABLE ones - factions the rules engine knows (Home hex placement,
## player board, Feat decks) - can be claimed. Add a faction to PLAYABLE
## once its rules exist.
##
## Names follow the Heros/Feats CSVs ("Tua Than", "Hokqan"); the Playerboards
## CSV spells two of them differently (BOARD_KEY). No class_name - preload it.

const FACTIONS: Array[String] = [
	"Druwhn", "Duerkhar", "Krowh", "Mohyar",
	"Ytuma", "Renegade", "Tua Than", "Hokqan",
	"Pirates", "Titans",
]
const PLAYABLE: Array[String] = ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]

const BOX: Dictionary = {
	"Druwhn": "Core", "Duerkhar": "Core", "Krowh": "Core", "Mohyar": "Core",
	"Ytuma": "Arch", "Renegade": "Arch", "Tua Than": "Arch", "Hokqan": "Arch",
	"Pirates": "Titans", "Titans": "Titans",
}
const BOX_TITLE: Dictionary = {"Core": "Core box", "Arch": "Arch-Nemesis expansion", "Titans": "Titans expansion"}

## Full names where the faction goes by a short one.
const FULL_NAME: Dictionary = {
	"Renegade": "The Renegade Legion", "Pirates": "The Nethersea Pirates", "Titans": "The Titans of the First Age",
}

## Home hex as printed on the tile. The Hexes CSV lists the Titans' as
## "Titans Hex" and loses the ö in Sköke.
const HOME_HEX: Dictionary = {
	"Druwhn": "Yfelskog", "Duerkhar": "Khatrak Kautil", "Krowh": "Pak Glandris", "Mohyar": "Winterholm",
	"Ytuma": "Hromark", "Renegade": "Trifuth Gate", "Tua Than": "Tjurfalheim", "Hokqan": "Sjalt, Hjutar & Sköke",
	"Pirates": "The Drorslokh", "Titans": "The Obsidian Grave",
}
## Terrain of each Home hex (Hexes CSV).
const HOME_TERRAIN: Dictionary = {
	"Druwhn": "Woods", "Duerkhar": "Highlands", "Krowh": "Highlands", "Mohyar": "Woods",
	"Ytuma": "Badlands", "Renegade": "Ice Waste", "Tua Than": "Marshes", "Hokqan": "Woods",
	"Pirates": "Ice Waste", "Titans": "Highlands",
}

const ATLAS_DIR := "res://assets/images/Uprising+Final+EN/CORE_BOX_EN/HEXES_EN_TTS/Home/"
## TTS Home hex atlas per faction: top half face-down art, bottom half the
## face (see HexTextureLibrary).
const HOME_ATLAS: Dictionary = {
	"Druwhn": ATLAS_DIR + "Druwhn.png", "Duerkhar": ATLAS_DIR + "Duerkhar.png",
	"Krowh": ATLAS_DIR + "Krowh.png", "Mohyar": ATLAS_DIR + "Moyhar.png",
	"Ytuma": ATLAS_DIR + "Ytuma.png", "Renegade": ATLAS_DIR + "Renegades.png",
	"Tua Than": ATLAS_DIR + "TuaThan.png", "Hokqan": ATLAS_DIR + "Hoqkan.png",
	"Pirates": ATLAS_DIR + "Pirates.png", "Titans": ATLAS_DIR + "Titans.png",
}
## The face-down hex on a Home atlas (hex.obj's top-face UVs).
const BACK_REGION := Rect2(408, 63, 1032, 893)
## The Pirates' Home hex has rules text on both sides (The Drorslokh / The
## Fallen Drorslokh), so their token shows only the painting.
const ART_REGION: Dictionary = {"Pirates": Rect2(690, 246, 380, 328)}

## Accent per faction, from the frame of its player board.
const ACCENT: Dictionary = {
	"Druwhn": Color(0.86, 0.80, 0.55), "Duerkhar": Color(0.27, 0.68, 0.76),
	"Krowh": Color(0.80, 0.24, 0.32), "Mohyar": Color(0.90, 0.63, 0.25),
	"Ytuma": Color(0.89, 0.42, 0.22), "Renegade": Color(0.74, 0.77, 0.82),
	"Tua Than": Color(0.32, 0.78, 0.58), "Hokqan": Color(0.82, 0.70, 0.30),
	"Pirates": Color(0.24, 0.62, 0.95), "Titans": Color(0.64, 0.48, 0.92),
}

## Playerboards CSV spelling where it differs from the faction name.
const BOARD_KEY: Dictionary = {"Tua Than": "TuaThan", "Hokqan": "Hoqkan"}

## START Feats of the expansion Heroes, read off the card art (the Feats CSV
## has no START column): the Hero's own card plus the faction's shared Unit
## card, the same pattern as the Core decks in card_abilities.gd. The Titans
## have no shared card - each Titan starts with two of its own.
const EXPANSION_START_FEATS: Dictionary = {
	"Fjalka": ["Shepherd", "Herdmaster"], "Mjor": ["Stampede", "Herdmaster"],
	"Mukla": ["Mutant Instincts", "Legionnaires"], "Tlak": ["Prismatic Magic", "Legionnaires"],
	"Kyushi": ["Cartographer", "Stoneshells"], "Yvaj": ["Light of the Than", "Stoneshells"],
	"Azyr": ["Flanking Strike", "Stalkers"], "Tzadani": ["Nimble Reflexes", "Stalkers"],
	"Eyvind": ["Cardshark", "Sharkskald"], "Xaidine": ["Nethersea Queen", "Sharkskald"],
	"Mother of Night": ["Huntress Prime", "Vargmother"], "Father of Thunder": ["Skaga the Splitter", "Souldrinker"],
}
## Other cards a faction starts with (the Ytuma's Herd card, a Feats row).
const FACTION_START_CARDS: Dictionary = {"Ytuma": ["The Herd Card"]}


static func is_playable(faction: String) -> bool:
	return PLAYABLE.has(faction)


static func box_title(faction: String) -> String:
	return str(BOX_TITLE.get(BOX.get(faction, ""), ""))


static func board_key(faction: String) -> String:
	return str(BOARD_KEY.get(faction, faction))


static func home_region(faction: String) -> Rect2:
	return ART_REGION.get(faction, BACK_REGION)


static func accent(faction: String) -> Color:
	return ACCENT.get(faction, Color(0.055, 0.592, 0.635))


## The faction's Heroes (EN rows of any box - CardDatabase.heroes is Core only).
static func heroes_of(card_db: Node, faction: String) -> Array[HeroCard]:
	var out: Array[HeroCard] = []
	if card_db == null:
		return out
	for h: HeroCard in card_db.heroes_all:
		if h.lang == "EN" and h.faction == faction:
			out.append(h)
	return out


## Cards `hero` starts the game with: START Feats, then faction cards.
static func start_cards(faction: String, hero: String) -> Array[String]:
	var out: Array[String] = []
	if EXPANSION_START_FEATS.has(hero):
		for f: Variant in (EXPANSION_START_FEATS[hero] as Array):
			out.append(str(f))
	else:
		var abilities: GDScript = GameActions.CardAbilities
		for f: String in abilities.feat_deck_for(hero):
			if abilities.START_FEATS.has(f):
				out.append(f)
	for c: Variant in (FACTION_START_CARDS.get(faction, []) as Array):
		out.append(str(c))
	return out


static func feat_card(card_db: Node, card_name: String) -> FeatCard:
	if card_db == null:
		return null
	for f: FeatCard in card_db.feats_all:
		if f.lang == "EN" and f.card_name == card_name:
			return f
	return null
