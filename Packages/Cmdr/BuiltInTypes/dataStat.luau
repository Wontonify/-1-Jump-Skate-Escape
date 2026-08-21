-- Cmdr type "dataStat": which player data value the `setdata` command edits, as an
-- autocompleting enum (each key has a DataService Set<key> behind it)
local Util = require(script.Parent.Parent.Shared.Util)

return function (cmdr)
	cmdr:RegisterType("dataStat", Util.MakeEnumType("dataStat", {
		"Level", "Rebirth", "Wins", "XP", "LevelProgress",
		"ExtraJumps", "SpeedUpgrade", "Jumps", "Playtime",
	}))
end
