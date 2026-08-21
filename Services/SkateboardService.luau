--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local SkateboardConfig = require(RS.Shared.SkateboardConfig)

local SkateboardService = Knit.CreateService({
	Name = "SkateboardService",

	Client = {
		Boosted = Knit.CreateSignal(),
		Fell = Knit.CreateSignal(),
	},
})

local BOARD_C0 = CFrame.new(0, -2.953238, 0) * CFrame.Angles(0, -math.pi / 2, 0) -- matches the ANIMATIONNPC Board motor
local BOARD_C1 = CFrame.Angles(0, math.pi, 0) -- nose-faces-forward flip lives on C1: applied after anim transforms, so tracks stay authored
local HIP_HEIGHT = 0.55 -- raises the character so the board's wheels rest on the ground

local function boardEntry(name: string?)
	for _, entry in SkateboardConfig.Boards do
		if entry.Name == name then return entry end
	end
	return SkateboardConfig.Boards[1]
end

function SkateboardService:GetBoardXP(player: Player): number
	local data = DataService:GetData(player)
	return boardEntry(data and data.Board).XP
end

function SkateboardService:NotifyBoosted(player: Player)
	self.Client.Boosted:Fire(player)
end

local function attachBoard(player: Player, character: Model)
	if not DataService:WaitForData(player) then return end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not (hrp and hrp:IsA("BasePart") and character.Parent) then return end

	local entry = boardEntry((DataService:GetData(player) or {}).Board)
	local asset = RS.Assets.Skateboards:FindFirstChild(entry.Asset)
	if not (asset and asset:IsA("Model")) then return end

	local old = character:FindFirstChild("Skateboard")
	if old then old:Destroy() end
	-- destroying the model does NOT remove its Motor6D from the HRP
	for _, j in hrp:GetChildren() do
		if j:IsA("Motor6D") and j.Name == "Board" then j:Destroy() end
	end

	local board = asset:Clone()
	board.Name = "Skateboard"
	board:ScaleTo(board:GetScale() * SkateboardConfig.BoardScale) -- relative assets carry their own authored scale

	local root = board:FindFirstChild("Board")
	if not (root and root:IsA("BasePart")) then return end
	for _, part in board:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if part ~= root then
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = part
				weld.C0 = root.CFrame:ToObjectSpace(part.CFrame)
				weld.Parent = root
			end
			part.Anchored = false
		end
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "Board"
	motor.Part0 = hrp
	motor.Part1 = root
	motor.C0 = BOARD_C0
	motor.C1 = BOARD_C1
	motor.Parent = hrp
	board.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HipHeight = HIP_HEIGHT
	end
end

-- re-attaches the equipped board on the live character (used by the shop on equip)
function SkateboardService:RefreshBoard(player: Player)
	local character = player.Character
	if character then
		task.spawn(attachBoard, player, character)
	end
end

-- zero friction with max weight walls can never grab the character, it slides down instead
local SLICK = PhysicalProperties.new(0.7, 0, 0, 100, 1)
local function makeSlick(character: Model)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then part.CustomPhysicalProperties = SLICK end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CustomPhysicalProperties = SLICK end
	end)
end

function SkateboardService:KnitInit()
	Players.RespawnTime = 1.5
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			makeSlick(character)
			task.spawn(attachBoard, player, character)
		end)
		-- respawn only unparents the old character
		player.CharacterRemoving:Connect(function(character)
			task.delay(1, function()
				if character.Parent == nil then character:Destroy() end
			end)
		end)
		if player.Character then
			makeSlick(player.Character)
			task.spawn(attachBoard, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return SkateboardService