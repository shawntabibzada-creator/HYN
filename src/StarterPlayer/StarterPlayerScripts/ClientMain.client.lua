-- Code Duel client UI: code-guess box, flashbang button/key, screen-flash
-- overlay, and round/elimination status banners.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SubmitCodeGuess = Remotes:WaitForChild("SubmitCodeGuess")
local ThrowFlashbang = Remotes:WaitForChild("ThrowFlashbang")
local FlashbangEffect = Remotes:WaitForChild("FlashbangEffect")
local FlashbangCooldownRemote = Remotes:WaitForChild("FlashbangCooldown")
local PlayerEliminated = Remotes:WaitForChild("PlayerEliminated")
local RoundStatus = Remotes:WaitForChild("RoundStatus")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CodeDuelUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Status bar
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 520, 0, 40)
statusLabel.Position = UDim2.new(0.5, -260, 0, 10)
statusLabel.BackgroundTransparency = 0.35
statusLabel.BackgroundColor3 = Color3.new(0, 0, 0)
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextScaled = true
statusLabel.Text = "Waiting for players..."
statusLabel.Parent = screenGui

-- Guess panel
local guessFrame = Instance.new("Frame")
guessFrame.Size = UDim2.new(0, 260, 0, 90)
guessFrame.Position = UDim2.new(0.5, -130, 1, -120)
guessFrame.BackgroundTransparency = 0.25
guessFrame.BackgroundColor3 = Color3.new(0, 0, 0)
guessFrame.Parent = screenGui

local guessBox = Instance.new("TextBox")
guessBox.Size = UDim2.new(1, -20, 0, 40)
guessBox.Position = UDim2.new(0, 10, 0, 10)
guessBox.PlaceholderText = "Enter 4-digit code"
guessBox.Text = ""
guessBox.TextScaled = true
guessBox.Font = Enum.Font.GothamBold
guessBox.ClearTextOnFocus = false
guessBox.Parent = guessFrame

local submitButton = Instance.new("TextButton")
submitButton.Size = UDim2.new(1, -20, 0, 30)
submitButton.Position = UDim2.new(0, 10, 0, 55)
submitButton.Text = "SUBMIT (Enter)"
submitButton.TextScaled = true
submitButton.Font = Enum.Font.GothamBold
submitButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
submitButton.TextColor3 = Color3.new(1, 1, 1)
submitButton.Parent = guessFrame

guessBox:GetPropertyChangedSignal("Text"):Connect(function()
	local filtered = guessBox.Text:gsub("%D", "")
	if #filtered > 4 then
		filtered = filtered:sub(1, 4)
	end
	if filtered ~= guessBox.Text then
		guessBox.Text = filtered
	end
end)

local function submitGuess()
	if guessBox.Text:match("^%d%d%d%d$") then
		SubmitCodeGuess:FireServer(guessBox.Text)
		guessBox.Text = ""
	end
end

submitButton.MouseButton1Click:Connect(submitGuess)
guessBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitGuess()
	end
end)

-- Flashbang
local flashButton = Instance.new("TextButton")
flashButton.Size = UDim2.new(0, 150, 0, 60)
flashButton.Position = UDim2.new(1, -170, 1, -80)
flashButton.Text = "FLASHBANG (F)"
flashButton.TextScaled = true
flashButton.Font = Enum.Font.GothamBold
flashButton.BackgroundColor3 = Color3.fromRGB(60, 140, 220)
flashButton.TextColor3 = Color3.new(1, 1, 1)
flashButton.Parent = screenGui

local flashReady = true
local cooldownConn

local FLASHBANG_THROW_RANGE = 90

local function getAimPoint()
	local camera = workspace.CurrentCamera
	local character = player.Character
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * FLASHBANG_THROW_RANGE

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = character and { character } or {}

	local result = workspace:Raycast(origin, direction, raycastParams)
	if result then
		return result.Position
	end
	return origin + direction
end

local function useFlashbang()
	if not flashReady then
		return
	end
	ThrowFlashbang:FireServer(getAimPoint())
