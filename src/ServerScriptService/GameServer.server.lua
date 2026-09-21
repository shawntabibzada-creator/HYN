-- Code Duel: FFA round loop.
-- Every alive player wears a random 4-digit code above their head. Type
-- another player's code into the guess box to kill them; guess wrong (no
-- living player has that code) and you die instead. Three thrown grenades
-- are available, each on its own personal cooldown: a flashbang that
-- blinds nearby players, an EMP that jams guessing, and a stun that slows
-- movement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MapGenerator = require(ReplicatedStorage.Modules.MapGenerator)
local CodeUtils = require(ReplicatedStorage.Modules.CodeUtils)
local MonetizationService = require(ServerScriptService.Modules.MonetizationService)

-- NOTE: StreamingEnabled can no longer be written from a normal script at
-- runtime (Roblox now restricts it to Studio/plugin capability), so doing
-- this here used to throw and silently kill this entire script before it
-- ever reached the round loop. Turn it off from Studio instead: File >
-- Game Settings > World tab > Streaming, or just leave it off (default
-- for new places) - this arena is small and doesn't benefit from
-- streaming anyway.

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
local PlayerEliminated = Remotes:WaitForChild("PlayerEliminated")
local RoundStatus = Remotes:WaitForChild("RoundStatus")

local MIN_PLAYERS = 2
local INTERMISSION_TIME = 15
local POST_ROUND_TIME = 6
local DEFAULT_WALK_SPEED = 16
local SPECTATOR_POSITION = Vector3.new(0, 300, 0)
local GRENADE_FUSE_TIME = 1.6 -- fixed time-to-detonate for every thrown grenade
local GRENADE_MIN_CHARGE_FRACTION = 0.2 -- a quick tap still throws it this far

local FLASHBANG_COOLDOWN = 6
local FAST_FLASHBANG_COOLDOWN = 4 -- with the "Quick Fuse" game pass
local FLASHBANG_RADIUS = 40
local FLASHBANG_MAX_DURATION = 3 -- at the center of the blast
local FLASHBANG_MIN_DURATION = 0.5 -- at the edge of the radius
local FLASHBANG_THROW_RANGE = 225
local FLASHBANG_BACK_TURNED_MULTIPLIER = 0.3 -- min effect when facing fully away from the blast

local EMP_COOLDOWN = 8
local EMP_RADIUS = 25
local EMP_BLOCK_DURATION = 4 -- seconds guessing is jammed for
local EMP_THROW_RANGE = 150

local STUN_COOLDOWN = 8
local STUN_RADIUS = 15
local STUN_DURATION = 4
local STUN_SPEED_MULTIPLIER = 0.35
local STUN_THROW_RANGE = 150

local SIGN_COLORS = {
	Default = Color3.fromRGB(255, 220, 90),
	GoldSign = Color3.fromRGB(255, 200, 40),
	CrimsonSign = Color3.fromRGB(230, 60, 60),
}

local playerCodes = {} -- [Player] = "1234"
local aliveSet = {} -- [Player] = true
local flashbangReadyAt = {} -- [Player] = os.clock() timestamp
local empReadyAt = {}
local stunReadyAt = {}
local empBlockedUntil = {} -- [Player] = os.clock() timestamp until guessing is jammed
local stunnedUntil = {} -- [Player] = os.clock() timestamp until movement is slowed
local roundActive = false
local pinnedNextMap = nil -- set by a "pick next map" purchase; consumed by the next round

local MAP_NAMES = {}
for _, choice in ipairs(MapGenerator.Choices) do
	MAP_NAMES[choice.key] = choice.name
end

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
	if os.clock() < (empBlockedUntil[player] or 0) then
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

-- Clamps the aim point to throwRange from the thrower. Returns a spawn
-- origin nudged forward off the thrower's shoulder (so the grenade doesn't
-- spawn inside their own hitbox and immediately collide with them) and the
-- clamped target the arc should aim for.
local function computeThrowTarget(hrp, aimPoint, throwRange)
	local shoulder = hrp.Position + Vector3.new(0, 1.5, 0)
	local toTarget = aimPoint - shoulder
	if toTarget.Magnitude > throwRange then
		toTarget = toTarget.Unit * throwRange
	end
	local landingTarget = shoulder + toTarget

	local horizontalDir = Vector3.new(toTarget.X, 0, toTarget.Z)
	horizontalDir = horizontalDir.Magnitude > 0.001 and horizontalDir.Unit or hrp.CFrame.LookVector
	local origin = shoulder + horizontalDir * 3

	return origin, landingTarget
