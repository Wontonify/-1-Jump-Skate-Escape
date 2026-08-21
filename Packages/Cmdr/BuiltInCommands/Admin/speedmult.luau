return {
	Name = "speedmult",
	Aliases = {},
	Description = "Gives everyone in THIS server a speed multiplier for a while.",
	Group = "DefaultAdmin",
	Args = {
		{ Type = "number", Name = "Multiplier", Description = "e.g. 2 for 2x speed" },
		{ Type = "number", Name = "Duration", Description = "How long it lasts, in seconds" },
	},
}

