return function(_context, mult: number, duration: number)
	local AdminService = require(game:GetService("ServerScriptService").Services.AdminService)
	AdminService:StartSpeedEvent(mult, duration)
	return string.format("%gx Speed for %ds (this server)", mult, duration)
end