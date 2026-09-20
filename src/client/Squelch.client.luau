-- /squelch and /unsquelch: one person deciding what they would rather not read.
--
-- ---- nothing of this reaches the server -------------------------------------------------
-- And nothing should. Squelching does not stop somebody speaking, it stops you hearing them,
-- so the only machine that has to know is this one. A server that held the list would be
-- deciding for you who may talk to you -- which is moderation, a different thing with
-- different rules -- and it would carry a per-player filter on every line it sent.
--
-- So the command is made HERE. TextChatService replicates, but a client's own changes to it
-- do not go up: a TextChatCommand created on this side exists on this side, and the runtime
-- finds it when a line beginning with "/" is sent because it scans the service's descendants
-- on the client before sending anything. The "Command" message still goes up with an id the
-- server cannot resolve, and the server drops it, which is the right amount of nothing.
--
-- ---- what it silences ------------------------------------------------------------------
-- Every line they say, in the general chat and in a whisper both. Chat.client.luau asks
-- Squelch.has before it draws, so there is one place that decides and no channel that can be
-- forgotten. What it does not silence is the game: their hearts still hang over their head
-- and their spoon still connects. This is a chat window setting.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Squelch = require(ReplicatedStorage:WaitForChild("Squelch"))
local Whom = require(ReplicatedStorage:WaitForChild("Whom"))

local me = Players.LocalPlayer

--- Says something in the log without sending it anywhere: this machine only, which is where
--- an answer about your own typing belongs.
local function tell(what: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general then
		pcall(function() general:DisplaySystemMessage(what) end)
	else
		warn("squelch: " .. what)
	end
end

--- The name typed after the alias, or "" if there was none.
local function argOf(text: string): string
	return (text:match("^%S+%s+(.+)$") or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function squelch(text: string)
	local typed = argOf(text)
	if typed == "" then
		local names = Squelch.names()
		tell(#names == 0 and "You have not squelched anybody. /squelch <name> to stop reading them."
			or ("Squelched: " .. table.concat(names, ", ")))
		return
	end
	local them, why = Whom.find(typed)
	if not them then
		tell(why or ("There is nobody here called " .. typed .. "."))
		return
	end
	if them == me then
		tell("You cannot squelch yourself, though it is a thought.")
		return
	end
	tell(Squelch.add(them.UserId, them.DisplayName)
		and (them.DisplayName .. " is squelched. /unsquelch " .. them.DisplayName .. " to undo it.")
		or (them.DisplayName .. " is already squelched."))
end

local function unsquelch(text: string)
	local typed = argOf(text)
	if typed == "" then
		local names = Squelch.names()
		tell(#names == 0 and "You have not squelched anybody."
			or ("/unsquelch <name>, or /unsquelch all. Squelched: " .. table.concat(names, ", ")))
		return
	end
	-- "all" before a name lookup, so it works for somebody who has left: half the reason to
	-- clear the list is that you cannot remember who is on it.
	if typed:lower() == "all" then
		local n = Squelch.clear()
		tell(n == 0 and "You had not squelched anybody."
			or ("Listening to everybody again (" .. n .. " forgotten)."))
		return
	end
	local them, why = Whom.find(typed)
	if not them then
		tell(why or ("There is nobody here called " .. typed .. "."))
		return
	end
	tell(Squelch.remove(them.UserId)
		and ("Listening to " .. them.DisplayName .. " again.")
		or (them.DisplayName .. " was not squelched."))
end

--- A command of this client's own, under the replicated service but not replicated itself.
local function command(name: string, alias: string, run: (string) -> ())
	local commands = TextChatService:WaitForChild("TextChatCommands", 30)
	if not commands then return end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = name
	cmd.PrimaryAlias = alias
	cmd.Parent = commands
	cmd.Triggered:Connect(function(_source, text)
		run(tostring(text or ""))
	end)
end

task.spawn(function()
	command("SquelchCommand", "/squelch", squelch)
	command("UnsquelchCommand", "/unsquelch", unsquelch)
end)
