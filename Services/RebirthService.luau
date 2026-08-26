--!strict
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local XPService = require(script.Parent.XPService)
local PassService = require(script.Parent.PassService)
local Rebirths = require(RS.Shared.Rebirths)
local GamepassConfig = require(RS.Shared.GamepassConfig)
local Worlds = require(RS.Shared.Worlds)

local RebirthService = Knit.CreateService({
	Name = "RebirthService",

	Client = {
		Request = Knit.CreateSignal(),
	},
})

-- increase max lvl resets current lvl progress and xp
-- force var for rbx purchase
function RebirthService:DoRebirth(player: Player, force: boolean?)
	local data = DataService:GetData(player)
	if not data then return end
	if not force and data.Level < Rebirths.MaxLevelFor(data.Rebirth) then return end

	DataService:AddRebirth(player, 1)
	DataService:SetLevel(player, 1)
	DataService:SetLevelProgress(player, 0)
	DataService:SetXP(player, 0)
	XPService:RefreshXPPerStep(player) -- +0.5x multi

	local char = player.Character
	if char then
		char:PivotTo(Worlds.SpawnCFrame(Worlds.PlayerWorld(player)))
	end
end

function RebirthService:KnitInit()
	self.Client.Request:Connect(function(player)
		RebirthService:DoRebirth(player)
	end)

	PassService.Products[GamepassConfig.SkipRebirthProduct.Id] = function(player)
		if not DataService:GetData(player) then return false end
		RebirthService:DoRebirth(player, true)
		return true
	end
end

return RebirthService
