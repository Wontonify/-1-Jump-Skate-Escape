--!strict
local RS = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local UIController = require(script.Parent.UIController)

local EventController = Knit.CreateController({
	Name = "EventController",
})

-- admin server-wide boosts announce themselves in chat
local function announce(msg: string)
	task.spawn(function()
		pcall(function()
			local channels = TextChatService:WaitForChild("TextChannels", 10)
			local general = channels and channels:WaitForChild("RBXGeneral", 10)
			if general and general:IsA("TextChannel") then
				general:DisplaySystemMessage(msg)
			end
		end)
	end)
	if UIController.Notify then
		UIController.Notify(msg, Color3.fromRGB(120, 220, 255))
	end
end

local function speedText(): string?
	local untilT = Workspace:GetAttribute("EventSpeedUntil") :: number?
	if not untilT or untilT <= os.time() then return nil end
	local mult = (Workspace:GetAttribute("EventSpeedMult") :: number?) or 2
	return string.format("\u{26A1} %gx SPEED for everyone \u{2014} %ds!", mult, untilT - os.time())
end

local function jumpsText(): string?
	local untilT = Workspace:GetAttribute("EventJumpsUntil") :: number?
	if not untilT or untilT <= os.time() then return nil end
	return string.format("\u{1F680} DOUBLE JUMPS for everyone \u{2014} %ds!", untilT - os.time())
end

function EventController:KnitStart()
	Workspace:GetAttributeChangedSignal("EventSpeedUntil"):Connect(function()
		local msg = speedText()
		if msg then announce(msg) end
	end)
	Workspace:GetAttributeChangedSignal("EventJumpsUntil"):Connect(function()
		local msg = jumpsText()
		if msg then announce(msg) end
	end)
	-- joined mid-event
	task.spawn(function()
		task.wait(3)
		local speed = speedText()
		if speed then announce(speed) end
		local jumps = jumpsText()
		if jumps then announce(jumps) end
	end)
end

return EventController





