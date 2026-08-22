--!nonstrict
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(RS.Packages.Knit)

local AdonisService = Knit.CreateService({
	Name = "AdonisService",
	Client = {},
})

local MODULE_ID = 7510592873 -- https://www.roblox.com/library/7510592873/Adonis-MainModule
local LOADER_ID = 7510622625

local function boot()
	if RunService:FindFirstChild("__Adonis_MUTEX") then
		warn(":: Adonis :: already running! Aborting...")
		return
	end
	local mutex = Instance.new("StringValue")
	mutex.Name = "__Adonis_MUTEX"
	mutex.Archivable = false
	mutex.Value = script:GetFullName()
	mutex.Parent = RunService

	local config = RS.Packages.Adonis
	local data = {
		Settings = {},
		Descriptions = {},
		Messages = {},
		ServerPlugins = {},
		ClientPlugins = {},
		Packages = {},
		Themes = {},

		Config = config,
		Loader = script,
		Runner = script,

		ModuleID = MODULE_ID,
		LoaderID = LOADER_ID,
		NightlyMode = false,
		DebugMode = false,
		SilentStartup = false,
	}

	local settingsErrored = false
	for _, module in config.Settings:GetChildren() do
		local ok, err = pcall(function()
			for key, value in require(module) do
				if key == "Messages" then
					data.Messages = value
				end
				data.Settings[key] = value
			end
		end)
		if not ok then
			settingsErrored = true
			warn(`:: Adonis :: Settings.{module.Name} errored while loading; using defaults: {err}`)
		end
	end
	if settingsErrored then
		data.Settings.Ranks = {} -- broken settings must not fall back to unintended admin lists
	end
	pcall(function()
		data.Descriptions = require(config.InGameSettingsEditorSettings.Descriptions)
	end)
	pcall(function()
		data.Order = require(config.InGameSettingsEditorSettings.Order)
	end)

	for _, module in config.Plugins:GetChildren() do
		local name = string.lower(module.Name)
		if module:IsA("Folder") then
			table.insert(data.Packages, module)
		elseif string.match(name, "^client[%-:]") then
			table.insert(data.ClientPlugins, module)
		elseif string.match(name, "^server[%-:]") then
			table.insert(data.ServerPlugins, module)
		else
			warn(`:: Adonis :: Unknown plugin type for {module:GetFullName()}; name must start with 'Server:', 'Server-', 'Client:' or 'Client-'`)
		end
	end
	for _, theme in config.Themes:GetChildren() do
		table.insert(data.Themes, theme)
	end

	local offer = Instance.new("BindableFunction")
	offer.Name = "AdonisData"
	offer.OnInvoke = function()
		return data
	end
	offer.Parent = script

	local t0 = os.clock()
	while os.clock() - t0 < 180 do
		local response = script:GetAttribute("AdonisBoot")
		if response ~= nil then
			if response ~= "SUCCESS" then
				error(":: Adonis :: MainModule failed to load!")
			end
			return
		end
		task.wait(1)
	end
	warn(":: Adonis :: AdonisFetch never reported back!")
end

function AdonisService:KnitInit()
	task.spawn(boot)
end

return AdonisService