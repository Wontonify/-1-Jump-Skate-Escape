--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(RS.Packages.Knit)
local player = Players.LocalPlayer

local RaceController = Knit.CreateController({
	Name = "RaceController",
})

local OPEN_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OFFSET = UDim2.new(0, 0, 0.15, 0)

local function hover(button: GuiButton)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local normal = scale.Scale
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_TWEEN, { Scale = normal * 1.08 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_TWEEN, { Scale = normal }):Play()
	end)
end

function RaceController:KnitStart()
	local screenGui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local topFrame = screenGui:WaitForChild("TopFrame")
	local frame = topFrame:WaitForChild("RaceFrame") :: Frame
	local background = frame:WaitForChild("ReviveBackground")
	local yesButton = background:WaitForChild("PurchaseButton") :: ImageButton
	local noButton = background:WaitForChild("DeclineButton") :: ImageButton
	local nameLabel = background:WaitForChild("Name") :: TextLabel
	local bar = background:WaitForChild("Bar"):WaitForChild("Canvas")
	local filler = bar:WaitForChild("Filler") :: Frame
	local home = frame.Position
	local fullHeight = filler.Size.Y
	local promptText = nameLabel.Text

	frame.Visible = false
	filler.AnchorPoint = Vector2.new(0, 0.5)
	filler.Position = UDim2.fromScale(0, 0.5)
	hover(yesButton)
	hover(noButton)

	local raceService = Knit.GetService("RaceService")
	local tween: Tween? = nil
	local ticker: RBXScriptConnection? = nil
	local deadline = 0
	local joined = false

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

	local function close(upward: boolean?)
		stop()
		local destination = if upward then home - OFFSET else home + OFFSET
		local out = TweenService:Create(frame, CLOSE_TWEEN, { Position = destination })
		tween = out
		out.Completed:Connect(function()
			if tween ~= out then return end
			frame.Visible = false
		end)
		out:Play()
	end

	local function answer(accepted: boolean)
		if not frame.Visible then return end
		if accepted then
			if joined then return end
			joined = true
			raceService.Respond:Fire(true)
			-- Keep the countdown and Cancel option visible after joining.
			yesButton.Visible = true
			noButton.Visible = true
			nameLabel.Text = "Racing Starting In: " .. math.max(0, math.ceil(deadline - os.clock()))
		else
			-- No declines initially and cancels an existing signup.
			raceService.Respond:Fire(false)
			joined = false
			close(true)
		end
	end

	local function open(seconds: number)
		stop()
		joined = false
		yesButton.Visible = true
		noButton.Visible = true
		nameLabel.Text = promptText
		deadline = os.clock() + seconds
		filler.Size = UDim2.new(1, 0, fullHeight.Scale, fullHeight.Offset)
		frame.Visible = true
		frame.Position = home + OFFSET
		local into = TweenService:Create(frame, OPEN_TWEEN, { Position = home })
		tween = into
		into:Play()
		ticker = RunService.RenderStepped:Connect(function()
			local remaining = math.max(0, deadline - os.clock())
			local ratio = if seconds > 0 then remaining / seconds else 0
			filler.Size = UDim2.new(ratio, 0, fullHeight.Scale, fullHeight.Offset)
			if joined then
				nameLabel.Text = "Racing Starting In: " .. math.max(0, math.ceil(remaining))
			end
			if remaining <= 0 then close() end
		end)
	end

	raceService.Offer:Connect(open)
	raceService.Started:Connect(close)
	yesButton.Activated:Connect(function() answer(true) end)
	noButton.Activated:Connect(function() answer(false) end)
end

return RaceController