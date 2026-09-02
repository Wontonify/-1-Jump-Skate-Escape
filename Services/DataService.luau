local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)
local ProfileStore = require(RS.Packages.ProfileStore)

local PROFILE_TEMPLATE = {
	XP = 0,      -- lifetime XP this rebirth
	Wins = 0,    -- shop currency
	Board = "Green", -- equipped skateboard
	OwnedBoards = { "Green" }, --all owned boards
	OwnedTrains = {}, -- rbx training grounds
	Trail = "", -- equipped trail (TrailConfig name, "" = none)
	Trails = {}, -- owned trails
	Level = 1,
	LevelProgress = 0,   -- XP banked toward the next level (independent of the lifetime XP total)
	Rebirth = 0,
	Jumps = 0, -- lifetime jumps performed
	ExtraJumps = 0, -- +1 Jump purchases upgrade shop or rbx product
	SpeedUpgrade = 0, -- upgrade shop Speed level
	StarterPack = false, -- one-time Robux pack +1 Jump, +3 Speed, Green trail
	Playtime = 0, -- lifetime seconds in game
	DailyStreak = 0, -- consecutive daily rewards claimed (1-7, 0 = none yet)
	DailyLast = 0,   -- os.time of the last daily claim
	World = 1, -- current world; follows the player through portals
	MaxWorld = 1, -- highest world reached; the course-end portal raises it
}

local GameProfileStore = ProfileStore.New("PlayerData_v1", PROFILE_TEMPLATE)

local DataService = Knit.CreateService({
	Name = "DataService",
	Profiles = {} :: { [Player]: any },
	BeforeSessionEnd = {} :: { (Player) -> () },

	Client = {},
})

local function setupValues(player: Player, data)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = data.Wins
	wins.Parent = ls

	-- non-leaderboard live values 4 client
	local dataFolder = Instance.new("Folder")
	dataFolder.Name = "data"
	dataFolder.Parent = player

	local function num(name, value)
		local v = Instance.new("NumberValue")
		v.Name = name
		v.Value = value
		v.Parent = dataFolder
	end
	num("Level", data.Level)
	num("LevelProgress", data.LevelProgress)
	num("Rebirth", data.Rebirth)
	num("Jumps", data.Jumps or 0)
end

local function mirror(player: Player, name: string, value: number)
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild(name) then
		ls[name].Value = value
		return
	end
	local dataFolder = player:FindFirstChild("data")
	if dataFolder and dataFolder:FindFirstChild(name) then
		dataFolder[name].Value = value
	end
end

local function onPlayerAdded(player: Player)
	local profile = GameProfileStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent == nil
		end,
	})

	if not profile then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end

	if player.Parent == nil then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	-- pre-rework saves stored lifetime XP under "Power" carry it over once
	if profile.Data.Power ~= nil then
		if profile.Data.Power > (profile.Data.XP or 0) then profile.Data.XP = profile.Data.Power end
		profile.Data.Power = nil
	end
	if profile.Data.Level < 1 then profile.Data.Level = 1 end
	-- pre-MaxWorld saves count wherever they stand as reached
	if (profile.Data.MaxWorld or 1) < (profile.Data.World or 1) then
		profile.Data.MaxWorld = profile.Data.World
	end
	-- the equipped board must always be owned
	if not table.find(profile.Data.OwnedBoards, profile.Data.Board) then
		table.insert(profile.Data.OwnedBoards, profile.Data.Board)
	end

	DataService.Profiles[player] = profile

	profile.OnSessionEnd:Connect(function()
		DataService.Profiles[player] = nil
		player:Kick("Your data session ended (opened elsewhere). Please rejoin.")
	end)

	setupValues(player, profile.Data)
	DataService:PublishBoards(player)
	player:SetAttribute("World", profile.Data.World or 1)
end

local function onPlayerRemoving(player: Player)
	local profile = DataService.Profiles[player]
	if profile then
		for _, fn in DataService.BeforeSessionEnd do
			pcall(fn, player)
		end
		profile:EndSession()
		DataService.Profiles[player] = nil
	end
end

function DataService:WaitForData(player: Player, timeout: number?)
	local waited = 0
	local limit = timeout or 15
	while not self.Profiles[player] and waited < limit do
		if player.Parent == nil then return nil end
		task.wait(0.05)
		waited += 0.05
	end
	local profile = self.Profiles[player]
	return profile and profile.Data or nil
end

function DataService:GetData(player: Player)
	local profile = self.Profiles[player]
	return profile and profile.Data or nil
end

-- adds Get<name>/Set<name>/Add<name> + mirrors the leaderstats value
local function makeStat(name: string)
	DataService["Get" .. name] = function(self, player)
		local d = self:GetData(player); return d and d[name] or 0
	end
	DataService["Set" .. name] = function(self, player, amount)
		local d = self:GetData(player); if not d then return end
		d[name] = math.max(0, amount)
		mirror(player, name, d[name])
	end
	DataService["Add" .. name] = function(self, player, amount)
		local d = self:GetData(player); if not d then return end
		d[name] = math.max(0, (d[name] or 0) + amount)
		mirror(player, name, d[name])
	end
end
makeStat("XP")
makeStat("Money")
makeStat("Wins")
makeStat("Level")
makeStat("LevelProgress")
makeStat("Rebirth")
makeStat("Jumps")
makeStat("Playtime")
makeStat("ExtraJumps")
makeStat("SpeedUpgrade")

-- boards equipped name + owned set, published as attributes for the client shop UI
function DataService:PublishBoards(player: Player)
	local d = self:GetData(player); if not d then return end
	player:SetAttribute("Board", d.Board)
	player:SetAttribute("OwnedBoards", table.concat(d.OwnedBoards, "|"))
	player:SetAttribute("OwnedTrains", table.concat(d.OwnedTrains or {}, "|"))
end

function DataService:GetWorld(player: Player): number
	local d = self:GetData(player); return d and d.World or 1
end

function DataService:SetWorld(player: Player, world: number)
	local d = self:GetData(player); if not d then return end
	d.World = world
	d.MaxWorld = math.max(d.MaxWorld or 1, world)
	player:SetAttribute("World", world)
end

function DataService:GetMaxWorld(player: Player): number
	local d = self:GetData(player); return d and d.MaxWorld or 1
end

function DataService:GetBoard(player: Player): string
	local d = self:GetData(player); return d and d.Board or "Green"
end

function DataService:SetBoard(player: Player, name: string)
	local d = self:GetData(player); if not d then return end
	d.Board = name
	self:PublishBoards(player)
end

function DataService:OwnsBoard(player: Player, name: string): boolean
	local d = self:GetData(player); if not d then return false end
	return table.find(d.OwnedBoards, name) ~= nil
end

function DataService:UnlockBoard(player: Player, name: string)
	local d = self:GetData(player); if not d then return end
	if table.find(d.OwnedBoards, name) then return end
	table.insert(d.OwnedBoards, name)
	self:PublishBoards(player)
end

function DataService:KnitInit()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService