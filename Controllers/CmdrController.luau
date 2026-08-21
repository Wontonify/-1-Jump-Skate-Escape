--!strict
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)

local CmdrController = Knit.CreateController({
	Name = "CmdrController",
})

function CmdrController:KnitStart()
	task.spawn(function()
		local client = RS:WaitForChild("CmdrClient", 30)
		if not client then return end
		local Cmdr = require(client :: ModuleScript) :: any
		Cmdr:SetActivationKeys({ Enum.KeyCode.F2 })
	end)
end

return CmdrController