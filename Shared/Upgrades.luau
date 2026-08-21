--!strict
local Upgrades = {}

Upgrades.SpeedPerLevel = 1 -- walkspeed per upgrade
Upgrades.SpeedCosts = { 2, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000 }
Upgrades.SpeedRobux = { 0, 0, 9, 19, 29, 49, 67, 99, 149, 299 }
Upgrades.SpeedProducts = table.create(10, 3708144763)
Upgrades.SpeedMax = #Upgrades.SpeedCosts --rbx button

Upgrades.JumpCosts = { 5, 50, 250, 1000, 2500, 7500, 25000 }
Upgrades.JumpRobux = { 0, 9, 19, 49, 99, 149, 299 }
Upgrades.JumpProducts = table.create(7, 3645885179)
Upgrades.JumpMax = #Upgrades.JumpCosts --rbx button

function Upgrades.SpeedCost(level: number): number?
	return Upgrades.SpeedCosts[level + 1]
end

function Upgrades.JumpCost(level: number): number?
	return Upgrades.JumpCosts[level + 1]
end


return Upgrades