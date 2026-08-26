--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local ClickController = require(script.Parent.ClickController)
local UIController = require(script.Parent.UIController)
local TrainConfig = require(RS.Shared.TrainConfig)
local Worlds = require(RS.Shared.Worlds)

-- every world's Train pads together
local function trainPads(): { BasePart }
	local pads = {}
	for _, worldFolder in Worlds.List() do
		local folder = worldFolder:FindFirstChild("Train")
		if not folder then continue end
		for _, pad in folder:GetChildren() do
			if pad:IsA("BasePart") then table.insert(pads, pad) end
		end
	end
	return pads
end

local player = Players.LocalPlayer

local TrainController = Knit.CreateController({
	Name = "TrainController",
})

local GREEN = ColorSequence.new(Color3.fromRGB(45, 190, 70), Color3.fromRGB(160, 255, 175))
local RED = ColorSequence.new(Color3.fromRGB(190, 40, 40), Color3.fromRGB(255, 120, 120))

-- wheel-spin loop while training ticks keep arriving
local trainSound = Instance.new("Sound")
trainSound.SoundId = "rbxassetid://9119185706"
trainSound.Volume = 0.5
trainSound.Looped = true
trainSound.Parent = SoundService
local lastTrainTick = 0

local TRAIN_ANIM = 114645169589720
local trainTrack: AnimationTrack? = nil
local trainChar: Model? = nil

local function getTrainTrack(): AnimationTrack?
	local character = player.Character
	if not character then return nil end
	if trainTrack and trainChar == character then return trainTrack end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	-- a fresh character's Animator can lag behind the prompt: wait for it
	-- anim silently never plays and you just stand in the middle of the pad
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
	if not (animator and animator:IsA("Animator")) then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. TRAIN_ANIM
	local track = animator:LoadAnimation(anim)
	-- above the skateboard's own Action-priority anims, which would otherwise hold the joints
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	trainTrack = track
	trainChar = character
	return track
end

local function unlocked(name: string, ground: TrainConfig.Ground): boolean
	if ground.Robux then
		local owned = (player:GetAttribute("OwnedTrains") :: string?) or ""
		if table.find(string.split(owned, "|"), name) then return true end
		local passes = (player:GetAttribute("OwnedTrainPasses") :: string?) or ""
		return table.find(string.split(passes, "|"), name) ~= nil
	end
	local dataFolder = player:FindFirstChild("data")
	local rebirth = dataFolder and dataFolder:FindFirstChild("Rebirth")
	return rebirth ~= nil and (rebirth :: NumberValue).Value >= (ground.Rebirths or 0)
end

-- multiplier gradient: green = usable by this player, red = locked; re-asserted for streaming
local function refreshGradients()
	for _, pad in trainPads() do
		local ground = TrainConfig.Grounds[pad.Name]
		if not ground then continue end
		local gui = pad:FindFirstChildOfClass("BillboardGui")
		local label = gui and gui:FindFirstChild("PowerLoader", true)
		if not label then continue end
		local gradient = label:FindFirstChild("StateGradient") :: UIGradient?
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "StateGradient"
			gradient.Rotation = -90
			gradient.Parent = label
		end
		gradient.Color = if unlocked(pad.Name, ground) then GREEN else RED
	end
end

local function findPad(padName: string): BasePart?
	for _, pad in trainPads() do
		if pad.Name == padName then return pad end
	end
	return nil
end

