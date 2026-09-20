-- Token amounts, as digits.
--
-- A uint256 does not fit in a Luau number. Neither does a PLS balance in wei: 2^53 runs out
-- at about nine thousand PLS, and past that every arithmetic step is quietly approximate.
-- The chain answers in whole units of the smallest denomination, and `read` hands those
-- back as decimal STRINGS for exactly this reason -- so nothing here turns one into a
-- number. It is all string surgery: move the point, compare digit by digit.
--
-- The client has the same three functions in host/Wallet.gd and has to keep them, because
-- it formats its own balances before a place is even loaded. Both are tested against the
-- same cases; if they ever disagree, the one that spends money is wrong.
local Units = {}

--- "1500000" with 6 decimals and 2 places -> "1.5".
---
--- `places` is how many digits after the point to keep, not how many to show: trailing
--- zeroes come off, and a fraction that rounds to nothing leaves the whole number alone
--- rather than "12.00".
function Units.format(dec, decimals, places)
	if type(dec) ~= "string" or dec == "" then return "?" end
	if decimals <= 0 then return dec end
	local s = dec
	while #s <= decimals do s = "0" .. s end
	local whole = s:sub(1, #s - decimals)
	local frac = s:sub(#s - decimals + 1)
	if places <= 0 then return whole end
	while #frac < places do frac = frac .. "0" end
	frac = frac:sub(1, places)
	while #frac > 1 and frac:sub(-1) == "0" do frac = frac:sub(1, #frac - 1) end
	if frac == "0" then return whole end
	return whole .. "." .. frac
end

--- "1.5" with 6 decimals -> "1500000". "" if it is not a number, which the caller must
--- treat as a refusal rather than as zero: sending zero because a field was mistyped is a
--- different and worse mistake than sending nothing.
function Units.toUnits(amount, decimals)
	if type(amount) ~= "string" then return "" end
	local t = amount:match("^%s*(.-)%s*$")
	if t == "" then return "" end
	local dot = t:find("%.", 1)
	local whole = dot and t:sub(1, dot - 1) or t
	local frac = dot and t:sub(dot + 1) or ""
	if whole == "" then whole = "0" end
	if (whole .. frac):match("[^0-9]") then return "" end
	while #frac < decimals do frac = frac .. "0" end
	frac = frac:sub(1, decimals)
	local out = whole .. frac
	while #out > 1 and out:sub(1, 1) == "0" do out = out:sub(2) end
	return out
end

--- Whether a < b, for two decimal strings of any length. Length first, then digits: that
--- is the whole comparison, and it is why this never touches a number.
function Units.lessThan(a, b)
	local x = tostring(a):gsub("^0+", "")
	local y = tostring(b):gsub("^0+", "")
	if #x ~= #y then return #x < #y end
	return x < y
end

return Units
