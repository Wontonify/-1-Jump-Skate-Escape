--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)

local player = Players.LocalPlayer

local WinsController = Knit.CreateController({
	Name = "WinsController",
})

local COOLDOWN = 1.5
local lastTouch = 0

function WinsController:KnitStart()
	local winsService = Knit.GetService("WinsService")
	local folder = workspace:WaitForChild("WinsPads")

	local wired = setmetatable({} :: { [Instance]: boolean }, { __mode = "k" })
	local function wire(pad: Instance)
		if not pad:IsA("BasePart") or wired[pad] then return end
		wired[pad] = true
		pad.Touched:Connect(function(hit)
			if os.clock() - lastTouch < COOLDOWN then return end
			local character = player.Character
			if not character or not hit:IsDescendantOf(character) then return end
			lastTouch = os.clock()
			winsService.Touch:Fire(pad.Name)
		end)
	end
	for _, pad in folder:GetChildren() do
		wire(pad)
	end
	folder.ChildAdded:Connect(wire)
end

return WinsController