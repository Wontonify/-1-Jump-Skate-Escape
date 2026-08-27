local WinsConfig = {}

WinsConfig.PadWins = {
	[1] = 1,
	[2] = 2,
	[3] = 5,
	[4] = 12,
	[5] = 25,
	[6] = 60,
	[7] = 125,
	[8] = 300,
	[9] = 650,
	[10] = 1500,
	[11] = 3500,
	[12] = 10000,
}

-- world 1's ladder x25000: same pad-to-pad shape, and a world 1 bankroll is pocket change here
WinsConfig.PadWins2 = {
	[1] = 25000,
	[2] = 50000,
	[3] = 125000,
	[4] = 300000,
	[5] = 625000,
	[6] = 1500000,
	[7] = 3125000,
	[8] = 7500000,
	[9] = 16250000,
	[10] = 37500000,
	[11] = 87500000,
	[12] = 250000000,
}

function WinsConfig.For(world)
	return if world == 2 then WinsConfig.PadWins2 else WinsConfig.PadWins
end

return WinsConfig