end

flashButton.MouseButton1Click:Connect(useFlashbang)
UserInputService.InputBegan:Connect(function(input, processedByUI)
	if processedByUI then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		useFlashbang()
	end
end)

FlashbangCooldownRemote.OnClientEvent:Connect(function(cooldown)
	flashReady = false
	flashButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	if cooldownConn then
		cooldownConn:Disconnect()
	end

	local endTime = os.clock() + cooldown
	cooldownConn = RunService.Heartbeat:Connect(function()
		local remaining = endTime - os.clock()
		if remaining <= 0 then
			flashButton.Text = "FLASHBANG (F)"
			flashButton.BackgroundColor3 = Color3.fromRGB(60, 140, 220)
			flashReady = true
			cooldownConn:Disconnect()
			cooldownConn = nil
		else
			flashButton.Text = string.format("%.1fs", remaining)
		end
	end)
end)

-- Flash overlay (own screen blinded when hit by an enemy's flashbang)
local flashOverlay = Instance.new("Frame")
flashOverlay.Size = UDim2.new(1, 0, 1, 0)
flashOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
flashOverlay.BackgroundTransparency = 1
flashOverlay.ZIndex = 10
flashOverlay.Parent = screenGui

FlashbangEffect.OnClientEvent:Connect(function(duration)
	flashOverlay.BackgroundTransparency = 0
	local tween = TweenService:Create(
		flashOverlay,
		TweenInfo.new(duration, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
end)

-- Banner (elimination / win messages)
local banner = Instance.new("TextLabel")
banner.Size = UDim2.new(0, 520, 0, 80)
banner.Position = UDim2.new(0.5, -260, 0.35, 0)
banner.BackgroundTransparency = 0.2
banner.BackgroundColor3 = Color3.new(0, 0, 0)
banner.TextColor3 = Color3.fromRGB(255, 80, 80)
banner.Font = Enum.Font.GothamBold
banner.TextScaled = true
banner.Visible = false
banner.Parent = screenGui

local function showBanner(text, color, duration)
	banner.Text = text
	banner.TextColor3 = color
	banner.Visible = true
	task.delay(duration or 4, function()
		banner.Visible = false
	end)
end

PlayerEliminated.OnClientEvent:Connect(function(reason)
	if reason == "cracked" then
		showBanner("YOUR CODE WAS CRACKED — YOU'RE OUT", Color3.fromRGB(255, 80, 80))
	elseif reason == "wrong-guess" then
		showBanner("WRONG CODE — YOU'RE OUT", Color3.fromRGB(255, 80, 80))
	else
		showBanner("YOU'RE OUT", Color3.fromRGB(255, 80, 80))
	end
end)

local countdownConn

RoundStatus.OnClientEvent:Connect(function(status, data)
	print("[CodeDuel] client received RoundStatus:", status)
	if countdownConn then
		countdownConn:Disconnect()
		countdownConn = nil
	end

	if status == "Waiting" then
		statusLabel.Text = string.format("Waiting for players... (%d/%d)", data.count, data.needed)
	elseif status == "Intermission" then
		local endTime = os.clock() + data.seconds
		countdownConn = RunService.Heartbeat:Connect(function()
			local remaining = math.max(0, math.ceil(endTime - os.clock()))
			statusLabel.Text = string.format("Next round starting in %ds", remaining)
		end)
	elseif status == "RoundStart" then
		statusLabel.Text = string.format("FIGHT! %d players alive", data.aliveCount)
	elseif status == "PlayerDown" then
		statusLabel.Text = string.format("%s is out (%s) — %d left", data.name, data.reason, data.aliveCount)
	elseif status == "RoundEnd" then
		if data.winner then
			statusLabel.Text = data.winner .. " WINS THE ROUND!"
			if data.winner == player.Name then
				showBanner("YOU WIN!", Color3.fromRGB(90, 220, 120), 5)
			end
		else
			statusLabel.Text = "Round over."
		end
	end
end)
