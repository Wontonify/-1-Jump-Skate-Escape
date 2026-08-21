return function(_context, duration: number)
	local AdminService = require(game:GetService("ServerScriptService").Services.AdminService)
	local note = AdminService:Broadcast("Jumps", nil, duration)
	return string.format("Double Jumps for %ds (all servers)%s", duration, note)
end



