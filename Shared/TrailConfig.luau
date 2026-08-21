--!strict
local TrailConfig = {}

export type Trail = {
	Wins: number,
	Robux: number,
	GamepassId: number, -- 0 = not purchasable with Robux (button hidden)
	Multiplier: number, -- wins multiplier while equipped
	Color: Color3, -- UI card tint
}

TrailConfig.Order = { "Green", "White", "Red", "Orange", "Purple", "Black", "Gold", "Bubble" }

TrailConfig.Trails = {
	Green  = { Wins = 10,    Robux = 0,   GamepassId = 0,          Multiplier = 1.5,  Color = Color3.fromRGB(85, 255, 100) },
	White  = { Wins = 25,    Robux = 0,   GamepassId = 0,          Multiplier = 1.75, Color = Color3.fromRGB(255, 255, 255) },
	Red    = { Wins = 100,   Robux = 0,   GamepassId = 0,          Multiplier = 2,    Color = Color3.fromRGB(255, 70, 70) },
	Orange = { Wins = 500,   Robux = 0,   GamepassId = 0,          Multiplier = 2.5,  Color = Color3.fromRGB(255, 150, 40) },
	Purple = { Wins = 2000,  Robux = 0,   GamepassId = 0,          Multiplier = 3,    Color = Color3.fromRGB(170, 85, 255) },
	Black  = { Wins = 5000,  Robux = 0,   GamepassId = 0,          Multiplier = 3.5,  Color = Color3.fromRGB(70, 70, 70) },
	Gold   = { Wins = 12500, Robux = 225, GamepassId = 1940485472, Multiplier = 4,    Color = Color3.fromRGB(255, 200, 50) },
	Bubble = { Wins = 25000, Robux = 450, GamepassId = 1941949446, Multiplier = 5,    Color = Color3.fromRGB(130, 200, 255) },
} :: { [string]: Trail }

function TrailConfig.FormatMultiplier(mult: number): string
	return "x" .. (string.format("%.2f", mult):gsub("%.?0+$", ""))
end

return TrailConfig
