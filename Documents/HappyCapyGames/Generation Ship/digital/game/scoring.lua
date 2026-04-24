local M = {}

function M.score_player(state, player)
	local total = 0

	for _, sector in ipairs(player.ship.sectors) do
		for _, card_id in ipairs(sector.cards) do
			local card = state.card_db[card_id]
			if card then total = total + (card.stars or 0) end
		end

		total = total + #sector.stored_supplies

		for _, tucked in ipairs(sector.tucked_cards) do
			if tucked.facedown then
				total = total + 1
			else
				local card = state.card_db[tucked.card_id]
				if card then total = total + (card.stars or 0) end
			end
		end
	end

	return total
end

-- Returns a sorted list: { { player, score }, ... }, highest first.
function M.rankings(state)
	local rows = {}
	for _, player in ipairs(state.players) do
		table.insert(rows, { player = player, score = M.score_player(state, player) })
	end
	table.sort(rows, function(a, b) return a.score > b.score end)
	return rows
end

return M
