local C = require("game.constants")

local M = {}

local function in_same_chain(a, b)
	local function has(chain, x)
		for _, v in ipairs(chain) do if v == x then return true end end
	end
	return (has(C.CHAIN_1, a) and has(C.CHAIN_1, b))
		or (has(C.CHAIN_2, a) and has(C.CHAIN_2, b))
end

-- Returns true if payment_type is valid to pay a card that costs cost_type.
-- Rule: same type, OR higher rank in the same supply chain.
function M.can_pay_with(cost_type, payment_type)
	if cost_type == payment_type then return true end
	if not in_same_chain(cost_type, payment_type) then return false end
	return C.CHAIN_RANK[payment_type] >= C.CHAIN_RANK[cost_type]
end

-- Returns list of supply types that supply_type can be fused into (2:1).
function M.fuse_targets(supply_type)
	local seen, result = {}, {}
	for _, chain in ipairs({ C.CHAIN_1, C.CHAIN_2 }) do
		for i, v in ipairs(chain) do
			if v == supply_type and chain[i + 1] and not seen[chain[i + 1]] then
				seen[chain[i + 1]] = true
				table.insert(result, chain[i + 1])
			end
		end
	end
	return result
end

-- Validates and applies a fuse: lose 2 of supply_type, gain 1 of target_type.
function M.apply_fuse(supplies, supply_type, target_type)
	if (supplies[supply_type] or 0) < 2 then
		return false, "need 2 " .. supply_type .. " to fuse"
	end
	local valid = false
	for _, t in ipairs(M.fuse_targets(supply_type)) do
		if t == target_type then valid = true; break end
	end
	if not valid then
		return false, target_type .. " is not a valid fuse target for " .. supply_type
	end
	supplies[supply_type] = supplies[supply_type] - 2
	supplies[target_type] = (supplies[target_type] or 0) + 1
	return true
end

-- Validates and spends `amount` of payment_type to cover a card costing cost_type.
-- amount defaults to 1. payment_type defaults to cost_type.
function M.spend(supplies, cost_type, amount, payment_type)
	if type(amount) ~= "number" then
		-- backward-compat: called as spend(supplies, cost_type, payment_type)
		payment_type, amount = amount, 1
	end
	amount       = amount or 1
	payment_type = payment_type or cost_type
	if not M.can_pay_with(cost_type, payment_type) then
		return false, "cannot use " .. payment_type .. " to pay for " .. cost_type
	end
	if (supplies[payment_type] or 0) < amount then
		return false, "need " .. amount .. " " .. payment_type .. " (have " .. (supplies[payment_type] or 0) .. ")"
	end
	supplies[payment_type] = supplies[payment_type] - amount
	return true
end

return M
