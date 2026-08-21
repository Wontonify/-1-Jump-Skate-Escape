--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)

local player = Players.LocalPlayer

local LandingImpactController = Knit.CreateController({
	Name = "LandingImpactController",
})

local TRIGGER_SPEED = 90 -- min downward speed (studs/s) at landing to trigger (~20-stud fall)
local BLOCKS = 3
local RING_MIN, RING_MAX = 4.0, 7.5
local THICK_MIN, THICK_MAX = 1.0, 2.0
local RISE_MIN, RISE_MAX = 0.4, 1.2 -- fraction of each slab left poking out; the bottom stays buried
local RISE_TIME = 0.28
local HOLD_TIME = 0.5
local SINK_TIME = 0.45
local TILT_DEG = 22 -- lean toward the player
local COOLDOWN = 0.4

local lastImpact = -math.huge

local function raycastDown(from: Vector3, char: Instance, dist: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true
	return Workspace:Raycast(from + Vector3.new(0, 2, 0), Vector3.new(0, -(dist + 2), 0), params)
end

local function eruptBlock(landingCenter: Vector3, angle: number, char: Instance)
	local r = RING_MIN + math.random() * (RING_MAX - RING_MIN)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local spot = landingCenter + dir * r
	local hit = raycastDown(spot + Vector3.new(0, 8, 0), char, 20)
	if not hit or hit.Instance.Name == "Floor" then return end -- never erupt the water
	local surfacePart = hit.Instance :: BasePart
	local surfaceY = hit.Position.Y

	-- flat slab, vertical axis thin and the two horizontal sides unequal so the top reads as a rectangle
	local thick = THICK_MIN + math.random() * (THICK_MAX - THICK_MIN)
	local long = thick * (2.6 + math.random() * 2.2)
	local short = thick * (1.3 + math.random() * 0.7)
	local sx, sz = long, short
	if math.random() < 0.5 then sx, sz = short, long end
	local sy = thick

	local block = Instance.new("Part")
	block.Name = "ImpactBlock"
	block.Size = Vector3.new(sx, sy, sz)
	block.Anchored = true
	block.CanCollide = false
	block.CanQuery = false
	block.CanTouch = false
	block.CastShadow = true
	block.Material = surfacePart.Material
	block.Color = surfacePart.Color
	block.Transparency = surfacePart.Transparency

	local toPlayer = landingCenter - spot
	toPlayer = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	if toPlayer.Magnitude < 0.05 then toPlayer = Vector3.new(0, 0, -1) end
	toPlayer = toPlayer.Unit
	local tiltAxis = toPlayer:Cross(Vector3.yAxis).Unit
	local rot = CFrame.fromAxisAngle(tiltAxis, math.rad(TILT_DEG)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)

	-- rest it so only the top pokes out and the bottom stays under the surface ground pushed up, never a floating block
	local vHalf = 0.5 * (math.abs(rot.RightVector.Y) * sx + math.abs(rot.UpVector.Y) * sy + math.abs(rot.LookVector.Y) * sz)
	local poke = RISE_MIN + math.random() * (RISE_MAX - RISE_MIN)
	local restY = surfaceY + vHalf * (poke - 1)
	local topCF = rot + Vector3.new(spot.X, restY, spot.Z)
	local buriedCF = rot + Vector3.new(spot.X, surfaceY - vHalf - 1.5, spot.Z)

	block.CFrame = buriedCF
	block.Parent = Workspace

	local up = TweenService:Create(block, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = topCF })
	up:Play()
	up.Completed:Once(function()
		task.delay(HOLD_TIME, function()
			if block.Parent then
				TweenService:Create(block, TweenInfo.new(SINK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = buriedCF }):Play()
			end
		end)
	end)
	Debris:AddItem(block, RISE_TIME + HOLD_TIME + SINK_TIME + 0.2)
end

local function doImpact(char: Model, hrp: BasePart)
	local ground = raycastDown(hrp.Position, char, 12)
	if not ground or ground.Instance.Name == "Floor" then return end
	local center = Vector3.new(hrp.Position.X, ground.Position.Y, hrp.Position.Z)
	-- one slab per evenly-spaced sector at a random angle within it
	local base = math.random() * math.pi * 2
	local sector = math.pi * 2 / BLOCKS
	for i = 1, BLOCKS do
		local angle = base + (i - 1) * sector + (math.random() - 0.5) * sector * 0.8
		eruptBlock(center, angle, char)
	end
end

function LandingImpactController:KnitStart()
	local airborne = false
	local minVelY = 0

	RunService.Heartbeat:Connect(function()
		if not airborne then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local vy = (hrp :: BasePart).AssemblyLinearVelocity.Y
			if vy < minVelY then minVelY = vy end
		end
	end)

	local function bindCharacter(char: Model)
		airborne = false
		minVelY = 0
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Freefall then
				airborne = true
				minVelY = 0
			elseif new == Enum.HumanoidStateType.Landed then
				local impactSpeed = -minVelY
				airborne = false
				minVelY = 0
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp and impactSpeed >= TRIGGER_SPEED and (os.clock() - lastImpact) >= COOLDOWN then
					lastImpact = os.clock()
					doImpact(char, hrp :: BasePart)
				end
			end
		end)
	end

	if player.Character then bindCharacter(player.Character) end
	player.CharacterAdded:Connect(bindCharacter)
end

return LandingImpactController