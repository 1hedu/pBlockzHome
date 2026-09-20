-- Bytes as text, because `store` takes text.
--
-- The host will only accept a blob as base64: an attribute is a string, and a Luau string
-- holding raw bytes does not survive JSONEncode. So everything that goes on chain from here
-- -- a drawing, a model, a description -- comes through this.
--
-- It lived in Png.luau, which is where it was first needed. That was fine while the tailor
-- was the only thing publishing; it is not fine now that an Engram publishes two documents
-- with no picture anywhere in them. One implementation, named for what it does.
local Base64 = {}

local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

--- A string of bytes, base64'd. Three bytes in, four characters out, padded with "=".
function Base64.encode(bytes)
	local out, i = {}, 1
	while i <= #bytes do
		local a = string.byte(bytes, i)
		local b = string.byte(bytes, i + 1)
		local c = string.byte(bytes, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local function ch(shift)
			local k = bit32.band(bit32.rshift(n, shift), 63)
			return CHARS:sub(k + 1, k + 1)
		end
		out[#out + 1] = ch(18) .. ch(12) .. (b and ch(6) or "=") .. (c and ch(0) or "=")
		i += 3
	end
	return table.concat(out)
end

return Base64
