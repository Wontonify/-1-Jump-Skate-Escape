--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local Analytics = game:GetService("AnalyticsService")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local Worlds = require(RS.Shared.Worlds)

local AnalyticsService = Knit.CreateService({
	Name = "AnalyticsService",
})

local F1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local F2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local F3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name

local joinClock: { [Player]: number } = {}
local onboardingStep: { [Player]: number } = {}
local maxPad: { [Player]: number } = {} -- highest World 1 pad cashed out this session
local rampZs: { [number]: { number } } = {}

local function call(fn: string, ...: any)
	local ok, err = pcall(Analytics[fn], Analytics, ...)
	if not ok then
		warn("[AnalyticsService] " .. fn .. ": " .. tostring(err))
	end
end

-- lifetime activation funnel steps re-log each session, Roblox keeps the first per user;
-- pad steps read session cash-outs, so each carries a persistent fallback for returning players
local STEPS = {
	{ name = "Joined", done = function(d: any, p: Player) return true end },
	{ name = "First Jump", done = function(d: any, p: Player)
		return (d.Jumps or 0) >= 1 or d.Level >= 2 or d.Rebirth > 0 end },
	{ name = "First Cash Out", done = function(d: any, p: Player)
		return (maxPad[p] or 0) >= 1 or d.Wins > 0 or d.Level >= 3 or d.Rebirth > 0 end },
	{ name = "Level 5", done = function(d: any, p: Player) return d.Level >= 5 or d.Rebirth > 0 end },
	{ name = "First Board", done = function(d: any, p: Player) return #d.OwnedBoards > 1 end },
	{ name = "Level 10", done = function(d: any, p: Player) return d.Level >= 10 or d.Rebirth > 0 end },
	{ name = "Halfway Pad 6", done = function(d: any, p: Player)
		return (maxPad[p] or 0) >= 6 or (d.MaxWorld or 1) > 1 end },
	{ name = "First Rebirth", done = function(d: any, p: Player) return d.Rebirth > 0 end },
	{ name = "Course End Pad 12", done = function(d: any, p: Player)
		return (maxPad[p] or 0) >= 12 or (d.MaxWorld or 1) > 1 end },
	{ name = "World 2", done = function(d: any, p: Player) return (d.MaxWorld or 1) > 1 end },
}

local function pumpOnboarding(player: Player)
	local d = DataService:GetData(player)
	if not d then return end
	local step = onboardingStep[player] or 0
	while step < #STEPS and STEPS[step + 1].done(d, player) do
		step += 1
		call("LogOnboardingFunnelStepEvent", player, step, STEPS[step].name)
	end
	onboardingStep[player] = step
end

local function levelBucket(level: number): string
	if level >= 100 then return "100+" end
	if level >= 50 then return "50-99" end
	if level >= 20 then return "20-49" end
	if level >= 10 then return "10-19" end
	if level >= 5 then return "5-9" end
	if level >= 2 then return "2-4" end
	return "1"
end

-- island N sits after ramp N deaths report where along the course they happened
local function islandLabel(player: Player): string
	local world = Worlds.PlayerWorld(player)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return "W" .. world .. " ?" end
	local z = hrp.Position.Z
	local count = 0
	for _, rampZ in rampZs[world] or {} do
		if rampZ <= z + 1 then count += 1 else break end
	end
	return if count == 0 then "W" .. world .. " Lobby" else "W" .. world .. " Island " .. count
end

function AnalyticsService:LogDeath(player: Player, cause: string)
	local world = Worlds.PlayerWorld(player)
	call("LogCustomEvent", player, "Death", 1, {
		[F1] = cause,
		[F2] = "World " .. world,
		[F3] = islandLabel(player),
	})
end

-- wins pad cash-out economy source + a per-run course funnel (fresh session id per run)
function AnalyticsService:LogCashOut(player: Player, world: number?, index: number?, granted: number)
	call("LogEconomyEvent", player, Enum.AnalyticsEconomyFlowType.Source, "Wins", granted,
		DataService:GetWins(player), Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
		"Pad" .. tostring(index or 0))
	if not (world and index) then return end
	if world == 1 and index > (maxPad[player] or 0) then
		maxPad[player] = index
		pumpOnboarding(player)
	end
	local runId = HttpService:GenerateGUID(false)
	for step = 1, index do
		call("LogFunnelStepEvent", player, "Course World " .. world, runId, step, "Pad " .. step)
	end
end

function AnalyticsService:LogWinsEarned(player: Player, amount: number, transactionType: string, sku: string)
	call("LogEconomyEvent", player, Enum.AnalyticsEconomyFlowType.Source, "Wins", amount,
		DataService:GetWins(player), transactionType, sku)
end

function AnalyticsService:LogPortalDenied(player: Player)
	local d = DataService:GetData(player)
	call("LogCustomEvent", player, "PortalDenied", 1, {
		[F1] = "Level " .. levelBucket(d and d.Level or 1),
		[F2] = "Rebirth " .. math.min(d and d.Rebirth or 0, 10),
	})
end

function AnalyticsService:LogWinsSpent(player: Player, amount: number, sku: string)
	call("LogEconomyEvent", player, Enum.AnalyticsEconomyFlowType.Sink, "Wins", amount,
		DataService:GetWins(player), Enum.AnalyticsEconomyTransactionType.Shop.Name, sku)
end

function AnalyticsService:KnitInit()
	for world, folder in Worlds.List() do
		local zs = {}
		local ramps = folder:FindFirstChild("Ramps")
		if ramps then
			for _, ramp in ramps:GetChildren() do
				if ramp:IsA("Model") and tonumber(ramp.Name) then
					local cf, size = ramp:GetBoundingBox()
					table.insert(zs, cf.Z - size.Z / 2)
				end
			end
			table.sort(zs)
		end
		rampZs[world] = zs
	end

	local function setup(player: Player)
		joinClock[player] = os.clock()
		task.spawn(function()
			if DataService:WaitForData(player) then
				pumpOnboarding(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end

	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				pumpOnboarding(player)
			end
		end
	end)

	-- runs before the profile closes, so the leaving snapshot still has data
	table.insert(DataService.BeforeSessionEnd, function(player: Player)
		local d = DataService:GetData(player)
		if not d then return end
		local seconds = math.floor(os.clock() - (joinClock[player] or os.clock()))
		local rebirth = math.min(d.Rebirth or 0, 10)
		call("LogCustomEvent", player, "SessionEnd", seconds, {
			[F1] = "World " .. (d.World or 1),
			[F2] = "Level " .. levelBucket(d.Level or 1),
			[F3] = "Rebirth " .. rebirth .. (if rebirth >= 10 then "+" else ""),
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		joinClock[player] = nil
		onboardingStep[player] = nil
		maxPad[player] = nil
	end)
end

return AnalyticsService