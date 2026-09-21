-- Code Duel client UI: code-guess box, grenade buttons/keys (flashbang,
-- EMP, stun), their screen effects, and round/elimination status banners.

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
local ThrowEMP = Remotes:WaitForChild("ThrowEMP")
local EMPEffect = Remotes:WaitForChild("EMPEffect")
local EMPCooldownRemote = Remotes:WaitForChild("EMPCooldown")
local ThrowStun = Remotes:WaitForChild("ThrowStun")
local StunEffect = Remotes:WaitForChild("StunEffect")
local StunCooldownRemote = Remotes:WaitForChild("StunCooldown")
local ThrowScanner = Remotes:WaitForChild("ThrowScanner")
local ScannerPing = Remotes:WaitForChild("ScannerPing")
local ScannerCooldownRemote = Remotes:WaitForChild("ScannerCooldown")
local BountyUpdate = Remotes:WaitForChild("BountyUpdate")
local BountyClaimed = Remotes:WaitForChild("BountyClaimed")
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

local guessBlockedUntil = 0

local function submitGuess()
	if os.clock() < guessBlockedUntil then
		return
	end
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

-- Just the camera's facing direction. The server scales this by the
-- charge fraction to get the actual throw distance - no raycast here,
-- since a nearby wall/floor in your crosshair shouldn't cap a fully
-- charged throw short (the grenade's own physics handles bouncing off
-- whatever it actually hits along the way).
local function getAimDirection()
	return workspace.CurrentCamera.CFrame.LookVector
end

local GRENADE_MAX_CHARGE_TIME = 1.2 -- seconds held to reach full throw distance
local GRENADE_MIN_CHARGE_FRACTION = 0.2 -- a quick tap still throws it this far

-- Builds one grenade button: hold click or `key` down to charge up the
-- throw distance (a quick tap still throws a short distance), release to
-- throw. Shows a live cooldown countdown on the button while recharging.
local function createGrenadeButton(config)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 150, 0, 60)
	button.Position = config.position
	button.Text = config.label
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.BackgroundColor3 = config.color
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = screenGui

	local ready = true
	local cooldownConn
	local charging = false
	local chargeStartTime = 0
	local chargeConn

	local function startCharge()
		if not ready or charging then
			return
		end
		charging = true
		chargeStartTime = os.clock()
		if chargeConn then
			chargeConn:Disconnect()
		end
		chargeConn = RunService.Heartbeat:Connect(function()
			local fraction = math.clamp((os.clock() - chargeStartTime) / GRENADE_MAX_CHARGE_TIME, 0, 1)
			button.Text = string.format("%d%%", math.floor(fraction * 100))
			button.BackgroundColor3 = config.color:Lerp(Color3.new(1, 1, 1), fraction * 0.5)
		end)
	end

	local function releaseCharge()
		if not charging then
			return
		end
		charging = false
		if chargeConn then
			chargeConn:Disconnect()
			chargeConn = nil
		end
		local fraction =
			math.clamp((os.clock() - chargeStartTime) / GRENADE_MAX_CHARGE_TIME, GRENADE_MIN_CHARGE_FRACTION, 1)
		button.Text = config.label
		button.BackgroundColor3 = config.color
		config.throwRemote:FireServer(getAimDirection(), fraction)
	end

	button.MouseButton1Down:Connect(startCharge)
	button.MouseButton1Up:Connect(releaseCharge)
	UserInputService.InputBegan:Connect(function(input, processedByUI)
		if processedByUI then
			return
		end
		if input.KeyCode == config.key then
			startCharge()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == config.key then
			releaseCharge()
		end
	end)

	config.cooldownRemote.OnClientEvent:Connect(function(cooldown)
		ready = false
		charging = false
		if chargeConn then
			chargeConn:Disconnect()
			chargeConn = nil
		end
		button.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
		if cooldownConn then
			cooldownConn:Disconnect()
		end

		local endTime = os.clock() + cooldown
		cooldownConn = RunService.Heartbeat:Connect(function()
			local remaining = endTime - os.clock()
			if remaining <= 0 then
				button.Text = config.label
				button.BackgroundColor3 = config.color
				ready = true
				cooldownConn:Disconnect()
				cooldownConn = nil
			else
				button.Text = string.format("%.1fs", remaining)
			end
		end)
	end)
