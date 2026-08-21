--!strict
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(RS.Packages.Knit)
local DataService = require(script.Parent.DataService)
local XPService = require(script.Parent.XPService)
local PassService = require(script.Parent.PassService)

local AdminService = Knit.CreateService({
	Name = "AdminService",
	Client = {},
})

local TOPIC = "SkateAdminEvent"
local speedToken = 0
local jumpsToken = 0

local DATA_KEYS = {
	Level = true, Rebirth = true, Wins = true, XP = true, LevelProgress = true,
	ExtraJumps = true, SpeedUpgrade = true, Jumps = true, Playtime = true,
}

function AdminService:SetData(player: Player, key: string, value: number): string
	if not DATA_KEYS[key] then return "Unknown data key: " .. tostring(key) end
	if not DataService:GetData(player) then return "No data loaded for " .. player.Name end
	local setter = (DataService :: any)["Set" .. key]
	setter(DataService, player, value)
	-- every derived stat re-derives PPC, walkspeed, jump pool, shop/upgrade attributes
	XPService:RefreshXPPerStep(player)
	PassService:Refresh(player)
	return player.Name .. "'s " .. key .. " is now " .. value
end

-- timed server-wide boosts ride workspace attributes so every client receives it
local function reapplyAllWalkspeeds()
	for _, p in Players:GetPlayers() do
		task.spawn(function() PassService:Refresh(p) end)
	end
end

function AdminService:StartSpeedEvent(mult: number, duration: number)
	speedToken += 1
	local token = speedToken
	Workspace:SetAttribute("EventSpeedMult", mult)
	Workspace:SetAttribute("EventSpeedUntil", os.time() + duration)
	reapplyAllWalkspeeds()
	task.delay(duration, function()
		if speedToken ~= token then return end -- a newer event took over
		Workspace:SetAttribute("EventSpeedMult", nil)
		Workspace:SetAttribute("EventSpeedUntil", nil)
		reapplyAllWalkspeeds()
	end)
end

function AdminService:StartJumpsEvent(duration: number)
	jumpsToken += 1
	local token = jumpsToken
	Workspace:SetAttribute("EventJumpsUntil", os.time() + duration)
	task.delay(duration, function()
		if jumpsToken ~= token then return end
		Workspace:SetAttribute("EventJumpsUntil", nil)
	end)
end

function AdminService:Broadcast(kind: string, mult: number?, duration: number): string
	local ok = pcall(function()
		MessagingService:PublishAsync(TOPIC, { kind = kind, mult = mult, duration = duration })
	end)
	if ok then return "" end
	if kind == "Speed" then
		self:StartSpeedEvent(mult or 2, duration)
	else
		self:StartJumpsEvent(duration)
	end
	return " (messaging unavailable, ran on this server only)"
end

function AdminService:KnitInit()
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if typeof(data) ~= "table" then return end
			if data.kind == "Speed" then
				self:StartSpeedEvent(tonumber(data.mult) or 2, tonumber(data.duration) or 60)
			elseif data.kind == "Jumps" then
				self:StartJumpsEvent(tonumber(data.duration) or 60)
			end
		end)
	end)
end

return AdminService