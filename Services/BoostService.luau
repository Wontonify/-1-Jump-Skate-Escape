--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local HazardService = require(script.Parent.HazardService)
local ReviveService = require(script.Parent.ReviveService)
local SkateboardService = require(script.Parent.SkateboardService)
local TrailService = require(script.Parent.TrailService)
local BoostConfig = require(RS.Shared.BoostConfig)
local Levels = require(RS.Shared.Levels)

local BoostService = Knit.CreateService({
	Name = "BoostService",
})

local BOOST_DURATION = 0.25   -- how long the LinearVelocity steers before handing momentum back
local COOLDOWN = 0.5          -- seconds between boosts per player
local UP_MARGIN = 6           -- studs of clearance above the tallest obstacle at the arc's apex
local MIN_UP = 20             -- studs/s floor for the upward component
local MIN_FORWARD = 10        -- studs/s floor for the forward component
local HIP_HEIGHT = 3          -- HRP center sits about this far above the ground on landing
local TELEPORT_COOLDOWN = 1.5

local lastBoost: { [Player]: number } = {}
local lastTeleport: { [Player]: number } = {}
local platformFront: { [number]: { d: number, y: number } } = {}

local function findPlatformFront(index: number, origin: Vector3, travelDir: Vector3, fromAlong: number, toAlong: number): { d: number, y: number }?
	local cached = platformFront[index]
	if cached then return cached end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then table.insert(chars, pl.Character) end
	end
	params.FilterDescendantsInstances = chars
	local originAlong = origin:Dot(travelDir)
	local sawWater = false
	for d = fromAlong - originAlong, toAlong - originAlong, 2 do
		local p = origin + travelDir * d
		local hit = Workspace:Raycast(Vector3.new(p.X, 300, p.Z), Vector3.new(0, -500, 0), params)
		if hit and hit.Instance.Name == "Floor" then
			sawWater = true
		elseif hit and sawWater then
			local entry = { d = originAlong + d, y = hit.Position.Y }
			platformFront[index] = entry
			return entry
		end
	end
	return nil
end

local function playerFromHit(hit: BasePart): (Player?, Model?, BasePart?)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then return nil, nil, nil end
	local hrp = (character :: Model):FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return nil, nil, nil end
	return player, character :: Model, hrp
end

