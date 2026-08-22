--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local SkateboardConfig = require(RS:WaitForChild("Shared"):WaitForChild("SkateboardConfig"))
local UtilController = require(script.Parent.UtilController)

local player = Players.LocalPlayer

local ShopController = Knit.CreateController({
	Name = "ShopController",
})

local billboards: { { gui: BillboardGui, price: TextLabel?, xp: TextLabel, entry: any } } = {}

-- rewrites the label when wrong, and when the engine laid out zero glyphs for a visible label
local function assertText(label: TextLabel, text: string)
	if label.Text ~= text
		or (text ~= "" and label.TextBounds.X == 0 and label.AbsoluteSize.Y >= 1) then
		label.Text = ""
		label.Text = text
	end
end

local function makeSound(id: number, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local equipSound = makeSound(104579897781033, 0.7)
local buySound = makeSound(120672563582350, 0.8)

local PAD_RED = Color3.fromRGB(238, 63, 63)
local PAD_GREEN = Color3.fromRGB(63, 238, 63)
local PAD_SIZE = Vector3.new(5, 0.5, 5)
local greenPad: BasePart? = nil

-- the 5x0.5x5 pedestal top directly under a display board
local function findPadUnder(model: Model): BasePart?
	local cf = model:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model.Parent :: Instance }
	local origin = cf.Position
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
		if not hit then return nil end
		local part = hit.Instance
		if part:IsA("BasePart") and (part.Size - PAD_SIZE).Magnitude < 0.1 then return part end
		params:AddToFilter(part)
		origin = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return nil
end

-- the equipped stand's pedestal shows green for this player (local-only colour)
local function updatePadColor(shop: Instance)
	local entry = SkateboardConfig.ByName(player:GetAttribute("Board"))
	local model = entry and shop:FindFirstChild(entry.Asset)
	local pad = (model and model:IsA("Model")) and findPadUnder(model) or nil
	if greenPad ~= pad then
		if greenPad and greenPad.Parent then greenPad.Color = PAD_RED end
		greenPad = pad
	end
	if greenPad then greenPad.Color = PAD_GREEN end -- re-assert
end

local function priceText(entry): string
	if player:GetAttribute("Board") == entry.Name then return "(Equipped)" end
	local owned = string.split((player:GetAttribute("OwnedBoards") :: string?) or "", "|")
	if table.find(owned, entry.Name) then return "(Owned)" end
	if entry.Robux then return "R$ " .. entry.Robux end
	return "🏆 " .. UtilController.Short(entry.Wins) .. " Wins"
end

local function refreshAll()
	for _, b in billboards do
		if b.price then assertText(b.price, priceText(b.entry)) end
		assertText(b.xp, "+" .. (b.entry.XP or 0) .. " XP")
	end
end

