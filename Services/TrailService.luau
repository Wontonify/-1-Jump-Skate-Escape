--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local GamepassConfig = require(RS.Shared.GamepassConfig)
local TrailConfig = require(RS.Shared.TrailConfig)
local SkateboardConfig = require(RS.Shared.SkateboardConfig)
local Levels = require(RS.Shared.Levels)

local TrailService = Knit.CreateService({
	Name = "TrailService",

	Client = {
		Buy = Knit.CreateSignal(),
		Equip = Knit.CreateSignal(),
		Unequip = Knit.CreateSignal(),
		Bought = Knit.CreateSignal(),
		Equipped = Knit.CreateSignal(),
		Denied = Knit.CreateSignal(),
		SpeedCap = Knit.CreateSignal(), -- client SpeedAdjuster
	},
})

local BASE_WALKSPEED = StarterPlayer.CharacterWalkSpeed
if BASE_WALKSPEED <= 0 then BASE_WALKSPEED = 16 end

-- speedadjuster typed cap 4 server to change walkspeed
local speedCaps: { [Player]: number } = {}

function TrailService:GetActualWalkSpeed(player: Player): number
	return math.min(self:ComputeWalkSpeed(player), speedCaps[player] or math.huge)
end

local function publish(player: Player)
	local d = DataService:GetData(player); if not d then return end
	player:SetAttribute("Trail", d.Trail or "")
	player:SetAttribute("OwnedTrails", table.concat(d.Trails or {}, "|"))
end

local function owns(player: Player, name: string): boolean
	local d = DataService:GetData(player)
	return d and d.Trails and table.find(d.Trails, name) ~= nil or false
end

-- base + level + board's xp + shop upgrades
function TrailService:ComputeWalkSpeed(player: Player): number
	local d = DataService:GetData(player)
	local level = d and d.Level or 1
	local board = d and SkateboardConfig.ByName(d.Board or "")
	local boardBonus = board and board.XP or 0
	local upgrades = d and d.SpeedUpgrade or 0
	local pack = if d and d.StarterPack then 3 else 0
	local friends = (player:GetAttribute("FriendBoost") :: number?) or 1
	local event = if ((Workspace:GetAttribute("EventSpeedUntil") :: number?) or 0) > os.time()
		then ((Workspace:GetAttribute("EventSpeedMult") :: number?) or 1)
		else 1
	return (BASE_WALKSPEED + math.max(level - 1, 0) + boardBonus + upgrades + pack) * PassService:SpeedMultiplier(player) * friends * event
end

-- equipped trail's wins multiplier
function TrailService:WinsMultiplier(player: Player): number
	local d = DataService:GetData(player)
	local entry = d and TrailConfig.Trails[d.Trail or ""]
	return entry and entry.Multiplier or 1
end

