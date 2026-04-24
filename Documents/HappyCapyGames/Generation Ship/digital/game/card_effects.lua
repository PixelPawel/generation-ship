-- Registers all card effect handlers with the effects dispatch system.
-- Require this module once at startup (host.lua) to wire up all effects.

local effects = require("game.effects")
local deck_m  = require("game.deck")

local E = effects.TRIGGER

-- ─── helpers ─────────────────────────────────────────────────────────────────

local function gain(player, supply, n)
	player.supplies[supply] = (player.supplies[supply] or 0) + (n or 1)
end

local function draw(state, player, n)
	local drawn = deck_m.draw(state.market.tech_deck, n or 1)
	for _, id in ipairs(drawn) do table.insert(player.hand, id) end
	return drawn
end

local function store(sector, supply)
	table.insert(sector.stored_supplies, supply)
end

-- Queue a choice-based effect for the player to resolve via RESOLVE_EFFECT action.
local function pending(player, effect)
	player.pending_effect = effect
end

-- Count distinct colors already on a sector's placed cards.
local function distinct_colors(sector, db)
	local colors = {}
	for _, cid in ipairs(sector.cards) do
		local c = db[cid]
		if c then colors[c.color] = (colors[c.color] or 0) + 1 end
	end
	return colors
end

-- Reveal up to N sectors from piles into the market.
local function reveal_sectors(state, n)
	local revealed = 0
	for i = 1, 3 do
		if revealed >= n then break end
		local pile = state.market.sector_piles[i]
		if #pile > 0 then
			table.insert(state.market.sector_revealed, table.remove(pile))
			revealed = revealed + 1
		end
	end
end

-- Reveal up to N expeditions from the deck into the market.
local function reveal_expeditions(state, n)
	for _ = 1, n do
		if #state.market.expedition_deck > 0 then
			table.insert(state.market.expeditions, table.remove(state.market.expedition_deck))
		end
	end
end

-- ─── DUST TECH ───────────────────────────────────────────────────────────────

effects.register("hangars", E.IF_NEW, function(state, player, sector, card)
	gain(player, "dust", 3)
end)

effects.register("containers", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "choose_supply_gain", options = {"dust","metals","liquids"}, amount = 1 })
end)

effects.register("chemlabs", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 2 })
end)
effects.register("chemlabs", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	gain(player, "dust", 2)
end)

effects.register("ancient_airlock", E.ON_PLACE, function(state, player, sector, card)
	reveal_sectors(state, 1)
end)
effects.register("ancient_airlock", E.IF_NEW, function(state, player, sector, card)
	pending(player, { type = "buy_sector_discount", discount = 1 })
end)

effects.register("chemical_synthesizer", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 1)
	pending(player, { type = "tuck", count = 1, facedown = true, sector_card = sector.sector_card })
end)

effects.register("asteroid_capture", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 2 })
end)
effects.register("asteroid_capture", E.IF_NEW, function(state, player, sector, card)
	draw(state, player, 1)
end)

effects.register("printed_library", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "tuck", count = 1, facedown = true, sector_card = sector.sector_card })
end)
effects.register("printed_library", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	draw(state, player, 2)
end)

effects.register("gas_cloud", E.ON_PLACE, function(state, player, sector, card)
	for _, p in ipairs(state.players) do draw(state, p, 1) end
end)

effects.register("osmosis_filter", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_then_draw", count = 1 })
end)

-- Draw 1 then immediately recycle it (deterministic: recycle the drawn card)
effects.register("passing_comet", E.ON_PLACE, function(state, player, sector, card)
	local drawn = draw(state, player, 1)
	if drawn[1] then
		local hand_idx
		for i, c in ipairs(player.hand) do
			if c == drawn[1] then hand_idx = i; break end
		end
		if hand_idx then
			local c = state.card_db[drawn[1]]
			table.remove(player.hand, hand_idx)
			table.insert(state.market.tech_discard, drawn[1])
			if c then gain(player, c.color, 1) end
		end
	end
end)

-- ─── METALS TECH ─────────────────────────────────────────────────────────────

effects.register("magnetized_hull", E.IF_COMPLETE, function(state, player, sector, card)
	pending(player, { type = "choose_supply_gain", options = {"organix","electrix"}, amount = 1 })
end)

