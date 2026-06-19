class_name CardData
extends Resource

enum CardType { SECTOR, TECH, EXPEDITION }
enum SupplyColor { DUST, METALS, LIQUIDS, ORGANIX, ELECTRIX, THRUST }
enum TriggerType { ALWAYS, PLACE, SCORE }

const OPTIMIZE_ANY: int = -1

@export var id: int
@export var card_name: String
@export var card_type: CardType
@export var color: SupplyColor
@export var cost: int
@export var effect_text: String
@export var flavor_text: String
@export var image_url: String
@export var stars: int
@export var is_star_card: bool = false

static func color_name(supply_color: SupplyColor) -> String:
	match supply_color:
		SupplyColor.DUST:     return "Dust"
		SupplyColor.METALS:   return "Metals"
		SupplyColor.LIQUIDS:  return "Liquids"
		SupplyColor.ORGANIX:  return "Organix"
		SupplyColor.ELECTRIX: return "Electrix"
		SupplyColor.THRUST:   return "Thrust"
	return "?"

static func color_tint(supply_color: SupplyColor) -> Color:
	match supply_color:
		SupplyColor.DUST:     return Color(0.776, 0.769, 0.827)
		SupplyColor.METALS:   return Color(0.780, 0.180, 0.196)
		SupplyColor.LIQUIDS:  return Color(0.267, 0.494, 0.753)
		SupplyColor.ORGANIX:  return Color(0.251, 0.694, 0.286)
		SupplyColor.ELECTRIX: return Color(0.914, 0.471, 0.141)
		SupplyColor.THRUST:   return Color(0.945, 0.702, 0.118)
	return Color.WHITE

static func color_store_choice(prompt: String, any_sector: bool = false) -> Dictionary:
	var step_type: String = "store_on_any_sector" if any_sector else "store_on_slot"
	var options: Array = []
	var all_colors: Array[SupplyColor] = [
		SupplyColor.DUST, SupplyColor.METALS, SupplyColor.LIQUIDS,
		SupplyColor.ORGANIX, SupplyColor.ELECTRIX, SupplyColor.THRUST,
	]
	for sc: SupplyColor in all_colors:
		options.append({
			label = color_name(sc),
			tint = color_tint(sc),
			steps = [{type = step_type, color = sc, amount = 1}],
		})
	return {type = "choice", prompt = prompt, options = options}

static func effective_color(cd: CardData, is_advanced: bool) -> SupplyColor:
	if cd.card_type == CardType.SECTOR and is_advanced:
		return cd.adv_color
	return cd.color

static func valid_payment_colors(card_color: SupplyColor) -> Array[SupplyColor]:
	var result: Array[SupplyColor] = []
	match card_color:
		SupplyColor.DUST:
			result = [SupplyColor.DUST, SupplyColor.METALS, SupplyColor.LIQUIDS,
					  SupplyColor.ELECTRIX, SupplyColor.ORGANIX, SupplyColor.THRUST]
		SupplyColor.METALS:
			result = [SupplyColor.METALS, SupplyColor.ELECTRIX, SupplyColor.THRUST]
		SupplyColor.LIQUIDS:
			result = [SupplyColor.LIQUIDS, SupplyColor.ORGANIX, SupplyColor.THRUST]
		SupplyColor.ORGANIX:
			result = [SupplyColor.ORGANIX, SupplyColor.THRUST]
		SupplyColor.ELECTRIX:
			result = [SupplyColor.ELECTRIX, SupplyColor.THRUST]
		SupplyColor.THRUST:
			result = [SupplyColor.THRUST]
	return result

@export var trigger_type: TriggerType = TriggerType.ALWAYS

func frame_trigger() -> String:
	match trigger_type:
		TriggerType.PLACE: return "place"
		TriggerType.SCORE: return "score"
	return "always"

func frame_trigger_exp() -> String:
	match trigger_type:
		TriggerType.PLACE: return "place"
		TriggerType.SCORE: return "vp"
	return "always"

static func effective_cost(cd: CardData, is_advanced: bool) -> int:
	if cd.card_type == CardType.SECTOR and is_advanced:
		return cd.adv_cost
	return cd.cost

@export var opt1_req: Array[int] = []

@export var local_art_path: String = ""

# Advanced side (sector cards only)
@export var adv_name: String = ""
@export var adv_color: SupplyColor = SupplyColor.DUST
@export var adv_cost: int = 0
@export var adv_effect_text: String = ""
@export var adv_flavor_text: String = ""
@export var adv_image_url: String = ""
@export var adv_local_art_path: String = ""
@export var adv_opt1_req: Array[int] = []
@export var adv_opt2_req: Array[int] = []
@export var adv_opt3_req: Array[int] = []
