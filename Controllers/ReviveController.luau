--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(RS.Packages.Knit)
local GamepassConfig = require(RS:WaitForChild("Shared"):WaitForChild("GamepassConfig"))

local player = Players.LocalPlayer

local ReviveController = Knit.CreateController({
	Name = "ReviveController",
})

local OPEN_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OFFSET = UDim2.new(0, 0, 0.15, 0) -- the card slides up into place

local function hover(button: GuiButton)
	local normal = button.Size
	local big = UDim2.new(normal.X.Scale * 1.08, normal.X.Offset, normal.Y.Scale * 1.08, normal.Y.Offset)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { Size = big }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { Size = normal }):Play()
	end)
end

function ReviveController:KnitStart()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Revive") :: ScreenGui
	local frame = gui:WaitForChild("Revive") :: Frame
	local timer = frame:WaitForChild("Timer") :: TextLabel
	local buy = frame:WaitForChild("Buy") :: ImageButton
	local decline = frame:WaitForChild("Decline") :: ImageButton
	local home = frame.Position

	gui.Enabled = false
	frame.Visible = false
	hover(buy)
	hover(decline)

	-- keep the authored price label honest against the store
	task.spawn(function()
		local label = buy:FindFirstChild("HeaderText")
		if not (label and label:IsA("TextLabel")) then return end
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService,
			GamepassConfig.ReviveProduct.Id, Enum.InfoType.Product)
		if ok and info and info.PriceInRobux then
			label.Text = (label.Text:gsub("%d+", tostring(info.PriceInRobux), 1))
		end
	end)

	local tween: Tween? = nil
	local ticker: RBXScriptConnection? = nil
	local deadline = 0
	local held: number? = nil -- countdown pauses while the Robux prompt is up

	local function stop()
		if tween then
			tween:Cancel()
			tween = nil
		end
		if ticker then
			ticker:Disconnect()
			ticker = nil
		end
	end

	local function close()
		stop()
		held = nil
		local out = TweenService:Create(frame, CLOSE_TWEEN, { Position = home + OFFSET })
		tween = out
		out.Completed:Connect(function()
			if tween ~= out then return end -- a fresh offer opened mid-close
			frame.Visible = false
			gui.Enabled = false
		end)
		out:Play()
	end

	local function open(seconds: number) 
		stop()
		held = nil
		deadline = os.clock() + seconds
		timer.Text = string.format("%.2f", seconds)
		gui.Enabled = true
		frame.Visible = true
		frame.Position = home + OFFSET
		local into = TweenService:Create(frame, OPEN_TWEEN, { Position = home })
		tween = into
		into:Play()
		ticker = RunService.RenderStepped:Connect(function()
			if held then return end
			local remaining = math.max(0, deadline - os.clock())
			timer.Text = string.format("%.2f", remaining)
			if remaining <= 0 then close() end
		end)
	end

	Knit.GetService("ReviveService").Offer:Connect(open)

	decline.Activated:Connect(close)
	buy.Activated:Connect(function()
		if held then return end
		held = math.max(0, deadline - os.clock())
		MarketplaceService:PromptProductPurchase(player, GamepassConfig.ReviveProduct.Id)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, purchased)
		if productId ~= GamepassConfig.ReviveProduct.Id then return end
		if purchased then
			close()
		elseif held then -- backed out, so the offer runs out the clock it had left
			deadline = os.clock() + held
			held = nil
		end
	end)
end

return ReviveController