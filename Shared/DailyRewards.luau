--!strict
local DailyRewards = {}

DailyRewards.Interval = 24 * 60 * 60 -- seconds between claims
DailyRewards.Grace = 48 * 60 * 60    -- miss this window and the streak restarts at day 1

export type Day = { Type: "Wins" | "XP", Amount: number }
DailyRewards.Days = {
	{ Type = "Wins", Amount = 25 },
	{ Type = "Wins", Amount = 5000 }, -- day 2 comeback hook, deliberately outsized
	{ Type = "Wins", Amount = 7500 },
	{ Type = "XP", Amount = 25000 },
	{ Type = "Wins", Amount = 12500 },
	{ Type = "XP", Amount = 100000 },
	{ Type = "Wins", Amount = 25000 },
} :: { Day }

DailyRewards.SkipOneProduct = 0
DailyRewards.SkipAllProduct = 0

return DailyRewards