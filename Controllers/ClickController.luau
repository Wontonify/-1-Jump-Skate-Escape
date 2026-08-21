--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Knit = require(RS.Packages.Knit)
local UtilController = require(script.Parent.UtilController)
local ClickConfig = require(RS:WaitForChild("Shared"):WaitForChild("ClickConfig"))

local player = Players.LocalPlayer

local ClickController = Knit.CreateController({
	Name = "ClickController",
})

local CLICK_SOUND_ID = 8755541422 -- audio pop per "+N" feedback tick

local clickSound = Instance.new("Sound")
clickSound.SoundId = "rbxassetid://" .. CLICK_SOUND_ID
clickSound.Volume = 0.25
clickSound.Parent = SoundService

local totalPowerLabel: TextLabel? = nil
local popupTemplate: ImageLabel? = nil
local fxGui: ScreenGui? = nil
local punchScale: UIScale? = nil

-- quick pop of the whole bottom bar per gain tick
local function punch()
	local scale = punchScale
	if not scale then return end
	scale.Scale = 1
	local up = TweenService:Create(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.06 })
	up.Completed:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	up:Play()
end

-- "+N" popup that pops in, drifts up a little and fades in place (never crossing the middle of the screen)
local function spawnPopup(screenX: number, screenY: number, amount: number)
	local template, gui, label = popupTemplate, fxGui, totalPowerLabel
	if not (template and gui and label) then return end

	local popup = template:Clone()
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Visible = true
	popup.Position = UDim2.fromOffset(screenX, screenY)
	popup.Parent = gui

	local text = popup:FindFirstChild("PlusClickPop")
	local stroke = text and text:FindFirstChildWhichIsA("UIStroke")
	if text and text:IsA("TextLabel") then
		text.Text = "+" .. UtilController.Short(amount)
	end

	local baseSize = popup.Size
	popup.Size = UDim2.new(baseSize.X.Scale * 0.5, baseSize.X.Offset * 0.5, baseSize.Y.Scale * 0.5, baseSize.Y.Offset * 0.5)
	TweenService:Create(popup, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = baseSize,
	}):Play()

	-- a short fully-visible hold before the drift-and-fade so the number is readable
	local travelInfo = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local travel = TweenService:Create(popup, travelInfo, {
		Position = UDim2.fromOffset(screenX, screenY - 55),
		ImageTransparency = 1,
	})
	task.delay(0.5, function()
		if not popup.Parent then return end
		if text and text:IsA("TextLabel") then
			TweenService:Create(text, travelInfo, { TextTransparency = 1 }):Play()
		end
		if stroke then
			TweenService:Create(stroke, travelInfo, { Transparency = 1 }):Play()
		end
		travel:Play()
		travel.Completed:Connect(function()
			popup:Destroy()
		end)
	end)
end

-- popups land anywhere across the whole screen except a protected middle box, so they never pile up on top of char
function ClickController.RandomPopupPos(): (number, number)
	local camera = workspace.CurrentCamera
	local vp = camera.ViewportSize
	local marginX, marginY = vp.X * 0.06, vp.Y * 0.1
	local cx, cy = vp.X / 2, vp.Y / 2
	local protectX, protectY = vp.X * 0.22, vp.Y * 0.26
	for _ = 1, 12 do
		local x = marginX + math.random() * (vp.X - 2 * marginX)
		local y = marginY + math.random() * (vp.Y - 2 * marginY)
		if math.abs(x - cx) > protectX or math.abs(y - cy) > protectY then
			return x, y
		end
	end
	return cx + protectX * (if math.random() < 0.5 then 1 else -1) * (1 + math.random()), cy
end

-- shared gain feedback: sound + "+N" popup + bar punch (train ticks reuse it)
function ClickController.PlayFeedback(amount: number, screenX: number, screenY: number)
	clickSound.TimePosition = 0
	clickSound:Play()
	spawnPopup(screenX, screenY, amount)
	punch()
end

function ClickController:KnitStart()
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("ScreenGui")
	local bottomFrame = hud:WaitForChild("BottomFrame")
	local bar = bottomFrame:WaitForChild("BarBackground")
	totalPowerLabel = bar:WaitForChild("TotalPower") :: TextLabel
	popupTemplate = hud:WaitForChild("PowerIconPop") :: ImageLabel

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClickFX"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = playerGui
	fxGui = gui

	local scale = bottomFrame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = bottomFrame
	end
	punchScale = scale

	-- XP comes from moving (skating, boosting, flying) one feedback pop per tick, scattered wide around the player so the popups don't stack up
	local acc = 0
	local lastPos: Vector3? = nil
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / ClickConfig.StepsPerSecond then return end
		acc = 0
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp and hrp:IsA("BasePart") and humanoid.Health > 0) then
			lastPos = nil
			return
		end
		local pos = hrp.Position
		local last = lastPos
		lastPos = pos
		if not last then return end
		local dist = ((pos - last) * Vector3.new(1, 0, 1)).Magnitude
		if dist < ClickConfig.MinTickStuds or dist > ClickConfig.MaxTickStuds then return end
		local amount = (player:GetAttribute("XPPerStep") :: number?) or 1
		ClickController.PlayFeedback(amount, ClickController.RandomPopupPos())
	end)
end

return ClickController

