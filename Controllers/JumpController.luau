--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local Levels = require(RS:WaitForChild("Shared"):WaitForChild("Levels"))

local player = Players.LocalPlayer

local JumpController = Knit.CreateController({
	Name = "JumpController",
})

local AIR_JUMP_DEBOUNCE = 0.15

local maxJumps = 1
local jumpsLeft = 1
local humanoid: Humanoid? = nil
local hrp: BasePart? = nil
local lastAirJump = 0
local lastRequest = 0
local armed = true -- air jumps need a seperate input

local jumpsLabel: TextLabel? = nil
local labelScale: UIScale? = nil
local clearAt = 0
local leaderboardService = nil

local function makeSound(id: number, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local groundJumpSound = makeSound(9125952513, 1.4) -- board rattle on every jump
local airJumpSound = makeSound(9125952513, 1.4)    -- second instance so spam jumps overlap

local airJumpUsed = false -- an air jump happened this airborne stint the touchdown gets a thud

-- the touchdown thud is SkateboardController's LandSound instance sharing it means a boost landing and a double-jump landing the same frame play once, not twice
local function playLandSound()
	local s = SoundService:FindFirstChild("LandSound")
	if s and s:IsA("Sound") then
		s.TimePosition = 0
		s:Play()
	end
end

local function showJumps()
	if not jumpsLabel then return end
	jumpsLabel.Text = "Jumps: " .. jumpsLeft .. "/" .. maxJumps
	if labelScale then
		labelScale.Scale = 1.25
		TweenService:Create(labelScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function clearJumpsSoon()
	clearAt = os.clock() + 1
	task.delay(1, function()
		if os.clock() >= clearAt and jumpsLabel then jumpsLabel.Text = "" end
	end)
end

-- touching the ground refills the whole pool instantly
local function refill()
	if jumpsLeft < maxJumps then
		jumpsLeft = maxJumps
		showJumps()
	end
	clearJumpsSoon()
end

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid") :: Humanoid
	humanoid = h
	hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	jumpsLeft = maxJumps
	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			if airJumpUsed then
				airJumpUsed = false
				playLandSound()
			end
			refill()
		elseif new == Enum.HumanoidStateType.Jumping then
			armed = false
			jumpsLeft = math.max(0, jumpsLeft - 1)
			showJumps()
			local isAirJump = os.clock() - lastAirJump < 0.1
			if isAirJump then airJumpUsed = true end
			local sound = if isAirJump then airJumpSound else groundJumpSound
			sound.TimePosition = 0
			sound:Play()
			if leaderboardService then leaderboardService.Jumped:Fire() end
		end
	end)
end

function JumpController:KnitStart()
	leaderboardService = Knit.GetService("LeaderboardService")
	-- a ramp boost always hands the full pool back, even when no grounded state fired
	Knit.GetService("SkateboardService").Boosted:Connect(function()
		jumpsLeft = maxJumps
		showJumps()
		clearJumpsSoon()
	end)
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local label = gui:WaitForChild("BottomFrame"):WaitForChild("Jumps") :: TextLabel
	label.Text = ""
	jumpsLabel = label
	local s = Instance.new("UIScale")
	s.Parent = label
	labelScale = s

	-- max jumps follow the level (+1 every 5 levels) plus the VIP bonus; 2x Jumps doubles the pool
	local dataFolder = player:WaitForChild("data")
	local levelV = dataFolder:WaitForChild("Level") :: NumberValue
	local function refreshMax()
		local pool = Levels.JumpsFor(levelV.Value) + (player:GetAttribute("BonusJumps") or 0)
		if player:GetAttribute("DoubleJumps") then pool *= 2 end
		-- admin Double Jumps event: the whole pool doubles while it runs
		if ((workspace:GetAttribute("EventJumpsUntil") :: number?) or 0) > os.time() then pool *= 2 end
		maxJumps = pool
		local h = humanoid
		if h and h.FloorMaterial ~= Enum.Material.Air then
			jumpsLeft = maxJumps
		end
	end
	levelV.Changed:Connect(refreshMax)
	player:GetAttributeChangedSignal("BonusJumps"):Connect(refreshMax)
	player:GetAttributeChangedSignal("DoubleJumps"):Connect(refreshMax)
	workspace:GetAttributeChangedSignal("EventJumpsUntil"):Connect(refreshMax)
	refreshMax()

	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(onCharacter)

	-- landings can settle into states the StateChanged hook doesn't cover (RunningNoPhysics, physics edge cases) while standing on a floor the pool always refills
	task.spawn(function()
		while true do
			task.wait(0.25)
			local h = humanoid
			if h and h.Health > 0 and h.FloorMaterial ~= Enum.Material.Air and jumpsLeft < maxJumps then
				refill()
			end
		end
	end)

	-- air jump space / mobile jump button while falling spends one jump
	UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		if now - lastRequest > 0.08 then armed = true end -- a gap in requests means the button was released yes to spamming
		lastRequest = now
		local h = humanoid
		if not h or h.Health <= 0 then return end
		if not armed then return end
		if now - lastAirJump < AIR_JUMP_DEBOUNCE then return end
		if h:GetState() ~= Enum.HumanoidStateType.Freefall then return end
		if jumpsLeft <= 0 then return end
		-- during a boost's launch window every axis is commanded; a jump would be eaten
		local r = hrp
		local lv = r and r:FindFirstChild("BoostVelocity")
		if lv and lv:IsA("LinearVelocity") and lv.MaxAxesForce.Y > 0 then return end
		lastAirJump = os.clock()
		h:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

return JumpController