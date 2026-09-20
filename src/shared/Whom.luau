-- Which player somebody meant when they typed a name.
--
-- Shared because two things ask it and they must not disagree: /w on the server, which needs
-- the player to put in a channel, and /squelch on the client, which needs the player to stop
-- listening to. Typing the same name at both and being answered differently is the kind of
-- fault nobody reports because they assume they mistyped.
local Players = game:GetService("Players")

local Whom = {}

--- The player somebody meant, or nil and a line to say to them.
---
--- Display name or user name, and case does not matter: you are typing a name you can read
--- over somebody's head, not filling in a form.
---
--- An exact match wins outright, which is what keeps a short name reachable when a longer one
--- starts with it -- "/w Mike" gets Mike and not Mikey. Failing that, one unambiguous prefix:
--- "/w fun" reaches Funmaster Mike. If two people both begin that way nobody is reached and
--- the typist is told, because guessing which of two people a private message was meant for
--- is the one wrong answer available.
function Whom.find(typed: string): (Player?, string?)
	if type(typed) ~= "string" or typed == "" then return nil, "Who?" end
	local want = typed:lower()
	local partial = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local user, shown = p.Name:lower(), p.DisplayName:lower()
		if user == want or shown == want then return p, nil end
		if user:sub(1, #want) == want or shown:sub(1, #want) == want then
			table.insert(partial, p)
		end
	end
	if #partial == 1 then return partial[1], nil end
	if #partial > 1 then
		local names = {}
		for _, p in ipairs(partial) do table.insert(names, p.DisplayName) end
		return nil, ("There is more than one " .. typed .. " here: " .. table.concat(names, ", "))
	end
	return nil, ("There is nobody here called " .. typed .. ".")
end

return Whom
