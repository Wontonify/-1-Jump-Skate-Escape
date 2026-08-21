--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local SkateboardService = require(script.Parent.SkateboardService)
local PassService = require(script.Parent.PassService)
local ClickConfig = require(RS.Shared.ClickConfig)
local GamepassConfig = require(RS.Shared.GamepassConfig)
local Levels = require(RS.Shared.Levels)
local Rebirths = require(RS.Shared.Rebirths)

local XPService = Knit.CreateService({
	Name = "XPService",

	Client = {
		LevelUp = Knit.CreateSignal(),
	},
})

local lastPos: { [Player]: Vector3 } = {}

-- the board's base XP per step, scaled by every multiplier
local function computeXPPerStep(player: Player): number
	local baseXP = SkateboardService:GetBoardXP(player)
	local data = DataService:GetData(player)
	local rebirth = data and data.Rebirth or 0
	return math.ceil(baseXP * Rebirths.MultiplierFor(rebirth) * PassService:XPMultiplier(player))
end

-- published so the client can predict step feedback; re-call when a multiplier changes
function XPService:RefreshXPPerStep(player: Player)
	player:SetAttribute("XPPerStep", computeXPPerStep(player))
end

-- grants XP + banks level progress; levels stop at the rebirth max level
function XPService:GrantXP(player: Player, amount: number)
	if amount <= 0 then return end
	local data = DataService:GetData(player)
	if not data then return end

	DataService:AddXP(player, amount)

	local maxLevel = Rebirths.MaxLevelFor(data.Rebirth)
	if data.Level >= maxLevel then return end
	local startLevel = data.Level
	local progress = data.LevelProgress + amount
	local level = startLevel
	local req = Levels.RequirementFor(level)
	while progress >= req and level < maxLevel do
		progress -= req
		level += 1
		req = Levels.RequirementFor(level)
	end
	if level >= maxLevel then
		level = maxLevel
		progress = 0
	end
	DataService:SetLevel(player, level)
	DataService:SetLevelProgress(player, progress)

	if level > startLevel then
		self.Client.LevelUp:Fire(player, level)
	end
end

function XPService:KnitInit()
	-- XP comes from moving one grant per tick while skating, boosting or flying
	task.spawn(function()
		while true do
			task.wait(1 / ClickConfig.StepsPerSecond)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if not (humanoid and hrp and hrp:IsA("BasePart") and humanoid.Health > 0) then
					lastPos[player] = nil
					continue
				end
				local pos = hrp.Position
				local last = lastPos[player]
				lastPos[player] = pos
				if not last then continue end
				local dist = ((pos - last) * Vector3.new(1, 0, 1)).Magnitude
				if dist < ClickConfig.MinTickStuds or dist > ClickConfig.MaxTickStuds then continue end
				if not DataService:GetData(player) then continue end
				XPService:GrantXP(player, computeXPPerStep(player))
			end
		end
	end)

	local function setup(player: Player)
		task.spawn(function()
			if DataService:WaitForData(player) then
				XPService:RefreshXPPerStep(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end

	Players.PlayerRemoving:Connect(function(p)
		lastPos[p] = nil
	end)

	table.insert(PassService.Changed, function(player)
		if DataService:GetData(player) then
			XPService:RefreshXPPerStep(player)
		end
	end)

	PassService.Products[GamepassConfig.LevelProduct.Id] = function(player)
		local data = DataService:GetData(player)
		if not data then return false end
		DataService:SetLevel(player, data.Level + 1)
		XPService.Client.LevelUp:Fire(player, data.Level)
		return true
	end
end

return XPService