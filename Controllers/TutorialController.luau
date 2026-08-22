--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local SkateboardConfig = require(RS:WaitForChild("Shared"):WaitForChild("SkateboardConfig"))
local Levels = require(RS:WaitForChild("Shared"):WaitForChild("Levels"))
local Upgrades = require(RS:WaitForChild("Shared"):WaitForChild("Upgrades"))
local UtilController = require(script.Parent.UtilController)

local player = Players.LocalPlayer

local TutorialController = Knit.CreateController({
	Name = "TutorialController",
})

local GOLD = Color3.fromRGB(255, 216, 102)
local STEP_SOUND = 107978604605265
local LEVEL_GOAL = 2

local function level(): number
	local data = player:FindFirstChild("data")
	local v = data and data:FindFirstChild("Level")
	return if v and v:IsA("NumberValue") then v.Value else 1
end
local function levelProgress(): number
	local data = player:FindFirstChild("data")
	local v = data and data:FindFirstChild("LevelProgress")
	return if v and v:IsA("NumberValue") then v.Value else 0
end
local function wins(): number
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Wins")
	return if v and v:IsA("IntValue") then v.Value else 0
end
local function ownedBoards(): { string }
	return string.split((player:GetAttribute("OwnedBoards") :: string?) or "", "|")
end
local function ownedCount(): number
	local n = 0
	for _, name in ownedBoards() do
		if name ~= "" then n += 1 end
	end
	return n
end
local function jumpUpgrades(): number
	return (player:GetAttribute("ExtraJumps") :: number?) or 0
end
local function nextBoard()
	local owned = ownedBoards()
	for _, entry in SkateboardConfig.Boards do
		if entry.Wins and entry.Wins > 0 and not table.find(owned, entry.Name) then
			return entry
		end
	end
	return nil
end

local function pivotOf(inst: Instance?): Vector3?
	if inst and inst:IsA("Model") then return inst:GetPivot().Position end
	if inst and inst:IsA("BasePart") then return inst.Position end
	return nil
end
local function findPath(...): Instance?
	local node: Instance? = Workspace
	for _, name in { ... } do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end
local function winPadPos(): Vector3?
	return pivotOf(findPath("WinsPads", "1"))
end

local STEPS = {
	{
		text = function()
			local req = Levels.RequirementFor(1)
			return "Train on the railing to reach Level " .. LEVEL_GOAL .. "!  ("
				.. UtilController.Short(math.min(levelProgress(), req)) .. "/" .. UtilController.Short(req) .. ")"
		end,
		done = function() return level() >= LEVEL_GOAL or wins() >= 1 or ownedCount() >= 2 end,
		target = function() return pivotOf(findPath("Train", "Bronze")) end,
	},
	{
		text = function() return "Ride the course to the 1st Win Pad and cash out!" end,
		-- buying the 2nd board can spend the wins back to 0 owning it still counts as done
		done = function() return wins() >= 1 or ownedCount() >= 2 end,
		target = winPadPos,
	},
	{
		-- short on wins the objective points back at the run affordable it points at the stand
		text = function()
			local entry = nextBoard()
			if not entry then return nil end
			if wins() < entry.Wins then
				return "Do more runs \u{2014} " .. UtilController.Short(entry.Wins) .. " Wins buys the next Skateboard!"
			end
			return "Buy the next Skateboard at the Wins Shop!"
		end,
		done = function() return ownedCount() >= 2 end,
		target = function()
			local entry = nextBoard()
			if not entry then return nil end
			if wins() < entry.Wins then return winPadPos() end
			return pivotOf(findPath("Shop", entry.Asset))
		end,
	},
	{
		-- stays silent until the wins are banked, then points straight at the stand
		text = function()
			if wins() < (Upgrades.JumpCosts[1] or 0) then return nil end
			return "Buy +1 Jump at the Upgrades stand!"
		end,
		done = function() return jumpUpgrades() >= 1 end,
		target = function()
			if wins() < (Upgrades.JumpCosts[1] or 0) then return nil end
			return pivotOf(findPath("Map", "Upgrade"))
		end,
	},
}

local currentStep = 0
local shownStep = 0
local beam: Beam? = nil
local beacon: BasePart? = nil
local objLabel: TextLabel? = nil
local stepSound: Sound? = nil
local staticBeam: Beam? = nil
local finished = false
local conns: { RBXScriptConnection } = {}

-- notification template but stays
local function makeObjective()
	local container = player:WaitForChild("PlayerGui"):WaitForChild("Notifications", 10)
	container = container and container:WaitForChild("Container", 10)
	local template = container and container:FindFirstChild("Template")
	if not (container and template and template:IsA("TextLabel")) then return end
	local label = template:Clone()
	label.Name = "TutorialObjective"
	label.LayoutOrder = -1000 -- pinned above the passing toasts
	label.Text = ""
	label.TextColor3 = GOLD
	label.TextTransparency = 0
	label.Visible = true
	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if stroke then stroke.Transparency = 0 end
	label.Parent = container
	objLabel = label

	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. STEP_SOUND
	s.Volume = 0.6
	s.Parent = SoundService
	stepSound = s
