local RS = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Knit = require(RS.Packages.Knit)

local EventRsvpController = Knit.CreateController({
	Name = "EventRsvpController",
})

local EVENT_ID = "3653789077947417202"
local FIRST_DELAY = 60
local REPEAT_MIN, REPEAT_MAX = 480, 600
local MAX_READ_FAILURES = 3


local function readStatus(): (boolean, boolean)
	local ok, status = pcall(function()
		return SocialService:GetEventRsvpStatusAsync(EVENT_ID)
	end)
	if not ok then return false, false end
	return status == Enum.RsvpStatus.Going, true
end

function EventRsvpController:KnitStart()
	task.spawn(function()
		task.wait(FIRST_DELAY)
		local failures = 0
		while true do
			local joined, readable = readStatus()
			if joined then return end
			if readable then
				failures = 0
				pcall(function()
					SocialService:PromptRsvpToEventAsync(EVENT_ID)
				end)
			else
				-- unreadable means an ended or bad event id give up rather than nag forever
				failures += 1
				if failures >= MAX_READ_FAILURES then return end
			end
			task.wait(REPEAT_MIN + math.random() * (REPEAT_MAX - REPEAT_MIN))
		end
	end)
end

return EventRsvpController