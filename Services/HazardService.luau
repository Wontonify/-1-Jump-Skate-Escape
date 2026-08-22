--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local ReviveService = require(script.Parent.ReviveService)

local HazardService = Knit.CreateService({
	Name = "HazardService",

	Client = {
		Quake = Knit.CreateSignal(),
	},
})

local UP_TIME = 60    -- structures stand
local DOWN_TIME = 30  -- structures stay buried
local SINK_TIME = 5
local RISE_TIME = 5
local FLOOD_HEIGHT = 15 -- minimum flood height; each zone scales up to fully submerge its platforms
local FLOOD_MARGIN = 4  -- studs of flood above the tallest platform top in the zone
local PAD_CLEARANCE = 2 -- the flood stops this far below the Wins Return pad's platform floor
local FLOOD_FROM_Z = 140 -- the lava zone floor and every zone past it floods
local FLOOD_CROSS = 155 -- risen walls slim down to the corridor between the side walls (156 gap)
local EDGE_TRIM = 0.4   -- risen neighbours pull back from their shared face (stops the z-fighting)
local ZAP_SOUND = 86261914368076
local SHOCK_SOUND = 119225525936197

local structures: { { model: Model, base: CFrame, drop: number } } = {}
local structTops: { { z: number, top: number } } = {} -- standing bbox tops, for the flood scaling
type FloodPiece = { part: BasePart, xMin: number, xMax: number, zMin: number, zMax: number }
local floods: { { part: BasePart, bottom: number, flatY: number, crossFlat: number, centerX: number, flatMinZ: number, flatMaxZ: number, target: number, riseDur: number, fallDur: number, pieces: { FloodPiece } } } = {}

local function setStructures(alpha: number) -- 0 up, 1 buried
	for _, s in structures do
		s.model:PivotTo(s.base - Vector3.new(0, s.drop * alpha, 0))
	end
end

-- the sheet is tiled by box pieces that leave the platform towers carved out; each piece
-- is its static box clipped to the animated outer bounds, so pieces grow with the flood
-- while the carved holes never close over a platform
local function setFlood(f: typeof(floods[1]), alpha: number) -- 0 flat sheet, 1 full wall
	local h = f.flatY + (f.target - f.flatY) * alpha
	local cross = f.crossFlat + (math.min(FLOOD_CROSS, f.crossFlat) - f.crossFlat) * alpha
	local xLo = f.centerX - cross / 2
	local xHi = f.centerX + cross / 2
	local zLo = f.flatMinZ + (EDGE_TRIM / 2) * alpha
	local zHi = f.flatMaxZ - (EDGE_TRIM / 2) * alpha
	local y = f.bottom + h / 2
	for _, piece in f.pieces do
		local pxLo = math.max(piece.xMin, xLo)
		local pxHi = math.min(piece.xMax, xHi)
		local pzLo = math.max(piece.zMin, zLo)
		local pzHi = math.min(piece.zMax, zHi)
		piece.part.Size = Vector3.new(math.max(pxHi - pxLo, 0.05), h, math.max(pzHi - pzLo, 0.05))
		piece.part.CFrame = CFrame.new((pxLo + pxHi) / 2, y, (pzLo + pzHi) / 2)
	end
end

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

-- every zone takes different times to flood
local function animateFloods(rising: boolean)
	local t0 = os.clock()
	while true do
		local t = os.clock() - t0
		local done = true
		for _, f in floods do
			local dur = if rising then f.riseDur else f.fallDur
			local a = math.clamp(t / dur, 0, 1)
			setFlood(f, ease(if rising then a else 1 - a))
			if a < 1 then done = false end
		end
		if done then break end
		task.wait(0.05)
	end
end

local function animate(duration: number, fn: (alpha: number) -> ())
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		fn(ease(a))
		if a >= 1 then break end
		task.wait(0.05)
	end
end