local function onWedgeTouched(wedge: BasePart, hit: BasePart)
	local player, character, hrp = playerFromHit(hit)
	if not (player and character and hrp) then return end

	local now = os.clock()
	if now - (lastBoost[player] or -math.huge) < COOLDOWN then return end
	if hrp:FindFirstChild("BoostVelocity") then return end -- brushing a wedge mid-flight must not re-boost

	local attachment = hrp:FindFirstChild("RootAttachment")
	if not (attachment and attachment:IsA("Attachment")) then return end

	-- the ramp model this wedge belongs to (direct child of the Ramps folder)
	local rampsFolder = wedge:FindFirstAncestor("Ramps")
	local ramp: Instance = wedge
	while ramp.Parent and ramp.Parent ~= rampsFolder do
		ramp = ramp.Parent :: Instance
	end
	local index = tonumber(ramp.Name)
	if not (ramp:IsA("Model") and index and rampsFolder) then return end
	lastBoost[player] = now

	local cf, size = ramp:GetBoundingBox()
	local gravity = Workspace.Gravity

	-- up-slope axis still models the gap crossing, but the launch itself goes wherever the
	-- player is heading (move input, else facing) -- the ramp never yanks onto its own axis
	local wedgeDir = -wedge.CFrame.LookVector
	wedgeDir = Vector3.new(wedgeDir.X, 0, wedgeDir.Z)
	wedgeDir = if wedgeDir.Magnitude > 0 then wedgeDir.Unit else Vector3.zAxis
	local mover = character:FindFirstChildOfClass("Humanoid")
	local travelDir = if mover and mover.MoveDirection.Magnitude > 0.2
		then Vector3.new(mover.MoveDirection.X, 0, mover.MoveDirection.Z)
		else hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	travelDir = if travelDir.Magnitude > 0.01 then travelDir.Unit else wedgeDir

	local function sizeAlong(modelCf: CFrame, modelSize: Vector3): number
		local rel = modelCf:VectorToObjectSpace(wedgeDir)
		return math.abs(rel.X) * modelSize.X + math.abs(rel.Y) * modelSize.Y + math.abs(rel.Z) * modelSize.Z
	end

	local thisBackAlong = cf.Position:Dot(wedgeDir) + sizeAlong(cf, size) / 2
	local backEdge = math.max(thisBackAlong - hrp.Position:Dot(wedgeDir), 0)
	local nextRamp = rampsFolder:FindFirstChild(tostring(index + 1))
	local landTargetY: number? = nil
	local carrySpeed = 0
	local maxHop = BoostConfig.MaxHopStuds
	if nextRamp and nextRamp:IsA("Model") then
		local ncf, nsize = nextRamp:GetBoundingBox()
		local nextFrontAlong = ncf.Position:Dot(wedgeDir) - sizeAlong(ncf, nsize) / 2
		local front = findPlatformFront(index, cf.Position, wedgeDir, thisBackAlong, nextFrontAlong)
		-- the water gap from this ramp's lip to the next platform's real front
		local gapLen = math.max((front and front.d or nextFrontAlong) - thisBackAlong, BoostConfig.MinHopStuds)
		local crossTime = BoostConfig.ArcTime + BoostConfig.JumpPeriod * (BoostConfig.JumpsToNext[index] or 0) + BoostConfig.FallGrace
		carrySpeed = gapLen / crossTime
		maxHop = math.max(carrySpeed * (BoostConfig.ArcTime + BoostConfig.FallGrace), BoostConfig.MinHopStuds)
		landTargetY = (front and front.y or (ncf.Position.Y + nsize.Y / 2)) + HIP_HEIGHT
	end

	local d = DataService:GetData(player)
	local levelXP = if d then Levels.TotalXPFor(d.Level) + (d.LevelProgress or 0) else 0
	local required = BoostConfig.XPToNext[index] or 50
	local fraction = if required > 0 then math.clamp(levelXP / required, 0, 1) else 1
	-- boost calc by current walkspeed
	local earnedSpeed = TrailService:ComputeWalkSpeed(player)
	local actualSpeed = if mover then mover.WalkSpeed else earnedSpeed
	local throttle = if earnedSpeed > 0 then math.clamp(actualSpeed / earnedSpeed, 0, 1) else 1
	fraction *= throttle

	local dist = backEdge + BoostConfig.MinHopStuds + (maxHop - BoostConfig.MinHopStuds) * fraction

	local y0 = hrp.Position.Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	-- ground height at the landing spot, so the flight time ends the arc exactly there
	local landPos = hrp.Position + travelDir * dist
	local rayHit = Workspace:Raycast(Vector3.new(landPos.X, 500, landPos.Z), Vector3.new(0, -1000, 0), rayParams)
	local landY = (rayHit and rayHit.Position.Y or y0 - HIP_HEIGHT) + HIP_HEIGHT
	if landY < y0 - 8 then
		-- only water below mid-gap
		landY = landTargetY or y0
	end

	local obstacles: { { number } } = {}
	local highest = -math.huge
	for i = 1, if backEdge > 0 then 8 else 0 do
		local d = backEdge * i / 8
		local p = hrp.Position + travelDir * d
		local hit2 = Workspace:Raycast(Vector3.new(p.X, 500, p.Z), Vector3.new(0, -1000, 0), rayParams)
		if hit2 and hit2.Position.Y > y0 + 1 then
			table.insert(obstacles, { d, hit2.Position.Y + HIP_HEIGHT + 1 })
			highest = math.max(highest, hit2.Position.Y)
		end
	end

	local T0 = BoostConfig.ArcTime
	local tau0 = T0 - BOOST_DURATION
	local upSpeed = (landY - y0 + gravity * tau0 * tau0 / 2) / (BOOST_DURATION + tau0)
	local apexTarget = math.max(highest + HIP_HEIGHT + UP_MARGIN, landY + 2)
	local clearSeed = math.sqrt((gravity * BOOST_DURATION) ^ 2 + 2 * gravity * math.max(0, apexTarget - y0)) - gravity * BOOST_DURATION
	upSpeed = math.max(upSpeed, clearSeed, MIN_UP)

	local function altitudeAt(up: number, t: number): number
		if t <= BOOST_DURATION then return y0 + up * t end
		local tau = t - BOOST_DURATION
		return y0 + up * BOOST_DURATION + up * tau - gravity * tau * tau / 2
	end

	local function solve(up: number): (number, number)
		local riseY = y0 + up * BOOST_DURATION
		local fallTime = (up + math.sqrt(math.max(0, up ^ 2 - 2 * gravity * (landY - riseY)))) / gravity
		local T = BOOST_DURATION + fallTime
		return T, math.max(MIN_FORWARD, dist / T)
	end

	local seedUp = upSpeed
	local flightTime, forwardSpeed = solve(upSpeed)
	local converged = false
	for _ = 1, 5 do
		local clears = true
		for _, ob in obstacles do
			local t = math.clamp(ob[1] / forwardSpeed, 0, flightTime)
			if altitudeAt(upSpeed, t) < ob[2] then
				clears = false
				break
			end
		end
		if clears then
			converged = true
			break
		end
		upSpeed *= 1.15
		flightTime, forwardSpeed = solve(upSpeed)
	end
	if not converged then
		upSpeed = seedUp
		flightTime, forwardSpeed = solve(upSpeed)
	end

	local incoming = math.max(0, hrp.AssemblyLinearVelocity:Dot(travelDir))
	local runSpeed = if mover then mover.WalkSpeed else 16
	if mover and mover.MoveDirection.Magnitude > 0.2 then
		incoming = math.max(incoming, runSpeed)
	end
	-- chained boosts must not compound into zone-skips
	-- and the launch is capped relative to this ramp's tuned crossing speed
	if incoming > runSpeed then
		incoming = runSpeed + (incoming - runSpeed) * BoostConfig.CarryDamp
	end
	forwardSpeed = math.max(forwardSpeed, incoming, fraction * carrySpeed)
	if carrySpeed > 0 then
		forwardSpeed = math.min(forwardSpeed, math.max(carrySpeed * BoostConfig.CarryCap, runSpeed))
	end

	-- the carry only commits while the player is pushing somewhere
	if mover and mover.MoveDirection.Magnitude < 0.2 then
		forwardSpeed = math.min(forwardSpeed, 8)
	end

	-- ramp launch up + forward
	upSpeed = math.max(upSpeed, math.min(forwardSpeed * 0.4, 120))

	local lv = Instance.new("LinearVelocity")
	lv.Name = "BoostVelocity"
	lv.Attachment0 = attachment
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.one * math.huge
	lv.VectorVelocity = travelDir * forwardSpeed + Vector3.new(0, upSpeed, 0)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = hrp

	-- wall hits at flight speed put uncontrolled spin on the character hold it upright until it lands
	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "BoostGyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = attachment
	gyro.RigidityEnabled = true
	gyro.CFrame = CFrame.lookAt(Vector3.zero, travelDir)
	gyro.Parent = hrp
	SkateboardService:NotifyBoosted(player)

	task.delay(BOOST_DURATION, function()
		if not lv.Parent then return end
		-- only the forward axis is commanded (attachment frame, gyro-held) sideways stays free
		-- so the player can steer left and right through the flight
		lv.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
		lv.MaxAxesForce = Vector3.new(0, 0, math.huge)
		lv.VectorVelocity = Vector3.new(0, 0, -forwardSpeed)
		
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local conn
			conn = humanoid.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.Jumping then
					if humanoid.MoveDirection.Magnitude > 0.2 then
						forwardSpeed += math.max(BoostConfig.JumpBoostMin, forwardSpeed * BoostConfig.JumpBoostFraction)
						lv.VectorVelocity = Vector3.new(0, 0, -forwardSpeed)
					end
				elseif newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
					conn:Disconnect()
					lv:Destroy()
					gyro:Destroy()
				end
			end)
			gyro.Destroying:Connect(function()
				conn:Disconnect()
			end)

			-- the flight steers wherever the player pushes
			local TURN_RATE = 4 -- rad/s
			task.spawn(function()
				while lv.Parent do
					local move = humanoid.MoveDirection
					if move.Magnitude < 0.2 then
						forwardSpeed = math.max(8, forwardSpeed * 0.7)
						lv.VectorVelocity = Vector3.new(0, 0, -forwardSpeed)
					else
						local target = Vector3.new(move.X, 0, move.Z).Unit
						local diff = math.atan(travelDir:Cross(target).Y, math.clamp(travelDir:Dot(target), -1, 1))
						local step = math.clamp(diff, -TURN_RATE * 0.05, TURN_RATE * 0.05)
						travelDir = (CFrame.fromAxisAngle(Vector3.yAxis, step) * travelDir).Unit
						gyro.CFrame = CFrame.lookAt(Vector3.zero, travelDir)
						-- pushing again after hovering in place (jump-spam) picks straight back up
						-- to run pace
						if forwardSpeed < humanoid.WalkSpeed then
							forwardSpeed = humanoid.WalkSpeed
							lv.VectorVelocity = Vector3.new(0, 0, -forwardSpeed)
						end
					end
					task.wait(0.05)
				end
			end)

			-- pinned against a wall the push can't climb
			-- cut boost so player can fall or spam jump back up dont kill
			task.spawn(function()
				local lastP = hrp.Position
				while lv.Parent do
					task.wait(0.2)
					if not lv.Parent then break end
					local p = hrp.Position
					if ((p - lastP) * Vector3.new(1, 0, 1)).Magnitude < 1 then
						lv:Destroy()
						gyro:Destroy()
						break
					end
					lastP = p
				end
			end)
		end
	end)
	Debris:AddItem(lv, 30)
	Debris:AddItem(gyro, 33)
