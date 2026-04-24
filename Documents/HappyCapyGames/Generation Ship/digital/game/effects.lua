-- Card effect dispatch system.
-- Card effects are registered by card id and triggered by game events.
-- This module has no knowledge of specific cards; card_data.lua registers them.

local M = {}

M.TRIGGER = {
	ON_PLACE           = "on_place",
	ALWAYS             = "always",
	ON_OPTIMIZE        = "on_optimize",
	IF_NEW             = "if_new",
	IF_COMPLETE        = "if_complete",
	IF_FULLY_OPTIMIZED = "if_fully_optimized",
}

local _registry = {}

function M.register(card_id, trigger, fn)
	if not _registry[card_id] then _registry[card_id] = {} end
	_registry[card_id][trigger] = fn
end

function M.trigger(trigger_type, state, player, sector, card, ...)
	if not card then return end
	local handlers = _registry[card.id]
	if not handlers then return end
	local fn = handlers[trigger_type]
	if fn then fn(state, player, sector, card, ...) end
end

-- Sector state helpers used by action resolution.

function M.is_new(sector)
	return #sector.cards == 0
end

function M.is_complete(sector)
	-- A sector is complete when the 5th card is placed (checked before placement).
	return #sector.cards == 4
end

-- Returns true if placing card_id onto sector would fully optimize it.
function M.would_fully_optimize(sector, card_id, card_db)
	local sector_card = card_db[sector.sector_card]
	if not sector_card or not sector_card.optimize_groups then return false end

	local counts = {}
	for _, cid in ipairs(sector.cards) do
		local c = card_db[cid]
		if c then counts[c.color] = (counts[c.color] or 0) + 1 end
	end
	local new_card = card_db[card_id]
	if new_card then counts[new_card.color] = (counts[new_card.color] or 0) + 1 end

	for _, group in ipairs(sector_card.optimize_groups) do
		if (counts[group.color] or 0) < group.required then return false end
	end
	return true
end

-- Returns current optimization tier (0..3) for a sector.
function M.optimization_tier(sector, card_db)
	local sector_card = card_db[sector.sector_card]
	if not sector_card or not sector_card.optimize_groups then return 0 end

	local counts = {}
	for _, cid in ipairs(sector.cards) do
		local c = card_db[cid]
		if c then counts[c.color] = (counts[c.color] or 0) + 1 end
	end

	local tier = 0
	for _, group in ipairs(sector_card.optimize_groups) do
		if (counts[group.color] or 0) >= group.required then
			tier = tier + 1
		else
			break
		end
	end
	return tier
end

return M
