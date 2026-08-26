--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local UtilController = require(script.Parent.UtilController)
local UIController = require(script.Parent.UIController)
local Upgrades = require(RS:WaitForChild("Shared"):WaitForChild("Upgrades"))
local Worlds = require(RS:WaitForChild("Shared"):WaitForChild("Worlds"))

local player = Players.LocalPlayer

local UpgradeController = Knit.CreateController({
	Name = "UpgradeController",
})

local GREEN = Color3.fromRGB(90, 235, 110)
local RED = Color3.fromRGB(255, 80, 80)

local function setText(inst: Instance?, text: string)
	if inst and inst:IsA("TextLabel") then inst.Text = text end
end

function UpgradeController:KnitStart()
	local upgradeService = Knit.GetService("UpgradeService")
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local mainFrames = gui:WaitForChild("MainFrames")
	local frame = mainFrames:WaitForChild("UpgradesFrame")
	local bg = frame:WaitForChild("UpgradesBackground")
	local scroll = bg:WaitForChild("ScrollingFrame")
	local rows = { Speed = scroll:WaitForChild("Speed"), Jump = scroll:WaitForChild("Jump") }
	frame.Visible = false

	local function open()
		if UIController.OpenFrame then UIController.OpenFrame(frame) else frame.Visible = true end
	end
	local function close()
		if UIController.CloseFrame then UIController.CloseFrame(frame) else frame.Visible = false end
	end
	local closeBtn = bg:FindFirstChild("CloseButton")
	if closeBtn and closeBtn:IsA("GuiButton") then closeBtn.Activated:Connect(close) end

	for key, row in rows do
		local cash = row:FindFirstChild("CashButton")
		if cash and cash:IsA("GuiButton") then
			cash.Active = true
			cash.Activated:Connect(function() upgradeService.Buy:Fire(key) end)
		end
	end

	-- per-level Robux skips price and product follow the next level (id 0 = hidden)
	local robuxIds = { Speed = 0, Jump = 0 }
	for key, row in rows do
		local btn = row:FindFirstChild("RobuxButton")
		if btn and btn:IsA("GuiButton") then
			btn.Active = true
			btn.Activated:Connect(function()
				if robuxIds[key] > 0 then
					MarketplaceService:PromptProductPurchase(player, robuxIds[key])
				end
			end)
		end
	end

	local livePrices: { [number]: number } = {} -- real Robux prices fetched from the products
	local function refreshRow(key: string, row: Instance, level: number, max: number, prev: string, next: string)
		local maxed = level >= max
		setText(row:FindFirstChild("Previous"), prev)
		setText(row:FindFirstChild("Next"), next)
		local costs = if key == "Speed" then Upgrades.SpeedCosts else Upgrades.JumpCosts
		local cash = row:FindFirstChild("CashButton")
		if cash and cash:IsA("GuiButton") then
			cash.Visible = not maxed
			setText(cash:FindFirstChild("Price"), UtilController.Short(costs[level + 1] or 0))
		end
		local maxText = row:FindFirstChild("MaxText")
		if maxText and maxText:IsA("TextLabel") then maxText.Visible = maxed end
		local products = if key == "Speed" then Upgrades.SpeedProducts else Upgrades.JumpProducts
		local prices = if key == "Speed" then Upgrades.SpeedRobux else Upgrades.JumpRobux
		local id = if maxed then 0 else (products[level + 1] or 0)
		robuxIds[key] = id
		local robux = row:FindFirstChild("RobuxButton")
		if robux and robux:IsA("GuiButton") then
			robux.Visible = id > 0
			local rPrice = livePrices[id] or prices[level + 1] or 0
			if rPrice > 0 then
				local priceLabel = robux:FindFirstChild("Price")
				if priceLabel and priceLabel:IsA("TextLabel") then
					priceLabel.Text = (priceLabel.Text:gsub("%d+", tostring(rPrice)))
				end
			end
		end
	end

	local function refresh()
		-- flat +1 Speed per level
		local speedLv = (player:GetAttribute("SpeedUpgrade") :: number?) or 0
		local nextSpeed = math.min(speedLv + 1, Upgrades.SpeedMax)
		refreshRow("Speed", rows.Speed, speedLv, Upgrades.SpeedMax,
			"+" .. speedLv, "+" .. nextSpeed)
		local jumpLv = (player:GetAttribute("ExtraJumps") :: number?) or 0
		refreshRow("Jump", rows.Jump, jumpLv, Upgrades.JumpMax,
			"+" .. jumpLv, "+" .. math.min(jumpLv + 1, Upgrades.JumpMax))
	end
	player:GetAttributeChangedSignal("SpeedUpgrade"):Connect(refresh)
	player:GetAttributeChangedSignal("ExtraJumps"):Connect(refresh)
	refresh()

	-- one shared product can back many levels
	task.spawn(function()
		local seen: { [number]: boolean } = {}
		for _, list in { Upgrades.SpeedProducts, Upgrades.JumpProducts } do
			for _, id in list do
				if id > 0 and not seen[id] then
					seen[id] = true
					local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.Product)
					if ok and info and info.PriceInRobux then
						livePrices[id] = info.PriceInRobux
					end
				end
			end
		end
		refresh()
	end)

	upgradeService.Result:Connect(function(ok: boolean, msg: string)
		if ok then
			if UIController.Notify then UIController.Notify(msg, GREEN) end
		elseif UIController.ShowDeny then -- deny path adds the error sound
			UIController.ShowDeny(msg)
		end
	end)

	-- walk-up open on either world's Upgrade stand pad walking away closes it again
	task.spawn(function()
		local wasNear = false
		while true do
			task.wait(0.3)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local near = false
			if hrp and hrp:IsA("BasePart") then
				for _, worldFolder in Worlds.List() do
					local map = worldFolder:FindFirstChild("Map")
					local stand = map and map:FindFirstChild("Upgrade")
					local pad = stand and stand:FindFirstChild("Pad")
					if not (pad and pad:IsA("Model") and pad:FindFirstChildWhichIsA("BasePart", true)) then continue end
					local cf, size = (pad :: Model):GetBoundingBox()
					local p = cf:PointToObjectSpace(hrp.Position)
					if math.abs(p.X) <= size.X / 2 + 2 and math.abs(p.Z) <= size.Z / 2 + 2 and math.abs(p.Y) <= 8 then
						near = true
						break
					end
				end
			end
			if near and not wasNear then
				open()
			elseif not near and wasNear and frame.Visible then
				close()
			end
			wasNear = near
			player:SetAttribute("OnUpgradePad", near)
		end
	end)
end

return UpgradeController 