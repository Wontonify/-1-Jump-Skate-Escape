--!strict
local Players = game:GetService("Players")
local RobloxBadges = game:GetService("BadgeService")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)

local BadgeService = Knit.CreateService({
	Name = "BadgeService",
})

BadgeService.Ids = {
	PurchaseUpgrade = 1368123238519797,
	ReachEndWorld1 = 2424594913518191,
	ReachEndWorld2 = 679801997462273,
	Wins25 = 4047256622965791,
	Wins250 = 2287743242885660,
	Wins5K = 3885638173637681,
	Playtime10Min = 135585004360728,
	Playtime1Hour = 135585004360728, -- given id duplicates 10 Min, awaiting the real one
	Playtime10Hour = 1759278731277767,
	Upgrades5 = 2690956575603628,
}

local WIN_BADGES = {
	{ wins = 25, id = BadgeService.Ids.Wins25 },
	{ wins = 250, id = BadgeService.Ids.Wins250 },
	{ wins = 5000, id = BadgeService.Ids.Wins5K },
}

local PLAYTIME_BADGES = {
	{ seconds = 600, id = BadgeService.Ids.Playtime10Min },
	{ seconds = 3600, id = BadgeService.Ids.Playtime1Hour },
	{ seconds = 36000, id = BadgeService.Ids.Playtime10Hour },
}

local awarded: { [Player]: { [number]: boolean } } = {}

function BadgeService:Award(player: Player, badgeId: number)
	if badgeId <= 0 then return end
	local seen = awarded[player]
	if not seen then
		seen = {}
		awarded[player] = seen
	end
	if seen[badgeId] then return end
	seen[badgeId] = true
	task.spawn(function()
		local okHas, has = pcall(RobloxBadges.UserHasBadgeAsync, RobloxBadges, player.UserId, badgeId)
		if okHas and has then return end
		local ok, granted = pcall(RobloxBadges.AwardBadge, RobloxBadges, player.UserId, badgeId)
		if not ok or granted == false then
			seen[badgeId] = nil -- throttled or failed, the next trigger retries
		end
	end)
end

-- wins milestones follow the leaderstat, whichever way the wins arrive
local function watchWins(player: Player)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 30)
		local wins = ls and ls:WaitForChild("Wins", 10)
		if not (wins and wins:IsA("IntValue")) then return end
		local function check()
			for _, b in WIN_BADGES do
				if wins.Value >= b.wins then BadgeService:Award(player, b.id) end
			end
		end
		wins.Changed:Connect(check)
		check()
	end)
end

function BadgeService:KnitInit()
	Players.PlayerAdded:Connect(watchWins)
	for _, p in Players:GetPlayers() do watchWins(p) end
	Players.PlayerRemoving:Connect(function(p) awarded[p] = nil end)

	-- lifetime playtime milestones; profile Playtime is flushed each leaderboard cycle,
	-- so this lags a cycle at most
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local playtime = DataService:GetPlaytime(player)
				for _, b in PLAYTIME_BADGES do
					if playtime >= b.seconds then BadgeService:Award(player, b.id) end
				end
			end
			task.wait(60)
		end
	end)
end

return BadgeService