end

-- falling in the water kills
local function drown(player: Player, character: Model, hrp: BasePart)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local now = os.clock()
	if now - (lastTeleport[player] or -math.huge) < TELEPORT_COOLDOWN then return end
	lastTeleport[player] = now

	local stale = hrp:FindFirstChild("BoostVelocity")
	if stale then stale:Destroy() end
	local staleGyro = hrp:FindFirstChild("BoostGyro")
	if staleGyro then staleGyro:Destroy() end

	SkateboardService.Client.Fell:Fire(player)
	-- Permanent Revive no death, just straight back to the last island
	if ReviveService:TryInstantRevive(player) then return end
	humanoid.Health = 0
end

local function onFloorTouched(floor: BasePart, hit: BasePart)
	local player, character, hrp = playerFromHit(hit)
	if not (player and character and hrp) then return end

	-- rising floor kill on impact
	if floor.Size.Y <= 3 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local below = Workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), params)
		if below and below.Instance.Name ~= "Floor" then return end
		if hrp.AssemblyLinearVelocity.Y > 10 then return end
	end
	drown(player, character, hrp)
end

function BoostService:KnitInit()
	local ramps = Workspace:WaitForChild("Ramps")

	local function wireWedge(inst: Instance)
		if inst:IsA("BasePart") and inst.Name == "Wedge" then
			inst.Touched:Connect(function(hit)
				onWedgeTouched(inst, hit)
			end)
		end
	end
	for _, inst in ramps:GetDescendants() do
		wireWedge(inst)
	end
	ramps.DescendantAdded:Connect(wireWedge)

	local function wireFloor(inst: Instance)
		if inst:IsA("BasePart") and inst.Name == "Floor" then
			inst.Touched:Connect(function(hit)
				onFloorTouched(inst, hit)
			end)
		end
	end
	for _, inst in Workspace:WaitForChild("Map"):GetDescendants() do
		wireFloor(inst)
	end
	Workspace.Map.DescendantAdded:Connect(wireFloor)
	local floorFolder = Workspace:FindFirstChild("Floor")
	if floorFolder then
		for _, inst in floorFolder:GetDescendants() do
			wireFloor(inst)
		end
		floorFolder.DescendantAdded:Connect(wireFloor)
	end

	-- laser beams kill on touch, same death as the water
	local lasers = Workspace:FindFirstChild("Lasers")
	if lasers then
		local function wireLaser(inst: Instance)
			if inst:IsA("BasePart") and inst.Name == "Laser" then
				inst.Touched:Connect(function(hit)
					local player, character, hrp = playerFromHit(hit)
					if player and character and hrp then
						local humanoid = character:FindFirstChildOfClass("Humanoid")
						if humanoid and humanoid.Health > 0
							and os.clock() - (lastTeleport[player] or -math.huge) >= TELEPORT_COOLDOWN then
							HazardService.Zap(character) -- the laser's hum slams to full volume on the victim
						end
						drown(player, character, hrp)
					end
				end)
			end
		end
		for _, inst in lasers:GetDescendants() do
			wireLaser(inst)
		end
		lasers.DescendantAdded:Connect(wireLaser)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastBoost[player] = nil
		lastTeleport[player] = nil
	end)

	-- fell past everything same death as hitting the water
	task.spawn(function()
		while true do
			task.wait(0.4)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") and hrp.Position.Y < -15 then
					drown(player, character :: Model, hrp)
				end
			end
		end
	end)
end

return BoostService