return {
	Name = "setdata",
	Aliases = {},
	Description = "Sets a player's data value (Level, Rebirth, Wins, XP, ...).",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "player", Name = "Player", Description = "Whose data to change" },
		{ Type = "dataStat", Name = "Key", Description = "Which value to set" },
		{ Type = "number", Name = "Value", Description = "The new value" },
	},
}
