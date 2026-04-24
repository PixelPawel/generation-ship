-- Client receives state snapshots from the host and sends player actions.
-- The local player's UI calls the send_* helpers; on_message() is called
-- whenever a raw Steam message arrives from the host.

local C        = require("game.constants")
local protocol = require("net.protocol")

local M = {}

local _state          = nil
local _local_player_id = nil
local _send_fn        = nil  -- function(raw_string) sends to host
local _on_state_cb    = nil  -- function(state) called on every state update
local _on_game_over_cb = nil -- function(rankings)

-- ─── init ────────────────────────────────────────────────────────────────────

function M.init(local_player_id, send_fn, on_state_cb, on_game_over_cb)
	_local_player_id  = local_player_id
	_send_fn          = send_fn
	_on_state_cb      = on_state_cb
	_on_game_over_cb  = on_game_over_cb
end

-- ─── incoming ────────────────────────────────────────────────────────────────

function M.on_message(raw)
	local msg_type, data = protocol.decode(raw)
	if not msg_type then return end

	if msg_type == protocol.MSG.STATE_FULL or msg_type == protocol.MSG.STATE_DELTA then
		_state = data
		if _on_state_cb then _on_state_cb(_state) end

	elseif msg_type == protocol.MSG.GAME_OVER then
		if _on_game_over_cb then _on_game_over_cb(data) end
	end
end

-- ─── outgoing helpers ────────────────────────────────────────────────────────

local function send(action_type, payload)
	payload       = payload or {}
	payload.type  = action_type
	if _send_fn then _send_fn(protocol.encode(protocol.MSG.ACTION, payload)) end
end

function M.buy_tech(card_id, sector_index, payment_type)
	send(C.ACTION.BUY_TECH, { card_id = card_id, sector_index = sector_index, payment_type = payment_type })
end

function M.buy_sector(card_id, payment_type)
	send(C.ACTION.BUY_SECTOR, { card_id = card_id, payment_type = payment_type })
end

function M.start_bid(card_id, amount)
	send(C.ACTION.BID, { card_id = card_id, amount = amount })
end

function M.raise_bid(amount)
	send(C.ACTION.BID, { amount = amount })
end

function M.pass_bid()
	send(C.ACTION.BID, { pass = true })
end

function M.place_expedition(card_id, sector_index)
	send(C.ACTION.PLACE_EXPEDITION, { card_id = card_id, sector_index = sector_index })
end

function M.pass()
	send(C.ACTION.PASS)
end

function M.research(card_id)
	send(C.ACTION.RESEARCH, { card_id = card_id })
end

function M.recycle(card_id)
	send(C.ACTION.RECYCLE, { card_id = card_id })
end

function M.fuse(supply_type, target_type)
	send(C.ACTION.FUSE, { supply_type = supply_type, target_type = target_type })
end

function M.resolve_effect(data)
	send(C.ACTION.RESOLVE_EFFECT, data or {})
end

-- ─── accessors ───────────────────────────────────────────────────────────────

function M.get_state()
	return _state
end

function M.local_player()
	if not _state then return nil end
	for _, p in ipairs(_state.players) do
		if p.id == _local_player_id then return p end
	end
end

return M
