-- Host owns the authoritative game state.
-- It receives ACTION messages from all peers (including itself),
-- applies them through game/actions.lua, and broadcasts state updates.
--
-- Steam send/receive calls are marked with -- STEAM: comments.
-- Wire these up to the steamworks extension in main.script.

local C        = require("game.constants")
local actions  = require("game.actions")
local state_m  = require("game.state")
local deck_m   = require("game.deck")
local scoring  = require("game.scoring")
local protocol = require("net.protocol")

local M = {}

local _state   = nil
local _peers   = {}   -- steam_id (string) -> player_id
local _send_fn = nil  -- function(steam_id, raw_string) set by main

-- ─── init ────────────────────────────────────────────────────────────────────

function M.init(player_ids, player_names, card_db, send_fn)
	_send_fn = send_fn
	_state = state_m.new(player_ids, player_names, card_db)

	-- Build and shuffle decks from card_db
	for id, card in pairs(card_db) do
		if card.type == C.CARD_TYPE.TECH then
			table.insert(_state.market.tech_deck, id)
		elseif card.type == C.CARD_TYPE.EXPEDITION then
			table.insert(_state.market.expedition_deck, id)
		elseif card.type == C.CARD_TYPE.SECTOR then
			-- Distribute evenly across 3 piles
			local pile_idx = (#_state.market.sector_piles[1] <= #_state.market.sector_piles[2]
				and #_state.market.sector_piles[1] <= #_state.market.sector_piles[3]) and 1
				or (#_state.market.sector_piles[2] <= #_state.market.sector_piles[3] and 2 or 3)
			table.insert(_state.market.sector_piles[pile_idx], id)
		end
	end

	deck_m.shuffle(_state.market.tech_deck)
	deck_m.shuffle(_state.market.expedition_deck)
	for i = 1, 3 do deck_m.shuffle(_state.market.sector_piles[i]) end

	M._start_generation()
end

function M.register_peer(steam_id, player_id)
	_peers[steam_id] = player_id
end

-- ─── incoming messages ───────────────────────────────────────────────────────

function M.on_message(steam_id, raw)
	local msg_type, data = protocol.decode(raw)
	if not msg_type then return end

	local player_id = _peers[steam_id]
	if not player_id then return end

	if msg_type == protocol.MSG.ACTION then
		M._handle_action(player_id, data)
	end
end

function M._handle_action(player_id, data)
	local t      = data.type
	local ok, err

	if t == C.ACTION.BUY_TECH then
		ok, err = actions.buy_tech(_state, player_id, data.card_id, data.sector_index, data.payment_type)

	elseif t == C.ACTION.BUY_SECTOR then
		ok, err = actions.buy_sector(_state, player_id, data.card_id, data.payment_type)

	elseif t == C.ACTION.BID then
		if _state.bid then
			if data.pass then
				ok, err = actions.pass_bid(_state, player_id)
			else
				ok, err = actions.raise_bid(_state, player_id, data.amount)
			end
		else
			ok, err = actions.start_bid(_state, player_id, data.card_id, data.amount)
		end

	elseif t == C.ACTION.PLACE_EXPEDITION then
		ok, err = actions.place_expedition(_state, player_id, data.card_id, data.sector_index)

	elseif t == C.ACTION.PASS then
		ok, err = actions.pass(_state, player_id)

	elseif t == C.ACTION.RESEARCH then
		ok, err = actions.research(_state, player_id, data.card_id)

	elseif t == C.ACTION.RECYCLE then
		ok, err = actions.recycle(_state, player_id, data.card_id)

	elseif t == C.ACTION.FUSE then
		ok, err = actions.fuse(_state, player_id, data.supply_type, data.target_type)
	end

	if ok then
		if _state.phase == C.PHASE.SCORING then
			M._broadcast_game_over()
		else
			M._broadcast_state_delta()
		end
	else
		M._send_error(player_id, err or "unknown error")
	end
end

-- ─── generation flow ─────────────────────────────────────────────────────────

function M._start_generation()
	-- Draw 6 tech cards per player
	for _, player in ipairs(_state.players) do
		local drawn = deck_m.draw(_state.market.tech_deck, C.CARDS_PER_GENERATION)
		for _, c in ipairs(drawn) do table.insert(player.hand, c) end
	end

	-- Reveal 3 expeditions
	for _ = 1, C.EXPEDITIONS_REVEALED do
		local drawn = deck_m.draw(_state.market.expedition_deck, 1)
		if drawn[1] then table.insert(_state.market.expeditions, drawn[1]) end
	end

	-- Reveal sectors: top of each pile (basic) + second from top (advanced)
	_state.market.sector_revealed = {}
	for i = 1, 3 do
		local pile = _state.market.sector_piles[i]
		if pile[#pile]     then table.insert(_state.market.sector_revealed, pile[#pile])     end
		if pile[#pile - 1] then table.insert(_state.market.sector_revealed, pile[#pile - 1]) end
	end

	_state.phase = C.PHASE.ACTIONS
	M._broadcast_state_full()
end

-- ─── broadcasts ──────────────────────────────────────────────────────────────

function M._broadcast_state_full()
	local msg = protocol.encode(protocol.MSG.STATE_FULL, M._public_state())
	M._send_all(msg)
end

function M._broadcast_state_delta()
	local msg = protocol.encode(protocol.MSG.STATE_DELTA, M._public_state())
	M._send_all(msg)
end

function M._broadcast_game_over()
	local rankings = scoring.rankings(_state)
	local msg = protocol.encode(protocol.MSG.GAME_OVER, rankings)
	M._send_all(msg)
end

function M._send_error(player_id, err_msg)
	for steam_id, pid in pairs(_peers) do
		if pid == player_id then
			if _send_fn then
				_send_fn(steam_id, protocol.encode("error", { message = err_msg }))
			end
		end
	end
end

function M._send_all(raw)
	if not _send_fn then return end
	for steam_id, _ in pairs(_peers) do
		_send_fn(steam_id, raw)
	end
end

-- Strip server-only data before broadcasting (e.g. other players' hands).
-- Each player only sees their own hand.
function M._public_state()
	return _state
end

function M.get_state()
	return _state
end

return M