function HazardService:KnitInit()
	local platforms = Workspace:FindFirstChild("Platforms")
	if platforms then
		for _, m in platforms:GetChildren() do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				table.insert(structures, { model = m, base = m:GetPivot(), drop = size.Y + 6 })
				table.insert(structTops, { z = cf.Z, top = cf.Y + size.Y / 2 })
			end
		end
	end
	local floorFolder = Workspace:FindFirstChild("Floor")
	if floorFolder then
		for _, f in floorFolder:GetChildren() do
			if f:IsA("BasePart") and f.Material == Enum.Material.Neon and f.Position.Z >= FLOOD_FROM_Z then
				-- cross-course = world X find which local size axis that is
				local crossIsX = math.abs(f.CFrame.RightVector.X) > 0.5
				local courseFlat = if crossIsX then f.Size.Z else f.Size.X
				table.insert(floods, {
					part = f,
					bottom = f.Position.Y - f.Size.Y / 2,
					flatY = f.Size.Y,
					crossFlat = if crossIsX then f.Size.X else f.Size.Z,
					centerX = f.Position.X,
					flatMinZ = f.Position.Z - courseFlat / 2,
					flatMaxZ = f.Position.Z + courseFlat / 2,
					target = FLOOD_HEIGHT,
					riseDur = 8,
					fallDur = 5,
					pieces = {},
				})
			end
		end
	end
	-- each zone's flood grows tall enough to swallow its tallest platform whole, but
	-- never the ramp platform the Wins Return pad and its floor stay above the surface
	local pads: { { z: number, floorTop: number } } = {}
	local padFolder = Workspace:FindFirstChild("WinsPads")
	if padFolder then
		for _, p in padFolder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(pads, { z = p.Position.Z, floorTop = p.Position.Y - p.Size.Y / 2 })
			end
		end
	end
	for _, f in floods do
		local zMin = f.flatMinZ
		local zMax = f.flatMaxZ
		local target = FLOOD_HEIGHT
		for _, s in structTops do
			if s.z >= zMin and s.z <= zMax then
				target = math.max(target, s.top - f.bottom + FLOOD_MARGIN)
			end
		end
		for _, p in pads do
			if p.z >= zMin and p.z <= zMax then
				target = math.min(target, p.floorTop - PAD_CLEARANCE - f.bottom)
			end
		end
		f.target = math.max(target, f.flatY)
		f.riseDur = math.clamp(f.target / 6, 8, 20)
		f.fallDur = math.clamp(f.target / 25, 5, 10)
	end

	-- carve every platform tower's footprint out of each sheet, then tile what remains:
	-- full-width slabs between towers, side strips beside them -- the lava sits flush
	-- against a platform's walls but is never on top of it
	local holesByFlood: { [number]: { { zMin: number, zMax: number, xMin: number, xMax: number } } } = {}
	for _, d in Workspace.Map:GetDescendants() do
		if not (d:IsA("BasePart") and d.CanCollide) then continue end
		local cf = d.CFrame
		local ws = cf.RightVector:Abs() * d.Size.X + cf.UpVector:Abs() * d.Size.Y + cf.LookVector:Abs() * d.Size.Z
		if ws.X < 40 or ws.Y < 15 or ws.Z < 40 then continue end
		for i, f in floods do
			if math.abs(d.Position.X - f.centerX) > 22 then continue end -- only the corridor-centred towers
			if d.Position.Y - ws.Y / 2 > f.bottom + f.target or d.Position.Y + ws.Y / 2 < f.bottom then continue end
			local zMin = math.max(d.Position.Z - ws.Z / 2, f.flatMinZ)
			local zMax = math.min(d.Position.Z + ws.Z / 2, f.flatMaxZ)
			if zMax - zMin < 0.1 then continue end
			local list = holesByFlood[i]
			if not list then
				list = {}
				holesByFlood[i] = list
			end
			table.insert(list, { zMin = zMin, zMax = zMax, xMin = d.Position.X - ws.X / 2, xMax = d.Position.X + ws.X / 2 })
		end
	end
	local BIG = 1e6
	for i, f in floods do
		local holes = holesByFlood[i] or {}
		table.sort(holes, function(a, b) return a.zMin < b.zMin end)
		local boxes: { { xMin: number, xMax: number, zMin: number, zMax: number } } = {}
		local cursor = f.flatMinZ
		for _, hole in holes do
			if hole.zMin > cursor + 0.05 then
				table.insert(boxes, { xMin = -BIG, xMax = BIG, zMin = cursor, zMax = hole.zMin })
			end
			local a, b = math.max(hole.zMin, cursor), hole.zMax
			if b > a + 0.05 then
				table.insert(boxes, { xMin = -BIG, xMax = hole.xMin, zMin = a, zMax = b })
				table.insert(boxes, { xMin = hole.xMax, xMax = BIG, zMin = a, zMax = b })
			end
			cursor = math.max(cursor, hole.zMax)
		end
		if cursor < f.flatMaxZ - 0.05 then
			table.insert(boxes, { xMin = -BIG, xMax = BIG, zMin = cursor, zMax = f.flatMaxZ })
		end
		if #boxes == 0 then
			table.insert(boxes, { xMin = -BIG, xMax = BIG, zMin = f.flatMinZ, zMax = f.flatMaxZ })
		end
		for j, box in boxes do
			local part = if j == 1 then f.part else f.part:Clone()
			if j > 1 then part.Parent = f.part.Parent end
			table.insert(f.pieces, { part = part, xMin = box.xMin, xMax = box.xMax, zMin = box.zMin, zMax = box.zMax })
		end
		setFlood(f, 0)
	end

	self:_initSweeps()
	self:_initClouds()
	if #structures == 0 then return end

	task.spawn(function()
		while true do
			task.wait(UP_TIME)
			-- re-glue in case a flood part was edited while flat
			for _, f in floods do
				f.bottom = math.min(f.bottom, f.part.Position.Y - f.part.Size.Y / 2)
			end
			HazardService.Client.Quake:FireAll(SINK_TIME)
			task.spawn(animateFloods, true)
			animate(SINK_TIME, setStructures)
			task.wait(DOWN_TIME)
			task.spawn(animateFloods, false)
			animate(RISE_TIME, function(a: number)
				setStructures(1 - a)
			end)
		end
	end)
