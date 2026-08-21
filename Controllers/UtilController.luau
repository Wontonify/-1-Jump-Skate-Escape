--!strict
local RS = game:GetService("ReplicatedStorage")

local Knit = require(RS.Packages.Knit)

local UtilController = Knit.CreateController({
	Name = "UtilController",
})

local UNITS = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }

function UtilController.Short(n: number): string
	n = math.floor((n or 0) + 0.5)
	if n < 1000 then return tostring(n) end
	local i, v = 0, n
	while v >= 1000 and i < #UNITS do v /= 1000; i += 1 end
	return (string.format("%.1f", v):gsub("%.0$", "")) .. UNITS[i]
end

return UtilController


