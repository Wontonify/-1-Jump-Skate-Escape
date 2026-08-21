--!strict
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)

local CmdrService = Knit.CreateService({
	Name = "CmdrService",
	Client = {},
})

function CmdrService:KnitStart()
	local package = RS.Packages.Cmdr

	local adminCommands = package.BuiltInCommands.Admin
	local Cmdr = require(package) :: any
	Cmdr:RegisterHooksIn(package.Hooks)
	Cmdr:RegisterCommandsIn(adminCommands)
	self.Cmdr = Cmdr
end

return CmdrService



