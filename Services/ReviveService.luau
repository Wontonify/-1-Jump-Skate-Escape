--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local PassService = require(script.Parent.PassService)
local GamepassConfig = require(RS.Shared.GamepassConfig)
local Worlds = require(RS.Shared.Worlds)

local ReviveService = Knit.CreateService({
	Name = "ReviveService",
})

local PENDING_LIFETIME = 120

local lastSafe: { [Player]: Vector3 } = {}
local maxZ: { [Player]: number } = {}
local pending: { [Player]: { pos: Vector3, t: number } } = {}
local autoRevive: { [Player]: boolean } = {}

local anchorsByWorld: { [number]: { { z: number, pos: Vector3 } } } = {}

-- the furthest anchor passed this run beats the last stood-on spot
local function checkpointPos(player: Player): Vector3?
	local z = maxZ[player]
	local best: Vector3? = nil
	if z then
		for _, a in anchorsByWorld[Worlds.PlayerWorld(player)] or {} do
			if a.z <= z + 1 then best = a.pos else break end
		end
	end
	return best or lastSafe[player]
end

-- crossing into another world starts a fresh run there
function ReviveService:ResetRun(player: Player)
	lastSafe[player] = nil
	maxZ[player] = nil
end

local function reviveTo(character: Model, pos: Vector3)
	character:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
end

-- Permanent Revive owners get tp straight away
function ReviveService:TryInstantRevive(player: Player): boolean
	if not PassService:OwnsPass(player, GamepassConfig.PermanentRevive.Id) then return false end
	local pos = checkpointPos(player)
	local character = player.Character
	if not (pos and character) then return false end
	reviveTo(character, pos)
	return true
end

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then return end

	if autoRevive[player] then
		autoRevive[player] = nil
		local entry = pending[player]
		pending[player] = nil
		if entry and os.clock() - entry.t <= PENDING_LIFETIME then
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait()
			reviveTo(character, entry.pos)
		end
	end

	humanoid.Died:Connect(function()
		if not PassService:OwnsPass(player, GamepassConfig.PermanentRevive.Id) then return end
		local pos = checkpointPos(player)
		if not pos then return end
		pending[player] = { pos = pos, t = os.clock() }
		autoRevive[player] = true
	end)
end

function ReviveService:KnitInit()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(c) hookCharacter(player, c) end)
		if player.Character then task.spawn(hookCharacter, player, player.Character) end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end
	Players.PlayerRemoving:Connect(function(p)
		lastSafe[p] = nil
		maxZ[p] = nil
		pending[p] = nil
		autoRevive[p] = nil
	end)

	local lobbyZ = -math.huge
	for world, folder in Worlds.List() do
		local anchors = {}
		local ramps = folder:FindFirstChild("Ramps")
		if ramps then
			for _, ramp in ramps:GetChildren() do
				if ramp:IsA("Model") and tonumber(ramp.Name) then
					local cf, size = ramp:GetBoundingBox()
					local pos = Vector3.new(cf.X, cf.Y - size.Y / 2 + 4, cf.Z - size.Z / 2 - 12)
					table.insert(anchors, { z = pos.Z, pos = pos })
				end
			end
			table.sort(anchors, function(a, b) return a.z < b.z end)
		end
		anchorsByWorld[world] = anchors
		if #anchors > 0 then lobbyZ = math.max(lobbyZ, anchors[1].z - 6) end
	end

	local platformFolders = {}
	for _, folder in Worlds.List() do
		local platforms = folder:FindFirstChild("Platforms")
		if platforms then table.insert(platformFolders, platforms) end
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not (character and hrp and hrp:IsA("BasePart") and humanoid)
					or humanoid.Health <= 0 then continue end
				local z = hrp.Position.Z
				if z < lobbyZ then
					maxZ[player] = nil
				else
					maxZ[player] = math.max(maxZ[player] or -math.huge, z)
				end
				if humanoid.FloorMaterial == Enum.Material.Air then continue end
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { character }
				local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), params)
				if not hit or hit.Instance.Name == "Floor" or hit.Instance.Name == "Laser" then continue end
				local onPlatform = false
				for _, platforms in platformFolders do
					if hit.Instance:IsDescendantOf(platforms) then
						onPlatform = true
						break
					end
				end
				if onPlatform then continue end
				lastSafe[player] = hrp.Position
			end
		end
	end)
end

return ReviveService