effects.register("hydrogen_cell", E.IF_NEW, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 2 })
end)

effects.register("smelter", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 3 })
end)
effects.register("smelter", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	store(sector, "metals")
end)

effects.register("fusion_synthesizer", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse_all", supply = "dust" })
end)

effects.register("cleaning_robot", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_double", count = 1 })
end)

effects.register("deep_space_radar", E.ON_PLACE, function(state, player, sector, card)
	reveal_expeditions(state, 2)
end)

effects.register("robotic_workforce", E.IF_NEW, function(state, player, sector, card)
	pending(player, { type = "recycle_then_draw", count = 2, optional = true })
end)

effects.register("transforming_hull", E.ON_PLACE, function(state, player, sector, card)
	reveal_sectors(state, 2)
end)
effects.register("transforming_hull", E.IF_NEW, function(state, player, sector, card)
	pending(player, { type = "buy_sector_discount", discount = 1 })
end)

effects.register("radiation_absorber", E.IF_COMPLETE, function(state, player, sector, card)
	pending(player, { type = "recycle_then_draw", count = 3, optional = true })
end)

-- ─── LIQUIDS TECH ────────────────────────────────────────────────────────────

effects.register("atmospheric_system", E.IF_NEW, function(state, player, sector, card)
	draw(state, player, 1)
end)

effects.register("ice_mining", E.ON_PLACE, function(state, player, sector, card)
	reveal_expeditions(state, 1)
end)

effects.register("medical_hub", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 2)
	pending(player, { type = "recycle", count = 1 })
end)

-- "When you place a liquids card, draw 1. (including this)"
effects.register("biodomes", E.ALWAYS_PLACE, function(state, player, sector, card, placed_card)
	if placed_card and placed_card.color == "liquids" then
		draw(state, player, 1)
	end
end)

effects.register("ice_shield", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 2)
end)
effects.register("ice_shield", E.IF_COMPLETE, function(state, player, sector, card)
	draw(state, player, 1)  -- +1 extra on completion
end)

effects.register("inflatable_hull", E.ON_PLACE, function(state, player, sector, card)
	reveal_sectors(state, 3)
	pending(player, { type = "buy_sector_free", color_filter = {"dust","liquids"} })
end)

effects.register("black_hole_encounter", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "reshuffle_expeditions", max = 3 })
end)

-- "The next tech card placed here costs -1" — stored on the sector until consumed by buy_tech.
effects.register("day_night_cycle", E.ON_PLACE, function(state, player, sector, card)
	sector.cost_discount = (sector.cost_discount or 0) + 1
end)

-- "The next tech card placed here costs -2"
effects.register("seasons", E.ON_PLACE, function(state, player, sector, card)
	sector.cost_discount = (sector.cost_discount or 0) + 2
end)

effects.register("reflectors", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "copy_place_effect", sector_card = sector.sector_card })
end)

effects.register("cryogenics", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "tuck_then_draw", count = 2, facedown = true, optional = true, sector_card = sector.sector_card })
end)

-- ─── ORGANIX TECH ────────────────────────────────────────────────────────────

-- "Gain 1 organix per printed star on the next card placed here."
effects.register("crops", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_sector ~= sector then return end
	if not placed_card or placed_card.id == "crops" then return end
	gain(player, "organix", placed_card.stars or 0)
end)

-- "Draw 1 per printed star on the next card placed here."
effects.register("living_hull", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_sector ~= sector then return end
	if not placed_card or placed_card.id == "living_hull" then return end
	draw(state, player, placed_card.stars or 0)
end)

-- "When you place a new color on this sector, store 1 supply of that color here."
effects.register("pollinators", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_sector ~= sector then return end
	if not placed_card then return end
	local colors = distinct_colors(sector, state.card_db)
	if (colors[placed_card.color] or 0) == 1 then  -- placed card is the only card of its color
		store(sector, placed_card.color)
	end
end)

effects.register("lab_meats", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	gain(player, "dust", 6)
end)

effects.register("artists_quarter", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "tuck", count = 3, facedown = true, sector_card = sector.sector_card })
end)
effects.register("artists_quarter", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	-- Override: tuck 1 faceup instead
	player.pending_effect = { type = "tuck", count = 1, facedown = false, sector_card = sector.sector_card }
end)

