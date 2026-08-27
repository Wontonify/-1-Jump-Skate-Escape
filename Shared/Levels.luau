--!strict
local Levels = {}

-- XP required to go from one level to next, per world
Levels.Curves = {
	{ Base = 60, Growth = 1.22 },
	{ Base = 310, Growth = math.sqrt(1.22) },
}

local function curveFor(world: number?)
	return Levels.Curves[world or 1] or Levels.Curves[1]
end

function Levels.RequirementFor(level: number, world: number?): number
	if level < 1 then level = 1 end
	local c = curveFor(world)
	return math.floor(c.Base * (c.Growth ^ (level - 1)) + 0.5)
end

-- walkspeed earned per level, indexed by world world 2 pays half
Levels.SpeedPerLevel = { 1, 0.5 }

function Levels.SpeedFromLevel(level: number, world: number?): number
	return math.max(level - 1, 0) * (Levels.SpeedPerLevel[world or 1] or 1)
end

function Levels.JumpsFor(level: number): number
	return 1 + (if level >= 2 then 1 else 0) + math.floor(math.max(level, 0) / 5)
end

-- total XP accumulated by the time level is reached
function Levels.TotalXPFor(level: number, world: number?): number
	if level <= 1 then return 0 end
	local c = curveFor(world)
	return math.floor(c.Base * ((c.Growth ^ (level - 1)) - 1) / (c.Growth - 1) + 0.5)
end

return Levels