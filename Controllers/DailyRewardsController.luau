--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knit = require(RS.Packages.Knit)
local UtilController = require(script.Parent.UtilController)
local UIController = require(script.Parent.UIController)
local DailyRewards = require(RS:WaitForChild("Shared"):WaitForChild("DailyRewards"))

local player = Players.LocalPlayer

local DailyRewardsController = Knit.CreateController({
	Name = "DailyRewardsController",
})

local GREEN = Color3.fromRGB(90, 235, 110)
local WINS_ICON = "rbxassetid://128576837035866" -- the HUD trophy
local XP_ICON = "rbxassetid://109537907969172"   -- the +N popup

local ORDER = {
	"DayOneRewardButton", "DayTwoRewardButton", "DayThreeRewardButton", "DayFourRewardButton",
	"DayFiveRewardButton", "DaySixRewardButton", "DaySevenRewardButton",
}

local function rewardLabel(day: number): string
	local r = DailyRewards.Days[day]
	if not r then return "" end
	return "+" .. UtilController.Short(r.Amount) .. " " .. (if r.Type == "XP" then "XP" else "Wins")
end

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", sec // 3600, sec % 3600 // 60, sec % 60)
end

function DailyRewardsController:KnitStart()
	local service = Knit.GetService("DailyRewardService")
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")
	local frame = gui:WaitForChild("MainFrames"):WaitForChild("DailyRewardsFrame")
	local bg = frame:WaitForChild("DailyRewardsBackground")
	frame.Visible = false

	local function open()
		if UIController.OpenFrame then UIController.OpenFrame(frame) else frame.Visible = true end
	end
	local function close()
		if UIController.CloseFrame then UIController.CloseFrame(frame) else frame.Visible = false end
	end
	local closeBtn = bg:WaitForChild("CloseButton")
	if closeBtn:IsA("GuiButton") then closeBtn.Activated:Connect(close) end

	local claimSound = Instance.new("Sound")
	claimSound.SoundId = "rbxassetid://1169806635"
	claimSound.Volume = 0.7
	claimSound.Parent = SoundService

	local buttons: { GuiButton } = {}
	for i, name in ORDER do
		buttons[i] = bg:WaitForChild(name) :: GuiButton
	end

	-- card faces reward text + matching icon
	for i, btn in buttons do
		local r = DailyRewards.Days[i]
		local icon = btn:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			icon.Image = if r.Type == "XP" then XP_ICON else WINS_ICON
		end
		local nameL = btn:FindFirstChild("Name")
		if nameL and nameL:IsA("TextLabel") then nameL.Text = rewardLabel(i) end
		local comb = btn:FindFirstChild("Combinasion")
		if comb and comb:IsA("TextLabel") then comb.Text = rewardLabel(i) end
	end

	-- day 2 is the comeback hook: rainbow text sweep + pulsing icon pull the eye to it
	local day2 = buttons[2]
	if day2 then
		local RAINBOW = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 190, 60)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(250, 250, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 235, 110)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(80, 170, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(190, 110, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
		})
		local gradients: { UIGradient } = {}
		for _, name in { "Name", "Day" } do
			local label = day2:FindFirstChild(name)
			if label and label:IsA("TextLabel") then
				local g = Instance.new("UIGradient")
				g.Color = RAINBOW
				g.Parent = label
				table.insert(gradients, g)
			end
		end
		-- offset sweeps -1 -> 1 both ends sit on the same red, so the loop is seamless
		RunService.Heartbeat:Connect(function()
			if not frame.Visible then return end
			local t = os.clock() % 2 - 1
			for _, g in gradients do
				g.Offset = Vector2.new(t, 0)
			end
		end)
		local icon = day2:FindFirstChild("Icon")
		local iconScale = icon and icon:FindFirstChild("UIScale")
		if iconScale and iconScale:IsA("UIScale") then
			TweenService:Create(iconScale,
				TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.35 }):Play()
		end
	end

	local nextDay = bg:WaitForChild("NextDay") :: TextLabel

	local function streak(): number return (player:GetAttribute("DailyStreak") :: number?) or 0 end
	local function last(): number return (player:GetAttribute("DailyLast") :: number?) or 0 end
	local function waitLeft(): number
		return math.max(0, last() + DailyRewards.Interval - os.time())
	end
	-- streak
	local function shownStreak(): number
		local s = streak()
		if s >= #DailyRewards.Days and waitLeft() <= 0 then return 0 end
		return s
	end

	local function render()
		local s = shownStreak()
		local ready = waitLeft() <= 0
		for i, btn in buttons do
			local claimed = i <= s
			local claimedFrame = btn:FindFirstChild("ClaimedFrame")
			if claimedFrame and claimedFrame:IsA("Frame") then claimedFrame.Visible = claimed end
			local lockedFrame = btn:FindFirstChild("LockedFrame")
			if lockedFrame and lockedFrame:IsA("Frame") then
				-- the padlock only lifts off the next card once its timer is actually up
				lockedFrame.Visible = not claimed and not (i == s + 1 and ready)
			end
		end
		nextDay.Text = if ready then "Reward Ready!" else "Next Reward: " .. fmt(waitLeft())
	end

	for i, btn in buttons do
		btn.Activated:Connect(function()
			if i ~= shownStreak() + 1 then return end -- only the next card claims
			if waitLeft() > 0 then
				if UIController.ShowDeny then UIController.ShowDeny("Come back tomorrow!") end
				return
			end
			service.Claim:Fire()
		end)
	end

	-- rbx skips stay hidden until their products exist
	local function wireSkip(name: string, productId: number)
		local btn = bg:WaitForChild(name)
		if not btn:IsA("GuiButton") then return end
		if productId <= 0 then
			btn.Visible = false
			return
		end
		btn.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end
	wireSkip("SkipOneDayButton", DailyRewards.SkipOneProduct)
	wireSkip("SkipAllDaysButton", DailyRewards.SkipAllProduct)

	service.Claimed:Connect(function(_day: number, text: string)
		claimSound.TimePosition = 0
		claimSound:Play()
		if UIController.Notify then UIController.Notify("Daily Reward: " .. text .. "!", GREEN) end
		render()
	end)
	service.Denied:Connect(function(msg: string)
		if UIController.ShowDeny then UIController.ShowDeny(msg) end
	end)

	player:GetAttributeChangedSignal("DailyStreak"):Connect(render)
	player:GetAttributeChangedSignal("DailyLast"):Connect(render)
	task.spawn(function()
		while true do
			task.wait(1)
			if frame.Visible then render() end
		end
	end)

	local function tutorialDone(): boolean
		local owned = 0
		for _, name in string.split((player:GetAttribute("OwnedBoards") :: string?) or "", "|") do
			if name ~= "" then owned += 1 end
		end
		return owned >= 2 and ((player:GetAttribute("ExtraJumps") :: number?) or 0) >= 1
	end
	task.spawn(function()
		local deadline = os.clock() + 20
		while player:GetAttribute("DailyLast") == nil and os.clock() < deadline do
			task.wait(0.2)
		end
		render()
		while not tutorialDone() do
			task.wait(1)
		end
		if waitLeft() <= 0 then
			task.wait(3)
			open()
		end
	end)
end

return DailyRewardsController