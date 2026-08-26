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

WinsConfig.PadWins2 = {
	[1] = 25000,
	[2] = 60000,
	[3] = 140000,
	[4] = 325000,
	[5] = 750000,
	[6] = 1750000,
	[7] = 4000000,
	[8] = 9000000,
	[9] = 21000000,
	[10] = 50000000,
	[11] = 110000000,
	[12] = 250000000,
}

function WinsConfig.For(world)
	return if world == 2 then WinsConfig.PadWins2 else WinsConfig.PadWins
end

return WinsConfig