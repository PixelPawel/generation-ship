local C       = require("game.constants")
local supply  = require("game.supply")
local state_m = require("game.state")
local effects = require("game.effects")
local deck_m  = require("game.deck")

local M = {}

-- ─── helpers ────────────────────────────────────────────────────────────────

-- Compute effective cost after discounts from ALWAYS cards and temporary bonuses.
-- sector is nil when buying a sector card (player's ship has no target sector yet).
local function effective_cost(player, card, sector)
	local discount = 0

	-- Sector one-time discounts (day_night_cycle, seasons)
	if sector then
		discount = discount + (sector.cost_discount or 0)
		sector.cost_discount = nil
	end

	-- Permanent ALWAYS discounts from cards on the player's ship
	for _, s in ipairs(player.ship.sectors) do
		for _, cid in ipairs(s.cards) do
			if cid == "waste_management"   and card.color == "liquids"  then discount = discount + 1 end
			if cid == "industrial_academy" and card.color == "metals"   then discount = discount + 1 end
			if cid == "cloning_lab"        and card.color == "organix"  then discount = discount + 1 end
			if cid == "physics_academy"    and card.color == "electrix" then discount = discount + 1 end
			if cid == "skyhook"            and (card.stars or 0) > 0    then discount = discount + 1 end
		end
	end

	-- Temporary player-level discount (from sector-buy effects like ancient_airlock)
	if card.type == "sector" then
		discount = discount + (player.next_sector_discount or 0)
		player.next_sector_discount = nil
	end

	return math.max(0, card.cost - discount)
end

local function find_in_hand(player, card_id)
	for i, c in ipairs(player.hand) do
		if c == card_id then return i end
	end
end

local function remove_from_market(list, card_id)
	for i, c in ipairs(list) do
		if c == card_id then table.remove(list, i); return true end
	end
	return false
end

local function guard_active(state, player_id)
	local p = state_m.get_player(state, player_id)
	if not p then return nil, "player not found" end
	if state_m.active_player(state).id ~= player_id then return nil, "not your turn" end
	if p.passed then return nil, "you have already passed" end
	return p
end

-- Fires placement effects, checks sector state triggers.
local function on_card_placed(state, player, sector, card_id)
	local card = state.card_db[card_id]
	if not card then return end

	if effects.is_new(sector) then
		effects.trigger(effects.TRIGGER.IF_NEW, state, player, sector, card)
	end

	local prev_tier = effects.optimization_tier(sector, state.card_db)
	table.insert(sector.cards, card_id)
	local new_tier = effects.optimization_tier(sector, state.card_db)

	effects.trigger(effects.TRIGGER.ON_PLACE, state, player, sector, card)

	if #sector.cards == 5 then
		effects.trigger(effects.TRIGGER.IF_COMPLETE, state, player, sector, card)
		effects.trigger_all(effects.TRIGGER.ALWAYS_COMPLETE, state, player, card, sector)
	end

	for tier = prev_tier + 1, new_tier do
		effects.trigger(effects.TRIGGER.ON_OPTIMIZE, state, player, sector, card)
		local sc = state.card_db[sector.sector_card]
		if sc and sc.optimize_groups and tier == #sc.optimize_groups then
			effects.trigger(effects.TRIGGER.IF_FULLY_OPTIMIZED, state, player, sector, card)
		end
	end

	-- ALWAYS_PLACE fires on every card on the player's ship whenever a card is placed.
	-- Extra args: (placed_card, placed_sector)
	effects.trigger_all(effects.TRIGGER.ALWAYS_PLACE, state, player, card, sector)
end

-- ─── main actions ────────────────────────────────────────────────────────────

function M.buy_tech(state, player_id, card_id, sector_index, payment_type)
	local player, err = guard_active(state, player_id)
	if not player then return false, err end

	local card = state.card_db[card_id]
	if not card or card.type ~= C.CARD_TYPE.TECH then return false, "not a tech card" end

	local hand_idx = find_in_hand(player, card_id)
	if not hand_idx then return false, "card not in hand" end

	local sector = player.ship.sectors[sector_index]
	if not sector then return false, "sector not found" end
	if #sector.cards >= C.MAX_CARDS_PER_SECTOR then return false, "sector is full" end

	local cost = effective_cost(player, card, sector)
	local ok, serr = supply.spend(player.supplies, card.color, cost, payment_type)
	if not ok then return false, serr end

	table.remove(player.hand, hand_idx)
	on_card_placed(state, player, sector, card_id)
	player.has_taken_action = true
	M._advance_turn(state)
	return true
end

function M.buy_sector(state, player_id, sector_card_id, payment_type)
	local player, err = guard_active(state, player_id)
	if not player then return false, err end
	if #player.ship.sectors >= C.MAX_SECTORS then return false, "ship sector limit reached" end

	local card = state.card_db[sector_card_id]
	if not card or card.type ~= C.CARD_TYPE.SECTOR then return false, "not a sector card" end
	if not remove_from_market(state.market.sector_revealed, sector_card_id) then
		return false, "sector not in market"
	end

	-- Check free-sector grant (from inflatable_hull etc.)
	local free_colors = player.next_sector_free_colors
	player.next_sector_free_colors = nil
	local is_free = false
	if free_colors then
		for _, fc in ipairs(free_colors) do
			if fc == card.color then is_free = true; break end
		end
	end

	local cost = is_free and 0 or effective_cost(player, card, nil)
	local ok, serr = supply.spend(player.supplies, card.color, cost, payment_type)
	if not ok then
		table.insert(state.market.sector_revealed, sector_card_id)
		player.next_sector_free_colors = free_colors  -- restore
		return false, serr
	end

	local slot = { sector_card = sector_card_id, cards = {}, tucked_cards = {}, stored_supplies = {} }
	table.insert(player.ship.sectors, slot)
	player.has_taken_action = true

	effects.trigger(effects.TRIGGER.ON_PLACE, state, player, slot, card)
	-- Notify ALWAYS_PLACE cards that a sector was placed (e.g. einstein_rosen_portal)
	effects.trigger_all(effects.TRIGGER.ALWAYS_PLACE, state, player, card, slot)
	M._advance_turn(state)
	return true
end

-- ─── bidding ─────────────────────────────────────────────────────────────────

function M.start_bid(state, player_id, expedition_card_id, bid_amount)
	local player, err = guard_active(state, player_id)
	if not player then return false, err end
	if state.bid then return false, "bid already active" end

	local card = state.card_db[expedition_card_id]
	if not card or card.type ~= C.CARD_TYPE.EXPEDITION then return false, "not an expedition" end

	local in_market = false
	for _, e in ipairs(state.market.expeditions) do
		if e == expedition_card_id then in_market = true; break end
	end
	if not in_market then return false, "expedition not in market" end
	if bid_amount < card.cost then return false, "bid below minimum cost of " .. card.cost end

	state.bid = {
		card_id          = expedition_card_id,
		bids             = { [player_id] = bid_amount },
		passed           = {},
		current_high     = bid_amount,
		current_high_id  = player_id,
		second_high_id   = nil,
		second_high      = 0,
	}
	player.has_taken_action = true
	return true
end

function M.raise_bid(state, player_id, amount)
	if not state.bid then return false, "no active bid" end
	if amount <= state.bid.current_high then return false, "must exceed current high bid" end

	state.bid.second_high    = state.bid.current_high
	state.bid.second_high_id = state.bid.current_high_id
	state.bid.current_high   = amount
	state.bid.current_high_id = player_id
	state.bid.bids[player_id] = amount
	state.bid.passed[player_id] = nil
	return true
end

function M.pass_bid(state, player_id)
	if not state.bid then return false, "no active bid" end
	state.bid.passed[player_id] = true

	local remaining = 0
	for _, p in ipairs(state.players) do
		if not state.bid.passed[p.id] then remaining = remaining + 1 end
	end

	if remaining <= 1 then
		return M._resolve_bid(state)
	end
	return true
end

-- Player must call this after winning a bid to choose a sector slot.
function M.place_expedition(state, player_id, card_id, sector_index)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	if player.pending_expedition ~= card_id then return false, "no pending expedition to place" end

	if #player.ship.sectors == 0 then
		-- No sectors: recycle it
		table.insert(state.market.expedition_deck, 1, card_id)
		player.pending_expedition = nil
		return true
	end

	local sector = player.ship.sectors[sector_index]
	if not sector then return false, "sector not found" end
	if #sector.cards >= C.MAX_CARDS_PER_SECTOR then return false, "sector is full" end

	player.pending_expedition = nil
	on_card_placed(state, player, sector, card_id)
	return true
end

-- ─── pass / research ─────────────────────────────────────────────────────────

function M.pass(state, player_id)
	local player, err = guard_active(state, player_id)
	if not player then return false, err end
	if player.pending_effect    then return false, "resolve pending effect first" end
	if player.pending_expedition then return false, "place your expedition first" end
	player.passed = true
	M._advance_turn(state)
	return true
end

function M.research(state, player_id, discard_card_id)
	local player, err = guard_active(state, player_id)
	if not player then return false, err end
	if player.researched then return false, "already researched this generation" end

	local hand_idx = find_in_hand(player, discard_card_id)
	if not hand_idx then return false, "card not in hand" end

	table.remove(player.hand, hand_idx)
	table.insert(state.market.tech_discard, discard_card_id)

	local drawn = deck_m.draw_with_reshuffle(state.market.tech_deck, state.market.tech_discard, 1)
	for _, id in ipairs(drawn) do table.insert(player.hand, id) end

	player.researched = true
	M._advance_turn(state)
	return true, drawn
end

-- ─── free actions ────────────────────────────────────────────────────────────

function M.recycle(state, player_id, card_id)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end

	local hand_idx = find_in_hand(player, card_id)
	if not hand_idx then return false, "card not in hand" end

	local card = state.card_db[card_id]
	table.remove(player.hand, hand_idx)
	table.insert(state.market.tech_discard, card_id)
	local gain = 1
	-- trash_compactor: gain 1 extra supply when recycling
	for _, s in ipairs(player.ship.sectors) do
		for _, cid in ipairs(s.cards) do
			if cid == "trash_compactor" then gain = gain + 1 end
		end
	end
	player.supplies[card.color] = (player.supplies[card.color] or 0) + gain
	return true
end

function M.fuse(state, player_id, supply_type, target_type)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	return supply.apply_fuse(player.supplies, supply_type, target_type)
end

-- ─── end-of-round ────────────────────────────────────────────────────────────

-- Each sector generates 1 supply of its color. Tech cards do not generate passively.
function M.gain_supplies(state)
	for _, player in ipairs(state.players) do
		for _, sector in ipairs(player.ship.sectors) do
			local sc = state.card_db[sector.sector_card]
			if sc then
				player.supplies[sc.color] = (player.supplies[sc.color] or 0) + 1
			end
		end
	end
end

-- ─── internal ────────────────────────────────────────────────────────────────

function M._advance_turn(state)
	local all_passed = true
	for _, p in ipairs(state.players) do
		if not p.passed then all_passed = false; break end
	end

	if all_passed then
		M.gain_supplies(state)
		M._start_next_generation(state)
		return
	end

	local n   = #state.players
	local idx = state.active_player_index
	for _ = 1, n do
		idx = (idx % n) + 1
		if not state.players[idx].passed then
			state.active_player_index = idx
			return
		end
	end
end

function M._start_next_generation(state)
	state.generation = state.generation + 1
	if state.generation > C.GENERATIONS then
		state.phase = C.PHASE.SCORING
		return
	end

	for _, p in ipairs(state.players) do
		p.passed           = false
		p.researched       = false
		p.has_taken_action = false
	end

	state.first_player_index  = (state.first_player_index % #state.players) + 1
	state.active_player_index = state.first_player_index
	state.phase = C.PHASE.DRAW
end

function M._resolve_bid(state)
	local bid    = state.bid
	local card   = state.card_db[bid.card_id]
	local winner = state_m.get_player(state, bid.current_high_id)

	remove_from_market(state.market.expeditions, bid.card_id)

	-- Winner pays their full bid amount; if they can't, second bidder pays printed cost.
	local ok = supply.spend(winner.supplies, card.color, bid.current_high)
	if not ok then
		if bid.second_high_id then
			local second = state_m.get_player(state, bid.second_high_id)
			supply.spend(second.supplies, card.color, card.cost)
			second.pending_expedition = bid.card_id
			effects.trigger_all(effects.TRIGGER.ALWAYS_BUY_EXP, state, second)
		end
	else
		winner.pending_expedition = bid.card_id
		effects.trigger_all(effects.TRIGGER.ALWAYS_BUY_EXP, state, winner)
	end

	state.bid = nil
	M._advance_turn(state)  -- bid initiator used their action; move to next player

	-- Immediately refill expedition market up to the standard cap
	local needed = C.EXPEDITIONS_REVEALED - #state.market.expeditions
	for _ = 1, needed do
		if #state.market.expedition_deck > 0 then
			table.insert(state.market.expeditions, table.remove(state.market.expedition_deck))
		end
	end

	return true
end

-- ─── resolve pending effects ─────────────────────────────────────────────────

function M.resolve_effect(state, player_id, data)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	local pe = player.pending_effect
	if not pe then return false, "no pending effect" end

	local t = pe.type

	if t == "choose_supply_gain" then
		local choice = data.supply
		local valid = false
		for _, opt in ipairs(pe.options) do if opt == choice then valid = true; break end end
		if not valid then return false, "invalid supply choice" end
		player.supplies[choice] = (player.supplies[choice] or 0) + (pe.amount or 1)

	elseif t == "gain_supply" then
		player.supplies[pe.supply] = (player.supplies[pe.supply] or 0) + (pe.amount or 1)

	elseif t == "fuse" then
		local ok, err = supply.apply_fuse(player.supplies, data.supply_type, data.target_type)
		if not ok then return false, err end
		pe.count = pe.count - 1
		if pe.count > 0 then return true end  -- keep pending for remaining fuses

	elseif t == "fuse_all" then
		local from = pe.supply
		while (player.supplies[from] or 0) >= 2 do
			local ok = supply.apply_fuse(player.supplies, from, data.target_type)
			if not ok then break end
		end

	elseif t == "recycle_then_draw" then
		local choices = data.card_ids or {}
		local count = math.min(#choices, pe.count or 1)
		for i = 1, count do
			local cid = choices[i]
			local hand_idx = find_in_hand(player, cid)
			if hand_idx then
				local c = state.card_db[cid]
				table.remove(player.hand, hand_idx)
				table.insert(state.market.tech_discard, cid)
				if c then player.supplies[c.color] = (player.supplies[c.color] or 0) + 1 end
			end
		end
		local drawn = deck_m.draw_with_reshuffle(state.market.tech_deck, state.market.tech_discard, count)
		for _, id in ipairs(drawn) do table.insert(player.hand, id) end

	elseif t == "recycle" then
		local choices = data.card_ids or {}
		for _, cid in ipairs(choices) do
			local hand_idx = find_in_hand(player, cid)
			if hand_idx then
				local c = state.card_db[cid]
				table.remove(player.hand, hand_idx)
				table.insert(state.market.tech_discard, cid)
				if c then player.supplies[c.color] = (player.supplies[c.color] or 0) + 1 end
			end
		end

	elseif t == "recycle_double" then
		local cid = data.card_id
		local hand_idx = find_in_hand(player, cid)
		if not hand_idx then return false, "card not in hand" end
		local c = state.card_db[cid]
		table.remove(player.hand, hand_idx)
		table.insert(state.market.tech_discard, cid)
		if c then player.supplies[c.color] = (player.supplies[c.color] or 0) + 2 end

	elseif t == "tuck" or t == "tuck_from_hand" then
		local sector = M._find_sector_by_card(player, pe.sector_card)
		if not sector then return false, "sector not found" end
		local choices = data.card_ids or {}
		local count = math.min(#choices, pe.count or 1)
		for i = 1, count do
			local cid = choices[i]
			local hand_idx = find_in_hand(player, cid)
			if hand_idx then
				table.remove(player.hand, hand_idx)
				table.insert(sector.tucked_cards, { card_id = cid, facedown = pe.facedown ~= false })
			end
		end

	elseif t == "tuck_multi" then
		local choices = data.tucks or {}  -- [{card_id, sector_card, facedown}]
		for _, entry in ipairs(choices) do
			local sector = M._find_sector_by_card(player, entry.sector_card)
			if sector then
				local hand_idx = find_in_hand(player, entry.card_id)
				if hand_idx then
					table.remove(player.hand, hand_idx)
					table.insert(sector.tucked_cards, { card_id = entry.card_id, facedown = pe.facedown ~= false })
				end
			end
		end

	elseif t == "store_supply" then
		local sector = M._find_sector_by_card(player, pe.sector_card)
		if not sector then return false, "sector not found" end
		local supply_type = data.supply or pe.supply
		if not supply_type then return false, "no supply specified" end
		table.insert(sector.stored_supplies, supply_type)

	elseif t == "store_supply_multi" then
		local entries = data.stores or {}  -- [{supply, sector_card}]
		for _, entry in ipairs(entries) do
			local s = M._find_sector_by_card(player, entry.sector_card)
			if s then table.insert(s.stored_supplies, entry.supply) end
		end

	elseif t == "buy_sector_discount" then
		player.next_sector_discount = (player.next_sector_discount or 0) + (pe.discount or 1)
		player.pending_effect = nil
		return true  -- discount stored, no further resolution

	elseif t == "buy_sector_free" then
		player.next_sector_free_colors = pe.color_filter
		player.pending_effect = nil
		return true

	elseif t == "reshuffle_expeditions" then
		local choices = data.card_ids or {}
		local count = math.min(#choices, pe.max or 3)
		local reshuffled = 0
		for i = 1, count do
			if remove_from_market(state.market.expeditions, choices[i]) then
				table.insert(state.market.expedition_deck, choices[i])
				reshuffled = reshuffled + 1
			end
		end
		deck_m.shuffle(state.market.expedition_deck)
		for _ = 1, reshuffled do
			if #state.market.expedition_deck > 0 then
				table.insert(state.market.expeditions, table.remove(state.market.expedition_deck))
			end
		end

	elseif t == "choose_effect" then
		local idx = data.choice_index or 1
		local chosen = (pe.options or {})[idx]
		if not chosen then return false, "invalid choice" end
		-- Re-queue the chosen sub-effect
		player.pending_effect = chosen
		return true

	else
		return false, "unknown pending effect type: " .. tostring(t)
	end

	player.pending_effect = nil
	return true
end

-- Find a sector slot by its sector_card id.
function M._find_sector_by_card(player, sector_card_id)
	for _, s in ipairs(player.ship.sectors) do
		if s.sector_card == sector_card_id then return s end
	end
end

return M
