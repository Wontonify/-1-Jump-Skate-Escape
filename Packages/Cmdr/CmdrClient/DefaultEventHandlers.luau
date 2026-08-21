local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local Window = require(script.Parent.CmdrInterface.Window)

return function (Cmdr)
	Cmdr:HandleEvent("Message", function (text)
		-- Show the (server-filtered) announcement via TextChatService, the current chat system.
		-- Rich-text keeps the yellow tint; the user text is escaped so it can't break the markup.
		local escaped = (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		local formatted = ('<font color="#F9D938">[Announcement] %s</font>'):format(escaped)
		local ok = pcall(function ()
			TextChatService:DisplaySystemMessage(formatted)
		end)
		if not ok then -- fall back to legacy chat if the game isn't on TextChatService
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = ("[Announcement] %s"):format(text);
				Color = Color3.fromRGB(249, 217, 56);
			})
		end
	end)

	Cmdr:HandleEvent("AddLine", function (...)
		Window:AddLine(...)
	end)
end