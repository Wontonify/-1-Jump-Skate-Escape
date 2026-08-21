return function(_context, player: Player, key: string, value: number)
	local AdminService = require(game:GetService("ServerScriptService").Services.AdminService)
	return AdminService:SetData(player, key, value)
end
