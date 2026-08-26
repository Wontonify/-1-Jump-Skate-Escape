local SkateboardConfig = {}

-- World: 1 or 2 for wins/group boards (they live in one shop); nil = the stand exists in every world
SkateboardConfig.Boards = {
	{ Name = "Green", Asset = "Green Skate", XP = 1, Wins = 0, World = 1 },
	{ Name = "Red", Asset = "Red Skate", XP = 2, Wins = 1, World = 1 },
	{ Name = "Blue", Asset = "Water Skate", XP = 5, Wins = 5, World = 1 },
	{ Name = "Gold", Asset = "Golden Skate", XP = 10, Wins = 50, World = 1 },
	{ Name = "Bright Gold", Asset = "Godly Skate", XP = 15, Wins = 250, World = 1 },
	{ Name = "Bright Purple", Asset = "Love Skate", XP = 20, Wins = 1200, World = 1 },
	{ Name = "Banana", Asset = "Fire Skate", XP = 25, Wins = 7000, World = 1 },
	{ Name = "White Angel", Asset = "Light Skate", XP = 30, Wins = 40000, World = 1 },
	{ Name = "Snow Angel", Asset = "White Void Skate", XP = 35, Wins = 250000, World = 1 },
	
	-- Elemental Skate Bundle boards, basic to cool
	{ Name = "Normal", Asset = "Normal Skate1", XP = 40, Wins = 500000, World = 2 },
	{ Name = "Normal 2", Asset = "Normal Skate2", XP = 46, Wins = 1600000, World = 2 },
	{ Name = "Wooden", Asset = "Wooden Skate", XP = 52, Wins = 5000000, World = 2 },
	{ Name = "Blocked", Asset = "Blocked Skate", XP = 60, Wins = 16000000, World = 2 },
	{ Name = "Race", Asset = "Race Skate", XP = 68, Wins = 50000000, World = 2 },
	{ Name = "Nature", Asset = "Nature Skate", XP = 76, Wins = 160000000, World = 2 },
	{ Name = "Lucky Block", Asset = "Lucky Block Skate", XP = 85, Wins = 500000000, World = 2 },
	{ Name = "Mystic", Asset = "Mystic Skate", XP = 95, Wins = 1750000000, World = 2 },
	{ Name = "Death", Asset = "Death Skate", XP = 105, Wins = 6000000000, World = 2 },
	{ Name = "Water", Asset = "Water Skate 2", XP = 20, Robux = 45, GamepassId = 1940239118 },
	{ Name = "Invisible", Asset = "Glass Skate", XP = 25, Robux = 45, GamepassId = 1940629137 },
	{ Name = "Dark", Asset = "Void Skate", XP = 45, Robux = 360, GamepassId = 1940353090 },
	{ Name = "Boned", Asset = "Boned Skate", XP = 8, Group = 521202898, World = 1 },
}

SkateboardConfig.DefaultBoard = "Green" -- free board

function SkateboardConfig.ByName(name)
	for _, entry in SkateboardConfig.Boards do
		if entry.Name == name then return entry end
	end
	return nil
end

-- the same display asset backs a different board per world, so lookups carry the shop's world
function SkateboardConfig.ByAsset(assetName, world)
	for _, entry in SkateboardConfig.Boards do
		if entry.Asset == assetName and (world == nil or entry.World == nil or entry.World == world) then
			return entry
		end
	end
	return nil
end
SkateboardConfig.BoardScale = 0.5859    -- scale down board to fit anim

return SkateboardConfig