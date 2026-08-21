--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local TrailConfig = require(RS:WaitForChild("Shared"):WaitForChild("TrailConfig"))
local UtilController = require(script.Parent.UtilController)

local player = Players.LocalPlayer

local TrailController = Knit.CreateController({
	Name = "TrailController",
})

local function makeSound(id: number, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local equipSound = makeSound(104579897781033, 0.7)
local buySound = makeSound(120672563582350, 0.8)

local rows: { [string]: ImageLabel } = {}

local function label(holder: Instance, name: string): TextLabel
	return holder:FindFirstChild(name) :: TextLabel
end

local function refresh()
	local ownedList = string.split((player:GetAttribute("OwnedTrails") :: string?) or "", "|")
	local equipped = (player:GetAttribute("Trail") :: string?) or ""
	for name, row in rows do
		local owned = table.find(ownedList, name) ~= nil
		local entry = TrailConfig.Trails[name]
		local buttons = row:FindFirstChild("Buttons") :: Frame
		local winsButton = buttons:FindFirstChild("WinsButton") :: ImageButton
		local robuxButton = buttons:FindFirstChild("RobuxButton") :: ImageButton
		local equipButton = buttons:FindFirstChild("EquipButton") :: ImageButton
		local unequipButton = buttons:FindFirstChild("UnequipButton") :: ImageButton
		winsButton.Visible = not owned
		robuxButton.Visible = not owned and entry.GamepassId > 0
		equipButton.Visible = owned
		unequipButton.Visible = owned
		label(equipButton, "Text").Text = if equipped == name then "Equipped" else "Equip"
	end
end

function TrailController:KnitStart()
	local trailService = Knit.GetService("TrailService")
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local scrolling = hud:WaitForChild("MainFrames"):WaitForChild("TrailsFrame")
		:WaitForChild("TrailsBackground"):WaitForChild("Scrolling")
	local template = scrolling:WaitForChild("Template") :: ImageLabel
	template.Visible = false

	for i, name in TrailConfig.Order do
		local entry = TrailConfig.Trails[name]
		local row = template:Clone()
		row.Name = name
		row.LayoutOrder = i
		row.Visible = true
		label(row, "Name").Text = name .. " Trail"
		label(row, "SpeedBoost").Text = TrailConfig.FormatMultiplier(entry.Multiplier) .. " Trophies";
		(row:FindFirstChild("Image") :: ImageLabel).ImageColor3 = entry.Color
		local buttons = row:FindFirstChild("Buttons") :: Frame
		local winsButton = buttons:FindFirstChild("WinsButton") :: ImageButton
		local robuxButton = buttons:FindFirstChild("RobuxButton") :: ImageButton
		local equipButton = buttons:FindFirstChild("EquipButton") :: ImageButton
		local unequipButton = buttons:FindFirstChild("UnequipButton") :: ImageButton
		label(winsButton, "Text").Text = UtilController.Short(entry.Wins)
		label(robuxButton, "Text").Text = " " .. entry.Robux
		robuxButton.Visible = entry.GamepassId > 0
		winsButton.Activated:Connect(function()
			trailService.Buy:Fire(name)
		end)
		robuxButton.Activated:Connect(function()
			if entry.GamepassId > 0 then
				MarketplaceService:PromptGamePassPurchase(player, entry.GamepassId)
			end
		end)
		equipButton.Activated:Connect(function()
			if player:GetAttribute("Trail") ~= name then
				trailService.Equip:Fire(name)
			end
		end)
		unequipButton.Activated:Connect(function()
			if player:GetAttribute("Trail") == name then
				trailService.Unequip:Fire()
			end
		end)
		row.Parent = scrolling
		rows[name] = row
	end

	-- canvas hugs the rows exactly so you can't scroll past the last trail
	local layout = scrolling:FindFirstChildOfClass("UIListLayout")
	if layout then
		local function fitCanvas()
			scrolling.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
		end
		fitCanvas()
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitCanvas)
	end

	player:GetAttributeChangedSignal("Trail"):Connect(refresh)
	player:GetAttributeChangedSignal("OwnedTrails"):Connect(refresh)
	refresh()

	trailService.Bought:Connect(function()
		buySound.TimePosition = 0
		buySound:Play()
	end)
	trailService.Equipped:Connect(function(name: string)
		if name ~= "" then
			equipSound.TimePosition = 0
			equipSound:Play()
		end
	end)
end

return TrailController