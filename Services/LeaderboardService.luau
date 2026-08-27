--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local TrailService = require(script.Parent.TrailService)
local Worlds = require(RS.Shared.Worlds)

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",

	Client = {
		Jumped = Knit.CreateSignal(),
	},
})

local UPDATE_INTERVAL = 300
local TOP_N = 50
local MAX_JUMPS_PER_SECOND = 8

local BOARDS = {
	{ stat = "Playtime", store = DataStoreService:GetOrderedDataStore("LB_Playtime"), model = "PlaytimeLeaderboard",
		value = function(_player: Player, data): number return data.Playtime or 0 end },
	{ stat = "Wins", store = DataStoreService:GetOrderedDataStore("LB_Wins"), model = "WinsLeaderboard",
		value = function(_player: Player, data): number return data.Wins or 0 end },
	-- the Speed board ranks actual WalkSpeed (fresh store: the old LB_Power one held lifetime XP)
	{ stat = "Speed", store = DataStoreService:GetOrderedDataStore("LB_Speed"), model = "PowerLeaderboard",
		value = function(player: Player, _data): number return TrailService:ComputeWalkSpeed(player) end },
}

local jumpBuckets: { [Player]: { t: number, n: number } } = {}
local sessionStart: { [Player]: number } = {}
local nameCache: { [number]: string } = {}

local function playerName(userId: number): string
	local cached = nameCache[userId]
	if cached then return cached end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = if ok then name else "User " .. userId
	return nameCache[userId]
end

local SUFFIXES = { "K", "M", "B", "T" }
local function short(n: number): string
	if n < 1000 then return tostring(n) end
	local v, i = n, 0
	while v >= 1000 and i < #SUFFIXES do v /= 1000; i += 1 end
	local s = string.format("%.2f", v)
	s = (s:gsub("%.?0+$", ""))
	return s .. SUFFIXES[i]
end

local function fmtTime(sec: number): string
	sec = math.floor(sec)
	if sec < 60 then return sec .. "s" end
	local m = sec // 60
	if m < 60 then return m .. "m" end
	return (m // 60) .. "h " .. (m % 60) .. "m"
end

-- unflushed session seconds move into the profile; called on the cycle and just before session end
local function flushPlaytime(player: Player)
	local started = sessionStart[player]
	if not started then return end
	local now = os.clock()
	local elapsed = math.floor(now - started)
	if elapsed > 0 then
		sessionStart[player] = started + elapsed
		DataService:AddPlaytime(player, elapsed)
	end
end

-- every world hosts its own copy of the boards; publish to all of them
local function boardGuis(modelName: string): { SurfaceGui }
	local guis = {}
	for _, worldFolder in Worlds.List() do
		local map = worldFolder:FindFirstChild("Map")
		local model = map and map:FindFirstChild(modelName)
		if not model then continue end
		for _, part in model:GetChildren() do
			local gui = part:FindFirstChildOfClass("SurfaceGui")
			if gui then
				table.insert(guis, gui)
				break
			end
		end
	end
	return guis
end

local function publish(gui: SurfaceGui, entries: { { userId: number, value: number } }, isTime: boolean)
	local sf = gui:FindFirstChild("ScrollingFrame")
	local template = sf and sf:FindFirstChild("LeaderboardEntry")
	if not (sf and template and template:IsA("Frame")) then return end
	template.Visible = false
	for _, c in sf:GetChildren() do
		if c:IsA("Frame") and c ~= template then c:Destroy() end
	end
	for rank, e in entries do
		local row = template:Clone()
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Visible = true;
		(row:FindFirstChild("RankLabel") :: TextLabel).Text = "#" .. rank;
		(row:FindFirstChild("NameLabel") :: TextLabel).Text = playerName(e.userId);
		(row:FindFirstChild("ScoreLabel") :: TextLabel).Text = if isTime then fmtTime(e.value) else short(e.value)
		row.Parent = sf
	end
	
	(sf :: ScrollingFrame).CanvasSize = UDim2.fromOffset(0, #entries * 52 + 6)
end

local function cycle()
	for _, player in Players:GetPlayers() do
		flushPlaytime(player)
	end
	for _, board in BOARDS do
		for _, player in Players:GetPlayers() do
			local data = DataService:GetData(player)
			if data then
				pcall(board.store.SetAsync, board.store, tostring(player.UserId), math.floor(board.value(player, data)))
			end
		end
		local ok, pages = pcall(board.store.GetSortedAsync, board.store, false, TOP_N)
		if not ok then
			warn("[LeaderboardService] GetSortedAsync failed for " .. board.stat)
			continue
		end
		local entries = {}
		for _, item in pages:GetCurrentPage() do
			table.insert(entries, { userId = tonumber(item.key) or 0, value = item.value })
		end
		for _, gui in boardGuis(board.model) do
			publish(gui, entries, board.stat == "Playtime")
		end
	end
end

function LeaderboardService:KnitInit()
	self.Client.Jumped:Connect(function(player: Player)
		local now = os.clock()
		local b = jumpBuckets[player]
		if not b or now - b.t >= 1 then
			b = { t = now, n = 0 }
			jumpBuckets[player] = b
		end
		b.n += 1
		if b.n > MAX_JUMPS_PER_SECOND then return end
		DataService:AddJumps(player, 1)
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService:WaitForData(player) then
				sessionStart[player] = os.clock()
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do onPlayer(p) end

	-- runs before the profile session ends so the last partial minute still saves
	table.insert(DataService.BeforeSessionEnd, flushPlaytime)

	Players.PlayerRemoving:Connect(function(p)
		flushPlaytime(p) -- connection order vs DataService is unknown; double-flush adds 0
		jumpBuckets[p] = nil
		sessionStart[p] = nil
	end)

	task.spawn(function()
		task.wait(5)
		while true do
			cycle()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return LeaderboardService