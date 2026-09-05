--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Knit = require(RS.Packages.Knit)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local ReviveService = require(script.Parent.ReviveService)
local SkateboardService = require(script.Parent.SkateboardService)
local WinsService = require(script.Parent.WinsService)
local Worlds = require(RS.Shared.Worlds)

local RaceService = Knit.CreateService({
	Name = "RaceService",

	Client = {
		Offer = Knit.CreateSignal(), -- (seconds)
		Respond = Knit.CreateSignal(), -- (accepted)
		Started = Knit.CreateSignal(),
		Finished = Knit.CreateSignal(), -- (place, trophies)
	},
})

local RACE_INTERVAL = 5 * 60
local SIGNUP_SECONDS = 15
local RACE_TIMEOUT = 4 * 60
local BOOST_DURATION = 0.25
local BOOST_COOLDOWN = 0.6
local REWARDS = { 10000, 5000, 1000 }

type Entry = {
	world: number,
	finished: boolean,
	deathConnection: RBXScriptConnection?,
}-

local raceMap = Workspace:WaitForChild("Race Map")
local startModel = raceMap:WaitForChild("Start") :: Model
local endModel = raceMap:WaitForChild("End") :: Model
local rampsFolder = raceMap:WaitForChild("Ramps")
local participants: { [Player]: Entry } = {}
local lastBoost: { [Player]: number } = {}
local signupOpen = false
local signupDeadline = 0
local raceActive = false
local finishCount = 0
local roundId = 0
local launchZs: { number } = {}

local function clearMotion(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	for _, name in { "BoostVelocity", "BoostGyro" } do
		local mover = hrp:FindFirstChild(name)
		if mover then mover:Destroy() end
	end
end

local function playerFromHit(hit: BasePart): (Player?, Model?, BasePart?)
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not (player and character) then return nil, nil, nil end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return nil, nil, nil end
	return player, character, hrp
end

local function returnToWorld(player: Player, world: number)
	local character = player.Character
	if not character then return end
	clearMotion(character)
	local cf = Worlds.SpawnCFrame(world)
	pcall(player.RequestStreamAroundAsync, player, cf.Position, 5)
	if character.Parent and character == player.Character then
		character:PivotTo(cf)
	end
end

local function retire(player: Player, returnPlayer: boolean)
	local entry = participants[player]
	if not entry or entry.finished then return end
	entry.finished = true
	if entry.deathConnection then
		entry.deathConnection:Disconnect()
		entry.deathConnection = nil
	end
	player:SetAttribute("InRace", nil)
	if returnPlayer then returnToWorld(player, entry.world) end
end

local function everyoneDone(): boolean
	for player, entry in participants do
		if player.Parent and not entry.finished then return false end
	end
	return true
end

local function finishPlayer(player: Player)
	if not raceActive then return end
	local entry = participants[player]
	if not entry or entry.finished then return end
	finishCount += 1
	local place = finishCount
	local reward = REWARDS[place] or 0
	if reward > 0 and DataService:GetData(player) then
		DataService:AddWins(player, reward)
		WinsService.Client.Collected:Fire(player, reward)
	end
	RaceService.Client.Finished:Fire(player, place, reward)
	retire(player, true)
	if everyoneDone() then raceActive = false end
end

local function startingCFrame(index: number, total: number): CFrame
	local cf, size = startModel:GetBoundingBox()
	local columns = math.min(total, 10)
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)
	local spacing = math.min(9, math.max(5, (size.X - 16) / math.max(columns - 1, 1)))
	local x = (column - (columns - 1) / 2) * spacing
	local z = math.min(size.Z * 0.25, 8) - row * 7
	local pos = cf.Position + Vector3.new(x, size.Y / 2 + 3, z)
	return CFrame.lookAt(pos, pos + Vector3.zAxis)
end

