--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local PassService = require(script.Parent.PassService)
local TrailService = require(script.Parent.TrailService)
local WinsConfig = require(RS.Shared.WinsConfig)
local GamepassConfig = require(RS.Shared.GamepassConfig)

local WinsService = Knit.CreateService({
	Name = "WinsService",

	Client = {
		Collected = Knit.CreateSignal(),
		Touch = Knit.CreateSignal(),
	},
})

local TOUCH_COOLDOWN = 1.5

local lastTouch: { [Player]: number } = {}

local SUFFIXES = { "K", "M", "B", "T" }
local function short(n: number): string
	if n < 1000 then return tostring(n) end
	local v, i = n, 0
	while v >= 1000 and i < #SUFFIXES do v /= 1000; i += 1 end
	local s = string.format("%.2f", v)
	s = (s:gsub("%.?0+$", ""))
	return s .. SUFFIXES[i]
end

local function grantWins(player: Player, amount: number)
	local granted = math.floor(amount * PassService:WinsMultiplier(player) * TrailService:WinsMultiplier(player))
	DataService:AddWins(player, granted)
	WinsService.Client.Collected:Fire(player, granted)

	-- back to the start for the next run a live boost hold or gyro must not come along
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local lv = hrp:FindFirstChild("BoostVelocity")
		if lv then lv:Destroy() end
		local gyro = hrp:FindFirstChild("BoostGyro")
		if gyro then gyro:Destroy() end
	end
	local sp = Workspace:FindFirstChild("SpawnLocation")
	if character and sp and sp:IsA("BasePart") then
		character:PivotTo(sp.CFrame + Vector3.new(0, 4, 0))
	end
end

local function onPadTouched(pad: BasePart, amount: number, hit: BasePart)
	local character = hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not (player and character) then return end
	if not DataService:GetData(player) then return end

	local now = os.clock()
	if now - (lastTouch[player] or -math.huge) < TOUCH_COOLDOWN then return end
	lastTouch[player] = now

	grantWins(player, amount)
end

function WinsService:KnitInit()
	local folder = Workspace:WaitForChild("WinsPads", 10)
	if not folder then
		warn("[WinsService] workspace.WinsPads is missing")
		return
	end

	local template = RS.Assets.UI:FindFirstChild("Wins")
	for _, pad in folder:GetChildren() do
		if not pad:IsA("BasePart") then continue end
		local index = tonumber(pad.Name)
		local amount = index and WinsConfig.PadWins[index]
		if not amount then
			warn("[WinsService] no PadWins entry for pad " .. pad.Name)
			continue
		end

		if template then
			local gui = template:Clone() :: BillboardGui
			local loader = gui:FindFirstChild("PowerLoader", true)
			if loader and loader:IsA("TextLabel") then
				loader.Text = "🏆 +" .. short(amount) .. " Wins"
			end
			gui.Parent = pad
		end

		pad.Touched:Connect(function(hit)
			onPadTouched(pad, amount, hit)
		end)
	end

	-- clients report their own pad touches a round-trip sooner than replicated physics server only sanity-checks range (the Touched path above stays as a fallback)
	WinsService.Client.Touch:Connect(function(player: Player, padName: unknown)
		if typeof(padName) ~= "string" then return end
		local pad = folder:FindFirstChild(padName)
		local index = tonumber(padName)
		local amount = index and WinsConfig.PadWins[index]
		if not (pad and pad:IsA("BasePart") and amount) then return end
		if not DataService:GetData(player) then return end
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then return end
		if (hrp.Position - pad.Position).Magnitude > 60 then return end
		local now = os.clock()
		if now - (lastTouch[player] or -math.huge) < TOUCH_COOLDOWN then return end
		lastTouch[player] = now
		grantWins(player, amount)
	end)

	-- purple pads each island prompts its own Skip Stage product 4 price scaling
	local PROMPT_COOLDOWN = 3
	local lastPrompt: { [Player]: number } = {}
	local ramps = Workspace:FindFirstChild("Ramps")
	-- island N holds wins pad N and ramp N+1, so the next island's deck sits just before ramp N+2; the last island has no further ramp -- land a little short of its wins pad
	local function nextStagePos(index: number): Vector3?
		local ramp = ramps and ramps:FindFirstChild(tostring(index + 2))
		if ramp and ramp:IsA("Model") then
			local cf, size = ramp:GetBoundingBox()
			-- the revive anchors' landing spot on the deck just before the ramp
			return Vector3.new(cf.X, cf.Y - size.Y / 2 + 4, cf.Z - size.Z / 2 - 12)
		end
		local lastRamp = ramps and ramps:FindFirstChild(tostring(index + 1))
		local padsFolder = Workspace:FindFirstChild("WinsPads")
		local pad = padsFolder and padsFolder:FindFirstChild(tostring(index + 1))
		if not (lastRamp and lastRamp:IsA("Model") and pad and pad:IsA("BasePart")) then return nil end
		return Vector3.new(lastRamp:GetPivot().X, pad.Position.Y - pad.Size.Y / 2 + 4, pad.Position.Z - 20)
	end
	for _, part in Workspace:WaitForChild("Map"):GetDescendants() do
		if not part:IsA("BasePart") then continue end
		local index = part:GetAttribute("Wins2xPad") :: number?
		local product = index and GamepassConfig.SkipStageProducts[index]
		if not (index and product and WinsConfig.PadWins[index] and nextStagePos(index)) then continue end

		if template then
			local gui = template:Clone() :: BillboardGui
			local loader = gui:FindFirstChild("PowerLoader", true)
			if loader and loader:IsA("TextLabel") then
				loader.Text = "\u{1F680} Skip Stage"
				local grad = loader:FindFirstChildOfClass("UIGradient")
				if grad then
					grad.Color = ColorSequence.new(Color3.fromRGB(93, 37, 182), Color3.fromRGB(190, 130, 255))
				end
			end
			gui.Parent = part
		end

		part.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if not player or not DataService:GetData(player) then return end
			local now = os.clock()
			if now - (lastPrompt[player] or -math.huge) < PROMPT_COOLDOWN then return end
			lastPrompt[player] = now
			MarketplaceService:PromptProductPurchase(player, product.Id)
		end)
	end

	-- each product's destination is fixed, so the receipt needs no pending state
	for index, product in GamepassConfig.SkipStageProducts do
		PassService.Products[product.Id] = function(player)
			if not DataService:GetData(player) then return false end
			local pos = nextStagePos(index)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (pos and character and humanoid and humanoid.Health > 0) then return false end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local lv = hrp:FindFirstChild("BoostVelocity")
				if lv then lv:Destroy() end
				local gyro = hrp:FindFirstChild("BoostGyro")
				if gyro then gyro:Destroy() end
			end
			character:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
			return true
		end
	end

	Players.PlayerRemoving:Connect(function(p)
		lastTouch[p] = nil
		lastPrompt[p] = nil
	end)
end

return WinsService