--!strict
local TrainConfig = {}

TrainConfig.Interval = 1 / 6 -- seconds between XP ticks while standing on a ground

export type Ground = {
	Rebirths: number?, -- required rebirths to use (nil for Robux grounds)
	Robux: number?,    -- Robux price shown on the billboard
	GamepassId: number?,
	Multiplier: number,
	AnimSpeed: number?, -- orbit animation playback rate (better grounds spin faster)
}

TrainConfig.Grounds = {
	Bronze = { Rebirths = 0, Multiplier = 1.5, AnimSpeed = 1 },
	Silver = { Rebirths = 1, Multiplier = 2, AnimSpeed = 1.15 },
	Gold = { Rebirths = 3, Multiplier = 2.5, AnimSpeed = 1.3 },
	Ice = { Rebirths = 5, Multiplier = 3, AnimSpeed = 1.45 },
	Purple = { Robux = 90, GamepassId = 1949547046, Multiplier = 4, AnimSpeed = 1.6 },
	Red = { Robux = 9, GamepassId = 1947555129, Multiplier = 2.5, AnimSpeed = 1.3 },
	-- world 2 continues world 1's ladder: its rebirth gates shifted by 5 (0/1/3/5 -> 5/6/8/10)
	Alien = { Rebirths = 5, Multiplier = 3, AnimSpeed = 1.2 },
	Plasma = { Rebirths = 6, Multiplier = 3.5, AnimSpeed = 1.35 },
	Cobalt = { Rebirths = 8, Multiplier = 4, AnimSpeed = 1.5 },
	Comet = { Rebirths = 10, Multiplier = 4.5, AnimSpeed = 1.65 },
	Solar = { Robux = 90, GamepassId = 1962342337, Multiplier = 5, AnimSpeed = 1.8 },
	Eclipse = { Robux = 18, GamepassId = 1963422323, Multiplier = 3.5, AnimSpeed = 1.5 },
} :: { [string]: Ground }

-- RebirthLoader gradient
TrainConfig.Gradients = {
	Bronze = { Color3.fromRGB(125, 70, 25), Color3.fromRGB(230, 160, 95) },
	Silver = { Color3.fromRGB(110, 110, 115), Color3.fromRGB(228, 228, 233) },
	Gold = { Color3.fromRGB(255, 94, 0), Color3.fromRGB(255, 247, 0) },
	Ice = { Color3.fromRGB(55, 145, 220), Color3.fromRGB(190, 240, 255) },
	Red = { Color3.fromRGB(150, 15, 15), Color3.fromRGB(255, 95, 95) },
	Purple = { Color3.fromRGB(20, 0, 35), Color3.fromRGB(160, 60, 230) },
	Alien = { Color3.fromRGB(20, 140, 90), Color3.fromRGB(120, 255, 190) },
	Plasma = { Color3.fromRGB(170, 25, 170), Color3.fromRGB(255, 120, 255) },
	Cobalt = { Color3.fromRGB(25, 70, 190), Color3.fromRGB(110, 190, 255) },
	Comet = { Color3.fromRGB(200, 90, 15), Color3.fromRGB(255, 190, 90) },
	Solar = { Color3.fromRGB(230, 90, 10), Color3.fromRGB(255, 235, 70) },
	Eclipse = { Color3.fromRGB(20, 20, 25), Color3.fromRGB(235, 240, 255) },
}

return TrainConfig