end

createGrenadeButton({
	position = UDim2.new(1, -170, 1, -80),
	label = "FLASHBANG (F)",
	color = Color3.fromRGB(60, 140, 220),
	key = Enum.KeyCode.F,
	throwRemote = ThrowFlashbang,
	cooldownRemote = FlashbangCooldownRemote,
})

createGrenadeButton({
	position = UDim2.new(1, -170, 1, -150),
	label = "EMP (G)",
	color = Color3.fromRGB(120, 90, 220),
	key = Enum.KeyCode.G,
	throwRemote = ThrowEMP,
	cooldownRemote = EMPCooldownRemote,
})

createGrenadeButton({
	position = UDim2.new(1, -170, 1, -220),
	label = "STUN (H)",
	color = Color3.fromRGB(230, 140, 40),
	key = Enum.KeyCode.H,
	throwRemote = ThrowStun,
	cooldownRemote = StunCooldownRemote,
})

createGrenadeButton({
	position = UDim2.new(1, -170, 1, -290),
	label = "SCANNER (J)",
	color = Color3.fromRGB(80, 220, 170),
	key = Enum.KeyCode.J,
	throwRemote = ThrowScanner,
	cooldownRemote = ScannerCooldownRemote,
})

-- Flash overlay (own screen blinded when hit by an enemy's flashbang)
local flashOverlay = Instance.new("Frame")
flashOverlay.Size = UDim2.new(1, 0, 1, 0)
flashOverlay.BackgroundColor3 = Color3.new(1, 1, 1)
flashOverlay.BackgroundTransparency = 1
flashOverlay.ZIndex = 10
flashOverlay.Parent = screenGui

local FLASH_HOLD_FRACTION = 0.55 -- fraction of the duration spent fully blind before fading
local activeFlashTween

FlashbangEffect.OnClientEvent:Connect(function(duration)
	if activeFlashTween then
		activeFlashTween:Cancel()
		activeFlashTween = nil
	end

	flashOverlay.BackgroundTransparency = 0
	local holdTime = duration * FLASH_HOLD_FRACTION
	local fadeTime = math.max(duration - holdTime, 0.05)

	task.delay(holdTime, function()
		activeFlashTween = TweenService:Create(
			flashOverlay,
			TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		activeFlashTween:Play()
	end)
end)

-- EMP effect: jams the guess box so you can't submit codes for a bit.
EMPEffect.OnClientEvent:Connect(function(duration)
	guessBlockedUntil = os.clock() + duration
	guessBox.Text = ""
	guessBox.TextEditable = false
	guessBox.PlaceholderText = "JAMMED..."
	submitButton.Text = "JAMMED"
	submitButton.AutoButtonColor = false
	submitButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)

	task.delay(duration, function()
		if os.clock() >= guessBlockedUntil then
			guessBox.TextEditable = true
			guessBox.PlaceholderText = "Enter 4-digit code"
			submitButton.Text = "SUBMIT (Enter)"
			submitButton.AutoButtonColor = true
			submitButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
		end
	end)
end)

-- Stun effect: the actual slow is server-side (WalkSpeed); this is just a
-- screen tint so it's obvious you got hit.
local stunOverlay = Instance.new("Frame")
stunOverlay.Size = UDim2.new(1, 0, 1, 0)
stunOverlay.BackgroundColor3 = Color3.fromRGB(230, 140, 40)
stunOverlay.BackgroundTransparency = 1
stunOverlay.ZIndex = 9
stunOverlay.Parent = screenGui

StunEffect.OnClientEvent:Connect(function(duration)
	TweenService:Create(stunOverlay, TweenInfo.new(0.15), { BackgroundTransparency = 0.75 }):Play()
	task.delay(duration, function()
		TweenService:Create(stunOverlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	end)
end)

-- Scanner ping: a brief, anonymous notice that someone scanned you (no
-- info on who or exactly where from - just that you were spotted).
local pingLabel = Instance.new("TextLabel")
pingLabel.Size = UDim2.new(0, 240, 0, 30)
pingLabel.Position = UDim2.new(0.5, -120, 0, 90)
pingLabel.BackgroundTransparency = 0.35
pingLabel.BackgroundColor3 = Color3.new(0, 0, 0)
pingLabel.TextColor3 = Color3.fromRGB(120, 255, 210)
pingLabel.Font = Enum.Font.GothamBold
pingLabel.TextScaled = true
pingLabel.Text = "YOU WERE SCANNED"
pingLabel.Visible = false
pingLabel.Parent = screenGui

ScannerPing.OnClientEvent:Connect(function()
	pingLabel.Visible = true
	task.delay(2, function()
		pingLabel.Visible = false
	end)
end)

-- Teammate label (Duos only) so you know who not to guess.
local teammateLabel = Instance.new("TextLabel")
teammateLabel.Size = UDim2.new(0, 260, 0, 26)
teammateLabel.Position = UDim2.new(0.5, -130, 0, 56)
teammateLabel.BackgroundTransparency = 0.35
teammateLabel.BackgroundColor3 = Color3.new(0, 0, 0)
teammateLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
teammateLabel.Font = Enum.Font.GothamBold
teammateLabel.TextScaled = true
teammateLabel.Visible = false
teammateLabel.Parent = screenGui

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
		showBanner("YOUR CODE WAS CRACKED. YOU'RE OUT.", Color3.fromRGB(255, 80, 80))
	elseif reason == "wrong-guess" then
		showBanner("WRONG CODE. YOU'RE OUT.", Color3.fromRGB(255, 80, 80))
	else
		showBanner("YOU'RE OUT", Color3.fromRGB(255, 80, 80))
	end
end)

BountyUpdate.OnClientEvent:Connect(function(bountyName)
	if bountyName then
		showBanner(string.format("%s IS NOW THE BOUNTY", bountyName:upper()), Color3.fromRGB(255, 90, 90), 3)
	end
end)

BountyClaimed.OnClientEvent:Connect(function(killerName)
	showBanner(string.format("BOUNTY CLAIMED BY %s", killerName:upper()), Color3.fromRGB(255, 200, 90), 3)
end)

local countdownConn

RoundStatus.OnClientEvent:Connect(function(status, data)
	-- Neither of these own the status bar, so they must not touch the
	-- countdown that may currently be running.
	if status == "MapPinned" then
		showBanner(
			string.format("%s LOCKED IN %s FOR NEXT ROUND", data.by:upper(), data.mapName:upper()),
			Color3.fromRGB(120, 190, 255),
			4
		)
		return
	elseif status == "TeamInfo" then
		if data.teammateName then
			teammateLabel.Text = "TEAMMATE: " .. data.teammateName:upper()
			teammateLabel.Visible = true
		else
			teammateLabel.Visible = false
		end
		return
	end

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
		if data.mode == "Duos" then
			statusLabel.Text = string.format("FIGHT on %s! Duos - %d teams left", data.mapName, data.teamCount)
		else
			statusLabel.Text = string.format("FIGHT on %s! %d players alive", data.mapName, data.aliveCount)
		end
	elseif status == "PlayerDown" then
		statusLabel.Text = string.format("%s is out (%s), %d left", data.name, data.reason, data.aliveCount)
	elseif status == "RoundEnd" then
		teammateLabel.Visible = false
		if data.winner then
			statusLabel.Text = data.winner .. " WINS THE ROUND!"
			if data.winner:find(player.Name, 1, true) then
				showBanner("YOU WIN!", Color3.fromRGB(90, 220, 120), 5)
			end
		else
			statusLabel.Text = "Round over."
		end
	end
end)
