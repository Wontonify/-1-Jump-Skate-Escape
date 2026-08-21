return function(_context, mult: number, duration: number)
	local AdminService = require(game:GetService("ServerScriptService").Services.AdminService)
	local note = AdminService:Broadcast("Speed", mult, duration)
	return string.format("%gx Speed for %ds (all servers)%s", mult, duration, note)
end