effects.register("seedbanks", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_to_store", sector_card = sector.sector_card })
end)

effects.register("computer_mind_interface", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 2)
end)
effects.register("computer_mind_interface", E.IF_COMPLETE, function(state, player, sector, card)
	draw(state, player, 2)  -- +2 extra on completion
end)

effects.register("earth_laser", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 3)
	pending(player, { type = "tuck", count = 1, facedown = true, sector_card = sector.sector_card })
end)

effects.register("fungi", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "store_supply", count = 1, sector_card = sector.sector_card })
end)
effects.register("fungi", E.IF_COMPLETE, function(state, player, sector, card)
	-- Store 1 more (total 2)
	if not player.pending_effect then
		pending(player, { type = "store_supply", count = 1, sector_card = sector.sector_card })
	else
		player.pending_effect.count = (player.pending_effect.count or 0) + 1
	end
end)

-- ─── ELECTRIX TECH ────────────────────────────────────────────────────────────

effects.register("nanobots", E.ON_PLACE, function(state, player, sector, card)
	local colors = distinct_colors(sector, state.card_db)
	local n = 0; for _ in pairs(colors) do n = n + 1 end
	gain(player, "electrix", n)
end)

effects.register("bio_printer", E.ON_PLACE, function(state, player, sector, card)
	gain(player, "organix", 1)
end)
effects.register("bio_printer", E.IF_FULLY_OPTIMIZED, function(state, player, sector, card)
	gain(player, "organix", 1)  -- +1 extra
end)

-- "Store any 1 supply per printed star on the next card placed here."
effects.register("quantum_archives", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_sector ~= sector then return end
	if not placed_card or placed_card.id == "quantum_archives" then return end
	local stars = placed_card.stars or 0
	if stars > 0 then
		pending(player, { type = "store_supply_multi", count = stars, sector_card = sector.sector_card })
	end
end)

effects.register("mass_converter", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 4 })
end)

effects.register("interfleet_comms", E.ON_PLACE, function(state, player, sector, card)
	-- Each player draws 1; full draft pass is complex, simplified to each keep their draw
	for _, p in ipairs(state.players) do draw(state, p, 1) end
end)

effects.register("nano_assembly", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "fuse", count = 3 })
end)
effects.register("nano_assembly", E.IF_COMPLETE, function(state, player, sector, card)
	if player.pending_effect and player.pending_effect.type == "fuse" then
		player.pending_effect.count = (player.pending_effect.count or 0) + 3
	else
		pending(player, { type = "fuse", count = 3 })
	end
end)

-- ─── THRUST TECH ─────────────────────────────────────────────────────────────

effects.register("replicators", E.ON_PLACE, function(state, player, sector, card)
	for _, cid in ipairs(sector.cards) do
		local c = state.card_db[cid]
		if c then store(sector, c.color) end
	end
end)

effects.register("entangled_radio", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 2)
	pending(player, { type = "tuck_from_hand", count = 2, facedown = true, sector_card = sector.sector_card })
end)

-- "When you complete a sector, gain 1 thrust."
effects.register("one_g_thrust", E.ALWAYS_COMPLETE, function(state, player, sector, card)
	gain(player, "thrust", 1)
end)

-- ─── SECTORS ─────────────────────────────────────────────────────────────────

effects.register("simulators", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 2)
end)

effects.register("bioreactor", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_then_draw", count = 4, optional = true })
end)

effects.register("habitation_ring", E.ON_PLACE, function(state, player, sector, card)
	gain(player, "dust", 8)
end)

effects.register("operations", E.ON_PLACE, function(state, player, sector, card)
	local exp_id = #state.market.expedition_deck > 0 and table.remove(state.market.expedition_deck) or nil
	if exp_id then
		table.insert(state.market.expeditions, exp_id)
		local ec = state.card_db[exp_id]
		if ec then gain(player, ec.color, 1) end
	end
end)

effects.register("cargo_bays", E.ON_PLACE, function(state, player, sector, card)
	reveal_sectors(state, 3)
	pending(player, { type = "buy_sector_discount", discount = 1 })
end)