end

local GRENADE_LAUNCH_ANGLE = math.rad(45)

-- The initial velocity, launched at a fixed 45-degree angle, that reaches
-- landingTarget from origin under gravity - a consistent lobbed arc rather
-- than a flight path that flattens out on long throws. Where it actually
-- ends up may differ once it starts bouncing.
local function computeArcVelocity(origin, landingTarget)
	local gravity = Workspace.Gravity
	local delta = landingTarget - origin
	local horizontalDelta = Vector3.new(delta.X, 0, delta.Z)
	local horizontalDistance = horizontalDelta.Magnitude
	local horizontalDir = horizontalDistance > 0.001 and horizontalDelta.Unit or Vector3.new(0, 0, 0)

	-- A 45-degree throw can't mathematically reach a target whose height
	-- gain exceeds the horizontal distance to it (that needs a steeper
	-- angle) - clamp so the formula always has a valid, positive solution.
	local effectiveDistance = math.max(horizontalDistance, 1)
	local rise = math.min(delta.Y, effectiveDistance * 0.9)

	local launchSpeed = math.sqrt((gravity * effectiveDistance ^ 2) / math.max(effectiveDistance - rise, 1))
	local horizontalSpeed = launchSpeed * math.cos(GRENADE_LAUNCH_ANGLE)
	local verticalSpeed = launchSpeed * math.sin(GRENADE_LAUNCH_ANGLE)

	return horizontalDir * horizontalSpeed + Vector3.new(0, verticalSpeed, 0)
end

-- Spawns a small glowing, trailing ball with real physics: gravity carries
-- it along an arc and it bounces off whatever it hits (walls, ramps,
-- dunes) instead of sliding straight to a precomputed point.
local function spawnGrenadeProjectile(name, origin, velocity, color)
	local grenade = Instance.new("Part")
	grenade.Name = name
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(1.4, 1.4, 1.4)
	grenade.Color = color
	grenade.Material = Enum.Material.Neon
	grenade.Anchored = false
	grenade.CanCollide = true
	grenade.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.55, 1, 1)
	grenade.Position = origin
	grenade.Parent = Workspace
	grenade.AssemblyLinearVelocity = velocity

	local glow = Instance.new("PointLight")
	glow.Color = color
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
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = grenade

	return grenade
end

-- Client-reported charge fraction is untrusted input: clamp it to a sane
-- range so nobody can throw further than the ability's own max by lying.
local function clampChargeFraction(rawFraction)
	if typeof(rawFraction) ~= "number" then
		return 1
	end
	return math.clamp(rawFraction, GRENADE_MIN_CHARGE_FRACTION, 1)
end

-- True (and starts the cooldown) if the player's ability was off cooldown.
local function tryStartCooldown(readyAtTable, player, cooldown, cooldownRemote)
	local now = os.clock()
	if now < (readyAtTable[player] or 0) then
		return false
	end
	readyAtTable[player] = now + cooldown
	cooldownRemote:FireClient(player, cooldown)
	return true
end

ThrowFlashbang.OnServerEvent:Connect(function(player, aimPoint, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimPoint) ~= "Vector3" then
		return
	end

	local cooldown = MonetizationService.Owns(player, "FastFlashbang") and FAST_FLASHBANG_COOLDOWN
		or FLASHBANG_COOLDOWN
	if not tryStartCooldown(flashbangReadyAt, player, cooldown, FlashbangCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = FLASHBANG_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimPoint, throwRange)
	local velocity = computeArcVelocity(origin, landingTarget)
	local grenade = spawnGrenadeProjectile("FlashbangGrenade", origin, velocity, Color3.fromRGB(255, 255, 255))

	task.delay(GRENADE_FUSE_TIME, function()
		local blastPoint = grenade.Position
		grenade:Destroy()

		for _, other in ipairs(Players:GetPlayers()) do
			if aliveSet[other] then
				local otherCharacter = other.Character
				local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				if otherHrp then
					local distance = (otherHrp.Position - blastPoint).Magnitude
					if distance <= FLASHBANG_RADIUS and hasLineOfSight(blastPoint, otherHrp.Position) then
						local closeness = 1 - (distance / FLASHBANG_RADIUS)
						local duration = FLASHBANG_MIN_DURATION
							+ (FLASHBANG_MAX_DURATION - FLASHBANG_MIN_DURATION) * closeness

						-- Looking at the blast gets the full duration; looking
						-- away tapers it down to a minimum, not to zero.
						local playerToBlast = blastPoint - otherHrp.Position
						if playerToBlast.Magnitude > 0.001 then
							local facingDot = otherHrp.CFrame.LookVector:Dot(playerToBlast.Unit)
							local facingFactor = FLASHBANG_BACK_TURNED_MULTIPLIER
								+ (1 - FLASHBANG_BACK_TURNED_MULTIPLIER) * ((facingDot + 1) / 2)
							duration *= facingFactor
						end

						FlashbangEffect:FireClient(other, duration)
					end
				end
			end
		end
	end)
end)

