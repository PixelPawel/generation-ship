class_name OptimizeLogic
extends RefCounted

# Pure, state-only sector-optimization rules shared by the real board
# (board.gd, operating on a live SectorSlot) and the bot AI (operating on a
# lightweight Dictionary board). Keeping this logic in one place means bots
# can never drift from the real optimize rules.

# Removes one instance of each required color from pool (specific colors first, ANY last).
static func consume_from_pool(pool: Array[int], req: Array[int]) -> void:
	var any_count: int = 0
	for r: int in req:
		if r == CardData.OPTIMIZE_ANY:
			any_count += 1
		else:
			var idx: int = pool.find(r)
			if idx >= 0:
				pool.remove_at(idx)
	for _i: int in any_count:
		if not pool.is_empty():
			pool.pop_back()

# Same matching order as consume_from_pool (specific colors first, ANY
# last) but reports which indices of req got matched instead of just
# consuming pool silently — used for per-icon "already placed" display
# (see SectorSlot.refresh_optimize_display), kept separate from
# consume_from_pool itself so that one function stays the single source
# of truth for the actual level-trigger/scoring pool consumption.
static func matched_indices(pool: Array[int], req: Array[int]) -> Array[bool]:
	var working_pool: Array[int] = pool.duplicate()
	var matched: Array[bool] = []
	matched.resize(req.size())
	matched.fill(false)
	for i: int in req.size():
		if req[i] == CardData.OPTIMIZE_ANY:
			continue
		var idx: int = working_pool.find(req[i])
		if idx >= 0:
			working_pool.remove_at(idx)
			matched[i] = true
	for i: int in req.size():
		if req[i] == CardData.OPTIMIZE_ANY and not working_pool.is_empty():
			matched[i] = true
			working_pool.pop_back()
	return matched

static func satisfies_optimize(placed: Array[int], required: Array[int]) -> bool:
	var counts: Dictionary = {}
	for c: int in placed:
		counts[c] = counts.get(c, 0) + 1
	var any_needed: int = 0
	for req: int in required:
		if req == CardData.OPTIMIZE_ANY:
			any_needed += 1
		else:
			if counts.get(req, 0) == 0:
				return false
			counts[req] -= 1
	var total_remaining: int = 0
	for v: Variant in counts.values():
		total_remaining += int(v)
	return total_remaining >= any_needed

static func max_optimizations(cd: CardData, is_advanced: bool) -> int:
	if is_advanced:
		if not cd.adv_opt3_req.is_empty():
			return 3
		if not cd.adv_opt2_req.is_empty():
			return 2
		if not cd.adv_opt1_req.is_empty():
			return 1
		return 0
	return 1 if not cd.opt1_req.is_empty() else 0

# Given a sector's placed tech colors, checks each optimize level in order and
# returns the levels (1-based) newly triggered by this call, mutating
# optimize_count/is_optimized/triggered_levels in place — mirrors
# board.gd:_update_optimize_state()'s pool-consuming logic exactly.
#
# Also un-triggers an already-triggered level if the current pool no longer
# satisfies its requirement — a placement alone can never cause this (it
# only ever adds colors to the pool, so anything satisfied stays satisfied),
# but a removal (e.g. Caldera Colony recycling a tucked tech) can shrink the
# pool enough that a color the level depended on is gone, in which case it's
# earnable again rather than staying permanently triggered off a
# combination the sector no longer actually has. Karma Chameleon being
# discarded after its placement shrinks the pool the same way — and per the
# rules its level may then be earned (and fire) again.
static func update_optimize_state(
	cd: CardData, is_advanced: bool, placed_tech_colors: Array[int],
	optimize_count: int, max_opt: int, triggered_levels: Array[bool]
) -> Dictionary:
	var level_reqs: Array = [
		(cd.adv_opt1_req if is_advanced else cd.opt1_req),
		(cd.adv_opt2_req if is_advanced else []),
		(cd.adv_opt3_req if is_advanced else []),
	]
	# Guards against slots restored from old snapshots where triggered_levels
	# wasn't sized/cleared consistently with optimize_count.
	if triggered_levels.size() != max_opt:
		triggered_levels.resize(max_opt)
		for i: int in triggered_levels.size():
			if i >= optimize_count:
				triggered_levels[i] = false
	var pool: Array[int] = placed_tech_colors.duplicate()
	var triggered: Array[int] = []
	for level_idx: int in 3:
		var req: Array = level_reqs[level_idx]
		if req.is_empty():
			break
		if level_idx < triggered_levels.size() and triggered_levels[level_idx]:
			if satisfies_optimize(pool, req):
				consume_from_pool(pool, req)
			else:
				triggered_levels[level_idx] = false
				optimize_count -= 1
			continue
		if satisfies_optimize(pool, req):
			if level_idx < triggered_levels.size():
				triggered_levels[level_idx] = true
			optimize_count += 1
			triggered.append(level_idx + 1)
			consume_from_pool(pool, req)
	return {
		"optimize_count": optimize_count,
		"is_optimized": optimize_count >= max_opt and max_opt > 0,
		"triggered_levels": triggered_levels,
		"triggered": triggered,
	}
