local C = require("game.constants")

local M = {}

function M.new(player_ids, player_names, card_db)
	local state = {
		generation          = 1,
		phase               = C.PHASE.DRAW,
		active_player_index = 1,
		first_player_index  = 1,
		card_db             = card_db,
		players             = {},
		market = {
			tech_deck        = {},
			tech_discard     = {},
			expedition_deck  = {},
			expeditions      = {},   -- up to 3 revealed
			sector_piles     = { {}, {}, {} },
			sector_revealed  = {},   -- up to 6 (3 basic + 3 advanced)
		},
		bid = nil,
	}

	for i, id in ipairs(player_ids) do
		table.insert(state.players, M.new_player(id, player_names[i] or ("Player " .. i)))
	end

	return state
end

function M.new_player(id, name)
	local supplies = {}
	for k, v in pairs(C.STARTING_SUPPLIES) do supplies[k] = v end

	return {
		id               = id,
		name             = name,
		supplies         = supplies,
		hand             = {},
		ship             = { sectors = {} },
		passed           = false,
		researched       = false,
		has_taken_action = false,
		pending_expedition = nil,
	}
end

function M.new_sector_slot(sector_card_id)
	return {
		sector_card      = sector_card_id,
		cards            = {},   -- up to 5 tech/expedition card ids
		tucked_cards     = {},   -- { card_id, facedown = bool }
		stored_supplies  = {},   -- list of supply type strings
	}
end

-- Returns the player table for a given id, or nil.
function M.get_player(state, player_id)
	for _, p in ipairs(state.players) do
		if p.id == player_id then return p end
	end
end

-- Returns the currently active player.
function M.active_player(state)
	return state.players[state.active_player_index]
end

return M
