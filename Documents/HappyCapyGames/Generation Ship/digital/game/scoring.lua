local M = {}

-- ─── helpers ────────────────────────────────────────────────────────────────

local function count_tucked(player)
	local n = 0
	for _, s in ipairs(player.ship.sectors) do n = n + #s.tucked_cards end
	return n
end

local function count_stored(player)
	local n = 0
	for _, s in ipairs(player.ship.sectors) do n = n + #s.stored_supplies end
	return n
end

local function is_complete(sector)
	return #sector.cards == 5
end

local function is_fully_optimized(sector, db)
	local sc = db[sector.sector_card]
	if not sc or not sc.optimize_groups then return false end
	local counts = {}
	for _, cid in ipairs(sector.cards) do
		local c = db[cid]
		if c then counts[c.color] = (counts[c.color] or 0) + 1 end
	end
	for _, g in ipairs(sc.optimize_groups) do
		if (counts[g.color] or 0) < g.required then return false end
	end
	return true
end

local function count_complete(player)
	local n = 0
	for _, s in ipairs(player.ship.sectors) do if is_complete(s) then n = n + 1 end end
	return n
end

local function count_optimized(player, db)
	local n = 0
	for _, s in ipairs(player.ship.sectors) do if is_fully_optimized(s, db) then n = n + 1 end end
	return n
end

local function count_color(player, db, color)
	local n = 0
	for _, s in ipairs(player.ship.sectors) do
		local sc = db[s.sector_card]
		if sc and sc.color == color then n = n + 1 end
		for _, cid in ipairs(s.cards) do
			local c = db[cid]
			if c and c.color == color then n = n + 1 end
		end
	end
	return n
end

-- ─── Conditional tech cards ──────────────────────────────────────────────────
-- Returns true if the card's printed stars should be counted for this player.

local conditional = {
	tectonic_accelerator = function(p, db) return count_optimized(p, db) >= 6 end,
	magneto_sphere        = function(p, db) return count_tucked(p) >= 9 end,
	genesis_device        = function(p, db) return (p.supplies["thrust"] or 0) >= 6 end,
	space_elevator        = function(p, db) return count_stored(p) >= 12 end,
	atmosphere_processor  = function(p, db) return count_complete(p) >= 6 end,
}

-- ─── Expedition scoring formulas ─────────────────────────────────────────────

local function score_expedition(id, player, state)
	local db = state.card_db
	if id == "interstellar_trade_port" then
		local n = 0
		for _, s in ipairs(player.ship.sectors) do if #s.stored_supplies >= 2 then n = n + 1 end end
		return math.min(n * 2, 12)

	elseif id == "lagrange_complex" then
		return math.min(count_optimized(player, db) * 2, 12)

	elseif id == "self_replication" then
		return math.min(count_color(player, db, "metals") * 2, 12)

	elseif id == "polar_planet" then
		local best = 0
		for _, s in ipairs(player.ship.sectors) do
			local colors = {}
			for _, sup in ipairs(s.stored_supplies) do colors[sup] = true end
			local n = 0; for _ in pairs(colors) do n = n + 1 end
			if n > best then best = n end
		end
		return math.min(best * 2, 12)

	elseif id == "waterworld" then
		local n = 0
		for _, s in ipairs(player.ship.sectors) do
			for _, cid in ipairs(s.cards) do
				if db[cid] and db[cid].color == "liquids" then n = n + 1; break end
			end
		end
		return math.min(n * 2, 12)

	elseif id == "alliance" then
		local n = 0
		for _, other in ipairs(state.players) do
			if other.id ~= player.id then
				for _, s in ipairs(other.ship.sectors) do
					for _, cid in ipairs(s.cards) do
						if db[cid] and db[cid].type == "expedition" then n = n + 1 end
					end
				end
			end
		end
		return math.min(n * 2, 12)

	elseif id == "millions_of_colonists" then
		return math.min(count_complete(player) * 2, 12)

	elseif id == "urbanized_planet" then
		local all = {}
		for _, s in ipairs(player.ship.sectors) do
			for _, sup in ipairs(s.stored_supplies) do all[sup] = (all[sup] or 0) + 1 end
		end
		local min_set = math.huge
		for _, t in ipairs({"dust","metals","liquids","organix","electrix","thrust"}) do
			local v = all[t] or 0
			if v < min_set then min_set = v end
		end
		return (min_set == math.huge and 0 or min_set) * 15

	elseif id == "cloud_colony" then
		local n = 0
		for _, s in ipairs(player.ship.sectors) do
			for _, t in ipairs(s.tucked_cards) do if t.facedown then n = n + 1 end end
		end
		return math.min(n, 18)

	elseif id == "hive_mind" then
		return math.min(count_color(player, db, "electrix"), 12)

	elseif id == "asteroid_colonies" then
		local n = 0
		for _, s in ipairs(player.ship.sectors) do
			if is_complete(s) and is_fully_optimized(s, db) then n = n + 1 end
		end
		return math.min(n * 3, 18)

	elseif id == "aeon_ark" then
		local colors = {}
		for _, s in ipairs(player.ship.sectors) do
			local sc = db[s.sector_card]; if sc then colors[sc.color] = true end
		end
		local n = 0; for _ in pairs(colors) do n = n + 1 end
		return math.min(n * 2, 12)

	elseif id == "astrobio_propagation" then
		local n = 0
		for _, s in ipairs(player.ship.sectors) do if #s.tucked_cards >= 2 then n = n + 1 end end
		return math.min(n * 3, 18)

	elseif id == "bio_compatible_world" then
		return math.min(count_color(player, db, "organix"), 12)

	elseif id == "pleasure_planet" then
		local colors = {}
		for _, s in ipairs(player.ship.sectors) do
			for _, cid in ipairs(s.cards) do
				local c = db[cid]
				if c and c.type == "expedition" then colors[c.color] = true end
			end
		end
		local n = 0; for _ in pairs(colors) do n = n + 1 end
		return math.min(n * 3, 15)

	elseif id == "exodus_fleets" then
		return math.min(count_color(player, db, "thrust") * 2, 24)

	elseif id == "earth_2_0" then
		local total = 0
		for _, s in ipairs(player.ship.sectors) do
			local sc = db[s.sector_card]; if sc then total = total + (sc.stars or 0) end
			for _, cid in ipairs(s.cards) do
				local c = db[cid]; if c then total = total + (c.stars or 0) end
			end
		end
		return total * 2
	end

	return nil  -- not a scoring-formula expedition
