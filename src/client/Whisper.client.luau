-- Typing /w, and what happens next.
--
-- The server half owns which channel a pair of people share; this half reads the line and
-- speaks on it. That split is Roblox's and it is not arbitrary: only a server can put a
-- TextSource in a channel, and only a client can send a message on one -- a server that
-- could send would be a server that can put words in your mouth.
--
-- So: parse, ask for the channel, send. Everything after that is the same road a line in
-- the general chat takes, because it is the same road -- a channel delivers to the people
-- whose TextSource is in it, and this one has two.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local me = Players.LocalPlayer

--- How long to wait for our own TextSource to turn up in a new channel.
---
--- The server makes the channel and adds both of us, then answers -- but the answer and the
--- instances come down the same wire and the answer can arrive first. Sending before the
--- source is here gets InvalidTextChannelPermissions and looks like the whisper being
--- refused.
local SETTLE = 3

--- Says something in the log without sending it anywhere. DisplaySystemMessage is a
--- client-only call and shows on this machine only, which is what a hint about your own
--- typing should do.
local function tell(what: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general then
		pcall(function() general:DisplaySystemMessage(what) end)
	else
		warn("whisper: " .. what)
	end
end

--- Our TextSource in `channel`, waited for.
local function mine(channel: Instance): Instance?
	local until_ = os.clock() + SETTLE
	while os.clock() < until_ do
		for _, s in ipairs(channel:GetChildren()) do
			if s:IsA("TextSource") and s.UserId == me.UserId then return s end
		end
		task.wait(0.05)
	end
	return nil
end

local function whisper(text: string)
	-- The whole line arrives, alias and all: "/w bob are you there". Two captures, because
	-- the message is everything after the name and may well have spaces in it.
	local to, said = text:match("^%S+%s+(%S+)%s+(.+)$")
	if not to then
		-- A name and no message is the common half-typed case, and worth telling apart from
		-- nonsense: you meant to whisper and stopped.
		local only = text:match("^%S+%s+(%S+)%s*$")
		tell(only and ("What do you want to say to " .. only .. "?")
			or "Whisper like this: /w <name> <message>")
		return
	end

	local channel, why = ReplicatedStorage:WaitForChild("WhisperChannel"):InvokeServer(to)
	if not channel then
		tell(why or ("There is nobody here called " .. to .. "."))
		return
	end
	if not mine(channel) then
		tell("That whisper did not go through. Try it again.")
		return
	end
	-- And from here it is an ordinary message on an ordinary channel: the server delivers it
	-- to the two TextSources in it, both of us see it come back through MessageReceived, and
	-- Chat.client.luau draws it as a whisper because of what the channel is called.
	local ok, err = pcall(function() channel:SendAsync(said) end)
	if not ok then tell("That whisper did not send: " .. tostring(err)) end
end

-- The command is made on the server so that it replicates; every client's copy of it fires
-- when that client types the word, which is where this listens.
task.spawn(function()
	local commands = TextChatService:WaitForChild("TextChatCommands", 30)
	local cmd = commands and commands:WaitForChild("WhisperCommand", 30)
	if not cmd then
		warn("whisper: /w was never registered, so nothing will answer it")
		return
	end
	cmd.Triggered:Connect(function(_source, text)
		-- Spawned, because this reaches the server and back and Triggered is not a place to
		-- block: the line has already been taken out of the box and the next keystroke
		-- should not wait on a round trip.
		task.spawn(whisper, tostring(text or ""))
	end)
end)
