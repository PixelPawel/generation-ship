-- Card database for Generation Ship: From Dust to Thrust.
-- Auto-generated from card artwork; verify card text against physical cards before shipping.
-- effect_text uses plain English; effects.lua maps ids to executable Lua functions.

local M = {}

M.db = {}

local function card(id, def)
	def.id = id
	M.db[id] = def
end

-- ── TECH: DUST ───────────────────────────────────────────────────────────────

card("mag_net",              { type="tech", color="dust", cost=0, stars=0, effect_type="place", effect_text="" })
card("inflatable_habs",      { type="tech", color="dust", cost=2, stars=1, effect_type="score", effect_text="" })
card("cargo_drones",         { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="You may move stored supplies and tucked cards between sectors." })
card("containers",           { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Store 1 dust, 1 metals or 1 liquids." })
card("chemlabs",             { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Fuse 1:1 two times. If this sector is fully optimized, also gain 2 dust." })
card("hangars",              { type="tech", color="dust", cost=1, stars=0, effect_type="place", effect_text="If this sector is new, gain 3 dust." })
card("ancient_airlock",      { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Reveal 1 sector. If this sector is new, buy 1 sector for -1." })
card("chemical_synthesizer", { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Tuck 1 card facedown under this sector, then draw 1." })
card("asteroid_capture",     { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Fuse 1:1 two times. If this sector is new, also draw 1." })
card("printed_library",      { type="tech", color="dust", cost=2, stars=0, effect_type="place", effect_text="Tuck 1 card facedown under this sector. If this sector is fully optimized, also draw 2." })
card("gas_cloud",            { type="tech", color="dust", cost=0, stars=0, effect_type="place", effect_text="Every player draws 1." })
card("osmosis_filter",       { type="tech", color="dust", cost=1, stars=0, effect_type="place", effect_text="Recycle 1, then draw 1." })
card("passing_comet",        { type="tech", color="dust", cost=1, stars=0, effect_type="place", effect_text="Draw 1, then recycle it." })

-- ── TECH: METALS ─────────────────────────────────────────────────────────────

card("magnetized_hull",    { type="tech", color="metals", cost=1, stars=0, effect_type="place",  effect_text="If this sector is complete, gain 1 organix or 1 electrix." })
card("hydrogen_cell",      { type="tech", color="metals", cost=1, stars=0, effect_type="place",  effect_text="If this sector is new, fuse 1:1 two times." })
card("smelter",            { type="tech", color="metals", cost=2, stars=0, effect_type="place",  effect_text="Fuse 1:1 three times. If this sector is fully optimized, store 1 metals." })
card("fusion_synthesizer", { type="tech", color="metals", cost=2, stars=0, effect_type="place",  effect_text="Fuse all your dust 1:1." })
card("cleaning_robot",     { type="tech", color="metals", cost=3, stars=0, effect_type="place",  effect_text="Recycle 1 but gain the supply twice." })
card("deep_space_radar",   { type="tech", color="metals", cost=2, stars=0, effect_type="place",  effect_text="Reveal 2 expeditions. You may bid on 1." })
card("robotic_workforce",  { type="tech", color="metals", cost=2, stars=0, effect_type="place",  effect_text="If this sector is new, recycle up to 2, then draw that many." })
card("transforming_hull",  { type="tech", color="metals", cost=2, stars=0, effect_type="place",  effect_text="Reveal 2 sectors. If this sector is new, buy 1 sector for -1." })
card("cargo_pods",         { type="tech", color="metals", cost=1, stars=1, effect_type="score",  effect_text="" })
card("cargo_landers",      { type="tech", color="metals", cost=2, stars=2, effect_type="score",  effect_text="" })
card("trash_compactor",    { type="tech", color="metals", cost=3, stars=0, effect_type="always", effect_text="When you recycle, gain 1 extra supply." })
card("waste_management",   { type="tech", color="metals", cost=2, stars=0, effect_type="always", effect_text="Buy liquids tech and sectors for -1." })
card("radiation_absorber", { type="tech", color="metals", cost=3, stars=0, effect_type="place",  effect_text="If this sector is complete, recycle up to 3, then draw that many." })

-- ── TECH: LIQUIDS ────────────────────────────────────────────────────────────

card("atmospheric_system",   { type="tech", color="liquids", cost=1, stars=0, effect_type="place",  effect_text="If this sector is new, draw 1." })
card("ice_mining",           { type="tech", color="liquids", cost=1, stars=0, effect_type="place",  effect_text="Reveal 1 expedition. You may bid on it." })
card("medical_hub",          { type="tech", color="liquids", cost=2, stars=0, effect_type="place",  effect_text="Draw 2, recycle 1 of them." })
card("purifier",             { type="tech", color="liquids", cost=1, stars=1, effect_type="score",  effect_text="" })
card("soil_maker",           { type="tech", color="liquids", cost=2, stars=2, effect_type="score",  effect_text="" })
card("biodomes",             { type="tech", color="liquids", cost=3, stars=0, effect_type="always", effect_text="When you place a liquids card, draw 1. (including this)" })
card("ice_shield",           { type="tech", color="liquids", cost=3, stars=0, effect_type="place",  effect_text="Draw 2. If this sector is complete, draw 3 instead." })
card("inflatable_hull",      { type="tech", color="liquids", cost=3, stars=0, effect_type="place",  effect_text="Reveal 3 sectors. Buy 1 dust or 1 liquids sector for free." })
card("seasons",              { type="tech", color="liquids", cost=4, stars=0, effect_type="always", effect_text="The next tech card placed here costs -2." })
card("black_hole_encounter", { type="tech", color="liquids", cost=1, stars=0, effect_type="place",  effect_text="Shuffle up to 3 expeditions back into the deck, then reveal that many." })
card("day_night_cycle",      { type="tech", color="liquids", cost=2, stars=0, effect_type="always", effect_text="The next tech card placed here costs -1." })
card("reflectors",           { type="tech", color="liquids", cost=2, stars=0, effect_type="place",  effect_text="Copy the place effect of another card in this sector." })
card("cryogenics",           { type="tech", color="liquids", cost=2, stars=0, effect_type="place",  effect_text="Tuck up to 2 cards facedown under this sector, then draw that many." })

-- ── TECH: ORGANIX ────────────────────────────────────────────────────────────

card("fish",                    { type="tech", color="organix", cost=1, stars=1, effect_type="score",  effect_text="" })
card("birds",                   { type="tech", color="organix", cost=2, stars=2, effect_type="score",  effect_text="" })
card("mammals",                 { type="tech", color="organix", cost=3, stars=3, effect_type="score",  effect_text="" })
card("crops",                   { type="tech", color="organix", cost=1, stars=0, effect_type="always", effect_text="Gain 1 organix per printed star on the next card placed here." })
card("living_hull",             { type="tech", color="organix", cost=2, stars=0, effect_type="always", effect_text="Draw 1 per printed star on the next card placed here." })
card("pollinators",             { type="tech", color="organix", cost=1, stars=0, effect_type="always", effect_text="When you place a new color on this sector, store 1 supply of that color here." })
card("lab_meats",               { type="tech", color="organix", cost=2, stars=0, effect_type="place",  effect_text="If this sector is fully optimized, gain 6 dust." })
card("artists_quarter",         { type="tech", color="organix", cost=2, stars=0, effect_type="place",  effect_text="Tuck 3 cards facedown under this sector. If this sector is fully optimized, tuck 1 faceup instead." })
card("seedbanks",               { type="tech", color="organix", cost=2, stars=0, effect_type="place",  effect_text="Recycle any cards, but store the supplies on this sector instead." })
card("computer_mind_interface", { type="tech", color="organix", cost=3, stars=0, effect_type="place",  effect_text="Draw 2. If this sector is complete, draw 4 instead." })
card("earth_laser",             { type="tech", color="organix", cost=2, stars=0, effect_type="place",  effect_text="Draw 3, tuck 1 of them facedown under this sector." })
card("fungi",                   { type="tech", color="organix", cost=2, stars=0, effect_type="place",  effect_text="Store 1 supply. If this sector is complete, store 2 instead." })

-- ── TECH: ELECTRIX ───────────────────────────────────────────────────────────

card("portable_reactor",  { type="tech", color="electrix", cost=1, stars=1, effect_type="score",  effect_text="" })
card("solar_power",       { type="tech", color="electrix", cost=2, stars=2, effect_type="score",  effect_text="" })
card("fusion_power",      { type="tech", color="electrix", cost=3, stars=3, effect_type="score",  effect_text="" })
card("nanobots",          { type="tech", color="electrix", cost=3, stars=0, effect_type="place",  effect_text="Gain 1 electrix per different color on this sector." })
card("bio_printer",       { type="tech", color="electrix", cost=2, stars=0, effect_type="place",  effect_text="Gain 1 organix. If this sector is fully optimized, gain 2 organix instead." })
card("quantum_archives",  { type="tech", color="electrix", cost=2, stars=0, effect_type="always", effect_text="Store any 1 supply per printed star on the next card placed here." })
card("mass_converter",    { type="tech", color="electrix", cost=2, stars=0, effect_type="place",  effect_text="Fuse 1:1 four times." })
card("interfleet_comms",  { type="tech", color="electrix", cost=1, stars=0, effect_type="place",  effect_text="Draw 1 per player. Keep 1, pass remaining left; each player keeps 1." })
card("nano_assembly",     { type="tech", color="electrix", cost=2, stars=0, effect_type="place",  effect_text="Fuse 1:1 three times, or six times if this sector is complete." })
card("industrial_academy",{ type="tech", color="metals",  cost=1, stars=0, effect_type="always", effect_text="Buy metals tech and sector for -1." })
card("cloning_lab",       { type="tech", color="organix", cost=2, stars=0, effect_type="always", effect_text="Buy organix tech and sector for -1." })
card("physics_academy",   { type="tech", color="electrix", cost=2, stars=0, effect_type="always", effect_text="Buy electrix tech and sector for -1." })
card("skyhook",           { type="tech", color="electrix", cost=3, stars=0, effect_type="always", effect_text="Buy any card with a printed star for -1." })

-- ── TECH: THRUST ─────────────────────────────────────────────────────────────

card("markets",              { type="tech", color="thrust", cost=1, stars=1,  effect_type="score",  effect_text="" })
card("theaters",             { type="tech", color="thrust", cost=2, stars=3,  effect_type="score",  effect_text="" })
card("civic_government",     { type="tech", color="thrust", cost=3, stars=5,  effect_type="score",  effect_text="" })
card("galactic_culture",     { type="tech", color="thrust", cost=4, stars=7,  effect_type="score",  effect_text="" })
card("one_g_thrust",         { type="tech", color="thrust", cost=3, stars=0,  effect_type="always", effect_text="When you complete a sector, gain 1 thrust." })
card("replicators",          { type="tech", color="thrust", cost=3, stars=0,  effect_type="place",  effect_text="For each card here, store 1 supply of that color on this sector. (including this)" })
card("entangled_radio",      { type="tech", color="thrust", cost=2, stars=0,  effect_type="place",  effect_text="Recycle 2, tuck them facedown under this sector, then draw 2." })
card("tectonic_accelerator", { type="tech", color="thrust", cost=2, stars=9,  effect_type="score",  effect_text="Score only if you have 6 fully optimized sectors." })
card("magneto_sphere",       { type="tech", color="thrust", cost=2, stars=6,  effect_type="score",  effect_text="Score only if you have 9+ tucked cards." })
card("genesis_device",       { type="tech", color="thrust", cost=2, stars=6,  effect_type="score",  effect_text="Score only if you have 6+ thrust." })
card("space_elevator",       { type="tech", color="thrust", cost=2, stars=6,  effect_type="score",  effect_text="Score only if you have 12+ stored supplies." })
card("atmosphere_processor", { type="tech", color="thrust", cost=2, stars=9,  effect_type="score",  effect_text="Score only if you have 6 complete sectors." })

-- ── SECTORS ──────────────────────────────────────────────────────────────────
-- optimize_groups: each table = one optimization tier. color+required cards
-- needed in that group to trigger the tier.

card("hibernators", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="metals",required=1}, {color="liquids",required=1} },
	effect = "Store 3 dust on any sector.",
})
card("simulators", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="metals",required=1}, {color="electrix",required=1} },
	effect = "Draw 2.",
})
card("bioreactor", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="liquids",required=1}, {color="organix",required=1} },
	effect = "Recycle up to 4 cards, then draw that many.",
})
card("habitation_ring", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="liquids",required=2} },
	effect = "Gain 8 dust.",
})
card("operations", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="metals",required=2} },
	effect = "Reveal 1 expedition, gain 1 supply of that color. You may bid on it.",
})
card("cargo_bays", {
	type="sector", color="dust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=4} },
	effect = "Reveal up to 3 sectors. Buy 1 sector for -1.",
})
card("central_transport", {
	type="sector", color="metals", cost=2, stars=1,
	optimize_groups = { {color="metals",required=1}, {color="metals",required=1}, {color="metals",required=1} },
	effect = "Fuse 1:1 for each metals and electrix here. (including this)",
})
card("fabrication", {
	type="sector", color="metals", cost=3, stars=1,
	optimize_groups = { {color="dust",required=2}, {color="metals",required=2} },
	effect = "Gain 6 dust OR fuse 1:1 three times.",
})
card("preservation", {
	type="sector", color="metals", cost=3, stars=1,
	optimize_groups = { {color="metals",required=2}, {color="metals",required=2} },
	effect = "Gain 2 dust per different color here, including this.",
})
card("space_bazaar", {
	type="sector", color="liquids", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="electrix",required=1}, {color="liquids",required=2} },
	effect = "Recycle up to 3, then draw that many.",
})
card("greenhouses", {
	type="sector", color="liquids", cost=2, stars=1,
	optimize_groups = { {color="liquids",required=1}, {color="liquids",required=1}, {color="liquids",required=1} },
	effect = "Store 1 liquids here. Gain 1 star per stored liquids here.",
})
card("academies", {
	type="sector", color="liquids", cost=2, stars=1,
	optimize_groups = { {color="liquids",required=1}, {color="metals",required=1}, {color="organix",required=1} },
	effect = "Draw 3.",
})
card("exosampling", {
	type="sector", color="organix", cost=2, stars=1,
	optimize_groups = { {color="organix",required=1}, {color="organix",required=1}, {color="organix",required=1} },
	effect = "Tuck 1 card faceup here.",
})
card("parliament", {
	type="sector", color="organix", cost=2, stars=1,
	optimize_groups = { {color="metals",required=1}, {color="liquids",required=1}, {color="organix",required=1}, {color="thrust",required=1} },
	effect = "Draw equal to the printed cost of the card just placed.",
})
card("cultivation", {
	type="sector", color="organix", cost=2, stars=1,
	optimize_groups = { {color="organix",required=1}, {color="metals",required=1}, {color="electrix",required=1}, {color="thrust",required=1} },
	effect = "Draw 4, tuck up to 4 cards facedown under any sectors.",
})
card("holoprinters", {
	type="sector", color="electrix", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="metals",required=1}, {color="organix",required=1}, {color="electrix",required=1} },
	effect = "Store any 2 supplies on any sectors.",
})
card("probe_launcher", {
	type="sector", color="electrix", cost=2, stars=1,
	optimize_groups = { {color="electrix",required=1}, {color="electrix",required=1}, {color="electrix",required=1} },
	effect = "Reveal 1 expedition. You may bid on any expedition.",
})
card("engines", {
	type="sector", color="electrix", cost=2, stars=1,
	optimize_groups = { {color="metals",required=1}, {color="liquids",required=1}, {color="electrix",required=1}, {color="thrust",required=1} },
	effect = "Gain 1 electrix per sector you have.",
})
card("astrogation", {
	type="sector", color="thrust", cost=2, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="organix",required=1}, {color="liquids",required=1}, {color="electrix",required=1} },
	effect = "Gain 2 thrust.",
})
card("astra_cultura", {
	type="sector", color="thrust", cost=3, stars=1,
	optimize_groups = { {color="metals",required=1}, {color="electrix",required=1}, {color="thrust",required=1} },
	effect = "Store 2 thrust here. Gain 2 stars per stored thrust here.",
})
card("central_ai", {
	type="sector", color="thrust", cost=3, stars=1,
	optimize_groups = { {color="dust",required=1}, {color="organix",required=1}, {color="metals",required=1}, {color="thrust",required=1} },
	effect = "Draw 3.",
})