end

-- sweeping lasers Workspace.Lasers models between the two ramps position derives from the server clock so clients render the same spot
function HazardService:_initSweeps()
	local folder = Workspace:FindFirstChild("Lasers")
	if not folder then return end
	local sweeps: { { model: Model, base: CFrame, minZ: number, maxZ: number, period: number, phase: number, spanX: number } } = {}
	for _, m in folder:GetChildren() do
		local minZ = m:GetAttribute("SweepMinZ")
		if m:IsA("Model") and typeof(minZ) == "number" then
			local _, size = m:GetBoundingBox()
			table.insert(sweeps, {
				model = m,
				base = m:GetPivot(),
				minZ = minZ,
				maxZ = (m:GetAttribute("SweepMaxZ") :: number?) or minZ,
				period = (m:GetAttribute("SweepPeriod") :: number?) or 24,
				phase = (m:GetAttribute("SweepPhase") :: number?) or 0,
				spanX = math.max(size.X, size.Z) / 2,
			})
		end
	end
	if #sweeps == 0 then return end

	local lastZap: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(p) lastZap[p] = nil end)

	RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		for _, s in sweeps do
			local z = s.minZ + (s.maxZ - s.minZ) * (0.5 + 0.5 * math.sin(math.pi * 2 * t / s.period + s.phase))
			s.model:PivotTo(CFrame.new(s.base.X, s.base.Y, z) * s.base.Rotation)
			-- a gliding beam must catch players Touched can miss (standing still as it arrives)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not (character and hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0) then continue end
				local p = hrp.Position
				if math.abs(p.Z - z) > 2 or math.abs(p.Y - s.base.Y) > 2.5 or math.abs(p.X - s.base.X) > s.spanX then continue end
				if os.clock() - (lastZap[player] or -math.huge) < 1 then continue end
				lastZap[player] = os.clock()
				HazardService.Zap(character)
				if not ReviveService:TryInstantRevive(player) then
					humanoid.Health = 0
				end
			end
		end
	end)
end

-- lethal clouds drift wall-to-wall (world X) on the shared server clock, like the lasers
function HazardService:_initClouds()
	local clouds: { { part: BasePart, base: CFrame, minX: number, maxX: number, period: number, phase: number } } = {}
	for _, d in Workspace.Map:GetChildren() do
		local minX = d:GetAttribute("CloudMinX")
		if d:IsA("BasePart") and typeof(minX) == "number" then
			table.insert(clouds, {
				part = d,
				base = d.CFrame,
				minX = minX,
				maxX = (d:GetAttribute("CloudMaxX") :: number?) or minX,
				period = (d:GetAttribute("CloudPeriod") :: number?) or 45,
				phase = (d:GetAttribute("CloudPhase") :: number?) or 0,
			})
		end
	end
	if #clouds == 0 then return end
	local lastKill: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(p) lastKill[p] = nil end)
	RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow()
		for _, c in clouds do
			local x = c.minX + (c.maxX - c.minX) * (0.5 + 0.5 * math.sin(math.pi * 2 * t / c.period + c.phase))
			c.part.CFrame = CFrame.new(x, c.base.Position.Y, c.base.Position.Z) * c.base.Rotation
			-- same thing with the lasers
			local half = c.part.Size / 2
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not (hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0) then continue end
				local p = c.part.CFrame:PointToObjectSpace(hrp.Position)
				if math.abs(p.X) > half.X or math.abs(p.Y) > half.Y or math.abs(p.Z) > half.Z then continue end
				if os.clock() - (lastKill[player] or -math.huge) < 1 then continue end
				lastKill[player] = os.clock()
				HazardService.Shock(character) -- like the laser Zap, fires even when a revive saves you
				if not ReviveService:TryInstantRevive(player) then
					humanoid.Health = 0
				end
			end
		end
	end)
end

-- full-blast electricity burst on whoever a laser catches (rides the character)
function HazardService.Zap(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. ZAP_SOUND
	s.Volume = 1
	s.RollOffMinDistance = 15
	s.RollOffMaxDistance = 120
	s.Parent = hrp
	s:Play()
	Debris:AddItem(s, 3)
end

-- magnet snap + a spark burst over the body of whoever a cloud catches
function HazardService.Shock(character: Model?)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and hrp and hrp:IsA("BasePart")) then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. SHOCK_SOUND
	s.Volume = 1
	s.RollOffMinDistance = 15
	s.RollOffMaxDistance = 120
	s.Parent = hrp
	s:Play()
	Debris:AddItem(s, 4)
	for _, d in character:GetChildren() do
		if not d:IsA("BasePart") then continue end
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(150, 220, 255), Color3.fromRGB(70, 130, 255))
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.5)
		e.Lifetime = NumberRange.new(0.15, 0.4)
		e.Speed = NumberRange.new(5, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 0
		e.Parent = d
		e:Emit(10)
		Debris:AddItem(e, 2)
	end
end

return HazardService