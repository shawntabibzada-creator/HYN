-- Code Duel: FFA round loop.
-- Every alive player wears a random 4-digit code above their head. Type
-- another player's code into the guess box to kill them; guess wrong (no
-- living player has that code) and you die instead. A flashbang is
-- available on a 6-second personal cooldown to blind nearby players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local MapGenerator = require(ReplicatedStorage.Modules.MapGenerator)
local CodeUtils = require(ReplicatedStorage.Modules.CodeUtils)
local MonetizationService = require(ServerScriptService.Modules.MonetizationService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SubmitCodeGuess = Remotes.SubmitCodeGuess
local ThrowFlashbang = Remotes.ThrowFlashbang
local FlashbangEffect = Remotes.FlashbangEffect
local FlashbangCooldownRemote = Remotes.FlashbangCooldown
local PlayerEliminated = Remotes.PlayerEliminated
local RoundStatus = Remotes.RoundStatus

local MIN_PLAYERS = 2
local INTERMISSION_TIME = 15
local POST_ROUND_TIME = 6
local FLASHBANG_COOLDOWN = 6
local FAST_FLASHBANG_COOLDOWN = 4 -- with the "Quick Fuse" game pass
local FLASHBANG_RADIUS = 40
local FLASHBANG_MAX_DURATION = 3 -- at the center of the blast
local FLASHBANG_MIN_DURATION = 0.5 -- at the edge of the radius
local FLASHBANG_THROW_RANGE = 90
local FLASHBANG_THROW_SPEED = 110 -- studs per second, sets how long it's in the air
local FLASHBANG_MIN_FLIGHT_TIME = 0.15
local SPECTATOR_POSITION = Vector3.new(0, 300, 0)

local SIGN_COLORS = {
	Default = Color3.fromRGB(255, 220, 90),
	GoldSign = Color3.fromRGB(255, 200, 40),
	CrimsonSign = Color3.fromRGB(230, 60, 60),
}

local playerCodes = {} -- [Player] = "1234"
local aliveSet = {} -- [Player] = true
local flashbangReadyAt = {} -- [Player] = os.clock() timestamp
local roundActive = false

local function ensureLeaderstats(player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats

	leaderstats.Parent = player
end

local function addStat(player, statName, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(statName)
	if stat then
		stat.Value += amount
	end
end

local function broadcastStatus(status, data)
	RoundStatus:FireAllClients(status, data)
end

-- Permanent ground so players don't free-fall during intermission, when
-- the previous round's generated map has already been destroyed and the
-- next one hasn't been built yet.
local function createLobbyFloor()
	local floor = Instance.new("Part")
	floor.Name = "LobbyFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(320, 2, 320)
	floor.Position = Vector3.new(0, -1, 0)
	floor.Color = Color3.fromRGB(40, 40, 44)
	floor.Material = Enum.Material.Concrete
	floor.Parent = Workspace
end
createLobbyFloor()

local function attachCodeTag(character, code, signColor)
	local head = character:WaitForChild("Head", 5)
	if not head then
		return
	end

	local existing = head:FindFirstChild("CodeTag")
	if existing then
		existing:Destroy()
	end

	-- Small sign-style tag, not "always on top" (so walls block it) and
	-- capped to a short render distance. A client-side script further
	-- restricts it to only show when a viewer is roughly in front of this
	-- player, like reading a sign held at chest height.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CodeTag"
	billboard.Size = UDim2.new(0, 70, 0, 26)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 28
	billboard.Enabled = false
	billboard.Parent = head

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 210, 60)
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -6, 1, -4)
	label.Position = UDim2.new(0, 3, 0, 2)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = signColor or SIGN_COLORS.Default
	label.Text = code
	label.Parent = frame
end

local function countAlive()
	local n = 0
	for _ in pairs(aliveSet) do
		n += 1
	end
	return n
end

local function killCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function eliminatePlayer(player, reason)
	if not aliveSet[player] then
		return
	end
	aliveSet[player] = nil
	killCharacter(player)
	PlayerEliminated:FireClient(player, reason)
	broadcastStatus("PlayerDown", { name = player.Name, reason = reason, aliveCount = countAlive() })
end

SubmitCodeGuess.OnServerEvent:Connect(function(player, guessedCode)
	if not roundActive or not aliveSet[player] then
		return
	end
	if not CodeUtils.IsValidCode(guessedCode) then
		return
	end

	local target
	for otherPlayer in pairs(aliveSet) do
		if otherPlayer ~= player and playerCodes[otherPlayer] == guessedCode then
			target = otherPlayer
			break
		end
	end

	if target then
		addStat(player, "Kills", 1)
		eliminatePlayer(target, "cracked")
	else
		eliminatePlayer(player, "wrong-guess")
	end
end)

-- True if nothing in the map (walls, roofs, crates, boundary) sits between
-- the two points. Characters themselves are excluded so a crowd of players
-- never blocks the check.
local function hasLineOfSight(fromPos, toPos)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(excluded, plr.Character)
		end
	end
	raycastParams.FilterDescendantsInstances = excluded

	local direction = toPos - fromPos
	local result = Workspace:Raycast(fromPos, direction, raycastParams)
	return result == nil
end

ThrowFlashbang.OnServerEvent:Connect(function(player, aimPoint)
	if not roundActive or not aliveSet[player] then
		return
	end
	if typeof(aimPoint) ~= "Vector3" then
		return
	end

	local now = os.clock()
	if now < (flashbangReadyAt[player] or 0) then
		return
	end
	local cooldown = MonetizationService.Owns(player, "FastFlashbang") and FAST_FLASHBANG_COOLDOWN
		or FLASHBANG_COOLDOWN
	flashbangReadyAt[player] = now + cooldown
	FlashbangCooldownRemote:FireClient(player, cooldown)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local origin = hrp.Position + Vector3.new(0, 1.5, 0)
	local toTarget = aimPoint - origin
	if toTarget.Magnitude > FLASHBANG_THROW_RANGE then
		toTarget = toTarget.Unit * FLASHBANG_THROW_RANGE
	end
	local landingPoint = origin + toTarget

	local flightTime = math.max(toTarget.Magnitude / FLASHBANG_THROW_SPEED, FLASHBANG_MIN_FLIGHT_TIME)

	local grenade = Instance.new("Part")
	grenade.Name = "FlashbangGrenade"
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(1.4, 1.4, 1.4)
	grenade.Color = Color3.fromRGB(255, 255, 255)
	grenade.Material = Enum.Material.Neon
	grenade.Anchored = true
	grenade.CanCollide = false
	grenade.Position = origin
	grenade.Parent = Workspace

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 255, 255)
	glow.Range = 14
	glow.Brightness = 3
	glow.Parent = grenade

	local attachmentTop = Instance.new("Attachment")
	attachmentTop.Position = Vector3.new(0, 0.3, 0)
	attachmentTop.Parent = grenade
	local attachmentBottom = Instance.new("Attachment")
	attachmentBottom.Position = Vector3.new(0, -0.3, 0)
	attachmentBottom.Parent = grenade

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachmentTop
	trail.Attachment1 = attachmentBottom
	trail.Lifetime = 0.35
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = grenade

	local tween = TweenService:Create(
		grenade,
		TweenInfo.new(flightTime, Enum.EasingStyle.Linear),
		{ Position = landingPoint }
	)
	tween:Play()

	task.delay(flightTime, function()
		grenade:Destroy()

		for _, other in ipairs(Players:GetPlayers()) do
			if aliveSet[other] then
				local otherCharacter = other.Character
				local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				if otherHrp then
					local distance = (otherHrp.Position - landingPoint).Magnitude
					if distance <= FLASHBANG_RADIUS and hasLineOfSight(landingPoint, otherHrp.Position) then
						local closeness = 1 - (distance / FLASHBANG_RADIUS)
						local duration = FLASHBANG_MIN_DURATION
							+ (FLASHBANG_MAX_DURATION - FLASHBANG_MIN_DURATION) * closeness
						FlashbangEffect:FireClient(other, duration)
					end
				end
			end
		end
	end)
end)

