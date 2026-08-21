--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local SkateboardService = require(script.Parent.SkateboardService)
local XPService = require(script.Parent.XPService)
local PassService = require(script.Parent.PassService)
local SkateboardConfig = require(RS.Shared.SkateboardConfig)

local ShopService = Knit.CreateService({
	Name = "ShopService",

	Client = {
		Bought = Knit.CreateSignal(),
		Equipped = Knit.CreateSignal(),
		Denied = Knit.CreateSignal(),
	},
})

local RED = Color3.fromRGB(238, 63, 63)
local BLUE = Color3.fromRGB(55, 119, 162)
local TOUCH_COOLDOWN = 0.8

local lastTouch: { [Player]: number } = {}

local function colorsMatch(a: Color3, b: Color3): boolean
	return (a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2 < 0.0004
end

-- raycast straight down from the display board to the two pedestal parts (red on top, blue below)
local function findPads(model: Model): (BasePart?, BasePart?)
	local cf = model:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model.Parent :: Instance }
	local origin = cf.Position
	local red: BasePart?, blue: BasePart? = nil, nil
	for _ = 1, 4 do
		local hit = workspace:Raycast(origin, Vector3.new(0, -8, 0), params)
		if not hit then break end
		local part = hit.Instance
		if part:IsA("BasePart") then
			if colorsMatch(part.Color, RED) then red = part
			elseif colorsMatch(part.Color, BLUE) then blue = part end
		end
		if red and blue then break end
		params:AddToFilter(part)
		origin = hit.Position - Vector3.new(0, 0.05, 0)
	end
	return red, blue
end

-- wins boards unlock strictly in config order rbx boards sit outside the chain
local function previousWinsBoard(name: string)
	local prev = nil
	for _, entry in SkateboardConfig.Boards do
		if entry.Wins ~= nil then
			if entry.Name == name then return prev end
			prev = entry
		end
	end
	return nil
end

local function equipBoard(player: Player, entry)
	DataService:SetBoard(player, entry.Name)
	SkateboardService:RefreshBoard(player)
	XPService:RefreshXPPerStep(player)
end

local function onShopTouched(entry, hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player and character then
		player = character.Parent and Players:GetPlayerFromCharacter(character.Parent)
	end
	if not player then return end

	local data = DataService:GetData(player)
	if not data then return end
	if data.Board == entry.Name then return end

	local now = os.clock()
	if now - (lastTouch[player] or 0) < TOUCH_COOLDOWN then return end
	lastTouch[player] = now

	if DataService:OwnsBoard(player, entry.Name) then
		equipBoard(player, entry)
		ShopService.Client.Equipped:Fire(player, entry.Name)
		return
	end
	if entry.GamepassId then
		if PassService:OwnsPass(player, entry.GamepassId) then
			DataService:UnlockBoard(player, entry.Name)
			equipBoard(player, entry)
			ShopService.Client.Bought:Fire(player, entry.Name)
		else
			MarketplaceService:PromptGamePassPurchase(player, entry.GamepassId)
		end
		return
	end
	if entry.Robux then return end -- remaining rbx boards buy through dev products
	local price = entry.Wins or 0
	if data.Wins < price then
		ShopService.Client.Denied:Fire(player, "Not Enough Wins")
		return
	end
	local prev = previousWinsBoard(entry.Name)
	if prev and not DataService:OwnsBoard(player, prev.Name) then
		ShopService.Client.Denied:Fire(player, "Unlock Previous Skateboard First")
		return
	end
	DataService:SetWins(player, data.Wins - price)
	DataService:UnlockBoard(player, entry.Name)
	equipBoard(player, entry) -- first purchase auto-equips
	ShopService.Client.Bought:Fire(player, entry.Name)
end

function ShopService:KnitInit()
	local shop = workspace:FindFirstChild("Shop")
	if not shop then
		warn("[ShopService] workspace.Shop is missing")
		return
	end

	for _, model in shop:GetChildren() do
		if not model:IsA("Model") then continue end
		local entry = SkateboardConfig.ByAsset(model.Name)
		if not entry then
			warn("[ShopService] no config entry for shop model " .. model.Name)
			continue
		end

		local red, blue = findPads(model)
		if red then
			-- center the display board over the red pad
			local pivot = model:GetPivot()
			model:PivotTo(CFrame.new(red.Position.X, pivot.Position.Y, red.Position.Z) * (pivot - pivot.Position))
		else
			warn("[ShopService] no red pad under " .. model.Name)
		end

		local function wire(part: BasePart)
			part.Touched:Connect(function(hit) onShopTouched(entry, hit) end)
		end
		if red then wire(red) end
		if blue then wire(blue) end
		-- display boards are walk-through
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				wire(d)
			end
		end
	end

	-- buying a board pass from the stand's prompt grants the board the moment the dialog closes
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then return end
		for _, entry in SkateboardConfig.Boards do
			if entry.GamepassId == passId and not DataService:OwnsBoard(player, entry.Name) then
				DataService:UnlockBoard(player, entry.Name)
				equipBoard(player, entry)
				ShopService.Client.Bought:Fire(player, entry.Name)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p) lastTouch[p] = nil end)
end

return ShopService