--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local XPService = require(script.Parent.XPService)
local PassService = require(script.Parent.PassService)
local DailyRewards = require(RS.Shared.DailyRewards)

local DailyRewardService = Knit.CreateService({
	Name = "DailyRewardService",

	Client = {
		Claim = Knit.CreateSignal(),   -- client asks for the next day
		Claimed = Knit.CreateSignal(), -- (day, rewardText) a claim landed
		Denied = Knit.CreateSignal(),
	},
})

local function rewardText(day: number): string
	local r = DailyRewards.Days[day]
	if not r then return "" end
	return "+" .. r.Amount .. " " .. (if r.Type == "XP" then "XP" else "Wins")
end

-- streak + last-claim time ride on attributes so the client renders cards and the countdown
local function publish(player: Player)
	local d = DataService:GetData(player)
	if not d then return end
	player:SetAttribute("DailyStreak", d.DailyStreak or 0)
	player:SetAttribute("DailyLast", d.DailyLast or 0)
end

function DailyRewardService:ClaimNext(player: Player, skipTimer: boolean?): boolean
	local d = DataService:GetData(player)
	if not d then return false end
	local now = os.time()
	local elapsed = now - (d.DailyLast or 0)
	if not skipTimer and elapsed < DailyRewards.Interval then
		self.Client.Denied:Fire(player, "Come back tomorrow!")
		return false
	end
	local streak = d.DailyStreak or 0
	if streak >= #DailyRewards.Days then streak = 0 end -- finished week starts over
	if (d.DailyLast or 0) > 0 and elapsed >= DailyRewards.Grace then streak = 0 end -- missed a day
	local day = streak + 1
	local r = DailyRewards.Days[day]
	if not r then return false end
	if r.Type == "Wins" then
		DataService:AddWins(player, r.Amount)
	else
		XPService:GrantXP(player, r.Amount)
	end
	d.DailyStreak = day
	d.DailyLast = now
	publish(player)
	self.Client.Claimed:Fire(player, day, rewardText(day))
	return true
end

function DailyRewardService:KnitInit()
	self.Client.Claim:Connect(function(player)
		self:ClaimNext(player, false)
	end)

	if DailyRewards.SkipOneProduct > 0 then
		PassService.Products[DailyRewards.SkipOneProduct] = function(player)
			local d = DataService:GetData(player)
			if not d or (d.DailyStreak or 0) >= #DailyRewards.Days then return false end
			return self:ClaimNext(player, true)
		end
	end
	if DailyRewards.SkipAllProduct > 0 then
		PassService.Products[DailyRewards.SkipAllProduct] = function(player)
			local d = DataService:GetData(player)
			if not d or (d.DailyStreak or 0) >= #DailyRewards.Days then return false end
			local any = false
			for _ = 1, #DailyRewards.Days do
				local dd = DataService:GetData(player)
				if not dd or (dd.DailyStreak or 0) >= #DailyRewards.Days then break end
				if not self:ClaimNext(player, true) then break end
				any = true
			end
			return any
		end
	end

	local function setup(player: Player)
		task.spawn(function()
			local d = DataService:WaitForData(player)
			if not d then return end
			-- coming back after the grace window restarts the week before the client renders
			local elapsed = os.time() - (d.DailyLast or 0)
			if (d.DailyLast or 0) > 0 and elapsed >= DailyRewards.Grace then
				d.DailyStreak = 0
			end
			publish(player)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end
end

return DailyRewardService
