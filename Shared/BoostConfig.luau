local Levels = require(script.Parent.Levels)

local BoostConfig = {}

BoostConfig.LevelToNext = { 1, 3, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50 }
BoostConfig.JumpsToNext = { 0, 2, 3, 4, 6, 8, 11, 14, 17, 20, 23, 26 }
-- each ramp's gate in XP
BoostConfig.XPToNext = {}
for i, level in BoostConfig.LevelToNext do
	BoostConfig.XPToNext[i] = Levels.TotalXPFor(level, 1)
end

-- world 2 mirrors world 1 ramp for ramp at twice the level, and asks for the jump
BoostConfig.World2 = {
	LevelToNext = { 2, 6, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 },
	JumpsToNext = { 0, 2, 3, 5, 8, 11, 15, 20, 24, 30, 35, 40 },
	XPToNext = {},
}
for i, level in BoostConfig.World2.LevelToNext do
	BoostConfig.World2.XPToNext[i] = Levels.TotalXPFor(level, 2)
end

function BoostConfig.For(world)
	return if world == 2 then BoostConfig.World2 else BoostConfig
end

BoostConfig.MinHopStuds = 12 -- hop length at level 1
BoostConfig.MaxHopStuds = 40 -- gate-level hop length when there is no next ramp
BoostConfig.JumpBoostMin = 5 -- studs/s a mid-air jump adds at least
BoostConfig.JumpBoostFraction = 0.06 -- share of the current carry each mid-air jump adds on top
BoostConfig.ArcTime = 0.65 -- seconds the launch arc hangs before the jump chain takes over
BoostConfig.JumpPeriod = 0.55 -- seconds of carry one chained mid-air jump buys
BoostConfig.FallGrace = 0.75 -- seconds of free carry the floaty launch and final fall add beyond ArcTime
BoostConfig.CarryDamp = 0.5 -- share of the above-run-speed carry a ramp keeps: chained boosts must not compound
BoostConfig.CarryCap = 1.35 -- launch speed ceiling as a multiple of the ramp's tuned crossing speed

return BoostConfig