local C       = require("game.constants")
local supply  = require("game.supply")
local state_m = require("game.state")
local effects = require("game.effects")

local M = {}

-- ─── helpers ────────────────────────────────────────────────────────────────

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
	if p.passed or p.researched then return nil, "already passed or researched" end
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

	if effects.is_complete(sector) then
		effects.trigger(effects.TRIGGER.IF_COMPLETE, state, player, sector, card)
	end

	for _ = prev_tier + 1, new_tier do
		effects.trigger(effects.TRIGGER.ON_OPTIMIZE, state, player, sector, card)
		if new_tier == #state.card_db[sector.sector_card].optimize_groups then
			effects.trigger(effects.TRIGGER.IF_FULLY_OPTIMIZED, state, player, sector, card)
		end
	end
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

	local ok, serr = supply.spend(player.supplies, card.cost_type, payment_type)
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

	local ok, serr = supply.spend(player.supplies, card.cost_type, payment_type)
	if not ok then
		table.insert(state.market.sector_revealed, sector_card_id)
		return false, serr
	end

	local slot = { sector_card = sector_card_id, cards = {}, tucked_cards = {}, stored_supplies = {} }
	table.insert(player.ship.sectors, slot)
	player.has_taken_action = true

	effects.trigger(effects.TRIGGER.ON_PLACE, state, player, slot, card)
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
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	if player.passed then return false, "already passed" end
	player.passed = true
	M._advance_turn(state)
	return true
end

function M.research(state, player_id, discard_card_id)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	if player.passed or player.researched then return false, "already passed or researched" end

	local hand_idx = find_in_hand(player, discard_card_id)
	if not hand_idx then return false, "card not in hand" end

	table.remove(player.hand, hand_idx)
	table.insert(state.market.tech_discard, discard_card_id)

	local drawn = {}
	if #state.market.tech_deck > 0 then
		local card_id = table.remove(state.market.tech_deck)
		table.insert(player.hand, card_id)
		drawn[1] = card_id
	end

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
	player.supplies[card.color] = (player.supplies[card.color] or 0) + 1
	return true
end

function M.fuse(state, player_id, supply_type, target_type)
	local player = state_m.get_player(state, player_id)
	if not player then return false, "player not found" end
	return supply.apply_fuse(player.supplies, supply_type, target_type)
end

-- ─── end-of-round ────────────────────────────────────────────────────────────

function M.gain_supplies(state)
	for _, player in ipairs(state.players) do
		for _, sector in ipairs(player.ship.sectors) do
			local sc = state.card_db[sector.sector_card]
			if sc then
				player.supplies[sc.color] = (player.supplies[sc.color] or 0) + 1
			end
			for _, cid in ipairs(sector.cards) do
				local card = state.card_db[cid]
				if card then
					player.supplies[card.color] = (player.supplies[card.color] or 0) + 1
				end
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
	local bid     = state.bid
	local card    = state.card_db[bid.card_id]
	local winner  = state_m.get_player(state, bid.current_high_id)

	remove_from_market(state.market.expeditions, bid.card_id)

	local ok = supply.spend(winner.supplies, card.cost_type)
	if not ok then
		-- Winner can't pay; second-highest bidder pays printed cost instead
		if bid.second_high_id then
			local second = state_m.get_player(state, bid.second_high_id)
			supply.spend(second.supplies, card.cost_type)
			second.pending_expedition = bid.card_id
		end
	else
		winner.pending_expedition = bid.card_id
	end

	state.bid = nil
	return true
end

return M
