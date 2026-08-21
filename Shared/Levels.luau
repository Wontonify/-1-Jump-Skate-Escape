--!strict
local Levels = {}

-- XP required to go from one level to next
Levels.Base = 60
Levels.Growth = 1.22

function Levels.RequirementFor(level: number): number
	if level < 1 then level = 1 end
	return math.floor(Levels.Base * (Levels.Growth ^ (level - 1)) + 0.5)
end

-- jumps available per airborne boost
-- 1 to start, +1 at level 2 and then +1 every 5 levels
function Levels.JumpsFor(level: number): number
	return 1 + (if level >= 2 then 1 else 0) + math.floor(math.max(level, 0) / 5)
end

-- total XP accumulated by the time level is reached
function Levels.TotalXPFor(level: number): number
	if level <= 1 then return 0 end
	return math.floor(Levels.Base * ((Levels.Growth ^ (level - 1)) - 1) / (Levels.Growth - 1) + 0.5)
end

return Levels






