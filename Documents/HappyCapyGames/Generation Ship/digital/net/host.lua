-- Host owns the authoritative game state.
-- It receives ACTION messages from all peers (including itself),
-- applies them through game/actions.lua, and broadcasts state updates.
--
-- Steam send/receive calls are marked with -- STEAM: comments.
-- Wire these up to the steamworks extension in main.script.

local C         = require("game.constants")
local actions   = require("game.actions")
local state_m   = require("game.state")
local deck_m    = require("game.deck")
local scoring   = require("game.scoring")
local card_data = require("game.card_data")
local protocol  = require("net.protocol")
require("game.card_effects")  -- register all card effects as a side effect

local M = {}

local _state   = nil
local _peers   = {}   -- steam_id (string) -> player_id
local _send_fn = nil  -- function(steam_id, raw_string) set by main

-- ─── init ────────────────────────────────────────────────────────────────────

function M.init(player_ids, player_names, send_fn)
	_send_fn = send_fn
	_state = state_m.new(player_ids, player_names, card_data.db)

	-- Build shuffled decks using declared copy counts
	_state.market.tech_deck       = deck_m.shuffle(card_data.build_deck(C.CARD_TYPE.TECH))
	_state.market.expedition_deck = deck_m.shuffle(card_data.build_deck(C.CARD_TYPE.EXPEDITION))

	-- Split sector cards into 3 shuffled piles
	local sector_ids = card_data.list(C.CARD_TYPE.SECTOR)
	deck_m.shuffle(sector_ids)
	_state.market.sector_piles = deck_m.make_piles(sector_ids, 3, C.SECTORS_PER_PILE)

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

	elseif t == C.ACTION.RESOLVE_EFFECT then
		ok, err = actions.resolve_effect(_state, player_id, data)
	end

	if ok then
		if _state.phase == C.PHASE.SCORING then
			M._broadcast_game_over()
		elseif _state.phase == C.PHASE.DRAW then
			M._do_generation_setup()   -- auto-advance through the draw phase
		else
			M._broadcast_state_delta()
		end
	else
		M._send_error(player_id, err or "unknown error")
	end
end

-- ─── generation flow ─────────────────────────────────────────────────────────

-- Called at the very start of each generation (including gen 1).
-- Draws cards, refills expedition market to 3, keeps sector market as-is.
function M._do_generation_setup()
	-- Each player draws C.CARDS_PER_GENERATION new tech cards
	for _, player in ipairs(_state.players) do
		local drawn = deck_m.draw_with_reshuffle(
			_state.market.tech_deck, _state.market.tech_discard, C.CARDS_PER_GENERATION)
		for _, c in ipairs(drawn) do table.insert(player.hand, c) end
	end

	-- Refill expedition market up to C.EXPEDITIONS_REVEALED
	local needed = C.EXPEDITIONS_REVEALED - #_state.market.expeditions
	for _ = 1, needed do
		if #_state.market.expedition_deck > 0 then
			table.insert(_state.market.expeditions, table.remove(_state.market.expedition_deck))
		end
	end

	-- On generation 1 only: expose the initial sector market (top + second of each pile)
	if _state.generation == 1 then
		_state.market.sector_revealed = {}
		for i = 1, 3 do
			local pile = _state.market.sector_piles[i]
			if pile[#pile]     then table.insert(_state.market.sector_revealed, pile[#pile])     end
			if pile[#pile - 1] then table.insert(_state.market.sector_revealed, pile[#pile - 1]) end
		end
	end

	_state.phase = C.PHASE.ACTIONS
	M._broadcast_state_full()
end

-- Kept for compatibility; calls _do_generation_setup on first gen.
function M._start_generation()
	M._do_generation_setup()
end

-- ─── broadcasts ──────────────────────────────────────────────────────────────

function M._broadcast_state_full()
	if not _send_fn then return end
	for steam_id, player_id in pairs(_peers) do
		_send_fn(steam_id, protocol.encode(protocol.MSG.STATE_FULL, M._public_state(player_id)))
	end
end

function M._broadcast_state_delta()
	if not _send_fn then return end
	for steam_id, player_id in pairs(_peers) do
		_send_fn(steam_id, protocol.encode(protocol.MSG.STATE_DELTA, M._public_state(player_id)))
	end
end

function M._broadcast_game_over()
	local rankings = scoring.rankings(_state)
	local msg = protocol.encode(protocol.MSG.GAME_OVER, rankings)
	for steam_id, _ in pairs(_peers) do
		if _send_fn then _send_fn(steam_id, msg) end
	end
end

function M._send_error(player_id, err_msg)
	for steam_id, pid in pairs(_peers) do
		if pid == player_id and _send_fn then
			_send_fn(steam_id, protocol.encode("error", { message = err_msg }))
		end
	end
end

-- Returns a serialisable state view for a specific player.
-- card_db is excluded (clients load it locally from card_data.lua).
-- Other players' hand contents are hidden; only hand_size is sent.
function M._public_state(for_player_id)
	local view = {
		generation          = _state.generation,
		phase               = _state.phase,
		active_player_index = _state.active_player_index,
		first_player_index  = _state.first_player_index,
		bid                 = _state.bid,
		market = {
			tech_deck_size       = #_state.market.tech_deck,
			tech_discard_size    = #_state.market.tech_discard,
			expedition_deck_size = #_state.market.expedition_deck,
			expeditions          = _state.market.expeditions,
			sector_piles_sizes   = {
				#_state.market.sector_piles[1],
				#_state.market.sector_piles[2],
				#_state.market.sector_piles[3],
			},
			sector_revealed      = _state.market.sector_revealed,
		},
	}

	local masked_players = {}
	for _, p in ipairs(_state.players) do
		if p.id == for_player_id then
			table.insert(masked_players, p)
		else
			local mp = {
				id               = p.id,
				name             = p.name,
				hand_size        = #p.hand,
				ship             = p.ship,
				supplies         = p.supplies,
				passed           = p.passed,
				researched       = p.researched,
				has_taken_action = p.has_taken_action,
			}
			table.insert(masked_players, mp)
		end
	end
	view.players = masked_players
	return view
end

function M.get_state()
	return _state
end

return M
