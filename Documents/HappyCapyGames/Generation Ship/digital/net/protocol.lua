-- Message types and serialization for Steam P2P networking.
-- All messages are JSON-encoded strings.

local M = {}

M.MSG = {
	-- Host -> All
	STATE_FULL  = "state_full",   -- sent to a new joiner
	STATE_DELTA = "state_delta",  -- incremental update after each action
	BID_UPDATE  = "bid_update",   -- current bid state broadcast
	GAME_OVER   = "game_over",    -- final rankings

	-- Client -> Host
	ACTION      = "action",       -- { type, ...payload }

	-- Lobby
	LOBBY_HELLO = "lobby_hello",  -- client announces name
	LOBBY_READY = "lobby_ready",  -- client is ready
	LOBBY_START = "lobby_start",  -- host starts game
}

-- Defold has a built-in json module.
local json = require("json")

function M.encode(msg_type, payload)
	return json.encode({ t = msg_type, d = payload })
end

function M.decode(raw)
	local ok, msg = pcall(json.decode, raw)
	if not ok or type(msg) ~= "table" then return nil, nil end
	return msg.t, msg.d
end

return M