end

-- Expedition IDs whose VP comes from a formula rather than printed stars.
local FORMULA_EXPEDITIONS = {
	interstellar_trade_port=true, lagrange_complex=true, self_replication=true,
	polar_planet=true, waterworld=true, alliance=true, millions_of_colonists=true,
	urbanized_planet=true, cloud_colony=true, hive_mind=true,
	asteroid_colonies=true, aeon_ark=true, astrobio_propagation=true,
	bio_compatible_world=true, pleasure_planet=true, exodus_fleets=true,
	earth_2_0=true, einstein_rosen_portal=true,
}

-- ─── Main scoring ────────────────────────────────────────────────────────────

function M.score_player(state, player)
	local db = state.card_db
	local total = 0

	for _, sector in ipairs(player.ship.sectors) do
		-- Sector card stars (1 VP each)
		local sc = db[sector.sector_card]
		if sc then total = total + (sc.stars or 0) end

		-- Sector-specific bonus VP (stored-supply multipliers)
		if sector.sector_card == "astra_cultura" then
			local thrust_stored = 0
			for _, sup in ipairs(sector.stored_supplies) do
				if sup == "thrust" then thrust_stored = thrust_stored + 1 end
			end
			total = total + thrust_stored * 2
		elseif sector.sector_card == "greenhouses" then
			local liq_stored = 0
			for _, sup in ipairs(sector.stored_supplies) do
				if sup == "liquids" then liq_stored = liq_stored + 1 end
			end
			total = total + liq_stored
		end

		-- Cards placed in the sector
		for _, cid in ipairs(sector.cards) do
			local card = db[cid]
			if card then
				if conditional[cid] then
					if conditional[cid](player, db) then
						total = total + (card.stars or 0)
					end
				elseif card.type == "expedition" and FORMULA_EXPEDITIONS[cid] then
					total = total + (score_expedition(cid, player, state) or 0)
				else
					total = total + (card.stars or 0)
				end
			end
		end

		-- Stored supplies: 1 VP each (already counted sector bonuses above separately)
		total = total + #sector.stored_supplies

		-- Tucked cards: facedown = 1 VP, faceup = card's printed stars
		for _, tucked in ipairs(sector.tucked_cards) do
			if tucked.facedown then
				total = total + 1
			else
				local card = db[tucked.card_id]
				if card then total = total + (card.stars or 0) end
			end
		end
	end

	-- Equatorial Superloop one-shot VP (stored by its place effect)
	total = total + (player._superloop_vp or 0)

	return total
end

-- Returns { { player, score }, ... } sorted highest first.
function M.rankings(state)
	local rows = {}
	for _, player in ipairs(state.players) do
		table.insert(rows, { player = player, score = M.score_player(state, player) })
	end
	table.sort(rows, function(a, b) return a.score > b.score end)
	return rows
end

return M
