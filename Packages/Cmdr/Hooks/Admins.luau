local RunService = game:GetService("RunService")

-- Add Roblox UserIds here to allow admin commands on a LIVE server.
local ADMINS = {
	[3655696236] = true,
	[4932834319] = true,
}

-- Who may run DefaultAdmin commands. Studio testing is always allowed; on a live server it's the
-- place owner (for a user-owned place) plus anyone listed in ADMINS above.
local function isAllowed(player)
	if RunService:IsStudio() then return true end
	if not player then return false end
	if ADMINS[player.UserId] or ADMINS[tostring(player.UserId)] then return true end -- accept number or string keys
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return false
end

return function(registry)
	registry:RegisterHook("BeforeRun", function(context)
		if context.Group == "DefaultAdmin" and not isAllowed(context.Executor) then
			return "You don't have permission to run this command"
		end
	end)
end