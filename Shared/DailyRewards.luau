--!strict
local DailyRewards = {}

DailyRewards.Interval = 24 * 60 * 60 -- seconds between claims
DailyRewards.Grace = 48 * 60 * 60    -- miss this window and the streak restarts at day 1

export type Day = { Type: "Wins" | "XP", Amount: number }
DailyRewards.Days = {
	{ Type = "Wins", Amount = 25 },
	{ Type = "XP", Amount = 2500 },
	{ Type = "Wins", Amount = 100 },
	{ Type = "XP", Amount = 10000 },
	{ Type = "Wins", Amount = 300 },
	{ Type = "XP", Amount = 50000 },
	{ Type = "Wins", Amount = 1000 },
} :: { Day }

DailyRewards.SkipOneProduct = 0
DailyRewards.SkipAllProduct = 0

return DailyRewards
