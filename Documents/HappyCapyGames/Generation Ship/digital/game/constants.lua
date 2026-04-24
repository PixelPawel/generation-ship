local M = {}

M.SUPPLY = {
	DUST     = "dust",
	LIQUIDS  = "liquids",
	METALS   = "metals",
	ORGANIX  = "organix",
	ELECTRIX = "electrix",
	THRUST   = "thrust",
}

-- Dust -> Metals -> Electrix -> Thrust
-- Dust -> Liquids -> Organix -> Thrust
M.CHAIN_1 = { "dust", "metals", "electrix", "thrust" }
M.CHAIN_2 = { "dust", "liquids", "organix", "thrust" }

-- Position in chain determines payment equivalence (higher = can pay for lower in same chain)
M.CHAIN_RANK = {
	dust     = 1,
	liquids  = 2,
	metals   = 2,
	organix  = 3,
	electrix = 3,
	thrust   = 4,
}

M.CARD_TYPE = {
	SECTOR      = "sector",
	TECH        = "tech",
	EXPEDITION  = "expedition",
	DESTINATION = "destination",
	DANGER      = "danger",
}

M.MAX_SECTORS            = 6
M.MAX_CARDS_PER_SECTOR   = 5
M.GENERATIONS            = 4
M.CARDS_PER_GENERATION   = 6
M.EXPEDITIONS_REVEALED   = 3
M.SECTOR_PILES           = 3
M.SECTORS_PER_PILE       = 10

M.STARTING_SUPPLIES = {
	dust     = 4,
	liquids  = 2,
	metals   = 2,
	organix  = 1,
	electrix = 1,
	thrust   = 0,
}

M.PHASE = {
	DRAW               = "draw",
	REVEAL_EXPEDITIONS = "reveal_expeditions",
	REVEAL_SECTORS     = "reveal_sectors",
	ACTIONS            = "actions",
	GAIN_SUPPLIES      = "gain_supplies",
	SCORING            = "scoring",
}

M.ACTION = {
	BUY_TECH    = "buy_tech",
	BUY_SECTOR  = "buy_sector",
	BID         = "bid",
	PASS        = "pass",
	RESEARCH    = "research",
	RECYCLE     = "recycle",
	FUSE        = "fuse",
	PLACE_EXPEDITION = "place_expedition",
}

return M