-- swaps the character's trail FX and walkspeed to match the equipped trail
local function apply(player: Player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp then return end
	-- the FX ride the skateboard so they follow it through animations (training areas)
	local boardModel = character and character:FindFirstChild("Skateboard")
	local boardRoot = boardModel and boardModel:FindFirstChild("Board")
	local mount: BasePart = if boardRoot and boardRoot:IsA("BasePart") then boardRoot else hrp :: BasePart
	for _, holder in { hrp, mount } do
		for _, c in holder:GetChildren() do
			if c:GetAttribute("TrailFX") then c:Destroy() end
		end
	end
	local d = DataService:GetData(player)
	local name = d and d.Trail or ""
	local entry = TrailConfig.Trails[name]
	if humanoid then
		humanoid.WalkSpeed = TrailService:GetActualWalkSpeed(player)
	end
	-- no trail equipped a plain white ribbon rides along, purely decorative (no multiplier)
	local folder = if entry
		then RS.Assets.Trails:FindFirstChild(name)
		else RS.Assets.Trails:FindFirstChild("DefaultWhite")
	if not folder then return end
	local clones: { [string]: Instance } = {}
	for _, c in folder:GetChildren() do
		local clone = c:Clone()
		clone:SetAttribute("TrailFX", true)
		if mount ~= hrp then
			-- the ribbon hugs the deck: a/b span the board's width just above it,
			-- anything else (particle holders) sits at the board's centre
			if clone:IsA("Attachment") then
				local size = mount.Size
				local deckY = size.Y / 2 + 0.15
				local half = math.min(size.X, size.Z) / 2 + 0.2
				local across = if size.Z <= size.X then Vector3.new(0, 0, half) else Vector3.new(half, 0, 0)
				if clone.Name == "a" then
					clone.CFrame = CFrame.new(Vector3.new(0, deckY, 0) + across)
				elseif clone.Name == "b" then
					clone.CFrame = CFrame.new(Vector3.new(0, deckY, 0) - across)
				else
					-- particle holders sit inside the deck (not at the feet) and keep their authored aim
					clone.CFrame = clone.CFrame.Rotation
				end
			elseif clone:IsA("Trail") then
				clone.FaceCamera = true -- a deck-level ribbon vanishes edge-on without this
			end
		end
		clone.Parent = mount
		clones[clone.Name] = clone
	end
	for _, clone in clones do
		if clone:IsA("Trail") then
			clone.Attachment0 = clones.a :: Attachment
			clone.Attachment1 = clones.b :: Attachment
		end
	end
end

local function grant(player: Player, name: string)
	local d = DataService:GetData(player); if not d then return end
	d.Trails = d.Trails or {}
	if not table.find(d.Trails, name) then table.insert(d.Trails, name) end
	publish(player)
end

local function equip(player: Player, name: string)
	local d = DataService:GetData(player); if not d then return end
	d.Trail = name
	publish(player)
	apply(player)
	TrailService.Client.Equipped:Fire(player, name)
end

local function onBuy(player: Player, name: string)
	if typeof(name) ~= "string" then return end
	local entry = TrailConfig.Trails[name]
	local d = DataService:GetData(player)
	if not entry or not d then return end
	if owns(player, name) then return end
	if d.Wins < entry.Wins then
		TrailService.Client.Denied:Fire(player, "Not Enough Wins")
		return
	end
	DataService:SetWins(player, d.Wins - entry.Wins)
	grant(player, name)
	TrailService.Client.Bought:Fire(player, name)
	equip(player, name)
end

local function onEquip(player: Player, name: string)
	if typeof(name) ~= "string" then return end
	if not TrailConfig.Trails[name] or not owns(player, name) then return end
	equip(player, name)
end

local function onUnequip(player: Player)
	equip(player, "")
end

local function setup(player: Player)
	task.spawn(function()
		local d = DataService:WaitForData(player)
		if not d then return end
		d.Trails = d.Trails or {}
		if d.Trail ~= "" and not table.find(d.Trails, d.Trail) then d.Trail = "" end
		if PassService:IsVIP(player) and GamepassConfig.VIP.Trail ~= "" then
			grant(player, GamepassConfig.VIP.Trail)
		end
		for name, entry in TrailConfig.Trails do
			if entry.GamepassId > 0 and not owns(player, name) and PassService:OwnsPass(player, entry.GamepassId) then
				grant(player, name)
			end
		end
		publish(player)
		apply(player)

		-- walkspeed grows with level, the equipped board and bought Speed upgrades
		local dataFolder = player:WaitForChild("data", 10)
		local levelValue = dataFolder and dataFolder:WaitForChild("Level", 10)
		if levelValue and levelValue:IsA("NumberValue") then
			levelValue.Changed:Connect(function()
				apply(player)
			end)
		end
		player:GetAttributeChangedSignal("Board"):Connect(function()
			apply(player)
		end)
		player:GetAttributeChangedSignal("SpeedUpgrade"):Connect(function()
			apply(player)
		end)
	end)
	local function watchBoard(character: Model)
		-- the board spawns after the character (and re-spawns on equip): remount the FX each time
		character.ChildAdded:Connect(function(child)
			if child.Name == "Skateboard" then task.defer(apply, player) end
		end)
	end
	player.CharacterAdded:Connect(function(character)
		watchBoard(character)
		task.defer(apply, player)
	end)
	if player.Character then watchBoard(player.Character) end
end

function TrailService:KnitInit()
	self.Client.Buy:Connect(onBuy)
	self.Client.Equip:Connect(onEquip)
	self.Client.Unequip:Connect(onUnequip)

	self.Client.SpeedCap:Connect(function(player, cap)
		if typeof(cap) == "number" and cap == cap then
			speedCaps[player] = math.clamp(math.floor(cap + 0.5), 1, 500)
		else
			speedCaps[player] = nil
		end
		apply(player)
	end)
	Players.PlayerRemoving:Connect(function(p) speedCaps[p] = nil end)

	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end

	-- friends in the same server speed you up: 1 friend = 1.5x, 2 = 1.75x, 3+ = 2x
	local FRIEND_MULTS = { 1.5, 1.75, 2 }
	local function refreshFriendBoosts()
		for _, p in Players:GetPlayers() do
			task.spawn(function()
				local n = 0
				for _, other in Players:GetPlayers() do
					if other ~= p and other.Parent then
						local ok, isFriend = pcall(p.IsFriendsWith, p, other.UserId)
						if ok and isFriend then n += 1 end
					end
				end
				local mult = if n == 0 then 1 else FRIEND_MULTS[math.min(n, #FRIEND_MULTS)]
				if p.Parent and p:GetAttribute("FriendBoost") ~= mult then
					p:SetAttribute("FriendBoost", mult)
					apply(p)
				end
			end)
		end
	end
	Players.PlayerAdded:Connect(refreshFriendBoosts)
	Players.PlayerRemoving:Connect(function()
		task.delay(0.5, refreshFriendBoosts) -- after the leaver is actually gone
	end)
	refreshFriendBoosts()

	-- VIP bought mid-session grants its trail immediately
	table.insert(PassService.Changed, function(player)
		if PassService:IsVIP(player) and not owns(player, GamepassConfig.VIP.Trail) then
			grant(player, GamepassConfig.VIP.Trail)
		end
		apply(player)
	end)

	-- Starter Pack
	PassService.Products[GamepassConfig.StarterPackProduct.Id] = function(player)
		local d = DataService:GetData(player)
		if not d then return false end
		if d.StarterPack then return true end -- already owned settle the receipt
		d.StarterPack = true
		if not owns(player, "Green") then grant(player, "Green") end
		PassService:Refresh(player) -- republishes BonusJumps/StarterPackOwned; the Changed hook re-applies walkspeed
		return true
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		for name, entry in TrailConfig.Trails do
			if entry.GamepassId == passId then
				if not owns(player, name) then grant(player, name) end
				TrailService.Client.Bought:Fire(player, name)
				equip(player, name)
				return
			end
		end
	end)
end

return TrailService