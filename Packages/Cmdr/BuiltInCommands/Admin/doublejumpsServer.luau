return function(_context, duration: number)
	local AdminService = require(game:GetService("ServerScriptService").Services.AdminService)
	AdminService:StartJumpsEvent(duration)
	return string.format("Double Jumps for %ds (this server)", duration)
end