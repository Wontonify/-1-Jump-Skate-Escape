--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local GamepassConfig = require(RS:WaitForChild("Shared"):WaitForChild("GamepassConfig"))
local Worlds = require(RS:WaitForChild("Shared"):WaitForChild("Worlds"))

local player = Players.LocalPlayer

local PassController = Knit.CreateController({
	Name = "PassController",
})

local function entryFor(passes: { GamepassConfig.Pass }, mult: number): GamepassConfig.Pass?
	for _, pass in passes do
		if pass.Mult == mult then return pass end
	end
	return nil
end

-- swaps just the number in the authored label text
local function setNumber(labelObj: Instance?, n: number)
	if labelObj and labelObj:IsA("TextLabel") then
		labelObj.Text = (labelObj.Text:gsub("%d+", tostring(n), 1))
	end
end

local function wire(button: ImageButton, passes: { GamepassConfig.Pass }, attr: string)
	local function refresh()
		local mult = (player:GetAttribute(attr) :: number?) or 2
		local entry = entryFor(passes, mult)
		if not entry then -- 0 = whole ladder owned
			button.Visible = false
			return
		end
		button.Visible = true
		setNumber(button:FindFirstChild("Name"), entry.Mult)
		setNumber(button:FindFirstChild("Price"), entry.Price)
	end
	player:GetAttributeChangedSignal(attr):Connect(refresh)
	refresh()

	button.Activated:Connect(function()
		local entry = entryFor(passes, (player:GetAttribute(attr) :: number?) or 2)
		if entry then
			MarketplaceService:PromptGamePassPurchase(player, entry.Id)
		end
	end)
end

