--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local GamepassConfig = require(RS.Shared.GamepassConfig)

local PassService = Knit.CreateService({
	Name = "PassService",
	Changed = {} :: { (Player) -> () }, -- other services register refreshers here
	Products = {} :: { [number]: (Player) -> boolean }, -- dev product handlers by id return true to grant

	Client = {},
})

local owned: { [Player]: { [number]: boolean } } = {}

local function ownsPass(player: Player, id: number): boolean
	if id == 0 then return false end
	local cache = owned[player]
	if not cache then return false end
	if cache[id] == nil then
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		cache[id] = ok and result or false
	end
	return cache[id]
end

local function bestMult(player: Player, passes: { GamepassConfig.Pass }): number
	local best = 1
	for _, pass in passes do
		if pass.Mult > best and ownsPass(player, pass.Id) then
			best = pass.Mult
		end
	end
	return best
end

function PassService:OwnsPass(player: Player, id: number): boolean
	return ownsPass(player, id)
end

function PassService:IsVIP(player: Player): boolean
	return ownsPass(player, GamepassConfig.VIP.Id)
end

function PassService:SpeedMultiplier(player: Player): number
	return if ownsPass(player, GamepassConfig.Speed.Id) then GamepassConfig.Speed.Mult else 1
end

function PassService:WinsMultiplier(player: Player): number
	local mult = bestMult(player, GamepassConfig.Wins)
	if self:IsVIP(player) then mult *= GamepassConfig.VIP.WinsMult end
	return mult
end

function PassService:XPMultiplier(player: Player): number
	local mult = bestMult(player, GamepassConfig.XP)
	if self:IsVIP(player) then mult *= GamepassConfig.VIP.XPMult end
	return mult
end

-- mult of the first unowned pass in the ladder (0 = all owned)
local function nextMult(player: Player, passes: { GamepassConfig.Pass }): number
	for _, pass in passes do
		if not ownsPass(player, pass.Id) then return pass.Mult end
	end
	return 0
end

function PassService:Refresh(player: Player)
	local data = DataService:GetData(player)
	local vipJumps = self:IsVIP(player) and GamepassConfig.VIP.BonusJumps or 0
	local packJumps = if data and data.StarterPack then 1 else 0
	player:SetAttribute("BonusJumps", vipJumps + packJumps + (data and data.ExtraJumps or 0))
	player:SetAttribute("VIPOwned", self:IsVIP(player))
	player:SetAttribute("StarterPackOwned", (data and data.StarterPack) == true)
	player:SetAttribute("SpeedOwned", self:SpeedMultiplier(player) > 1)
	player:SetAttribute("DoubleJumps", ownsPass(player, GamepassConfig.DoubleJumps.Id))
	player:SetAttribute("ReviveOwned", ownsPass(player, GamepassConfig.PermanentRevive.Id))
	player:SetAttribute("NextWinsPass", nextMult(player, GamepassConfig.Wins))
	player:SetAttribute("NextXPPass", nextMult(player, GamepassConfig.XP))
	for _, fn in self.Changed do
		task.spawn(fn, player)
	end
end

function PassService:KnitInit()
	local function setup(player: Player)
		owned[player] = {}
		task.spawn(function()
			DataService:WaitForData(player)
			PassService:Refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end
	Players.PlayerRemoving:Connect(function(p) owned[p] = nil end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and owned[player] then
			owned[player][passId] = true
			PassService:Refresh(player)
		end
	end)

	-- standing on the VIP stand prompts the pass
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 10)
		local stand = map and map:FindFirstChild("VIP")
		if not stand then return end
		local lastPrompt: { [Player]: number } = {}
		Players.PlayerRemoving:Connect(function(p) lastPrompt[p] = nil end)
		for _, part in stand:GetDescendants() do
			if not part:IsA("BasePart") then continue end
			part.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or PassService:IsVIP(player) then return end
				local now = os.clock()
				if now - (lastPrompt[player] or -math.huge) < 3 then return end
				lastPrompt[player] = now
				MarketplaceService:PromptGamePassPurchase(player, GamepassConfig.VIP.Id)
			end)
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local handler = PassService.Products[receipt.ProductId]
		if handler then
			local ok, granted = pcall(handler, player)
			if ok and granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return PassService