end

local function dingStep()
	if stepSound then
		stepSound.TimePosition = 0
		stepSound:Play()
	end
end

local function makeBeam()
	local t = RS:FindFirstChild("Assets")
	t = t and t:FindFirstChild("Attachments")
	t = t and t:FindFirstChild("ArrowBeam")
	if not (t and t:IsA("Beam")) then return end

	local part = Instance.new("Part")
	part.Name = "TutorialBeacon"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = Workspace
	beacon = part

	local targetAtt = Instance.new("Attachment")
	targetAtt.Name = "TutAttTarget"
	targetAtt.Parent = part

	local b = t:Clone()
	b.Attachment1 = targetAtt -- arrows flow toward the goal
	b.Enabled = false
	b.Parent = part
	beam = b

	local beamFolder = Workspace:FindFirstChild("Beam")
	staticBeam = beamFolder and beamFolder:FindFirstChildOfClass("Beam")
	if staticBeam then staticBeam.Enabled = false end -- one arrow at a time, restored on finish
end

local function attachToChar(char: Model)
	if not beam then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
	if not (hrp and hrp:IsA("BasePart")) then return end
	local bodyAtt = hrp:FindFirstChild("TutAttBody")
	if not bodyAtt then
		bodyAtt = Instance.new("Attachment")
		bodyAtt.Name = "TutAttBody"
		bodyAtt.Parent = hrp
	end
	beam.Attachment0 = bodyAtt
end

local function refreshArrow()
	local b, part = beam, beacon
	if not (b and part) or finished then return end
	local step = STEPS[currentStep]
	local pos = step and step.target()
	if pos and b.Attachment0 then
		part.Position = pos + Vector3.new(0, 1.5, 0)
		b.Enabled = true
	else
		b.Enabled = false
	end
end

local function finish()
	if finished then return end
	finished = true
	for _, c in conns do
		pcall(function() c:Disconnect() end)
	end
	if beam then beam:Destroy() end
	if beacon then beacon:Destroy() end
	if staticBeam then staticBeam.Enabled = true end
	dingStep()
	local label = objLabel
	if label then
		label.Text = "Tutorial complete \u{2014} good luck!"
		task.delay(4, function() label:Destroy() end)
	end
end

-- first not-yet-done step drives the objective + arrow; nil text hides both
local function evaluate()
	if finished then return end
	local i = 1
	while i <= #STEPS and STEPS[i].done() do i += 1 end
	if i > #STEPS then
		finish()
		return
	end
	currentStep = i
	local txt = STEPS[i].text()
	if objLabel then
		if txt then
			if shownStep ~= i then dingStep() end
			objLabel.Text = txt
			objLabel.Visible = true
			shownStep = i
		else
			objLabel.Visible = false
			shownStep = 0
		end
	end
	refreshArrow()
end

function TutorialController:KnitStart()
	-- wait for the join publish before judging
	local deadline = os.clock() + 20
	while (player:GetAttribute("OwnedBoards") == nil or player:GetAttribute("ExtraJumps") == nil)
		and os.clock() < deadline do
		task.wait(0.2)
	end
	if ownedCount() >= 2 and jumpUpgrades() >= 1 then return end -- past every step no tutorial

	local ls = player:WaitForChild("leaderstats", 20)
	local winsV = ls and ls:WaitForChild("Wins", 10)
	local dataFolder = player:WaitForChild("data", 20)
	local levelV = dataFolder and dataFolder:WaitForChild("Level", 10)
	local progressV = dataFolder and dataFolder:WaitForChild("LevelProgress", 10)
	if not (winsV and levelV and progressV) then return end

	makeObjective()
	makeBeam()

	if player.Character then attachToChar(player.Character) end
	table.insert(conns, player.CharacterAdded:Connect(function(char)
		attachToChar(char)
		task.wait(0.2)
		refreshArrow()
	end))

	table.insert(conns, levelV.Changed:Connect(evaluate))
	table.insert(conns, progressV.Changed:Connect(evaluate))
	table.insert(conns, winsV.Changed:Connect(evaluate))
	table.insert(conns, player:GetAttributeChangedSignal("OwnedBoards"):Connect(evaluate))
	table.insert(conns, player:GetAttributeChangedSignal("ExtraJumps"):Connect(evaluate))

	-- streaming can late-load targets re-aim once a second while the tutorial runs
	task.spawn(function()
		while not finished do
			task.wait(1)
			evaluate()
		end
	end)

	evaluate()
end

return TutorialController




