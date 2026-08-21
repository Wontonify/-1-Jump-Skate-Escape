return {
	Name = "globalspeedmult",
	Aliases = {},
	Description = "Gives EVERY live server a speed multiplier for a while.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "number", Name = "Multiplier", Description = "e.g. 2 for 2x speed" },
		{ Type = "number", Name = "Duration", Description = "How long it lasts, in seconds" },
	},
}
