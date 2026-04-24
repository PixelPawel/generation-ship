local M = {}

-- Fisher-Yates shuffle. rng is optional; defaults to math.random.
function M.shuffle(deck, rng)
	rng = rng or math.random
	for i = #deck, 2, -1 do
		local j = math.floor(rng() * i) + 1
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

-- Draws up to n cards from the top of deck (removes from end of array).
-- Returns a list of drawn card ids.
function M.draw(deck, n)
	n = n or 1
	local drawn = {}
	for _ = 1, n do
		if #deck == 0 then break end
		table.insert(drawn, table.remove(deck))
	end
	return drawn
end

-- Splits cards into piles of given size (for sector setup).
function M.make_piles(cards, pile_count, pile_size)
	local piles = {}
	for i = 1, pile_count do
		piles[i] = {}
		for j = 1, pile_size do
			local idx = (i - 1) * pile_size + j
			if cards[idx] then
				table.insert(piles[i], cards[idx])
			end
		end
	end
	return piles
end

-- Draw n cards, reshuffling the discard pile into the deck if it runs dry.
-- discard is modified in-place (cleared after shuffle).
function M.draw_with_reshuffle(deck, discard, n)
	n = n or 1
	if #deck < n and discard and #discard > 0 then
		for _, cid in ipairs(discard) do table.insert(deck, cid) end
		for i = #discard, 1, -1 do table.remove(discard, i) end
		M.shuffle(deck)
	end
	return M.draw(deck, n)
end

return M
