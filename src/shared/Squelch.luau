-- Who this machine has stopped listening to.
--
-- A module rather than a variable in one script because two client scripts need it: the one
-- that reads /squelch and the chat window that has to decide whether to draw a line. A
-- require is cached per runtime, so both get the same list -- and on the server this module
-- is loaded and never asked anything, which is correct. Squelching is not the server's
-- business: it is one person deciding what they would rather not read.
--
-- By user id and not by name. A name can be changed and two people can pick similar ones;
-- the id is who they are, and it is what a TextSource carries.
local Squelch = {}

local quiet = {}          -- userId -> the name they had when they were squelched

--- Stops listening to them. Returns false if they were already squelched.
function Squelch.add(userId: number, name: string): boolean
	if quiet[userId] then return false end
	quiet[userId] = name
	return true
end

--- Starts listening again. Returns the name they were squelched under, or nil.
function Squelch.remove(userId: number): string?
	local had = quiet[userId]
	quiet[userId] = nil
	return had
end

--- Everyone, forgotten. Returns how many there were.
function Squelch.clear(): number
	local n = 0
	for id in pairs(quiet) do
		quiet[id] = nil
		n += 1
	end
	return n
end

function Squelch.has(userId: number?): boolean
	return userId ~= nil and quiet[userId] ~= nil
end

--- The names, for saying back to whoever asked.
function Squelch.names(): { string }
	local out = {}
	for _, name in pairs(quiet) do table.insert(out, name) end
	table.sort(out)
	return out
end

return Squelch