-- ── EXPEDITIONS ──────────────────────────────────────────────────────────────

card("caldera_colony",        { type="expedition", color="metals",  cost=3, stars=3, effect_type="place",  effect_text="Recycle any cards from 1 sector and store the supplies on that sector." })
card("interstellar_trade_port",{ type="expedition", color="metals", cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per sector with 2+ stored supplies. Max 12." })
card("lagrange_complex",      { type="expedition", color="metals",  cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per fully optimized sector. Max 12." })
card("self_replication",      { type="expedition", color="metals",  cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per metals card on your ship. (including this) Max 12." })
card("polar_planet",          { type="expedition", color="liquids", cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per different color of stored supply on one sector. Max 12." })
card("waterworld",            { type="expedition", color="liquids", cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per sector with 1+ liquids. Max 12." })
card("alliance",              { type="expedition", color="liquids", cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per expedition another player has. Max 12." })
card("millions_of_colonists", { type="expedition", color="liquids", cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per complete sector. Max 12." })
card("urbanized_planet",      { type="expedition", color="electrix",cost=2, stars=0, effect_type="always", effect_text="Gain 15 stars per full set of all 6 different stored supply types." })
card("cloud_colony",          { type="expedition", color="electrix",cost=3, stars=0, effect_type="always", effect_text="Gain 1 star per facedown tucked card. Max 18." })
card("hive_mind",             { type="expedition", color="electrix",cost=3, stars=0, effect_type="always", effect_text="Gain 1 star per electrix card on your ship. (including this) Max 12." })
card("industrial_cradle",     { type="expedition", color="electrix",cost=2, stars=5, effect_type="always", effect_text="Gain 1 electrix when you buy an expedition." })
card("asteroid_colonies",     { type="expedition", color="electrix",cost=3, stars=0, effect_type="always", effect_text="Gain 3 stars per sector that is both complete and fully optimized. Max 18." })
card("aeon_ark",              { type="expedition", color="electrix",cost=2, stars=0, effect_type="always", effect_text="Gain 2 stars per different sector color. Max 12." })
card("astrobio_propagation",  { type="expedition", color="organix", cost=2, stars=0, effect_type="always", effect_text="Gain 3 stars per sector with 2+ tucked cards. Max 18." })
card("bio_compatible_world",  { type="expedition", color="organix", cost=2, stars=0, effect_type="always", effect_text="Gain 1 star per organix card on your ship. (including this) Max 12." })
card("dna_sculpting",         { type="expedition", color="organix", cost=3, stars=0, effect_type="place",  effect_text="Draw 3. Tuck up to 3 cards faceup under this sector." })
card("personality_library",   { type="expedition", color="organix", cost=2, stars=1, effect_type="place",  effect_text="Draw 6. Tuck up to 6 cards facedown." })
card("galactic_museum",       { type="expedition", color="organix", cost=2, stars=1, effect_type="always", effect_text="Tuck 1 card faceup or facedown when you buy an expedition." })
card("terraformed_planet",    { type="expedition", color="organix", cost=2, stars=1, effect_type="place",  effect_text="Recycle and tuck up to 4 cards facedown. You may store the recycled supplies." })
card("galactic_capital",      { type="expedition", color="thrust",  cost=3, stars=7, effect_type="always", effect_text="Draw 1 when you buy an expedition." })
card("pleasure_planet",       { type="expedition", color="thrust",  cost=2, stars=0, effect_type="always", effect_text="Gain 3 stars per different expedition color. Max 15." })
card("equatorial_superloop",  { type="expedition", color="thrust",  cost=3, stars=0, effect_type="place",  effect_text="Copy up to 6 printed stars from the top card in each sector. Max 36." })
card("exodus_fleets",         { type="expedition", color="thrust",  cost=3, stars=0, effect_type="always", effect_text="Gain 2 stars per thrust card on your ship. (including this) Max 24." })
card("earth_2_0",             { type="expedition", color="thrust",  cost=4, stars=0, effect_type="always", effect_text="Gain 2 stars per star on cards that are not tucked." })
card("einstein_rosen_portal", { type="expedition", color="thrust",  cost=2, stars=0, effect_type="always", effect_text="When you place a sector, store 1 supply of that color on that sector." })

-- ── DANGERS (co-op mode) ─────────────────────────────────────────────────────
-- effect_type: "place" = triggers once on reveal and again each generation if unsolved
--              "always" = continuous effect while unresolved
-- solve_text: what you do to solve it

card("asteroid_belt",        { type="danger", effect_type="place",  effect_text="Shuttle cost +1 dust.",                                               solve_text="Pay 2 dust per player." })
card("high_speed_impacts",   { type="danger", effect_type="place",  effect_text="Flip the top card of one sector facedown per player.",                solve_text="All players convert 3 supplies 1:1 to dust." })
card("hull_breach",          { type="danger", effect_type="place",  effect_text="Destroy the top card in your right-most sector.",                     solve_text="Complete your right-most sector." })
card("mining_incident",      { type="danger", effect_type="always", effect_text="Cannot gain dust (you can still store).",                             solve_text="Fully optimize a dust sector." })
card("accelerated_rusting",  { type="danger", effect_type="place",  effect_text="Destroy the top 2 cards in your left-most sector.",                  solve_text="Fully optimize a metals sector." })
card("smelter_accident",     { type="danger", effect_type="always", effect_text="Cannot fuse or gain metals (you can still store).",                   solve_text="Discard 1 metals per player." })
card("engine_overload",      { type="danger", effect_type="place",  effect_text="Each player chooses: Pay 2 metals or destroy 2 cards.",               solve_text="Pay 2 metals per player." })
card("totalitarianism",      { type="danger", effect_type="always", effect_text="Cannot use Always effects.",                                          solve_text="Discard cards worth 2 VP per player." })
card("anti_fusion_field",    { type="danger", effect_type="always", effect_text="Cannot store or fuse liquids (you can still gain).",                  solve_text="Fully optimize a liquids sector." })
card("algal_megabloom",      { type="danger", effect_type="place",  effect_text="Each player chooses: Lose 2 stored supplies or discard 2.",           solve_text="Pay 2 liquids per player." })
card("volatile_leak",        { type="danger", effect_type="always", effect_text="Liquids cards cost +2.",                                              solve_text="Discard 1 liquids per player." })
card("water_shortage",       { type="danger", effect_type="always", effect_text="Do not gain liquids at the end of a generation.",                     solve_text="Have 3+ liquids stored in 1 sector." })
card("oxygen_eating_supercolony",{ type="danger", effect_type="place", effect_text="Discard 3 advanced sectors from the market.",                      solve_text="Empty 1 of the sector decks." })
card("pandemic",             { type="danger", effect_type="always", effect_text="Cannot recycle cards.",                                               solve_text="Discard 1 organix per player." })
card("mutations",            { type="danger", effect_type="place",  effect_text="Each player destroys 1 card (organix if possible).",                  solve_text="Lose 1 tucked card per player." })
card("infestation",          { type="danger", effect_type="always", effect_text="Sectors with any organix cannot be optimized.",                       solve_text="Flip 1 facedown tucked card faceup per player." })
card("plant_virus",          { type="danger", effect_type="always", effect_text="Do not gain organix at the end of a generation.",                     solve_text="Have 3+ organix stored in 1 sector." })
card("alien_pathogen",       { type="danger", effect_type="always", effect_text="Organix cards cost +2.",                                              solve_text="Flip a faceup tucked card with 3+ VP facedown." })
card("gamma_ray_burst",      { type="danger", effect_type="place",  effect_text="Each player chooses: Lose 2 stored supplies or 2 tucked cards.",      solve_text="Complete a fully optimized sector." })
card("cybernetic_psycho",    { type="danger", effect_type="place",  effect_text="Each player destroys 1 card (metals if possible).",                   solve_text="Empty 1 of the sector decks." })
card("neural_gear_malfunction",{ type="danger", effect_type="always", effect_text="Cannot tuck cards or store supplies.",                              solve_text="Discard cards worth 3 VP per player." })
card("system_failure",       { type="danger", effect_type="place",  effect_text="Store 1 metals here. Reveal 1 danger per metals stored here.",        solve_text="Discard 1 metals per player." })
card("robot_uprising",       { type="danger", effect_type="always", effect_text="Sector cards cost +2.",                                               solve_text="Pay 1 metals per player." })
card("nanite_plague",        { type="danger", effect_type="always", effect_text="Do not gain metals at the end of a generation.",                      solve_text="Discard cards worth 3 VP per player." })
card("undetected_wormhole",  { type="danger", effect_type="place",  effect_text="Shuffle all expeditions back into the deck.",                         solve_text="Buy 1 expedition." })
card("sabotage",             { type="danger", effect_type="place",  effect_text="Each player removes the sector with the fewest cards.",               solve_text="Destroy 1 expedition on any sector." })
card("rogue_ai",             { type="danger", effect_type="always", effect_text="All cards cost +1.",                                                  solve_text="Discard 2 metals and/or expeditions per player." })
card("barbarism",            { type="danger", effect_type="always", effect_text="Cannot place or recycle expeditions.",                                solve_text="Complete a metals or organix sector." })
card("dimension_pocket",     { type="danger", effect_type="place",  effect_text="Each player passes their hand to the left.",                         solve_text="Discard 1 card of each color." })
card("unstable_wormhole",    { type="danger", effect_type="place",  effect_text="Each player discards 3 cards.",                                       solve_text="Any player has no cards in hand." })

-- ── DESTINATIONS (co-op mode) ────────────────────────────────────────────────
-- mission_type: "per_player" = all players pool; "all_players" = each must reach target
-- mission_metric: what is measured for mission completion

card("titan",           { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=5,  mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("mars",            { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=3,  mission_metric="any_supply",         shuttle_supply="dust", shuttle_cost=1 })
card("venus",           { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=5,  mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("europa",          { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=2,  mission_metric="optimized_sectors",  shuttle_supply="dust", shuttle_cost=1 })
card("jupiter",         { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=1,  mission_metric="expeditions",        shuttle_supply="dust", shuttle_cost=1 })
card("luna",            { type="destination", difficulty="easy",   duration=2, mission_type="per_player", mission_value=2,  mission_metric="complete_sectors",   shuttle_supply="dust", shuttle_cost=0 })
card("alpha_centauri",  { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=18, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("sirius",          { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=15, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("tau_ceti",        { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=15, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("epsilon_eridani", { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=15, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("cygnus",          { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=15, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("procyon",         { type="destination", difficulty="medium", duration=3, mission_type="per_player", mission_value=7,  mission_metric="vp",                shuttle_supply="dust", shuttle_cost=1 })
card("beta_hydri",      { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=30, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=2 })
card("las_vega",        { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=30, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=2 })
card("pollux",          { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=30, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=2 })
card("arcturus",        { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=30, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=2 })
card("gamma_serpentis", { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=1,  mission_metric="all_supply_types",   shuttle_supply="dust", shuttle_cost=2 })
card("theta_persei",    { type="destination", difficulty="hard",   duration=4, mission_type="per_player", mission_value=40, mission_metric="vp",                shuttle_supply="dust", shuttle_cost=2 })

-- ── DECK COMPOSITION ─────────────────────────────────────────────────────────
-- How many copies of each card go into the shuffled deck.
-- Rare/powerful cards = 1 copy; standard cards = 2 copies.

M.copies = {
	-- Tech (1 copy = rare/powerful, 2 = standard)
	seasons=1, waste_management=1, crops=1, living_hull=1, pollinators=1,
	quantum_archives=1, industrial_academy=1, cloning_lab=1, physics_academy=1,
	skyhook=1, tectonic_accelerator=1, magneto_sphere=1, genesis_device=1,
	space_elevator=1, atmosphere_processor=1,
}
local function copies(id) return M.copies[id] or 2 end

-- Returns a flat list of card ids for a given type (shuffle before use).
function M.build_deck(card_type)
	local deck = {}
	for id, def in pairs(M.db) do
		if def.type == card_type then
			for _ = 1, copies(id) do
				table.insert(deck, id)
			end
		end
	end
	return deck
end

-- Returns a list of unique ids of a given type (for destinations, dangers).
function M.list(card_type)
	local result = {}
	for id, def in pairs(M.db) do
		if def.type == card_type then table.insert(result, id) end
	end
	return result
end

return M
