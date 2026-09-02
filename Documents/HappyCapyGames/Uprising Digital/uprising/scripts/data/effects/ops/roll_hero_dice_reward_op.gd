class_name RollHeroDiceRewardOp
extends EffectOp

## "Roll your Hero Dice: Gain 1 <resource> per SKULL." - rolls dice_count
## dice via ctx.roll_symbol() (see its doc comment on the placeholder-vs-
## real distribution boundary) and, for each rolled `reward_symbol`,
## executes `reward_op` once.
##
## dice_count defaults to 0, meaning "roll the acting Hero's real Hero Dice
## count" - NOT modeled yet, since that depends on HeroCard
## Might/Magic/Lead/Guile attributes plus which attribute this particular
## roll uses, which isn't specified uniformly across the sampled hex text
## ("Roll your Hero Dice" with no attribute named). Left as an explicit
## Milestone 4 TODO (wire to a real attribute + HeroCard lookup) - for now
## callers must pass an explicit dice_count.
var dice_count: int = 1
var reward_symbol: String = "Skull"
var reward_op: EffectOp = null


func _init(p_dice_count: int = 1, p_reward_symbol: String = "Skull", p_reward_op: EffectOp = null) -> void:
	dice_count = p_dice_count
	reward_symbol = p_reward_symbol
	reward_op = p_reward_op


func execute(ctx: EffectContext) -> void:
	if reward_op == null:
		return
	var hits: int = 0
	for _i: int in range(dice_count):
		if ctx.roll_symbol() == reward_symbol:
			hits += 1
	ctx.log("Rolled %d dice, %d %s" % [dice_count, hits, reward_symbol])
	for _i: int in range(hits):
		reward_op.execute(ctx)


func describe() -> String:
	return "Roll %d dice: %s per %s" % [dice_count, reward_op.describe() if reward_op else "?", reward_symbol]
