local SkateboardConfig = {}

SkateboardConfig.Boards = {
	{ Name = "Green", Asset = "Green Skate", XP = 1, Wins = 0 },
	{ Name = "Red", Asset = "Red Skate", XP = 2, Wins = 1 },
	{ Name = "Blue", Asset = "Water Skate", XP = 5, Wins = 5 },
	{ Name = "Gold", Asset = "Golden Skate", XP = 10, Wins = 50 },
	{ Name = "Bright Gold", Asset = "Godly Skate", XP = 15, Wins = 250 },
	{ Name = "Bright Purple", Asset = "Love Skate", XP = 20, Wins = 1200 },
	{ Name = "Banana", Asset = "Fire Skate", XP = 25, Wins = 7000 },
	{ Name = "White Angel", Asset = "Light Skate", XP = 30, Wins = 40000 },
	{ Name = "Snow Angel", Asset = "White Void Skate", XP = 35, Wins = 250000 },
	{ Name = "Water", Asset = "Water Skate 2", XP = 20, Robux = 45, GamepassId = 1940239118 },
	{ Name = "Invisible", Asset = "Glass Skate", XP = 25, Robux = 45, GamepassId = 1940629137 },
	{ Name = "Dark", Asset = "Void Skate", XP = 45, Robux = 360, GamepassId = 1940353090 },
}

SkateboardConfig.DefaultBoard = "Green" -- free board

function SkateboardConfig.ByName(name)
	for _, entry in SkateboardConfig.Boards do
		if entry.Name == name then return entry end
	end
	return nil
end

function SkateboardConfig.ByAsset(assetName)
	for _, entry in SkateboardConfig.Boards do
		if entry.Asset == assetName then return entry end
	end
	return nil
end
SkateboardConfig.BoardScale = 0.5859    -- scale down board to fit anim

return SkateboardConfig


