--!strict
local Workspace = game:GetService("Workspace")

local Worlds = {}

Worlds.Count = 2

function Worlds.Folder(world: number): Folder?
	local f = Workspace:FindFirstChild("World " .. world)
	return if f and f:IsA("Folder") then f else nil
end

function Worlds.List(): { Folder }
	local list = {}
	for world = 1, Worlds.Count do
		local f = Worlds.Folder(world)
		if f then table.insert(list, f) end
	end
	return list
end

function Worlds.WaitList(timeout: number?): { Folder }
	local list = {}
	for world = 1, Worlds.Count do
		local f = Workspace:WaitForChild("World " .. world, timeout or 10)
		if f and f:IsA("Folder") then table.insert(list, f) end
	end
	return list
end

function Worlds.Of(inst: Instance): number
	for world = 1, Worlds.Count do
		local f = Worlds.Folder(world)
		if f and inst:IsDescendantOf(f) then return world end
	end
	return 1
end

function Worlds.PlayerWorld(player: Player): number
	return (player:GetAttribute("World") :: number?) or 1
end

function Worlds.SpawnCFrame(world: number): CFrame
	local folder = Worlds.Folder(world)
	local map = folder and folder:FindFirstChild("Map")
	local pad = map and map:FindFirstChild("Spawn")
	if pad and pad:IsA("BasePart") then
		return pad.CFrame + Vector3.new(0, 4, 0)
	end
	local sp = Workspace:FindFirstChild("SpawnLocation")
	if sp and sp:IsA("BasePart") then
		return sp.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 10, 0)
end

return Worlds