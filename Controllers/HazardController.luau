--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)

local player = Players.LocalPlayer

local HazardController = Knit.CreateController({
	Name = "HazardController",
})

local NEAR = 150 -- studs to the closest sinking structure before the quake is felt

local crumble = Instance.new("Sound")
crumble.SoundId = "rbxassetid://9113224719"
crumble.Volume = 0.6
crumble.Parent = SoundService

-- sweeping lasers glide on the shared server clock: rendering them locally every frame keeps the beam glass-smooth instead of stepping at replication rate
local function watchSweeps()
	local folder = workspace:WaitForChild("Lasers", 20)
	if not folder then return end
	local sweeps: { [Model]: { base: CFrame, minZ: number, maxZ: number, period: number, phase: number } } = {}
	local function wire(m: Instance)
		local minZ = m:GetAttribute("SweepMinZ")
		if m:IsA("Model") and typeof(minZ) == "number" and not sweeps[m] then
			sweeps[m] = {
				base = m:GetPivot(),
				minZ = minZ,
				maxZ = (m:GetAttribute("SweepMaxZ") :: number?) or minZ,
				period = (m:GetAttribute("SweepPeriod") :: number?) or 24,
				phase = (m:GetAttribute("SweepPhase") :: number?) or 0,
			}
		end
	end
	for _, m in folder:GetChildren() do wire(m) end
	folder.ChildAdded:Connect(wire) -- streaming hands models back
	folder.ChildRemoved:Connect(function(m)
		sweeps[m :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow()
		for m, s in sweeps do
			local z = s.minZ + (s.maxZ - s.minZ) * (0.5 + 0.5 * math.sin(math.pi * 2 * t / s.period + s.phase))
			m:PivotTo(CFrame.new(s.base.X, s.base.Y, z) * s.base.Rotation)
		end
	end)
end

-- cloud drift rendered locally for the same smooth motion as the lasers
local function watchClouds()
	local map = workspace:WaitForChild("Map", 20)
	if not map then return end
	local clouds: { [BasePart]: { base: CFrame, minX: number, maxX: number, period: number, phase: number } } = {}
	local function wire(d: Instance)
		local minX = d:GetAttribute("CloudMinX")
		if d:IsA("BasePart") and typeof(minX) == "number" and not clouds[d] then
			clouds[d] = {
				base = d.CFrame,
				minX = minX,
				maxX = (d:GetAttribute("CloudMaxX") :: number?) or minX,
				period = (d:GetAttribute("CloudPeriod") :: number?) or 45,
				phase = (d:GetAttribute("CloudPhase") :: number?) or 0,
			}
		end
	end
	for _, d in map:GetChildren() do wire(d) end
	map.ChildAdded:Connect(wire) -- streaming hands parts back
	map.ChildRemoved:Connect(function(d)
		clouds[d :: BasePart] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow()
		for part, c in clouds do
			local x = c.minX + (c.maxX - c.minX) * (0.5 + 0.5 * math.sin(math.pi * 2 * t / c.period + c.phase))
			part.CFrame = CFrame.new(x, c.base.Position.Y, c.base.Position.Z) * c.base.Rotation
		end
	end)
end

function HazardController:KnitStart()
	task.spawn(watchSweeps)
	task.spawn(watchClouds)
	Knit.GetService("HazardService").Quake:Connect(function(duration: number)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then return end
		local platforms = workspace:FindFirstChild("Platforms")
		if not platforms then return end
		local near = false
		for _, m in platforms:GetChildren() do
			if m:IsA("Model") and (m:GetPivot().Position - hrp.Position).Magnitude < NEAR then
				near = true
				break
			end
		end
		if not near then return end
		crumble.TimePosition = 0
		crumble:Play()
		-- small fading camera shake for as long as the structures sink
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if t >= duration or not humanoid then
				conn:Disconnect()
				if humanoid then humanoid.CameraOffset = Vector3.zero end
				return
			end
			local amp = 0.4 * (1 - t / duration)
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * 2 * amp, (math.random() - 0.5) * 2 * amp, 0)
		end)
	end)
end

return HazardController