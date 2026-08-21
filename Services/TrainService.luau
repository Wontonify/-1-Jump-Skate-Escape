--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PhysicsService = game:GetService("PhysicsService")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local XPService = require(script.Parent.XPService)
local TrainConfig = require(RS.Shared.TrainConfig)

local TrainService = Knit.CreateService({
	Name = "TrainService",

	Client = {
		Trained = Knit.CreateSignal(),
		Denied = Knit.CreateSignal(),
		TrainingStarted = Knit.CreateSignal(), -- (padName) the held prompt succeeded
		TrainingStopped = Knit.CreateSignal(),
		StopRequest = Knit.CreateSignal(),     -- client Leave button / movement
		GroupBoost = Knit.CreateSignal(),      -- (mult) your group-training multiplier changed
	},
})

local function multiplierText(mult: number): string
	local s = string.format("%.1f", mult)
	s = (s:gsub("%.0$", ""))
	return s .. "x XP"
end

local function requirementText(ground: TrainConfig.Ground): string
	if ground.Robux then
		return "R$ " .. ground.Robux
	end
	return "Requires: Rebirth " .. (ground.Rebirths or 0)
end

local training: { [Player]: BasePart } = {}
local padLabels: { [BasePart]: TextLabel } = {}

-- trainees swap to a collision group other characters pass through, so nobody can shove them off the pad mid-animation
local function setGroup(character: Model, group: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then part.CollisionGroup = group end
	end
end

local function canUse(player: Player, name: string, ground: TrainConfig.Ground): boolean
	local data = DataService:GetData(player)
	if not data then return false end
	if ground.Robux then
		if data.OwnedTrains ~= nil and table.find(data.OwnedTrains, name) ~= nil then return true end
		return ground.GamepassId ~= nil and PassService:OwnsPass(player, ground.GamepassId)
	end
	return data.Rebirth >= (ground.Rebirths or 0)
end

local function decorate(pad: BasePart, ground: TrainConfig.Ground)
	local template = RS.Assets.UI:FindFirstChild("Train")
	if not template then return end
	local gui = template:Clone() :: BillboardGui
	local power = gui:FindFirstChild("PowerLoader", true)
	if power and power:IsA("TextLabel") then
		power.Text = multiplierText(ground.Multiplier)
		padLabels[pad] = power
	end
	local req = gui:FindFirstChild("RebirthLoader", true)
	if req and req:IsA("TextLabel") then
		req.Text = requirementText(ground)
		local colors = TrainConfig.Gradients[pad.Name]
		local gradient = req:FindFirstChildOfClass("UIGradient")
		if gradient and colors then
			gradient.Color = ColorSequence.new(colors[1], colors[2])
		end
	end
	gui.Parent = pad

	-- ambient sparkle tinted to the ground better grounds glow denser
	local atts = RS.Assets:FindFirstChild("Attachments")
	if atts and not pad:FindFirstChild("TrainFX") then
		local att = Instance.new("Attachment")
		att.Name = "TrainFX"
		att.Position = Vector3.new(0, pad.Size.Y / 2 + 1.5, 0)
		local colors = TrainConfig.Gradients[pad.Name]
		local tier = math.clamp(((ground.AnimSpeed or 1) - 1) / 0.6, 0, 1)
		local taken = 0
		for _, e in atts:GetChildren() do
			if e.Name == "Rebirth" and e:IsA("ParticleEmitter") and taken < 2 then
				taken += 1
				local clone = e:Clone()
				clone.Enabled = true
				clone.Rate = 3 + tier * 9
				if colors then clone.Color = ColorSequence.new(colors[1], colors[2]) end
				clone.Parent = att
			end
		end
		att.Parent = pad
	end
end

function TrainService:KnitInit()
	-- the client billboards need to see gamepass-owned grounds too
	table.insert(PassService.Changed, function(player: Player)
		local names = {}
		for name, ground in TrainConfig.Grounds do
			if ground.GamepassId and PassService:OwnsPass(player, ground.GamepassId) then
				table.insert(names, name)
			end
		end
		player:SetAttribute("OwnedTrainPasses", table.concat(names, "|"))
	end)

	pcall(function() PhysicsService:RegisterCollisionGroup("Character") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("Trainee") end)
	PhysicsService:CollisionGroupSetCollidable("Trainee", "Character", false)
	PhysicsService:CollisionGroupSetCollidable("Trainee", "Trainee", false)
	PhysicsService:CollisionGroupSetCollidable("Character", "Character", false) -- players never collide with each other
	local function hookCharacter(player: Player, character: Model)
		setGroup(character, if training[player] then "Trainee" else "Character")
		character.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = if training[player] then "Trainee" else "Character"
			end
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(c) hookCharacter(p, c) end)
	end)
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function(c) hookCharacter(p, c) end)
		if p.Character then hookCharacter(p, p.Character) end
	end

	local folder = Workspace:WaitForChild("Train", 10)
	if not folder then
		warn("[TrainService] workspace.Train is missing")
		return
	end

	local lastGroupMult: { [Player]: number } = {}
	local graceUntil: { [Player]: number } = {}
	local function stopTraining(player: Player)
		lastGroupMult[player] = nil
		graceUntil[player] = nil
		if training[player] then
			training[player] = nil
			if player.Character then setGroup(player.Character, "Character") end
			TrainService.Client.TrainingStopped:Fire(player)
		end
	end

	for _, pad in folder:GetChildren() do
		if not pad:IsA("BasePart") then continue end
		local ground = TrainConfig.Grounds[pad.Name]
		if not ground then
			warn("[TrainService] no Grounds entry for " .. pad.Name)
			continue
		end
		decorate(pad, ground)

		-- training starts from a held prompt, not from stepping onto the pad
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TrainPrompt"
		prompt.ActionText = "Train"
		prompt.ObjectText = pad.Name
		prompt.HoldDuration = 0.5
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 14
		prompt.Parent = pad
		prompt.Triggered:Connect(function(player)
			if not canUse(player, pad.Name, ground) then
				if ground.GamepassId then
					MarketplaceService:PromptGamePassPurchase(player, ground.GamepassId)
				elseif not ground.Robux then
					-- interacting with a locked rebirth pad bounces you home, same as walking on
					local character = player.Character
					local sp = Workspace:FindFirstChild("SpawnLocation")
					if character and sp and sp:IsA("BasePart") then
						character:PivotTo(sp.CFrame + Vector3.new(0, 4, 0))
					end
					TrainService.Client.Denied:Fire(player, "You need to unlock Rebirth " .. (ground.Rebirths or 0))
				end
				return
			end
			if training[player] == pad then return end -- re-trigger must not refresh the grace
			training[player] = pad
			graceUntil[player] = os.clock() + 1.5
			if player.Character then setGroup(player.Character, "Trainee") end
			TrainService.Client.TrainingStarted:Fire(player, pad.Name)
		end)
	end

	local function padUnder(position: Vector3): BasePart?
		for _, pad in folder:GetChildren() do
			if not pad:IsA("BasePart") then continue end
			local p = pad.CFrame:PointToObjectSpace(position)
			if math.abs(p.X) <= pad.Size.X / 2 and math.abs(p.Z) <= pad.Size.Z / 2
				and p.Y >= -pad.Size.Y / 2 and p.Y <= pad.Size.Y / 2 + 6 then
				return pad
			end
		end
		return nil
	end

	Players.PlayerRemoving:Connect(function(p)
		training[p] = nil
		lastGroupMult[p] = nil
		graceUntil[p] = nil
	end)
	TrainService.Client.StopRequest:Connect(stopTraining)

	-- training together on the same pad pays more: 2 trainees = 1.5x, 3 = 1.75x, 4+ = 2x
	local GROUP_MULTS = { 1, 1.5, 1.75, 2 }
	task.spawn(function()
		local lastPadMult: { [BasePart]: number } = {}
		while true do
			task.wait(TrainConfig.Interval)
			-- pass 1: validate; only players verified on their pad count toward a group
			local verified: { Player } = {}
			local padCounts: { [BasePart]: number } = {}
			for player, pad in training do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local ground = TrainConfig.Grounds[pad.Name]
				if not hrp or not hrp:IsA("BasePart") or not humanoid or humanoid.Health <= 0
					or not ground or not canUse(player, pad.Name, ground) then
					stopTraining(player)
					continue
				end
				if padUnder(hrp.Position) ~= pad then
					if os.clock() < (graceUntil[player] or 0) then continue end
					stopTraining(player)
					continue
				end
				graceUntil[player] = nil
				table.insert(verified, player)
				padCounts[pad] = (padCounts[pad] or 0) + 1
			end
			-- pass 2 grant with the verified group sizes
			for _, player in verified do
				local pad = training[player]
				local ground = pad and TrainConfig.Grounds[pad.Name]
				if not pad or not ground then continue end
				local groupMult = GROUP_MULTS[math.clamp(padCounts[pad] or 1, 1, #GROUP_MULTS)]
				if lastGroupMult[player] ~= groupMult then
					lastGroupMult[player] = groupMult
					TrainService.Client.GroupBoost:Fire(player, groupMult)
				end
				local xpPerStep = player:GetAttribute("XPPerStep") or 0
				local amount = math.ceil(xpPerStep * ground.Multiplier * groupMult)
				XPService:GrantXP(player, amount)
				TrainService.Client.Trained:Fire(player, amount)
			end
			-- a grouped pad's billboard shows the boosted rate to everyone
			for pad, label in padLabels do
				local ground = TrainConfig.Grounds[pad.Name]
				if not ground then continue end
				local mult = GROUP_MULTS[math.clamp(padCounts[pad] or 1, 1, #GROUP_MULTS)]
				if lastPadMult[pad] ~= mult then
					lastPadMult[pad] = mult
					label.Text = multiplierText(ground.Multiplier * mult)
				end
			end
		end
	end)

	-- standing on a locked Robux pad pitches its gamepass locked rebirth pads tp only after proximity prompt interaction
	task.spawn(function()
		local lastBounce: { [Player]: number } = {}
		Players.PlayerRemoving:Connect(function(p) lastBounce[p] = nil end)
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not character or not hrp or not hrp:IsA("BasePart") or not humanoid
					or humanoid.Health <= 0 then continue end
				if hrp:FindFirstChild("BoostVelocity") then continue end -- a boost flight overhead is not a walk-on
				local pad = padUnder(hrp.Position)
				if not pad or training[player] == pad then continue end
				local ground = TrainConfig.Grounds[pad.Name]
				if not ground or not ground.Robux or canUse(player, pad.Name, ground) then continue end
				if os.clock() - (lastBounce[player] or 0) < 5 then continue end
				lastBounce[player] = os.clock()
				if ground.GamepassId then
					MarketplaceService:PromptGamePassPurchase(player, ground.GamepassId)
				end
			end
		end
	end)
end

return TrainService




