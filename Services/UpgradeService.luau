--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local XPService = require(script.Parent.XPService)
local BadgeService = require(script.Parent.BadgeService)
local Upgrades = require(RS.Shared.Upgrades)
local GamepassConfig = require(RS.Shared.GamepassConfig)

local UpgradeService = Knit.CreateService({
	Name = "UpgradeService",

	Client = {
		Buy = Knit.CreateSignal(),    -- client asks: "Speed" | "Jump"
		Result = Knit.CreateSignal(), -- (ok, message) purchase feedback
	},
})

local function publish(player: Player)
	local d = DataService:GetData(player)
	if not d then return end
	player:SetAttribute("SpeedUpgrade", d.SpeedUpgrade or 0)
	player:SetAttribute("ExtraJumps", d.ExtraJumps or 0)
end

function UpgradeService:BuySpeed(player: Player)
	local d = DataService:GetData(player)
	if not d then return end
	local level = d.SpeedUpgrade or 0
	if level >= Upgrades.SpeedMax then
		self.Client.Result:Fire(player, false, "Speed is maxed!")
		return
	end
	local cost = Upgrades.SpeedCost(level) :: number
	if d.Wins < cost then
		self.Client.Result:Fire(player, false, "Need " .. cost .. " Wins!")
		return
	end
	DataService:AddWins(player, -cost)
	DataService:SetSpeedUpgrade(player, level + 1)
	publish(player) -- TrailService watches the attribute and re-applies walkspeed
	BadgeService:Award(player, BadgeService.Ids.PurchaseUpgrade)
	self.Client.Result:Fire(player, true, "+" .. Upgrades.SpeedPerLevel .. " Speed!")
end

function UpgradeService:BuyJump(player: Player)
	local d = DataService:GetData(player)
	if not d then return end
	local level = d.ExtraJumps or 0
	if level >= Upgrades.JumpMax then
		self.Client.Result:Fire(player, false, "Jumps are maxed!")
		return
	end
	local cost = Upgrades.JumpCost(level) :: number
	if d.Wins < cost then
		self.Client.Result:Fire(player, false, "Need " .. cost .. " Wins!")
		return
	end
	DataService:AddWins(player, -cost)
	DataService:AddExtraJumps(player, 1)
	PassService:Refresh(player) -- republishes BonusJumps so the pool grows live
	publish(player)
	BadgeService:Award(player, BadgeService.Ids.PurchaseUpgrade)
	self.Client.Result:Fire(player, true, "+1 Jump!")
end

function UpgradeService:KnitInit()
	self.Client.Buy:Connect(function(player, key)
		if key == "Speed" then
			self:BuySpeed(player)
		elseif key == "Jump" then
			self:BuyJump(player)
		end
	end)

	-- the Robux +1 Jump product lands through PassService:Refresh; republish so the row moves
	table.insert(PassService.Changed, publish)

	-- per-level Robux skip products (ids live in Upgrades.*Products; 0 = not created yet)
	local function registerSkips(products: { number }, skip: (Player) -> boolean)
		for _, id in products do
			if id > 0 then PassService.Products[id] = skip end
		end
	end
	registerSkips(Upgrades.SpeedProducts, function(player)
		local d = DataService:GetData(player)
		if not d or (d.SpeedUpgrade or 0) >= Upgrades.SpeedMax then return false end
		DataService:SetSpeedUpgrade(player, (d.SpeedUpgrade or 0) + 1)
		publish(player)
		BadgeService:Award(player, BadgeService.Ids.PurchaseUpgrade)
		return true
	end)
	registerSkips(Upgrades.JumpProducts, function(player)
		local d = DataService:GetData(player)
		if not d or (d.ExtraJumps or 0) >= Upgrades.JumpMax then return false end
		DataService:AddExtraJumps(player, 1)
		PassService:Refresh(player)
		publish(player)
		BadgeService:Award(player, BadgeService.Ids.PurchaseUpgrade)
		return true
	end)

	-- +XP quick-buy products pay out XP directly; the level follows from it
	for _, product in GamepassConfig.XPProducts do
		PassService.Products[product.Id] = function(player)
			if not DataService:GetData(player) then return false end
			XPService:GrantXP(player, product.Amount)
			return true
		end
	end

	local function setup(player: Player)
		task.spawn(function()
			if DataService:WaitForData(player) then publish(player) end
		end)
	end
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do setup(p) end
end

return UpgradeService

