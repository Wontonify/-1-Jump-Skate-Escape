--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)

local SkateboardController = Knit.CreateController({ Name = "SkateboardController" })

local ANIMATIONS = {
	Go = 71465219705771,     -- skating push loop while moving
	Idle = 113707271519429,  -- stand-on-board pose replaces the default idle/walk/run via Animate
	Trick1 = 80148204137735, -- one of the three plays per boost and per jump
	Trick2 = 133501847223870,
	Trick3 = 76528767905733, -- front flip
}

local tracks: { [string]: AnimationTrack } = {}
local moving = false
local dustArmed = false -- a boost is in flight the next touchdown gets the dust burst

local function makeSound(id: number, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Parent = SoundService
	return s
end
local boostSound = makeSound(115950712237348, 0.7)
local landSound = makeSound(17806432221, 0.6)
landSound.Name = "LandSound" -- shared with JumpController's double-jump touchdown (same instance, never doubles)
local rollSound = makeSound(9125956819, 1.6) -- wheels on the ground while skating around
rollSound.Looped = true

local function loadTrack(animator: Animator, id: number, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id
	local track = animator:LoadAnimation(anim)
	track.Priority = priority
	track.Looped = looped
	return track
end

-- landing thud only the ground-block eruption visual lives in LandingImpactController
local function landDust(character: Model)
	landSound.TimePosition = 0
	landSound:Play()
end

local TRICK_KEYS = { "Trick1", "Trick2", "Trick3" }

local function playRandomTrick()
	local chosen = tracks[TRICK_KEYS[math.random(#TRICK_KEYS)]]
	if not chosen then return end
	for _, key in TRICK_KEYS do
		if tracks[key] then tracks[key]:Stop(0.1) end
	end
	chosen:Play(0.1)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator

	-- moving on the board should ride the default idle/walk/run animations all become the board idle
	local animate = character:WaitForChild("Animate", 5)
	if animate then
		for _, slotName in {"idle", "walk", "run", "jump", "fall"} do
			local slot = animate:FindFirstChild(slotName)
			if slot then
				for _, anim in slot:GetDescendants() do
					if anim:IsA("Animation") then
						anim.AnimationId = "rbxassetid://" .. ANIMATIONS.Idle
					end
				end
			end
		end
	end

	tracks.Go = loadTrack(animator, ANIMATIONS.Go, Enum.AnimationPriority.Action, true)
	tracks.Trick1 = loadTrack(animator, ANIMATIONS.Trick1, Enum.AnimationPriority.Action2, false)
	tracks.Trick2 = loadTrack(animator, ANIMATIONS.Trick2, Enum.AnimationPriority.Action2, false)
	tracks.Trick3 = loadTrack(animator, ANIMATIONS.Trick3, Enum.AnimationPriority.Action2, false)

	moving = false
	rollSound:Stop()

	-- the wheel loop runs whenever the board is actually rolling on the ground
	local function updateRoll()
		local shouldRoll = moving and humanoid.FloorMaterial ~= Enum.Material.Air and humanoid.Health > 0
		if shouldRoll and not rollSound.IsPlaying then
			rollSound:Play()
		elseif not shouldRoll and rollSound.IsPlaying then
			rollSound:Stop()
		end
	end

	humanoid.Running:Connect(function(speed)
		moving = speed > 0.5
		if moving and not tracks.Go.IsPlaying then
			tracks.Go:Play(0.2)
		elseif not moving and tracks.Go.IsPlaying then
			tracks.Go:Stop(0.2)
		end
		updateRoll()
	end)
	humanoid.Died:Connect(function() rollSound:Stop() end)

	-- every jump (ground or air) does a trick instead of the default jump animation the first touchdown after a boost kicks up dust right where the feet hit
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			playRandomTrick()
		elseif dustArmed and (new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running) then
			dustArmed = false
			landDust(character)
		end
		updateRoll()
	end)
end

local function playTrick(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- the trick starts once the player has fully left the boost wedge
		local deadline = os.clock() + 0.6
		while os.clock() < deadline and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall do
			task.wait()
		end
	end
	playRandomTrick()
end

function SkateboardController:KnitStart()
	local player = Players.LocalPlayer
	if player.Character then task.spawn(onCharacter, player.Character) end
	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, character)
	end)

	-- clipping a structure at flight speed physics-catapults the character (velocity spikes the boost never commanded)
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (hrp and hrp:IsA("BasePart") and humanoid) then return end
		if not hrp:FindFirstChild("BoostVelocity") then return end
		local v = hrp.AssemblyLinearVelocity
		local fwd = hrp.CFrame.LookVector
		local fComp = fwd * v:Dot(fwd)
		local rest = v - fComp
		local yComp = Vector3.new(0, rest.Y, 0)
		local lat = rest - yComp
		local latCap = 60 -- steering drift stays small
		local changed = false
		if yComp.Y > 130 then
			yComp = Vector3.new(0, 130, 0)
			changed = true
		end
		if lat.Magnitude > latCap then
			lat = lat.Unit * latCap
			changed = true
		end
		if changed then
			hrp.AssemblyLinearVelocity = fComp + yComp + lat
		end
	end)

	-- the server's corpse Destroy doesn't replicate once the character is unparented, so every client also drops its local replica of anyone's dead character
	local function watchCorpses(p: Player)
		p.CharacterRemoving:Connect(function(character)
			task.delay(1, function()
				if character.Parent == nil then character:Destroy() end
			end)
		end)
	end
	Players.PlayerAdded:Connect(watchCorpses)
	for _, p in Players:GetPlayers() do watchCorpses(p) end

	local SkateboardService = Knit.GetService("SkateboardService")
	SkateboardService.Boosted:Connect(function()
		boostSound.TimePosition = 0
		boostSound:Play()
		local character = player.Character
		if character then
			task.spawn(playTrick, character)
			-- arm the dust only once the character is actually airborne, so the launch's own running ticks don't spend it early
			task.spawn(function()
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid then return end
				local deadline = os.clock() + 1
				while os.clock() < deadline and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall do
					task.wait()
				end
				dustArmed = true
			end)
		end
	end)
	-- disarm dust
	SkateboardService.Fell:Connect(function()
		dustArmed = false
	end)
end

return SkateboardController