function TrainController:KnitStart()
	local trainService = Knit.GetService("TrainService")

	-- the first training after join can otherwise race the download
	task.spawn(function()
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. TRAIN_ANIM
		pcall(function() game:GetService("ContentProvider"):PreloadAsync({ anim }) end)
	end)

	trainService.Trained:Connect(function(amount: number)
		lastTrainTick = os.clock()
		if not trainSound.IsPlaying then trainSound:Play() end
		-- full-screen spread with the middle protected, same as the walking popups
		ClickController.PlayFeedback(amount, ClickController.RandomPopupPos())
	end)

	-- training with company pays more announce joins and the drop back down
	local trainingActive = false
	local lastGroupNotified = 1
	trainService.GroupBoost:Connect(function(mult: number)
		if not trainingActive then -- in-flight fire after a local stop must not toast
			lastGroupNotified = 1
			return
		end
		if UIController.Notify then
			if mult > 1 then
				-- green when the group grew, gray when someone left but a boost remains
				local color = if mult >= lastGroupNotified then Color3.fromRGB(90, 235, 110) else Color3.fromRGB(190, 190, 190)
				UIController.Notify("Group Training: " .. string.format("%g", mult) .. "x XP!", color)
			elseif lastGroupNotified > 1 then
				UIController.Notify("Group Training ended", Color3.fromRGB(190, 190, 190))
			end
		end
		lastGroupNotified = mult
	end)

	task.spawn(function()
		while true do
			refreshGradients()
			task.wait(1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.3)
			if trainSound.IsPlaying and os.clock() - lastTrainTick > 0.7 then
				trainSound:Stop()
			end
		end
	end)

	local trainSession = 0
	local moveConn: RBXScriptConnection? = nil

	-- already training no prompt
	local function setPromptsEnabled(enabled: boolean)
		for _, pad in trainPads() do
			local prompt = pad:FindFirstChild("TrainPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = enabled
			end
		end
	end

	local function leaveButton(): GuiButton?
		local playerGui = player:FindFirstChild("PlayerGui")
		local gui = playerGui and playerGui:FindFirstChild("ScreenGui")
		local bottom = gui and gui:FindFirstChild("BottomFrame")
		local btn = bottom and bottom:FindFirstChild("LeaveButton")
		return if btn and btn:IsA("GuiButton") then btn else nil
	end

	local function stopLocal()
		if moveConn then moveConn:Disconnect(); moveConn = nil end
		if not trainingActive then return end
		trainingActive = false
		lastGroupNotified = 1
		if trainTrack and trainTrack.IsPlaying then trainTrack:Stop(0) end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then Workspace.CurrentCamera.CameraSubject = humanoid end
		setPromptsEnabled(true)
		local btn = leaveButton()
		if btn then btn.Visible = false end
	end

	local function requestStop()
		trainService.StopRequest:Fire()
		stopLocal()
	end

	trainService.TrainingStarted:Connect(function(padName: string)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local pad = findPad(padName)
		if not (humanoid and hrp and hrp:IsA("BasePart") and pad and pad:IsA("BasePart")) then return end
		trainingActive = true
		hrp.AssemblyLinearVelocity = Vector3.zero
		-- the orbit anim is authored axis-aligned
		local look = hrp.CFrame.LookVector
		local yaw = math.round(math.atan2(-look.X, -look.Z) / (math.pi / 2)) * (math.pi / 2)
		hrp.CFrame = CFrame.new(pad.Position.X, hrp.Position.Y, pad.Position.Z) * CFrame.Angles(0, yaw, 0)
		-- camera follows the animated head, staying bound to the character as it circles
		local head = (character :: Model):FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			Workspace.CurrentCamera.CameraSubject = head
		end
		trainSession += 1
		local session = trainSession
		setPromptsEnabled(false)
		local btn = leaveButton()
		if btn then btn.Visible = true end
		-- moving cuts training the same frame (a poll would read as lag-back)
		if moveConn then moveConn:Disconnect() end
		local hum = humanoid :: Humanoid
		moveConn = hum:GetPropertyChangedSignal("MoveDirection"):Connect(function()
			if hum.MoveDirection.Magnitude > 0.05 then requestStop() end
		end)
		-- better grounds spin the orbit faster
		local ground = TrainConfig.Grounds[padName]
		local speed = ground and ground.AnimSpeed or 1
		local track = getTrainTrack() -- can wait on the Animator bail if training ended meanwhile
		if track and trainingActive and trainSession == session then
			track:Play(0.2)
			track:AdjustSpeed(speed)
			-- a still-downloading clip "plays" with Length 0 and shows nothing, leaving you standing in the middle of the pad replay once the clip actually arrives
			if track.Length == 0 then
				task.spawn(function()
					local deadline = os.clock() + 10
					while track.Length == 0 and os.clock() < deadline do task.wait(0.1) end
					if trainingActive and trainSession == session and track.Length > 0 then
						track:Stop(0)
						track:Play(0.2)
						track:AdjustSpeed(speed)
					end
				end)
			end
		end
	end)

	trainService.TrainingStopped:Connect(stopLocal)
	player.CharacterAdded:Connect(stopLocal)

	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
		local btn = gui:WaitForChild("BottomFrame"):WaitForChild("LeaveButton")
		if btn:IsA("GuiButton") then
			btn.Visible = false
			btn.Activated:Connect(requestStop)
		end
	end)
end

return TrainController