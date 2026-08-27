--!strict
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Knit = require(RS.Packages.Knit)
local Levels = require(RS:WaitForChild("Shared"):WaitForChild("Levels"))
local Rebirths = require(RS:WaitForChild("Shared"):WaitForChild("Rebirths"))
local TrailConfig = require(RS:WaitForChild("Shared"):WaitForChild("TrailConfig"))
local GamepassConfig = require(RS:WaitForChild("Shared"):WaitForChild("GamepassConfig"))
local Worlds = require(RS:WaitForChild("Shared"):WaitForChild("Worlds"))
local UtilController = require(script.Parent.UtilController)

local HOVER, HOVER_LEFT, PRESS = 1.08, 1.1, 0.94

local player = Players.LocalPlayer

local UIController = Knit.CreateController({
	Name = "UIController",
})

function UIController:KnitStart()
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("ScreenGui")
	local bar = hud:WaitForChild("BottomFrame"):WaitForChild("BarBackground")
	local totalPowerLabel = bar:WaitForChild("TotalPower") :: TextLabel

	local leaderstats = player:WaitForChild("leaderstats")
	local winsV = leaderstats:WaitForChild("Wins") :: IntValue
	local winsLoader = hud:WaitForChild("LeftFrame"):WaitForChild("WinsFrame")
		:WaitForChild("WinsBackground"):WaitForChild("WinsLoader") :: TextLabel
	local function updateWins()
		winsLoader.Text = UtilController.Short(winsV.Value)
	end
	winsV.Changed:Connect(updateWins)
	updateWins()

	-- level HUD current level, progress/requirement tracker, next-level tag, XP fill bar
	local currentLevel = bar:WaitForChild("CurrentLevel") :: TextLabel
	local requirement = bar:WaitForChild("Requirement") :: TextLabel
	local nextJumpLoader = bar:WaitForChild("NextJumpLoader") :: TextLabel
	local fill = bar:WaitForChild("BarCanvas"):WaitForChild("Progress") :: Frame

	local dataFolder = player:WaitForChild("data")
	local levelV = dataFolder:WaitForChild("Level") :: NumberValue
	local progressV = dataFolder:WaitForChild("LevelProgress") :: NumberValue
	local rebirthV = dataFolder:WaitForChild("Rebirth") :: NumberValue

	-- base + per-level gain (halved in world 2) + shop upgrades, doubled by the 2x Speed pass
	local baseSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
	if baseSpeed <= 0 then baseSpeed = 16 end
	local function speedFor(level: number): number
		local upgrades = (player:GetAttribute("SpeedUpgrade") :: number?) or 0
		local pack = if player:GetAttribute("StarterPackOwned") then 3 else 0
		local mult = if player:GetAttribute("SpeedOwned") then GamepassConfig.Speed.Mult else 1
		local friends = (player:GetAttribute("FriendBoost") :: number?) or 1
		local event = if ((workspace:GetAttribute("EventSpeedUntil") :: number?) or 0) > os.time()
			then ((workspace:GetAttribute("EventSpeedMult") :: number?) or 1)
			else 1
		local levelSpeed = Levels.SpeedFromLevel(level, Worlds.PlayerWorld(player))
		return (baseSpeed + levelSpeed + upgrades + pack) * mult * friends * event
	end
	-- the headline counter shows that whole number, not the lifetime grind balance
	local function updateTotalSpeed()
		totalPowerLabel.Text = "Total Speed: " .. math.floor(speedFor(levelV.Value) + 0.5)
	end
	levelV.Changed:Connect(updateTotalSpeed)
	player:GetAttributeChangedSignal("SpeedUpgrade"):Connect(updateTotalSpeed)
	player:GetAttributeChangedSignal("SpeedOwned"):Connect(updateTotalSpeed)
	player:GetAttributeChangedSignal("StarterPackOwned"):Connect(updateTotalSpeed)
	player:GetAttributeChangedSignal("FriendBoost"):Connect(updateTotalSpeed)
	player:GetAttributeChangedSignal("World"):Connect(updateTotalSpeed)
	workspace:GetAttributeChangedSignal("EventSpeedUntil"):Connect(updateTotalSpeed)
	updateTotalSpeed()

	local trailsBoost = bar:WaitForChild("TrailsBoost") :: TextLabel
	local function updateTrailsBoost()
		local entry = TrailConfig.Trails[player:GetAttribute("Trail") or ""]
		local m = entry and entry.Multiplier or 1
		trailsBoost.Text = "Trails: " .. (string.format("%.2f", m):gsub("%.?0+$", "")) .. "x"
	end
	player:GetAttributeChangedSignal("Trail"):Connect(updateTrailsBoost)
	updateTrailsBoost()

	local rebirthBoost = bar:WaitForChild("RebirthBoost") :: TextLabel
	local function updateLevel()
		local level = levelV.Value
		local maxLevel = Rebirths.MaxLevelFor(rebirthV.Value)
		currentLevel.Text = "Level " .. level
		rebirthBoost.Text = "Rebirth: " .. Rebirths.FormatMultiplier(rebirthV.Value)
		local frac
		if level >= maxLevel then
			requirement.Text = "MAX LEVEL"
			frac = 1
		else
			local req = Levels.RequirementFor(level, Worlds.PlayerWorld(player))
			requirement.Text = UtilController.Short(progressV.Value) .. "/" .. UtilController.Short(req)
			frac = if req > 0 then math.clamp(progressV.Value / req, 0, 1) else 0
		end
		nextJumpLoader.Text = ": Level " .. (math.floor(level / 5) + 1) * 5
		local y = fill.Size.Y
		fill.Size = UDim2.new(frac, 0, y.Scale, y.Offset)
	end
	levelV.Changed:Connect(updateLevel)
	progressV.Changed:Connect(updateLevel)
	rebirthV.Changed:Connect(updateLevel)
	player:GetAttributeChangedSignal("World"):Connect(updateLevel)
	updateLevel()

	-- level-up celebration sound + particle burst on the character
	local levelUpSound = Instance.new("Sound")
	levelUpSound.SoundId = "rbxassetid://140693247883244"
	levelUpSound.Volume = 0.525
	levelUpSound.Parent = SoundService

	local function playLevelVFX()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return end
		local assets = RS:FindFirstChild("Assets")
		local atts = assets and assets:FindFirstChild("Attachments")
		local template = atts and atts:FindFirstChild("LevelUpVFX")
		if not (template and template:IsA("Attachment")) then return end
		local att = template:Clone()
		att.Parent = hrp
		for _, e in att:GetDescendants() do
			if e:IsA("ParticleEmitter") then
				e:Emit(e.Rate > 0 and math.clamp(math.floor(e.Rate), 15, 100) or 30)
			end
		end
		Debris:AddItem(att, 3)
	end

	Knit.GetService("XPService").LevelUp:Connect(function()
		levelUpSound.TimePosition = 0
		levelUpSound:Play()
		playLevelVFX()
	end)

	-- TopFrame banner "Level 7 > Level 8" with the jump pool underneath
	local topFrame = hud:WaitForChild("TopFrame")
	local banner = topFrame:WaitForChild("LevelUpFrame")
	local bannerLevel = banner:WaitForChild("Level") :: TextLabel
	local bannerSpeed = banner:WaitForChild("Speed") :: TextLabel
	local bannerJump = banner:WaitForChild("Jump") :: TextLabel
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	local bannerHideAt = 0
	local function popBanner()
		topFrame.Visible = true
		bannerScale.Scale = 0.65
		TweenService:Create(bannerScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		bannerHideAt = os.clock() + 2.5
		task.delay(2.5, function()
			if os.clock() >= bannerHideAt then topFrame.Visible = false end
		end)
	end
	-- jump numbers always mean the full pool level jumps + bought/VIP bonus, doubled by 2x Jumps
	local function jumpPool(level: number): number
		local pool = Levels.JumpsFor(level) + ((player:GetAttribute("BonusJumps") :: number?) or 0)
		if player:GetAttribute("DoubleJumps") then pool *= 2 end
		return pool
	end
	local lastLevel = levelV.Value
	local lastPool = jumpPool(lastLevel)
	levelV.Changed:Connect(function(newLevel)
		local oldLevel = lastLevel
		lastLevel = newLevel
		lastPool = jumpPool(newLevel)
		if newLevel <= oldLevel then return end
		bannerLevel.Visible = true
		bannerLevel.Text = "Level " .. oldLevel .. " > Level " .. newLevel
		bannerJump.Visible = true
		bannerJump.Text = "Jump " .. jumpPool(oldLevel) .. " > Jump " .. lastPool
		bannerSpeed.Visible = true
		bannerSpeed.Text = "Speed " .. speedFor(oldLevel) .. " > Speed " .. speedFor(newLevel)
		popBanner()
	end)
	-- buying a jump (or 2x Jumps) pops the same banner with just the Jump line
	local bootUntil = os.clock() + 5 -- join-time attribute publishes must not pop it
	local function onPoolAttr()
		local pool = jumpPool(levelV.Value)
		local oldPool = lastPool
		lastPool = pool
		if pool == oldPool or os.clock() < bootUntil then return end
		bannerLevel.Visible = false
		bannerSpeed.Visible = false
		bannerJump.Visible = true
		bannerJump.Text = "Jump " .. oldPool .. " > Jump " .. pool
		levelUpSound.TimePosition = 0
		levelUpSound:Play()
		popBanner()
	end
	player:GetAttributeChangedSignal("BonusJumps"):Connect(onPoolAttr)
	player:GetAttributeChangedSignal("DoubleJumps"):Connect(onPoolAttr)
	-- buying +1 Speed pops the same banner with just the Speed line
	local lastSpeed = speedFor(levelV.Value)
	local function syncLastSpeed()
		lastSpeed = speedFor(levelV.Value)
	end
	levelV.Changed:Connect(syncLastSpeed)
	player:GetAttributeChangedSignal("Board"):Connect(syncLastSpeed)
	player:GetAttributeChangedSignal("SpeedOwned"):Connect(syncLastSpeed)
	player:GetAttributeChangedSignal("StarterPackOwned"):Connect(syncLastSpeed)
	player:GetAttributeChangedSignal("FriendBoost"):Connect(syncLastSpeed)
	workspace:GetAttributeChangedSignal("EventSpeedUntil"):Connect(syncLastSpeed)
	player:GetAttributeChangedSignal("SpeedUpgrade"):Connect(function()
		local speed = speedFor(levelV.Value)
		local oldSpeed = lastSpeed
		lastSpeed = speed
		if speed == oldSpeed or os.clock() < bootUntil then return end
		bannerLevel.Visible = false
		bannerJump.Visible = false
		bannerSpeed.Visible = true
		bannerSpeed.Text = "Speed " .. oldSpeed .. " > Speed " .. speed
		levelUpSound.TimePosition = 0
		levelUpSound:Play()
		popBanner()
	end)

	-- hover pop on every button
	local function addHover(button: GuiButton)
		if button:GetAttribute("HoverWired") then return end
		button:SetAttribute("HoverWired", true)
		local scale = button:FindFirstChildOfClass("UIScale")
		if not scale then scale = Instance.new("UIScale"); scale.Parent = button end
		local base = scale.Scale
		local hovering = false
		local IN = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local function to(target: number, info: TweenInfo)
			TweenService:Create(scale, info, { Scale = base * target }):Play()
		end
		local function hoverTarget(): number
			return button:FindFirstAncestor("LeftFrame") and HOVER_LEFT or HOVER
		end
		button.MouseEnter:Connect(function() hovering = true; to(hoverTarget(), IN) end)
		button.MouseLeave:Connect(function() hovering = false; to(1, OUT) end)
		button.MouseButton1Down:Connect(function() to(PRESS, OUT) end)
		button.MouseButton1Up:Connect(function() to(hovering and hoverTarget() or 1, IN) end)
	end
	for _, d in playerGui:GetDescendants() do
		if d:IsA("GuiButton") then addHover(d) end
	end
	playerGui.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then addHover(d) end
	end)

	-- main frames pop open / closed; opening one closes the others
	local mainFrames = hud:WaitForChild("MainFrames")
	local function frameScale(frame: GuiObject): UIScale
		local s = frame:FindFirstChildOfClass("UIScale")
		if not s then s = Instance.new("UIScale"); s.Parent = frame end
		return s
	end
	local function closeFrame(frame: GuiObject)
		local s = frameScale(frame)
		local tw = TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.65 })
		tw:Play()
		tw.Completed:Once(function() frame.Visible = false end)
	end
	local function openFrame(frame: GuiObject)
		for _, other in mainFrames:GetChildren() do
			if other:IsA("GuiObject") and other ~= frame and other.Visible then closeFrame(other) end
		end
		local s = frameScale(frame)
		s.Scale = 0.65
		frame.Visible = true
		TweenService:Create(s, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local function onClick(button: Instance?, fn: () -> ())
		if button and button:IsA("GuiButton") then button.Activated:Connect(fn) end
	end
	local function wireFrame(button: Instance?, frame: GuiObject, background: Instance, canOpen: (() -> boolean)?)
		onClick(button, function()
			if frame.Visible then
				closeFrame(frame)
			elseif not canOpen or canOpen() then
				openFrame(frame)
			end
		end)
		onClick(background:FindFirstChild("CloseButton"), function() closeFrame(frame) end)
	end
	-- walk-up frames in other controllers reuse the same pop + close-others behaviour
	UIController.OpenFrame = openFrame
	UIController.CloseFrame = closeFrame

	local left = hud:WaitForChild("LeftFrame")
	local shopFrame = mainFrames:WaitForChild("ShopFrame")
	local rebirthsFrame = mainFrames:WaitForChild("RebirthsFrame")
	local trailsFrame = mainFrames:WaitForChild("TrailsFrame")
	wireFrame(left:WaitForChild("ShopButton"), shopFrame, shopFrame:WaitForChild("ShopBackground"), function()
		-- the walk-up Upgrades pad owns the screen while you stand on it
		return player:GetAttribute("OnUpgradePad") ~= true
	end)
	wireFrame(left:WaitForChild("RebirthButton"), rebirthsFrame, rebirthsFrame:WaitForChild("RebirthsBackground"))
	wireFrame(left:WaitForChild("TrailsButton"), trailsFrame, trailsFrame:WaitForChild("TrailsBackground"))

	-- rebirth frame contents: current/next max level + multiplier, level progress bar
	local rebirthPct = left:WaitForChild("RebirthButton"):FindFirstChild("Percentage")
	local rebirthBg = rebirthsFrame.RebirthsBackground
	local reqText = rebirthBg:WaitForChild("Bar"):WaitForChild("RequirementText") :: TextLabel
	local fillerBar = rebirthBg.Bar:WaitForChild("Canvas"):WaitForChild("Filler") :: Frame
	-- the authored filler is centre-anchored; re-anchor it to the left edge so the fill can shrink
	fillerBar.AnchorPoint = Vector2.new(0, 0.5)
	fillerBar.Position = UDim2.new(0, 0, 0.5, 0)
	local function setName(holder: Instance?, text: string)
		local l = holder and holder:FindFirstChild("Name")
		if l and l:IsA("TextLabel") then l.Text = text end
	end
	local function updateRebirthFrame()
		local rebirth = rebirthV.Value
		local maxLevel = Rebirths.MaxLevelFor(rebirth)
		setName(rebirthBg, "Rebirth " .. rebirth) -- the frame's title counts your rebirths
		setName(rebirthBg:FindFirstChild("PreviousLevel"), "Level " .. maxLevel)
		setName(rebirthBg:FindFirstChild("NextLevel"), "Level " .. Rebirths.MaxLevelFor(rebirth + 1))
		setName(rebirthBg:FindFirstChild("PreviousMultiplier"), Rebirths.FormatMultiplier(rebirth) .. " Speed")
		setName(rebirthBg:FindFirstChild("NextMultiplier"), Rebirths.FormatMultiplier(rebirth + 1) .. " Speed")
		reqText.Text = "Level " .. levelV.Value .. " / " .. maxLevel
		local frac = math.clamp(levelV.Value / maxLevel, 0, 1)
		local sz = fillerBar.Size
		fillerBar.Size = UDim2.new(frac, 0, sz.Y.Scale, sz.Y.Offset)
		if rebirthPct and rebirthPct:IsA("TextLabel") then
			rebirthPct.Visible = frac < 1
			rebirthPct.Text = math.floor(frac * 100 + 0.5) .. "%"
			local stroke = rebirthPct:FindFirstChildOfClass("UIStroke")
			if stroke then
				-- outline sweeps dark red through dark yellow to dark green as the rebirth fills
				stroke.Color = Color3.fromHSV(frac / 3, 0.9, 0.5)
			end
		end
	end
	rebirthV.Changed:Connect(updateRebirthFrame)
	levelV.Changed:Connect(updateRebirthFrame)
	updateRebirthFrame()

	local rebirthService = Knit.GetService("RebirthService")
	onClick(rebirthBg:WaitForChild("RebirthButton"), function()
		rebirthService.Request:Fire()
	end)
	onClick(rebirthBg:WaitForChild("SkipRebirthButton"), function()
		MarketplaceService:PromptProductPurchase(player, GamepassConfig.SkipRebirthProduct.Id)
	end)

	-- rebirth celebration white flash + sound + particle burst when Rebirth increases
	local flashGui = Instance.new("ScreenGui")
	flashGui.Name = "RebirthFlash"
	flashGui.IgnoreGuiInset = true
	flashGui.ResetOnSpawn = false
	flashGui.DisplayOrder = 100
	flashGui.Parent = playerGui
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = flashGui
	local rebirthSound = Instance.new("Sound")
	rebirthSound.SoundId = "rbxassetid://96934141342962"
	rebirthSound.Volume = 0.7
	rebirthSound.Parent = SoundService

	local function playRebirthParticles()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local assets = RS:FindFirstChild("Assets")
		local atts = assets and assets:FindFirstChild("Attachments")
		if not atts then return end
		for _, emitter in atts:GetChildren() do
			if emitter.Name == "Rebirth" and emitter:IsA("ParticleEmitter") then
				local clone = emitter:Clone() :: ParticleEmitter
				clone.Enabled = true
				clone.Parent = hrp
				task.delay(1.2, function() if clone then clone.Enabled = false end end)
				Debris:AddItem(clone, 4)
			end
		end
	end

	-- background music
	local music = Instance.new("Sound")
	music.Name = "Music"
	music.SoundId = "rbxassetid://1840449070"
	music.Volume = 0.25
	music.Looped = true
	music.Parent = SoundService
	music:Play()

	-- wins pad collect sound + the screen filling with trophies over the teleport home
	local winsSound = Instance.new("Sound")
	winsSound.SoundId = "rbxassetid://1169806635"
	winsSound.Volume = 0.7
	winsSound.Parent = SoundService
	Knit.GetService("WinsService").Collected:Connect(function()
		winsSound.TimePosition = 0
		winsSound:Play()
		for _ = 1, 40 do
			local t = Instance.new("ImageLabel")
			t.BackgroundTransparency = 1
			t.Image = "rbxassetid://128576837035866"
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			local size = math.random(30, 70)
			t.Size = UDim2.fromOffset(size, size)
			local x = math.random()
			t.Position = UDim2.fromScale(x, -0.08)
			t.Rotation = math.random(-180, 180)
			t.ZIndex = 50
			t.Parent = flashGui
			task.delay(math.random() * 0.5, function()
				if not t.Parent then return end
				TweenService:Create(t, TweenInfo.new(1.4 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.2, 1.12),
					Rotation = t.Rotation + math.random(-270, 270),
				}):Play()
			end)
			Debris:AddItem(t, 3.4)
		end
	end)

	-- confetti drop over the whole screen: skateboard purchases and rebirths celebrate the same way the wins collect does
	local function confettiRain()
		for _ = 1, 60 do
			local c = Instance.new("Frame")
			c.BorderSizePixel = 0
			c.BackgroundColor3 = Color3.fromHSV(math.random(), 0.75, 1)
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Size = UDim2.fromOffset(math.random(6, 10), math.random(10, 18))
			local x = math.random()
			c.Position = UDim2.fromScale(x, -0.06)
			c.Rotation = math.random(-180, 180)
			c.ZIndex = 50
			c.Parent = flashGui
			task.delay(math.random() * 0.5, function()
				if not c.Parent then return end
				TweenService:Create(c, TweenInfo.new(1.3 + math.random() * 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.25, 1.12),
					Rotation = c.Rotation + math.random(-360, 360),
				}):Play()
			end)
			Debris:AddItem(c, 3.4)
		end
	end
	Knit.GetService("ShopService").Bought:Connect(function()
		confettiRain()
	end)

	-- one Notifications-template clone per message, stacked by the container list
	local notifContainer = playerGui:WaitForChild("Notifications"):WaitForChild("Container")
	local notifTemplate = notifContainer:WaitForChild("Template") :: TextLabel
	local notifOrder = 0
	local function notify(msg: string, color: Color3?)
		notifOrder += 1
		local label = notifTemplate:Clone()
		label.Text = msg
		if color then label.TextColor3 = color end
		label.LayoutOrder = notifOrder
		label.Visible = true
		label.Parent = notifContainer
		task.delay(1.6, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play() end
		end)
		Debris:AddItem(label, 2.1)
	end
	UIController.Notify = notify
	local errorSound = Instance.new("Sound")
	errorSound.SoundId = "rbxassetid://133843340754810"
	errorSound.Volume = 0.5
	errorSound.Parent = SoundService
	local function showDeny(msg: string)
		errorSound.TimePosition = 0
		errorSound:Play()
		notify(msg, Color3.fromRGB(255, 80, 80))
	end
	UIController.ShowDeny = showDeny
	Knit.GetService("ShopService").Denied:Connect(showDeny)
	Knit.GetService("TrainService").Denied:Connect(showDeny)
	Knit.GetService("TrailService").Denied:Connect(showDeny)

	--  green notification + sound once per eligibility, "!" badge while it lasts, and a dimmed-screen spotlight on the rebirth button so nobody misses it
	local readySound = Instance.new("Sound")
	readySound.SoundId = "rbxassetid://1169806635"
	readySound.Volume = 0.8
	readySound.Parent = SoundService
	local rebirthButton = left:WaitForChild("RebirthButton") :: GuiButton
	local rebirthBadge = rebirthButton:WaitForChild("Notification") :: Frame

	local dimGui = Instance.new("ScreenGui")
	dimGui.Name = "RebirthSpotlight"
	dimGui.ResetOnSpawn = false
	dimGui.DisplayOrder = 90
	dimGui.Enabled = false
	dimGui.Parent = playerGui
	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim:SetAttribute("HoverWired", true)
	dim.Position = UDim2.new(0, 0, 0, -60)
	dim.Size = UDim2.new(1, 0, 1, 120)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Parent = dimGui

	local wiggleInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local wiggle = TweenService:Create(rebirthBadge, wiggleInfo, { Rotation = 14 })
	local wiggleOn = false

	local spotlightButton: GuiButton? = nil
	local function hideSpotlight()
		dimGui.Enabled = false
		if spotlightButton then
			spotlightButton:Destroy()
			spotlightButton = nil
		end
	end
	-- the dim layer is a pure click sink while a spotlight runs, ONLY the spotlit clone works
	local function spotlight(target: GuiButton, onActivate: () -> ())
		if spotlightButton then
			spotlightButton:Destroy()
			spotlightButton = nil
		end
		local clone = target:Clone()
		clone:SetAttribute("HoverWired", true)
		clone.Visible = true
		clone.AnchorPoint = Vector2.zero
		clone.Position = UDim2.fromOffset(target.AbsolutePosition.X, target.AbsolutePosition.Y)
		clone.Size = UDim2.fromOffset(target.AbsoluteSize.X, target.AbsoluteSize.Y)
		clone.Parent = dimGui
		spotlightButton = clone
		local scale = clone:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = clone
		end
		scale.Scale = 1
		TweenService:Create(scale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 }):Play()
		local badge = clone:FindFirstChild("Notification")
		if badge and badge:IsA("Frame") then
			badge.Visible = true
			badge.Rotation = -14
			TweenService:Create(badge, wiggleInfo, { Rotation = 14 }):Play()
		end
		clone.Activated:Connect(onActivate)
		if not dimGui.Enabled then
			dim.BackgroundTransparency = 1
			dimGui.Enabled = true
		end
		TweenService:Create(dim, TweenInfo.new(0.4), { BackgroundTransparency = 0.25 }):Play()
	end
	-- the first rebirth is guided and unskippable dark screen with only the HUD rebirth button clickable, then dark again with only the frame's Rebirth button to confirm
	local function showSpotlight()
		if dimGui.Enabled or spotlightButton then return end
		if levelV.Value < Rebirths.MaxLevelFor(rebirthV.Value) then return end
		if rebirthButton.AbsoluteSize.X < 1 then return end
		spotlight(rebirthButton, function()
			if spotlightButton then
				spotlightButton:Destroy()
				spotlightButton = nil
			end
			openFrame(rebirthsFrame)
			task.delay(0.3, function() -- the open pop settles before the confirm button is measured
				if not dimGui.Enabled then return end
				local confirm = rebirthBg:FindFirstChild("RebirthButton")
				if not (confirm and confirm:IsA("GuiButton")) then
					hideSpotlight()
					return
				end
				spotlight(confirm, function()
					hideSpotlight()
					rebirthService.Request:Fire()
				end)
			end)
		end)
	end

	local wasEligible: boolean? = nil
	local function checkRebirthReady()
		local eligible = levelV.Value >= Rebirths.MaxLevelFor(rebirthV.Value)
		rebirthBadge.Visible = eligible
		if eligible and not wiggleOn then
			wiggleOn = true
			rebirthBadge.Rotation = -14
			wiggle:Play()
		elseif not eligible and wiggleOn then
			wiggleOn = false
			wiggle:Cancel()
			rebirthBadge.Rotation = 0
		end
		local firstEver = rebirthV.Value == 0 -- the dim spotlight only introduces the FIRST rebirth
		if not eligible then
			hideSpotlight()
		elseif wasEligible == false then
			readySound.TimePosition = 0
			readySound:Play()
			notify("You can now Rebirth!", Color3.fromRGB(90, 235, 110))
			if firstEver then showSpotlight() end
		elseif wasEligible == nil and firstEver then
			task.delay(2, showSpotlight) -- joined already eligible wait for the HUD to lay out
		end
		wasEligible = eligible
	end
	levelV.Changed:Connect(checkRebirthReady)
	rebirthV.Changed:Connect(checkRebirthReady)
	checkRebirthReady()

	local lastRebirth = rebirthV.Value
	rebirthV.Changed:Connect(function(v)
		if v > lastRebirth then
			rebirthSound.TimePosition = 0
			rebirthSound:Play()
			flash.BackgroundTransparency = 0
			TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			playRebirthParticles()
			confettiRain()
		end
		lastRebirth = v
	end)

	-- speedadjuster, type a speed to ride slower, click icon to reset
	do
		local adjuster = hud:WaitForChild("RightFrame"):WaitForChild("SpeedAdjuster")
		local box = adjuster:WaitForChild("TextBox") :: TextBox
		local icon = adjuster:WaitForChild("Icon")
		local trailService = Knit.GetService("TrailService")
		box.PlaceholderText = "Enter Speed..."
		local chosen: number? = nil
		local applying = false
		local function maxSpeed(): number
			return speedFor(levelV.Value)
		end
		local function apply()
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end
			local target = if chosen then math.clamp(chosen, 1, maxSpeed()) else maxSpeed()
			if humanoid.WalkSpeed ~= target then
				applying = true
				humanoid.WalkSpeed = target
				applying = false
			end
		end
		box.FocusLost:Connect(function()
			local n = tonumber(box.Text)
			if n then
				chosen = math.clamp(math.floor(n + 0.5), 1, math.floor(maxSpeed()))
				box.Text = tostring(chosen)
			else
				chosen = nil
				box.Text = ""
			end
			apply()
			-- the server mirrors the cap ramp boosts and the applied walkspeed follow it
			trailService.SpeedCap:Fire(chosen)
		end)
		icon.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				chosen = nil
				box.Text = ""
				apply()
				trailService.SpeedCap:Fire(nil)
			end
		end)
		-- the server re-applies the earned speed on level/board/upgrade changes
		local function hookHumanoid(char: Model)
			local humanoid = char:WaitForChild("Humanoid", 10)
			if not (humanoid and humanoid:IsA("Humanoid")) then return end
			humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
				if not applying and chosen then task.defer(apply) end
			end)

			if chosen then task.defer(apply) end
		end
		player.CharacterAdded:Connect(function(c) task.spawn(hookHumanoid, c) end)
		if player.Character then task.spawn(hookHumanoid, player.Character) end
	end
end

return UIController