ThrowEMP.OnServerEvent:Connect(function(player, aimPoint, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimPoint) ~= "Vector3" then
		return
	end
	if not tryStartCooldown(empReadyAt, player, EMP_COOLDOWN, EMPCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = EMP_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimPoint, throwRange)
	local velocity = computeArcVelocity(origin, landingTarget)
	local grenade = spawnGrenadeProjectile("EMPGrenade", origin, velocity, Color3.fromRGB(120, 190, 255))

	task.delay(GRENADE_FUSE_TIME, function()
		local blastPoint = grenade.Position
		grenade:Destroy()

		for _, other in ipairs(Players:GetPlayers()) do
			if aliveSet[other] then
				local otherCharacter = other.Character
				local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				if otherHrp and (otherHrp.Position - blastPoint).Magnitude <= EMP_RADIUS then
					empBlockedUntil[other] = os.clock() + EMP_BLOCK_DURATION
					EMPEffect:FireClient(other, EMP_BLOCK_DURATION)
				end
			end
		end
	end)
end)

-- Slows a player for STUN_DURATION. Repeated hits refresh the timer
-- instead of stacking or letting an earlier hit's restore-speed callback
-- cut a later stun short.
local function applyStun(player, humanoid)
	local alreadyStunned = (stunnedUntil[player] or 0) > os.clock()
	stunnedUntil[player] = os.clock() + STUN_DURATION
	if not alreadyStunned then
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED * STUN_SPEED_MULTIPLIER
	end

	task.delay(STUN_DURATION, function()
		if os.clock() >= (stunnedUntil[player] or 0) then
			local character = player.Character
			local currentHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			if currentHumanoid then
				currentHumanoid.WalkSpeed = DEFAULT_WALK_SPEED
			end
		end
	end)
end

ThrowStun.OnServerEvent:Connect(function(player, aimPoint, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimPoint) ~= "Vector3" then
		return
	end
	if not tryStartCooldown(stunReadyAt, player, STUN_COOLDOWN, StunCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = STUN_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimPoint, throwRange)
	local velocity = computeArcVelocity(origin, landingTarget)
	local grenade = spawnGrenadeProjectile("StunGrenade", origin, velocity, Color3.fromRGB(255, 165, 40))

	task.delay(GRENADE_FUSE_TIME, function()
		local blastPoint = grenade.Position
		grenade:Destroy()

		for _, other in ipairs(Players:GetPlayers()) do
			if aliveSet[other] then
				local otherCharacter = other.Character
				local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				local otherHumanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
				if otherHrp and otherHumanoid and (otherHrp.Position - blastPoint).Magnitude <= STUN_RADIUS then
					applyStun(other, otherHumanoid)
					StunEffect:FireClient(other, STUN_DURATION)
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

MonetizationService.MapPinned:Connect(function(player, mapKey)
	if MAP_NAMES[mapKey] then
		pinnedNextMap = mapKey
		broadcastStatus("MapPinned", { by = player.Name, mapName = MAP_NAMES[mapKey] })
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
		broadcastStatus("Waiting", { count = #players, needed = MIN_PLAYERS })
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
	local mapKey = pinnedNextMap or MapGenerator.RandomKey()
	pinnedNextMap = nil
	local mapFolder, spawnPoints = MapGenerator.Generate(mapKey, Workspace)

	table.clear(playerCodes)
	table.clear(aliveSet)
	table.clear(flashbangReadyAt)
	table.clear(empReadyAt)
	table.clear(stunReadyAt)
	table.clear(empBlockedUntil)
	table.clear(stunnedUntil)
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
				humanoid.WalkSpeed = DEFAULT_WALK_SPEED
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

	broadcastStatus("RoundStart", { aliveCount = countAlive(), mapName = MAP_NAMES[mapKey] or mapKey })

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
	empReadyAt[player] = nil
	stunReadyAt[player] = nil
	empBlockedUntil[player] = nil
	stunnedUntil[player] = nil
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