local function beginRace(thisRound: number)
	task.wait(SIGNUP_SECONDS)
	if thisRound ~= roundId then return end
	signupOpen = false

	local racers = {}
	for player, entry in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player.Parent and character and humanoid and humanoid.Health > 0 and not entry.finished then
			table.insert(racers, player)
		else
			entry.finished = true
		end
	end
	if #racers == 0 then return end

	table.sort(racers, function(a, b) return a.UserId < b.UserId end)
	raceActive = true
	finishCount = 0
	for index, player in racers do
		local entry = participants[player]
		local character = player.Character :: Model
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		ReviveService:ResetRun(player)
		clearMotion(character)
		player:SetAttribute("InRace", true)
		local cf = startingCFrame(index, #racers)
		pcall(player.RequestStreamAroundAsync, player, cf.Position, 5)
		if character.Parent then
			character:PivotTo(cf)
		end
		if humanoid then
			entry.deathConnection = humanoid.Died:Connect(function()
				-- Leave InRace set through the Died event so ReviveService ignores this race death.
				task.defer(function()
					retire(player, false)
					if everyoneDone() then raceActive = false end
				end)
			end)
		end
		RaceService.Client.Started:Fire(player)
	end

	task.delay(RACE_TIMEOUT, function()
		if thisRound ~= roundId then return end
		for player, entry in participants do
			if not entry.finished then retire(player, true) end
		end
		raceActive = false
	end)
end

local function openSignup()
	if signupOpen or raceActive then return end
	roundId += 1
	participants = {}
	signupOpen = true
	signupDeadline = os.clock() + SIGNUP_SECONDS
	RaceService.Client.Offer:FireAll(SIGNUP_SECONDS)
	task.spawn(beginRace, roundId)
end

local function targetZFor(wedge: BasePart): number
	local nearest = 1
	local best = math.huge
	for i, z in launchZs do
		local distance = math.abs(wedge.Position.Z - z)
		if distance < best then
			best = distance
			nearest = i
		end
	end
	if nearest < #launchZs then
		return launchZs[nearest + 1] - 35
	end
	return endModel:GetPivot().Z
end

local function launch(wedge: BasePart, hit: BasePart)
	if not raceActive then return end
	local player, character, hrp = playerFromHit(hit)
	if not (player and character and hrp) then return end
	local entry = participants[player]
	if not entry or entry.finished then return end
	local now = os.clock()
	if now - (lastBoost[player] or -math.huge) < BOOST_COOLDOWN then return end
	if hrp:FindFirstChild("BoostVelocity") then return end
	local attachment = hrp:FindFirstChild("RootAttachment")
	if not (attachment and attachment:IsA("Attachment")) then return end
	lastBoost[player] = now

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local direction = if humanoid and humanoid.MoveDirection.Magnitude > 0.2
		then humanoid.MoveDirection * Vector3.new(1, 0, 1)
		else Vector3.zAxis
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.zAxis
	if direction.Z < 0.2 then direction = Vector3.zAxis end

	local targetZ = targetZFor(wedge)
	local distance = math.max(30, (targetZ - hrp.Position.Z) / math.max(direction.Z, 0.2))
	local flightTime = math.clamp(distance / 165, 0.85, 3.2)
	local gravity = Workspace.Gravity
	local tau = flightTime - BOOST_DURATION
	local upSpeed = math.max(45, gravity * tau * tau / (2 * flightTime))
	local forwardSpeed = math.max(70, distance / flightTime)

	local lv = Instance.new("LinearVelocity")
	lv.Name = "BoostVelocity"
	lv.Attachment0 = attachment
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.one * math.huge
	lv.VectorVelocity = direction * forwardSpeed + Vector3.new(0, upSpeed, 0)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = hrp

	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "BoostGyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = attachment
	gyro.RigidityEnabled = true
	gyro.CFrame = CFrame.lookAt(Vector3.zero, direction)
	gyro.Parent = hrp
	SkateboardService:NotifyBoosted(player)

	task.delay(BOOST_DURATION, function()
		if not lv.Parent then return end
		lv.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
		lv.MaxAxesForce = Vector3.new(0, 0, math.huge)
		lv.VectorVelocity = Vector3.new(0, 0, -forwardSpeed)
		local mover = character:FindFirstChildOfClass("Humanoid")
		if not mover then return end
		local connection: RBXScriptConnection?
		connection = mover.StateChanged:Connect(function(_, state)
			if state == Enum.HumanoidStateType.Landed or state == Enum.HumanoidStateType.Running then
				if connection then connection:Disconnect() end
				if lv.Parent then lv:Destroy() end
				if gyro.Parent then gyro:Destroy() end
			end
		end)
		gyro.Destroying:Connect(function()
			if connection then connection:Disconnect() end
		end)
	end)
	Debris:AddItem(lv, 12)
	Debris:AddItem(gyro, 15)
end

local function eliminate(hit: BasePart)
	local player, character, hrp = playerFromHit(hit)
	if not (player and character and hrp) then return end
	local entry = participants[player]
	if not (raceActive and entry and not entry.finished) then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	clearMotion(character)
	SkateboardService.Client.Fell:Fire(player)
	AnalyticsService:LogDeath(player, "Race Floor")
	humanoid.Health = 0
end

function RaceService:KnitInit()
	RaceService.Client.Respond:Connect(function(player: Player, accepted: unknown)
		if not signupOpen or os.clock() > signupDeadline or typeof(accepted) ~= "boolean" then return end
		if accepted then
			if participants[player] or not DataService:GetData(player) then return end
			participants[player] = {
				world = DataService:GetWorld(player),
				finished = false,
				deathConnection = nil,
			}
		else
			-- Players may withdraw at any point before the signup timer expires.
			participants[player] = nil
		end
	end)

	local groups = {}
	for _, inst in rampsFolder:GetDescendants() do
		if inst:IsA("BasePart") and inst.Name == "Wedge" and inst.Size.Y >= 2.5 then
			local found = false
			for i, z in groups do
				if math.abs(z - inst.Position.Z) < 3 then
					groups[i] = (z + inst.Position.Z) / 2
					found = true
					break
				end
			end
			if not found then table.insert(groups, inst.Position.Z) end
			inst.Touched:Connect(function(hit) launch(inst, hit) end)
		end
	end
	table.sort(groups)
	launchZs = groups

	for _, inst in endModel:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit:FindFirstAncestorOfClass("Model"))
				if player then finishPlayer(player) end
			end)
		end
	end

	for _, inst in raceMap:GetChildren() do
		if inst:IsA("BasePart") and inst.Name == "Floor" then
			inst.Touched:Connect(eliminate)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		if signupOpen then
			RaceService.Client.Offer:Fire(player, math.max(0, signupDeadline - os.clock()))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local entry = participants[player]
		if entry and entry.deathConnection then entry.deathConnection:Disconnect() end
		participants[player] = nil
		lastBoost[player] = nil
	end)

	task.spawn(function()
		local nextOffer = os.clock() + RACE_INTERVAL
		while true do
			task.wait(1)
			local force = RunService:IsStudio() and Workspace:GetAttribute("RaceStartNow") == true
			if force then Workspace:SetAttribute("RaceStartNow", nil) end
			if force or os.clock() >= nextOffer then
				openSignup()
				local override = if RunService:IsStudio() then Workspace:GetAttribute("RaceIntervalOverride") else nil
				nextOffer = os.clock() + (if typeof(override) == "number" then math.max(30, override) else RACE_INTERVAL)
			end
		end
	end)
end

return RaceService