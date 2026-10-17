class_name RollHeroDiceRewardOp
extends EffectOp

## "Roll your Hero Dice: gain X per <symbol>" - rolls the acting player's
## real Hero Dice (DiceModel.hero_pool: Might red, Magic purple, Leadership
## blue, Guile yellow - the Skull-leaning pick, since these rewards count
## Skulls) and runs `reward_op` once per matching symbol. ctx.dice_roller,
## when set, replaces each die's face with its return value (tests).
var reward_symbol: String = "Skull"
var reward_op: EffectOp = null


func _init(p_reward_symbol: String = "Skull", p_reward_op: EffectOp = null) -> void:
	reward_symbol = p_reward_symbol
	reward_op = p_reward_op


func execute(ctx: EffectContext) -> void:
	if reward_op == null:
		return
	var p: PlayerFactionState = ctx.state.find_player(ctx.acting_faction)
	if p == null:
		return
	var guile: String = "white" if reward_symbol == "Shield" else "yellow"
	var pool: Array[String] = GameActions.CardAbilities.outside_roll_pool(ctx.card_db, p, guile)
	var hits: int = 0
	for color: String in pool:
		if ctx.dice_roller.is_valid():
			if str(ctx.dice_roller.call()) == reward_symbol:
				hits += 1
		else:
			for symbol: String in DiceModel.roll(color, ctx.rng):
				if symbol == reward_symbol:
					hits += 1
	ctx.log("%s rolls %d Hero Dice: %d %s" % [p.faction, pool.size(), hits, reward_symbol])
	for _i: int in range(hits):
		reward_op.execute(ctx)


func describe() -> String:
	return "Roll Hero Dice: %s per %s" % [reward_op.describe() if reward_op else "?", reward_symbol]