effects.register("central_transport", E.ON_PLACE, function(state, player, sector, card)
	local count = 0
	for _, cid in ipairs(sector.cards) do
		local c = state.card_db[cid]
		if c and (c.color == "metals" or c.color == "electrix") then count = count + 1 end
	end
	if count > 0 then pending(player, { type = "fuse", count = count }) end
end)

effects.register("fabrication", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "choose_effect", options = {
		{ type = "gain_supply", supply = "dust", amount = 6 },
		{ type = "fuse", count = 3 },
	}})
end)

effects.register("preservation", E.ON_PLACE, function(state, player, sector, card)
	local colors = distinct_colors(sector, state.card_db)
	local n = 0; for _ in pairs(colors) do n = n + 1 end
	gain(player, "dust", n * 2)
end)

effects.register("space_bazaar", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_then_draw", count = 3, optional = true })
end)

effects.register("greenhouses", E.ON_PLACE, function(state, player, sector, card)
	store(sector, "liquids")
end)

effects.register("academies", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 3)
end)

effects.register("exosampling", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "tuck", count = 1, facedown = false, sector_card = sector.sector_card })
end)

-- "Draw equal to the printed cost of the card just placed here."
effects.register("parliament", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_sector == sector and placed_card and placed_card.type == "tech" then
		draw(state, player, placed_card.cost or 0)
	end
end)

effects.register("cultivation", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 4)
	pending(player, { type = "tuck_multi", count = 4, optional = true, facedown = true })
end)

effects.register("holoprinters", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "store_supply_multi", count = 2, any_sector = true })
end)

effects.register("probe_launcher", E.ON_PLACE, function(state, player, sector, card)
	reveal_expeditions(state, 1)
end)

effects.register("engines", E.ON_PLACE, function(state, player, sector, card)
	gain(player, "electrix", #player.ship.sectors)
end)

effects.register("astrogation", E.ON_PLACE, function(state, player, sector, card)
	gain(player, "thrust", 2)
end)

effects.register("astra_cultura", E.ON_PLACE, function(state, player, sector, card)
	store(sector, "thrust"); store(sector, "thrust")
end)

effects.register("central_ai", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 3)
end)

effects.register("hibernators", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "store_supply_multi", supply = "dust", count = 3, any_sector = true })
end)

-- ─── EXPEDITIONS (place effects) ─────────────────────────────────────────────

effects.register("caldera_colony", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_to_store" })
end)

effects.register("dna_sculpting", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 3)
	pending(player, { type = "tuck", count = 3, facedown = false, optional = true, sector_card = sector.sector_card })
end)

effects.register("personality_library", E.ON_PLACE, function(state, player, sector, card)
	draw(state, player, 6)
	pending(player, { type = "tuck_multi", count = 6, optional = true, facedown = true })
end)

effects.register("terraformed_planet", E.ON_PLACE, function(state, player, sector, card)
	pending(player, { type = "recycle_tuck_store", count = 4, optional = true })
end)

effects.register("equatorial_superloop", E.ON_PLACE, function(state, player, sector, card)
	-- Score printed stars from the top card of each sector (max 36)
	local total = 0
	for _, s in ipairs(player.ship.sectors) do
		if #s.cards > 0 then
			local c = state.card_db[s.cards[#s.cards]]
			if c then total = math.min(total + (c.stars or 0), 36) end
		end
	end
	player._superloop_vp = (player._superloop_vp or 0) + total
end)

-- ─── ALWAYS_BUY_EXP effects ──────────────────────────────────────────────────

effects.register("industrial_cradle", E.ALWAYS_BUY_EXP, function(state, player, sector, card)
	gain(player, "electrix", 1)
end)

effects.register("galactic_capital", E.ALWAYS_BUY_EXP, function(state, player, sector, card)
	draw(state, player, 1)
end)

effects.register("galactic_museum", E.ALWAYS_BUY_EXP, function(state, player, sector, card)
	pending(player, { type = "tuck", count = 1, facedown = nil })  -- player chooses face
end)

-- "When you place a sector, store 1 supply of that color on that sector."
effects.register("einstein_rosen_portal", E.ALWAYS_PLACE, function(state, player, sector, this_card, placed_card, placed_sector)
	if placed_card and placed_card.type == "sector" and placed_sector then
		store(placed_sector, placed_card.color)
	end
end)

return {}  -- side-effect module; the return value is never used
