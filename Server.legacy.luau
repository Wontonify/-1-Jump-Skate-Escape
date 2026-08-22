local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

Knit.AddServices(script.Parent.Services)

Knit.Start()
	:andThen(function()
		print("Knit server started")
	end)
	:catch(warn)

local ADONIS_MODULE_ID = 7510592873
local ADONIS_BACKUP_ID = 17438792001

task.spawn(function()
	local service = script.Parent.Services:WaitForChild("AdonisService")
	local offer = service:WaitForChild("AdonisData", 300)
	if not offer then
		warn(":: Adonis :: AdonisService never offered its loader data!")
		return
	end
	local data = offer:Invoke()

	local ok, module = pcall(require, ADONIS_MODULE_ID)
	if not ok then
		warn(":: Adonis :: MainModule require failed, trying the backup:", module)
		ok, module = pcall(require, ADONIS_BACKUP_ID)
	end

	local response = "FAILED"
	if ok and module then
		local booted, result = pcall(module, data)
		if booted then
			response = tostring(result)
		else
			warn(":: Adonis :: MainModule boot errored:", result)
		end
	else
		warn(":: Adonis :: backup MainModule require failed too:", module)
	end
	service:SetAttribute("AdonisBoot", response)
end)