function ShopController:KnitStart()
	local template = RS:WaitForChild("Assets"):WaitForChild("UI"):WaitForChild("Shop")
	local groupTemplate = RS.Assets.UI:WaitForChild("Group Reward")
	local shop = workspace:WaitForChild("Shop")
	-- a plain Folder gets wiped from PlayerGui on respawn
	local holder = Instance.new("ScreenGui")
	holder.Name = "ShopBillboards"
	holder.ResetOnSpawn = false
	holder.Parent = player:WaitForChild("PlayerGui")

	for _, entry in SkateboardConfig.Boards do
		-- the group board keeps its own authored billboard, which has no price line
		local gui = (if entry.Group then groupTemplate else template):Clone() :: BillboardGui
		gui.Name = entry.Asset
		local xpLabel = gui:WaitForChild("Background"):WaitForChild("PowerLoader") :: TextLabel
		local price = if entry.Group then nil else gui:WaitForChild("PriceLoader") :: TextLabel
		xpLabel.Text = "+" .. (entry.XP or 0) .. " XP"
		-- adorn right away when the stand is already streamed in
		local model = shop:FindFirstChild(entry.Asset)
		local part = model and model:FindFirstChild("Board")
		if part and part:IsA("BasePart") then gui.Adornee = part end
		gui.Parent = holder
		table.insert(billboards, { gui = gui, price = price, xp = xpLabel, entry = entry })
	end
	refreshAll()

	local shopService = Knit.GetService("ShopService")
	shopService.Equipped:Connect(function()
		equipSound.TimePosition = 0
		equipSound:Play()
	end)
	shopService.Bought:Connect(function()
		buySound.TimePosition = 0
		buySound:Play()
	end)

	-- stepping onto a Robux board's stand chimes streaming swaps the stand parts in and out, so the slow loop below re-wires them
	local lastStandChime = -math.huge
	-- streaming destroys and recreates the stand parts, dead ones must not pile up
	local wiredStandParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function wireRobuxPart(part: BasePart, entry)
		if wiredStandParts[part] then return end
		wiredStandParts[part] = true
		part.Touched:Connect(function(hit)
			local char = player.Character
			if not char or not hit:IsDescendantOf(char) then return end
			local owned = string.split((player:GetAttribute("OwnedBoards") :: string?) or "", "|")
			if table.find(owned, entry.Name) then return end
			if os.clock() - lastStandChime < 2 then return end
			lastStandChime = os.clock()
			equipSound.TimePosition = 0
			equipSound:Play()
		end)
	end
	local function wireRobuxStands()
		for _, entry in SkateboardConfig.Boards do
			if not entry.Robux then continue end
			local model = shop:FindFirstChild(entry.Asset)
			if not (model and model:IsA("Model")) then continue end
			local pad = findPadUnder(model)
			if pad then wireRobuxPart(pad, entry) end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then wireRobuxPart(d, entry) end
			end
		end
	end
	wireRobuxStands()

	player:GetAttributeChangedSignal("Board"):Connect(function()
		refreshAll()
		updatePadColor(shop)
	end)
	player:GetAttributeChangedSignal("OwnedBoards"):Connect(refreshAll)
	updatePadColor(shop)

	-- display boards float a touch smaller, hovering up-down and slowly spinning (local-only)
	-- streaming hands back fresh authored-size instances, so shrink + rebase per instance)
	local displays: { [Model]: Vector3 } = {}
	local spun = 0
	RunService.Heartbeat:Connect(function(dt)
		spun += dt
		local bob = math.sin(spun * 2.5) * 0.35
		local turn = CFrame.Angles(0, spun * 0.8, 0)
		for _, entry in SkateboardConfig.Boards do
			local model = shop:FindFirstChild(entry.Asset)
			if not (model and model:IsA("Model") and model:FindFirstChild("Board")) then continue end
			local base = displays[model]
			if not base then
				model:ScaleTo(model:GetScale() * 0.9)
				base = model:GetPivot().Position -- position only every board shares one world orientation
				displays[model] = base
			end
			model:PivotTo(CFrame.new(base + Vector3.new(0, 0.6 + bob, 0)) * turn)
		end
	end)

	-- StreamingEnabled replaces the display parts, so re-point adornees on a slow loop instead of chasing events
	task.spawn(function()
		while true do
			for _, b in billboards do
				local model = shop:FindFirstChild(b.entry.Asset)
				local part = model and model:FindFirstChild("Board")
				local adornee = (part and part:IsA("BasePart")) and part or nil
				if b.gui.Adornee ~= adornee then
					b.gui.Adornee = adornee
					-- text laid out while unadorned can stay blank; rewrite once attached
					if adornee then
						local xpText = b.xp.Text
						b.xp.Text = ""
						b.xp.Text = xpText
						local price = b.price
						if price then
							local priceValue = price.Text
							price.Text = ""
							price.Text = priceValue
						end
					end
				end
			end
			refreshAll()
			for model in displays do
				if not model.Parent then displays[model] = nil end
			end
			updatePadColor(shop)
			wireRobuxStands()
			task.wait(1)
		end
	end)
end

return ShopController