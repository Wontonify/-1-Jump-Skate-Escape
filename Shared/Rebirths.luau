--!strict
local Rebirths = {}

-- max level = 10 per rebirth tier rebirth 0 -> 10
function Rebirths.MaxLevelFor(rebirth: number): number
	return 10 * (rebirth + 1)
end

-- +0.5x xp per rebirth
function Rebirths.MultiplierFor(rebirth: number): number
	return 1 + 0.5 * rebirth
end

-- formatting to multi
function Rebirths.FormatMultiplier(rebirth: number): string
	local m = Rebirths.MultiplierFor(rebirth)
	return (string.format("%.1f", m):gsub("%.0$", "")) .. "x"
end

return Rebirths
