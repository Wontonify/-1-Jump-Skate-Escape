--!strict
local GamepassConfig = {}

export type Pass = { Id: number, Mult: number, Price: number }

GamepassConfig.Wins = {
	{ Id = 1940406665, Mult = 2, Price = 149 },
	{ Id = 1940418649, Mult = 4, Price = 299 },
	{ Id = 1941378607, Mult = 8, Price = 499 },
	{ Id = 1940388596, Mult = 16, Price = 999 },
} :: { Pass }

-- 2x/4x/8x/16x/32x XP gamepass on rightframe
GamepassConfig.XP = {
	{ Id = 1941012641, Mult = 2, Price = 3 },
	{ Id = 1941078643, Mult = 4, Price = 9 },
	{ Id = 1941024657, Mult = 8, Price = 27 },
	{ Id = 1943508603, Mult = 16, Price = 81 },
	{ Id = 1940544619, Mult = 32, Price = 99 },
} :: { Pass }

GamepassConfig.Speed = { Id = 1943652578, Mult = 2, Price = 99 }
GamepassConfig.DoubleJumps = { Id = 1948286841, Price = 1800 }

GamepassConfig.PermanentRevive = { Id = 1949217106 }
-- one-time revive sold by the death countdown popup
GamepassConfig.ReviveProduct = { Id = 3708335665, Price = 9 }
GamepassConfig.JumpProduct = { Id = 3645885179, Price = 29 }

-- xp buttons on bottomframe
GamepassConfig.XPProducts = {
	Plus50KXP = { Id = 3708190819, Amount = 50000 },
	Plus250KXP = { Id = 3708190992, Amount = 250000 },
	Plus500KXP = { Id = 3708191041, Amount = 500000 },
}
-- purple pad skip stage
GamepassConfig.SkipStageProducts = {
	{ Id = 3669797413, Price = 9 },
	{ Id = 3708703571, Price = 6 },
	{ Id = 3708703645, Price = 9 },
	{ Id = 3708703671, Price = 14 },
	{ Id = 3708703684, Price = 21 },
	{ Id = 3708703717, Price = 27 },
	{ Id = 3708703747, Price = 34 },
	{ Id = 3708703782, Price = 39 },
	{ Id = 3708703798, Price = 49 },
	{ Id = 3708703817, Price = 67 },
	{ Id = 3708703869, Price = 79 },
}
GamepassConfig.StarterPackProduct = { Id = 3708678282, Price = 49 }
GamepassConfig.LevelProduct = { Id = 3708679922 }
GamepassConfig.SkipRebirthProduct = { Id = 3669823210, Price = 49 }

GamepassConfig.VIP = {
	Id = 1941456612,
	WinsMult = 2,
	XPMult = 2,
	Trail = "Green",
	BonusJumps = 2,
}

return GamepassConfig