MonetizationService.ExtraFlashbangGranted:Connect(function(player)
	if roundActive and aliveSet[player] then
		flashbangReadyAt[player] = 0
		FlashbangCooldownRemote:FireClient(player, 0)
	end
end)

local function assignCodes(players)
	local used = {}
	for _, plr in ipairs(players) do
		local code
		repeat
			code = CodeUtils.GenerateCode()
		until not used[code]
		used[code] = true
		playerCodes[plr] = code
	end
end

local function teleportToSpawns(players, spawnPoints)
	local shuffled = {}
	for i, spawnPoint in ipairs(spawnPoints) do
		shuffled[i] = spawnPoint
	end
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	for i, plr in ipairs(players) do
		local cframe = shuffled[((i - 1) % #shuffled) + 1]
		local character = plr.Character or plr.CharacterAdded:Wait()
		character:PivotTo(cframe)
	end
end

local function runRound()
	local players = Players:GetPlayers()
	if #players < MIN_PLAYERS then
		return
	end

	broadcastStatus("Intermission", { seconds = INTERMISSION_TIME })
	task.wait(INTERMISSION_TIME)

	players = Players:GetPlayers()
	if #players < MIN_PLAYERS then
		return
	end

	local oldMap = Workspace:FindFirstChild("GeneratedMap")
	if oldMap then
		oldMap:Destroy()
	end
	local mapFolder, spawnPoints = MapGenerator.Generate(Workspace)

	table.clear(playerCodes)
	table.clear(aliveSet)
	table.clear(flashbangReadyAt)
	roundActive = true

	assignCodes(players)
	for _, plr in ipairs(players) do
		aliveSet[plr] = true
	end

	teleportToSpawns(players, spawnPoints)

	for _, plr in ipairs(players) do
		local character = plr.Character
		if character then
			local signColor = SIGN_COLORS.Default
			if MonetizationService.Owns(plr, "GoldSign") then
				signColor = SIGN_COLORS.GoldSign
			elseif MonetizationService.Owns(plr, "CrimsonSign") then
				signColor = SIGN_COLORS.CrimsonSign
			end
			attachCodeTag(character, playerCodes[plr], signColor)

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				-- The default overhead name/health display would otherwise
				-- overlap the code sign; your code is your identity here.
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.Died:Connect(function()
					if roundActive then
						eliminatePlayer(plr, "eliminated")
					end
				end)
			end
		end
	end

	broadcastStatus("RoundStart", { aliveCount = countAlive() })

	while roundActive and countAlive() > 1 do
		task.wait(1)
	end
	roundActive = false

	local winner
	for plr in pairs(aliveSet) do
		winner = plr
	end
	if winner then
		addStat(winner, "Wins", 1)
	end
	broadcastStatus("RoundEnd", { winner = winner and winner.Name or nil })

	task.wait(POST_ROUND_TIME)
	if mapFolder and mapFolder.Parent then
		mapFolder:Destroy()
	end
end

Players.PlayerAdded:Connect(function(player)
	ensureLeaderstats(player)
	MonetizationService.Init(player)
	player.CharacterAdded:Connect(function(character)
		if roundActive and not aliveSet[player] then
			character:PivotTo(CFrame.new(SPECTATOR_POSITION))
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	aliveSet[player] = nil
	playerCodes[player] = nil
	flashbangReadyAt[player] = nil
	MonetizationService.Cleanup(player)
end)

task.spawn(function()
	while true do
		local ok, err = pcall(runRound)
		if not ok then
			warn("[CodeDuel] round error:", err)
		end
		task.wait(3)
	end
end)
