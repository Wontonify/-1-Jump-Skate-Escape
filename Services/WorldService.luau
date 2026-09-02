--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local ReviveService = require(script.Parent.ReviveService)
local Worlds = require(RS.Shared.Worlds)

local WorldService = Knit.CreateService({
	Name = "WorldService",

	Client = {
		Entered = Knit.CreateSignal(), -- (world) fired after the portal moves you
		Denied = Knit.CreateSignal(), -- (message) locked-portal feedback
	},
})

local TOUCH_COOLDOWN = 3
local lastTouch: { [Player]: number } = {}

-- streams the destination in while the player still stands on safe ground, then moves them
function WorldService:Teleport(player: Player, world: number)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and hrp) then return end
	local cf = Worlds.SpawnCFrame(world)
	pcall(player.RequestStreamAroundAsync, player, cf.Position, 5)
	if not character.Parent then return end
	local lv = hrp:FindFirstChild("BoostVelocity")
	if lv then lv:Destroy() end
	local gyro = hrp:FindFirstChild("BoostGyro")
	if gyro then gyro:Destroy() end
	character:PivotTo(cf)
end

local function enterWorld(player: Player, world: number, unlocks: boolean?)
	if not DataService:GetData(player) then return end
	-- lobby portals only revisit worlds already reached; the course-end portal unlocks the next
	if not unlocks and world > DataService:GetMaxWorld(player) then
		WorldService.Client.Denied:Fire(player, "Reach the end first!")
		AnalyticsService:LogPortalDenied(player)
		return
	end
	-- the world follows the player both ways; portals travel freely between unlocked worlds
	local changed = world ~= DataService:GetWorld(player)
	if changed then
		DataService:SetWorld(player, world)
	end
	ReviveService:ResetRun(player)
	WorldService:Teleport(player, world)
	if changed then
		WorldService.Client.Entered:Fire(player, world)
	end
end

local function wirePortal(portal: Instance, targetWorld: number, unlocks: boolean?)
	-- prefer the parts named "Portal"; portals without any wire every part
	local parts: { BasePart } = {}
	for _, part in portal:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Portal" then table.insert(parts, part) end
	end
	if #parts == 0 then
		for _, part in portal:GetDescendants() do
			if part:IsA("BasePart") then table.insert(parts, part) end
		end
	end
	for _, part in parts do
		part.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player then return end
			local now = os.clock()
			if now - (lastTouch[player] or -math.huge) < TOUCH_COOLDOWN then return end
			lastTouch[player] = now
			enterWorld(player, targetWorld, unlocks)
		end)
	end
end


function WorldService:KnitInit()
	-- every portal model in a world's Map leads to the next world around (the opposite one with two)
	for world, folder in Worlds.List() do
		local map = folder:FindFirstChild("Map")
		if map then
			local target = world % Worlds.Count + 1
			for _, m in map:GetChildren() do
				if m.Name:lower() == "portal" then
					-- the portal far down the course is the progression one; lobby portals just revisit
					wirePortal(m, target, m:GetPivot().Z > 1000)
				end
			end
		end
	end

	-- Roblox always drops characters at the World 1 SpawnLocation; later-world players move on
	local function hookCharacter(player: Player, character: Model)
		task.spawn(function()
			if not DataService:WaitForData(player) then return end
			local world = DataService:GetWorld(player)
			if world <= 1 then return end
			character:WaitForChild("HumanoidRootPart", 10)
			if character ~= player.Character then return end
			WorldService:Teleport(player, world)
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(c) hookCharacter(player, c) end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(c) hookCharacter(player, c) end)
		if player.Character then hookCharacter(player, player.Character) end
	end
	Players.PlayerRemoving:Connect(function(p) lastTouch[p] = nil end)
end

return WorldService