function PassController:KnitStart()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local right = gui:WaitForChild("RightFrame")
	wire(right:WaitForChild("DoubleWinsButton") :: ImageButton, GamepassConfig.Wins, "NextWinsPass")
	wire(right:WaitForChild("DoublePowerButton") :: ImageButton, GamepassConfig.XP, "NextXPPass")

	-- shop gamepass cards OWNED
	local shopScroll = gui:WaitForChild("MainFrames"):WaitForChild("ShopFrame")
		:WaitForChild("ShopBackground"):WaitForChild("ScrollingFrame")
	local function wireShopPass(cardName: string, id: number, price: number, ownedAttr: string, isProduct: boolean?)
		local card = shopScroll:WaitForChild(cardName)
		local button = card:WaitForChild("PurchaseButton") :: ImageButton
		local label = button:WaitForChild("Name", 10)
		-- rebuild from the authored text every refresh
		local baseText = if label and label:IsA("TextLabel") then label.Text else " %d"
		local function refresh()
			if not (label and label:IsA("TextLabel")) then return end
			label.Visible = true
			if player:GetAttribute(ownedAttr) then
				label.Text = "OWNED"
			elseif price > 0 then
				label.Text = (baseText:gsub("%d+", tostring(price), 1))
			else
				label.Text = baseText -- no config price
			end
		end
		-- prefer the live store price
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id,
				if isProduct then Enum.InfoType.Product else Enum.InfoType.GamePass)
			if ok and info and info.PriceInRobux then price = info.PriceInRobux end
			refresh()
		end)
		player:GetAttributeChangedSignal(ownedAttr):Connect(refresh)
		refresh()
		button.Activated:Connect(function()
			if player:GetAttribute(ownedAttr) then return end
			if isProduct then
				MarketplaceService:PromptProductPurchase(player, id)
			else
				MarketplaceService:PromptGamePassPurchase(player, id)
			end
		end)
	end
	wireShopPass("DoubleSpeed", GamepassConfig.Speed.Id, GamepassConfig.Speed.Price, "SpeedOwned")
	wireShopPass("DoubleJump", GamepassConfig.DoubleJumps.Id, GamepassConfig.DoubleJumps.Price, "DoubleJumps")
	wireShopPass("PermanentRevive", GamepassConfig.PermanentRevive.Id, 0, "ReviveOwned")
	wireShopPass("VIP", GamepassConfig.VIP.Id, 0, "VIPOwned")
	wireShopPass("StarterPack", GamepassConfig.StarterPackProduct.Id, GamepassConfig.StarterPackProduct.Price, "StarterPackOwned", true)

	-- the VIP card spells out everything the pass includes
	local vip = GamepassConfig.VIP
	local vipDesc = shopScroll:WaitForChild("VIP"):WaitForChild("Description")
	if vipDesc:IsA("TextLabel") then
		vipDesc.Text = vip.WinsMult .. "x Wins, " .. vip.XPMult .. "x XP, +"
			.. vip.BonusJumps .. " Jumps, " .. vip.Trail .. " Trail"
	end

	-- +XP quick-buys grant XP directly
	local xpFrame = gui:WaitForChild("BottomFrame"):WaitForChild("XPButtonsFrame")
	for name, product in GamepassConfig.XPProducts do
		local button = xpFrame:WaitForChild(name)
		if button:IsA("GuiButton") then
			button.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end)
		end
	end

	-- the level bar's green + buys one level outright
	local moreButton = gui:WaitForChild("BottomFrame"):WaitForChild("BarBackground"):WaitForChild("MoreButton")
	if moreButton:IsA("GuiButton") then
		moreButton.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(player, GamepassConfig.LevelProduct.Id)
		end)
	end

	-- the +500K XP rainbow scrolls one way forever: the colour sequence itself is rebuilt each frame from a cyclic palette
	task.spawn(function()
		local card = xpFrame:WaitForChild("Plus500KXP")
		local gradients = {}
		for _, d in card:GetDescendants() do
			if d:IsA("UIGradient") then table.insert(gradients, d) end
		end
		if #gradients == 0 then return end
		-- authored rainbow colours spread evenly around the cycle (wrap segment included), so every band scrolls past at the same width
		local cycle: { { t: number, c: Color3 } } = {}
		local keys = gradients[1].Color.Keypoints
		for i, k in keys do
			table.insert(cycle, { t = (i - 1) / #keys, c = k.Value })
		end
		local n = #cycle
		local function sample(t: number): Color3 -- colour of the cyclic palette at t
			for i = 1, n do
				local a, b = cycle[i], cycle[i % n + 1]
				local ta = a.t
				local tb = if i == n then b.t + 1 else b.t
				local tt = if t < ta then t + 1 else t
				if tt >= ta and tt <= tb then
					return a.c:Lerp(b.c, (tt - ta) / (tb - ta))
				end
			end
			return cycle[1].c
		end
		local PERIOD = 3
		for _, g in gradients do g.Offset = Vector2.zero end
		RunService.RenderStepped:Connect(function()
			local s = (os.clock() / PERIOD) % 1
			local edge = sample((0 - s) % 1) -- same colour at both ends
			local kps = { ColorSequenceKeypoint.new(0, edge) }
			for _, k in cycle do
				local u = (k.t + s) % 1
				if u > 0.002 and u < 0.998 then
					table.insert(kps, ColorSequenceKeypoint.new(u, k.c))
				end
			end
			table.insert(kps, ColorSequenceKeypoint.new(1, edge))
			table.sort(kps, function(a, b) return a.Time < b.Time end)
			local seq = ColorSequence.new(kps)
			for _, g in gradients do g.Color = seq end
		end)
	end)

	-- stepping on a VIP stand chimes alongside the server's purchase prompt (one per world;
	-- streaming hands stand parts back later, so late arrivals wire through DescendantAdded)
	local chime = Instance.new("Sound")
	chime.SoundId = "rbxassetid://104579897781033"
	chime.Volume = 0.7
	chime.Parent = SoundService
	local lastPlay = -math.huge
	local function wireVIPPart(part: Instance)
		if not part:IsA("BasePart") then return end
		part.Touched:Connect(function(hit)
			if not hit:IsDescendantOf(player.Character or player) then return end
			if os.clock() - lastPlay < 3 then return end
			lastPlay = os.clock()
			chime.TimePosition = 0
			chime:Play()
		end)
	end
	for _, worldFolder in Worlds.WaitList() do
		task.spawn(function()
			local map = worldFolder:WaitForChild("Map", 10)
			local stand = map and map:WaitForChild("VIP", 10)
			if not stand then return end
			for _, part in stand:GetDescendants() do
				wireVIPPart(part)
			end
			stand.DescendantAdded:Connect(wireVIPPart)
		end)
	end
end

return PassController