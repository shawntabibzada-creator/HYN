-- Code Duel: FFA (or Duos, auto-enabled at 4+ players) round loop.
-- Every alive player wears a random 4-digit code above their head. Type
-- another player's code into the guess box to kill them; guess wrong (no
-- living enemy has that code) and you die instead. Four thrown grenades
-- are available, each on its own personal cooldown: a flashbang that
-- blinds nearby players, an EMP that jams guessing, a stun that slows
-- movement, and a scanner that reveals nearby enemy signs to the thrower.
-- Kill two in a round and you become the bounty, visible to everyone.
-- A slow-shrinking safe zone kicks in late in longer rounds as a
-- camping safety net.

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
local ThrowScanner = Remotes:WaitForChild("ThrowScanner")
local ScannerEffect = Remotes:WaitForChild("ScannerEffect")
local ScannerPing = Remotes:WaitForChild("ScannerPing")
local ScannerCooldownRemote = Remotes:WaitForChild("ScannerCooldown")
local BountyUpdate = Remotes:WaitForChild("BountyUpdate")
local BountyClaimed = Remotes:WaitForChild("BountyClaimed")
local PlayerEliminated = Remotes:WaitForChild("PlayerEliminated")
local RoundStatus = Remotes:WaitForChild("RoundStatus")

local MIN_PLAYERS = 2
local DUOS_MIN_PLAYERS = 8 -- Duos auto-activates at this many players; below it, plain FFA
local INTERMISSION_TIME = 15
local POST_ROUND_TIME = 6
local DEFAULT_WALK_SPEED = 16
local SPECTATOR_POSITION = Vector3.new(0, 300, 0)
local GRENADE_FUSE_TIME = 1.6 -- fixed time-to-detonate for every thrown grenade
local GRENADE_MIN_CHARGE_FRACTION = 0.2 -- a quick tap still throws it this far
local GRENADE_LAUNCH_ANGLE = math.rad(45)

local FLASHBANG_COOLDOWN = 6
local FAST_FLASHBANG_COOLDOWN = 4 -- with the "Quick Fuse" game pass
local FLASHBANG_RADIUS = 40
local FLASHBANG_MAX_DURATION = 3 -- at the center of the blast
local FLASHBANG_MIN_DURATION = 0.5 -- at the edge of the radius
local FLASHBANG_THROW_RANGE = 225
local FLASHBANG_BACK_TURNED_MULTIPLIER = 0.3 -- min effect when facing fully away from the blast

local EMP_COOLDOWN = 8
local EMP_RADIUS = 14
local EMP_BLOCK_DURATION = 4 -- seconds guessing is jammed for
local EMP_THROW_RANGE = 150

local STUN_COOLDOWN = 8
local STUN_RADIUS = 15
local STUN_DURATION = 4
local STUN_SPEED_MULTIPLIER = 0.35
local STUN_THROW_RANGE = 150

local SCANNER_COOLDOWN = 10
local SCANNER_RADIUS = 45 -- ignores walls/facing - a real information tool, not a debuff
local SCANNER_REVEAL_DURATION = 0.175 -- a brief flash of the code, not a sustained reveal
local SCANNER_THROW_RANGE = 150

local VIP_COOLDOWN_MULTIPLIER = 0.7 -- with an active "VIP Day Pass"; stacks with Quick Fuse

local BOUNTY_KILL_THRESHOLD = 2 -- round kills needed to become (or take over) the bounty
local BOUNTY_KILL_BONUS = 1 -- extra Kills credit for claiming the bounty

-- Tuned as a late, gentle safety net rather than a core mechanic - it
-- doesn't kick in until well into a round, and only pushes people out of
-- the far edges, not the whole map. Set ZONE_START_DELAY very high (or
-- ZONE_DAMAGE_PER_TICK to 0) to effectively disable it if it still isn't
-- pulling its weight once tested.
local ZONE_START_DELAY = 45
local ZONE_START_RADIUS = 130
local ZONE_END_RADIUS = 40
local ZONE_SHRINK_DURATION = 45
local ZONE_DAMAGE_PER_TICK = 4
local ZONE_TICK_INTERVAL = 1

local SIGN_COLORS = {
	Default = Color3.fromRGB(255, 220, 90),
	GoldSign = Color3.fromRGB(255, 200, 40),
	CrimsonSign = Color3.fromRGB(230, 60, 60),
	EmeraldSign = Color3.fromRGB(60, 220, 120),
	VioletSign = Color3.fromRGB(170, 90, 230),
}

-- Checked in order; the first sign cosmetic a player owns wins, so the
-- flashier/more expensive ones are listed first. RainbowSign isn't a
-- static color (see attachCodeTag) so it's not in SIGN_COLORS.
local SIGN_COSMETIC_PRIORITY = { "RainbowSign", "GoldSign", "CrimsonSign", "EmeraldSign", "VioletSign" }

local NEON_TRAIL_COLOR = Color3.fromRGB(80, 220, 255)

local playerCodes = {} -- [Player] = "1234"
local aliveSet = {} -- [Player] = true
local flashbangReadyAt = {} -- [Player] = os.clock() timestamp
local empReadyAt = {}
local stunReadyAt = {}
local scannerReadyAt = {}
local empBlockedUntil = {} -- [Player] = os.clock() timestamp until guessing is jammed
local stunnedUntil = {} -- [Player] = os.clock() timestamp until movement is slowed
local roundKills = {} -- [Player] = kills this round, for the bounty
local playerJoinedAt = {} -- [Player] = os.clock() when they joined, for Duos party grouping
local roundActive = false
local roundId = 0 -- bumped each round so a stale safe-zone loop can tell it's obsolete
local isDuosRound = false
local pinnedNextMap = nil -- set by a "pick next map" purchase; consumed by the next round
local bountyPlayer = nil

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

local function attachCodeTag(character, code, signColor, rainbow)
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
	-- player, like reading a sign held at chest height (or when the
	-- viewer used a scanner pulse, or the viewer is a teammate in Duos).
	-- MaxDistance is a little past the scanner's reveal radius so a
	-- scanned sign can actually render that far out.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CodeTag"
	billboard.Size = UDim2.new(0, 70, 0, 26)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 50
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
	stroke.Color = signColor or SIGN_COLORS.Default
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

	-- "Rainbow Code Sign" cosmetic: cycles the sign's color instead of
	-- holding one. Self-stopping - once this billboard is replaced (next
	-- round) or its character is gone, billboard.Parent goes nil and the
	-- loop ends on its own with nothing else to clean up.
	if rainbow then
		task.spawn(function()
			while billboard.Parent do
				local color = Color3.fromHSV((os.clock() * 0.3) % 1, 0.85, 1)
				label.TextColor3 = color
				stroke.Color = color
				task.wait(0.05)
			end
		end)
	end
end

-- "Neon Trail" cosmetic: a glowing trail between two attachments on the
-- root part. Tied to this specific character instance, so it's cleaned
-- up automatically on death/respawn along with everything else on it.
local function applyTrailCosmetic(character, color)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local topAttachment = Instance.new("Attachment")
	topAttachment.Name = "TrailTop"
	topAttachment.Position = Vector3.new(0, 1, 0)
	topAttachment.Parent = hrp

	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Name = "TrailBottom"
	bottomAttachment.Position = Vector3.new(0, -1, 0)
	bottomAttachment.Parent = hrp

	local trail = Instance.new("Trail")
	trail.Attachment0 = topAttachment
	trail.Attachment1 = bottomAttachment
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Lifetime = 0.4
	trail.MinLength = 0
	trail.Parent = hrp
end

-- Always-visible marker (unlike the code sign) so the bounty target can
-- be hunted across the map - the cost of a kill streak.
local function createBountyMarker(character)
	local head = character:WaitForChild("Head", 5)
	if not head then
		return
	end

	local existing = head:FindFirstChild("BountyMarker")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BountyMarker"
	billboard.Size = UDim2.new(0, 90, 0, 34)
	billboard.StudsOffset = Vector3.new(0, 3.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = "BOUNTY"
	label.TextColor3 = Color3.fromRGB(255, 60, 60)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = billboard
end

local function removeBountyMarker(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local marker = head and head:FindFirstChild("BountyMarker")
	if marker then
		marker:Destroy()
	end
end

local function clearBounty()
	if bountyPlayer then
		removeBountyMarker(bountyPlayer)
		bountyPlayer = nil
		BountyUpdate:FireAllClients(nil)
	end
end

-- Promotes `player` to bounty if their round kill count clears the
-- threshold and beats whoever (if anyone) currently holds it.
local function maybePromoteBounty(player)
	local kills = roundKills[player] or 0
	if kills < BOUNTY_KILL_THRESHOLD then
		return
	end
	if bountyPlayer == player then
		return
	end
	if bountyPlayer and (roundKills[bountyPlayer] or 0) >= kills then
		return
	end

	if bountyPlayer then
		removeBountyMarker(bountyPlayer)
	end
	bountyPlayer = player
	local character = player.Character
	if character then
		createBountyMarker(character)
	end
	BountyUpdate:FireAllClients(player.Name)
end

local function countAlive()
	local n = 0
	for _ in pairs(aliveSet) do
		n += 1
	end
	return n
end

local function countAliveTeams()
	local teams = {}
	local n = 0
	for plr in pairs(aliveSet) do
		local teamId = plr:GetAttribute("TeamId")
		if teamId and not teams[teamId] then
			teams[teamId] = true
			n += 1
		end
	end
	return n
end

-- True while more than one side (team in Duos, player in FFA) is left.
local function roundContested()
	if isDuosRound then
		return countAliveTeams() > 1
	end
	return countAlive() > 1
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
	if player == bountyPlayer then
		clearBounty()
	end
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

	local myTeam = isDuosRound and player:GetAttribute("TeamId") or nil

	-- Guessing a living teammate's real code is a no-op, not a death -
	-- they were never a valid target.
	if myTeam then
		for otherPlayer in pairs(aliveSet) do
			if otherPlayer ~= player and otherPlayer:GetAttribute("TeamId") == myTeam then
				if playerCodes[otherPlayer] == guessedCode then
					return
				end
			end
		end
	end

	local target
	for otherPlayer in pairs(aliveSet) do
		local isTeammate = myTeam and otherPlayer:GetAttribute("TeamId") == myTeam
		if otherPlayer ~= player and not isTeammate and playerCodes[otherPlayer] == guessedCode then
			target = otherPlayer
			break
		end
	end

	if target then
		local wasBounty = target == bountyPlayer

		addStat(player, "Kills", 1)
		roundKills[player] = (roundKills[player] or 0) + 1
		eliminatePlayer(target, "cracked")

		if wasBounty then
			addStat(player, "Kills", BOUNTY_KILL_BONUS)
			BountyClaimed:FireAllClients(player.Name)
		end
		maybePromoteBounty(player)
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

-- Builds a target exactly throwRange studs out along aimDirection (already
-- scaled by the charge fraction by the caller) - not wherever a raycast
-- happens to hit nearby, so a fully charged throw always goes the full
-- distance regardless of what's directly in your crosshair. Also returns
-- a spawn origin nudged forward off the thrower's shoulder so the grenade
-- doesn't spawn inside their own hitbox and immediately collide with them.
local function computeThrowTarget(hrp, aimDirection, throwRange)
	local shoulder = hrp.Position + Vector3.new(0, 1.5, 0)
	local dirUnit = (typeof(aimDirection) == "Vector3" and aimDirection.Magnitude > 0.001) and aimDirection.Unit
		or hrp.CFrame.LookVector
	local landingTarget = shoulder + dirUnit * throwRange

	local horizontalDir = Vector3.new(dirUnit.X, 0, dirUnit.Z)
	horizontalDir = horizontalDir.Magnitude > 0.001 and horizontalDir.Unit or hrp.CFrame.LookVector
	local origin = shoulder + horizontalDir * 3

	return origin, landingTarget
end

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

-- Applies the VIP Day Pass discount on top of whatever cooldown a throw
-- would otherwise use (including any permanent gamepass discount, e.g.
-- Quick Fuse on Flashbang - the two stack).
local function applyVipDiscount(player, cooldown)
	if MonetizationService.HasActiveVIP(player) then
		return cooldown * VIP_COOLDOWN_MULTIPLIER
	end
	return cooldown
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

ThrowFlashbang.OnServerEvent:Connect(function(player, aimDirection, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimDirection) ~= "Vector3" then
		return
	end

	local cooldown = MonetizationService.Owns(player, "FastFlashbang") and FAST_FLASHBANG_COOLDOWN
		or FLASHBANG_COOLDOWN
	cooldown = applyVipDiscount(player, cooldown)
	if not tryStartCooldown(flashbangReadyAt, player, cooldown, FlashbangCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = FLASHBANG_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimDirection, throwRange)
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

ThrowEMP.OnServerEvent:Connect(function(player, aimDirection, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimDirection) ~= "Vector3" then
		return
	end
	if not tryStartCooldown(empReadyAt, player, applyVipDiscount(player, EMP_COOLDOWN), EMPCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = EMP_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimDirection, throwRange)
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

ThrowStun.OnServerEvent:Connect(function(player, aimDirection, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimDirection) ~= "Vector3" then
		return
	end
	if not tryStartCooldown(stunReadyAt, player, applyVipDiscount(player, STUN_COOLDOWN), StunCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = STUN_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimDirection, throwRange)
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

ThrowScanner.OnServerEvent:Connect(function(player, aimDirection, chargeFraction)
	if not roundActive or not aliveSet[player] or typeof(aimDirection) ~= "Vector3" then
		return
	end
	if not tryStartCooldown(scannerReadyAt, player, applyVipDiscount(player, SCANNER_COOLDOWN), ScannerCooldownRemote) then
		return
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local throwRange = SCANNER_THROW_RANGE * clampChargeFraction(chargeFraction)
	local origin, landingTarget = computeThrowTarget(hrp, aimDirection, throwRange)
	local velocity = computeArcVelocity(origin, landingTarget)
	local grenade = spawnGrenadeProjectile("ScannerGrenade", origin, velocity, Color3.fromRGB(120, 255, 190))

	task.delay(GRENADE_FUSE_TIME, function()
		local blastPoint = grenade.Position
		grenade:Destroy()

		-- Pure information tool: ignores walls and facing (unlike the
		-- normal code sign), only for the thrower. Scanned enemies get a
		-- brief, anonymous notice that they were spotted, for fairness.
		ScannerEffect:FireClient(player, blastPoint, SCANNER_RADIUS, SCANNER_REVEAL_DURATION)

		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and aliveSet[other] then
				local otherCharacter = other.Character
				local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
				if otherHrp and (otherHrp.Position - blastPoint).Magnitude <= SCANNER_RADIUS then
					ScannerPing:FireClient(other)
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

-- Picks `count` spawns out of the map's full list: preferring ones away
-- from the outer edge when there are only a few players (nobody needs to
-- be pushed to the boundary just to fill an otherwise-empty map), then
-- spreading the chosen spawns apart from each other so players don't land
-- right next to one another. "Away from the edge" uses horizontal-only
-- distance from the spawn set's center (elevation isn't what makes a spot
-- feel like a boundary); "spread apart" uses full 3D distance (a
-- different tier on Compound is a real separation even where it's
-- horizontally close to another spawn).
local function selectSpawnCFrames(spawnPoints, count)
	if count >= #spawnPoints then
		return spawnPoints
	end

	local sumX, sumZ = 0, 0
	for _, cframe in ipairs(spawnPoints) do
		sumX += cframe.Position.X
		sumZ += cframe.Position.Z
	end
	local centerX, centerZ = sumX / #spawnPoints, sumZ / #spawnPoints

	local byCentrality = {}
	for _, cframe in ipairs(spawnPoints) do
		local dx, dz = cframe.Position.X - centerX, cframe.Position.Z - centerZ
		table.insert(byCentrality, { cframe = cframe, horizontalDist = math.sqrt(dx * dx + dz * dz) })
	end
	table.sort(byCentrality, function(a, b)
		return a.horizontalDist < b.horizontalDist
	end)

	-- Grows toward the full set (edges included) as there are more
	-- players needing spread across the whole map.
	local candidateCount = math.min(#byCentrality, math.max(count * 3, 6))
	local candidates = {}
	for i = 1, candidateCount do
		table.insert(candidates, byCentrality[i].cframe)
	end

	local chosen = {}
	table.insert(chosen, table.remove(candidates, math.random(#candidates)))
	while #chosen < count and #candidates > 0 do
		local bestIndex, bestMinDist = 1, -1
		for i, candidate in ipairs(candidates) do
			local minDist = math.huge
			for _, picked in ipairs(chosen) do
				minDist = math.min(minDist, (candidate.Position - picked.Position).Magnitude)
			end
			if minDist > bestMinDist then
				bestMinDist = minDist
				bestIndex = i
			end
		end
		table.insert(chosen, table.remove(candidates, bestIndex))
	end

	return chosen
end

local function teleportToSpawns(players, spawnPoints)
	local chosen = selectSpawnCFrames(spawnPoints, #players)

	for i = #chosen, 2, -1 do
		local j = math.random(i)
		chosen[i], chosen[j] = chosen[j], chosen[i]
	end

	for i, plr in ipairs(players) do
		local cframe = chosen[((i - 1) % #chosen) + 1]
		local character = plr.Character or plr.CharacterAdded:Wait()
		character:PivotTo(cframe)
	end
end

-- Shuffles players into teams of 2 (an odd player out gets a team of 1,
-- which just behaves like FFA for them - no special-casing needed).
local PARTY_JOIN_WINDOW = 3 -- seconds; joining this close together stands in for "same party" (no public API for that)

local function areFriends(a, b)
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	return ok and result
end

local function areLikelyPartyMates(a, b)
	local ta, tb = playerJoinedAt[a], playerJoinedAt[b]
	return ta ~= nil and tb ~= nil and math.abs(ta - tb) <= PARTY_JOIN_WINDOW
end

-- Pairs off players from `remaining` (in place) wherever matchFn(a, b) is
-- true, assigning each pair the next TeamId. Whoever's left after a pass
-- carries over to the next.
local function pairOffMatching(remaining, matchFn, nextTeamId)
	local i = 1
	while i <= #remaining do
		local a = remaining[i]
		local matchedIndex
		for j = i + 1, #remaining do
			if matchFn(a, remaining[j]) then
				matchedIndex = j
				break
			end
		end
		if matchedIndex then
			local b = table.remove(remaining, matchedIndex)
			table.remove(remaining, i)
			a:SetAttribute("TeamId", nextTeamId)
			b:SetAttribute("TeamId", nextTeamId)
			nextTeamId += 1
		else
			i += 1
		end
	end
	return nextTeamId
end

-- Teams of 2, preferring to keep real-world groups together: mutual
-- friends first, then anyone who joined the server within a few seconds
-- of each other (a stand-in for Roblox Parties, which join together),
-- then whoever's left gets paired off randomly. An odd player out gets a
-- team of 1, which just plays like FFA for them - no special-casing
-- needed elsewhere.
local function assignDuosTeams(players)
	local remaining = {}
	for i, plr in ipairs(players) do
		remaining[i] = plr
	end
	for i = #remaining, 2, -1 do
		local j = math.random(i)
		remaining[i], remaining[j] = remaining[j], remaining[i]
	end

	local nextTeamId = 1
	nextTeamId = pairOffMatching(remaining, areFriends, nextTeamId)
	nextTeamId = pairOffMatching(remaining, areLikelyPartyMates, nextTeamId)

	local i = 1
	while i <= #remaining do
		local a, b = remaining[i], remaining[i + 1]
		a:SetAttribute("TeamId", nextTeamId)
		if b then
			b:SetAttribute("TeamId", nextTeamId)
		end
		nextTeamId += 1
		i += 2
	end
end

local function findTeammateName(player, players)
	local teamId = player:GetAttribute("TeamId")
	if not teamId then
		return nil
	end
	for _, other in ipairs(players) do
		if other ~= player and other:GetAttribute("TeamId") == teamId then
			return other.Name
		end
	end
	return nil
end

local function updateZoneWalls(walls, radius)
	local height = 400
	local thickness = 6
	local size = radius * 2
	local specs = {
		{ Vector3.new(size + thickness, height, thickness), Vector3.new(0, height / 2 - 100, radius) },
		{ Vector3.new(size + thickness, height, thickness), Vector3.new(0, height / 2 - 100, -radius) },
		{ Vector3.new(thickness, height, size + thickness), Vector3.new(radius, height / 2 - 100, 0) },
		{ Vector3.new(thickness, height, size + thickness), Vector3.new(-radius, height / 2 - 100, 0) },
	}
	for i, wall in ipairs(walls) do
		wall.Size = specs[i][1]
		wall.Position = specs[i][2]
	end
end

local function createZoneWalls(parent)
	local walls = {}
	for i = 1, 4 do
		local wall = Instance.new("Part")
		wall.Name = "ZoneWall"
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanQuery = false
		wall.Material = Enum.Material.ForceField
		wall.Color = Color3.fromRGB(255, 90, 60)
		wall.Transparency = 0.6
		wall.Parent = parent
		walls[i] = wall
	end
	updateZoneWalls(walls, ZONE_START_RADIUS)
	return walls
end

-- Shrinks the boundary from ZONE_START_RADIUS to ZONE_END_RADIUS starting
-- ZONE_START_DELAY seconds into the round, damaging anyone caught outside
-- it. Parented under the round's mapFolder, so it's cleaned up
-- automatically when the map is destroyed - this loop only needs to stop
-- iterating, not clean up after itself.
local function runSafeZone(thisRoundId, walls)
	local elapsed = 0
	while roundActive and roundId == thisRoundId do
		local t = math.clamp((elapsed - ZONE_START_DELAY) / ZONE_SHRINK_DURATION, 0, 1)
		local radius = ZONE_START_RADIUS - (ZONE_START_RADIUS - ZONE_END_RADIUS) * t
		updateZoneWalls(walls, radius)

		if elapsed >= ZONE_START_DELAY then
			for plr in pairs(aliveSet) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if hrp and humanoid then
					local flatDistance = Vector2.new(hrp.Position.X, hrp.Position.Z).Magnitude
					if flatDistance > radius then
						humanoid:TakeDamage(ZONE_DAMAGE_PER_TICK)
					end
				end
			end
		end

		task.wait(ZONE_TICK_INTERVAL)
		elapsed += ZONE_TICK_INTERVAL
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
	table.clear(scannerReadyAt)
	table.clear(empBlockedUntil)
	table.clear(stunnedUntil)
	table.clear(roundKills)
	clearBounty()
	roundActive = true
	roundId += 1
	local thisRoundId = roundId

	isDuosRound = #players >= DUOS_MIN_PLAYERS
	for _, plr in ipairs(players) do
		plr:SetAttribute("TeamId", nil)
	end
	if isDuosRound then
		assignDuosTeams(players)
	end

	assignCodes(players)
	for _, plr in ipairs(players) do
		aliveSet[plr] = true
	end

	teleportToSpawns(players, spawnPoints)

	for _, plr in ipairs(players) do
		local character = plr.Character
		if character then
			local signColor = SIGN_COLORS.Default
			local rainbow = false
			for _, passKey in ipairs(SIGN_COSMETIC_PRIORITY) do
				if MonetizationService.Owns(plr, passKey) then
					if passKey == "RainbowSign" then
						rainbow = true
					else
						signColor = SIGN_COLORS[passKey]
					end
					break
				end
			end
			attachCodeTag(character, playerCodes[plr], signColor, rainbow)
			if MonetizationService.Owns(plr, "NeonTrail") then
				applyTrailCosmetic(character, NEON_TRAIL_COLOR)
			end

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

	broadcastStatus("RoundStart", {
		aliveCount = countAlive(),
		mapName = MAP_NAMES[mapKey] or mapKey,
		mode = isDuosRound and "Duos" or "FFA",
		teamCount = isDuosRound and countAliveTeams() or nil,
	})
	for _, plr in ipairs(players) do
		RoundStatus:FireClient(plr, "TeamInfo", { teammateName = findTeammateName(plr, players) })
	end

	local zoneWalls = createZoneWalls(mapFolder)
	task.spawn(runSafeZone, thisRoundId, zoneWalls)

	while roundActive and roundContested() do
		task.wait(1)
	end
	roundActive = false

	if isDuosRound then
		local winningTeamId
		for plr in pairs(aliveSet) do
			winningTeamId = plr:GetAttribute("TeamId")
			break
		end
		local winnerNames = {}
		if winningTeamId then
			for plr in pairs(aliveSet) do
				if plr:GetAttribute("TeamId") == winningTeamId then
					addStat(plr, "Wins", 1)
					table.insert(winnerNames, plr.Name)
				end
			end
		end
		broadcastStatus("RoundEnd", { winner = #winnerNames > 0 and table.concat(winnerNames, " & ") or nil })
	else
		local winner
		for plr in pairs(aliveSet) do
			winner = plr
		end
		if winner then
			addStat(winner, "Wins", 1)
		end
		broadcastStatus("RoundEnd", { winner = winner and winner.Name or nil })
	end

	task.wait(POST_ROUND_TIME)
	if mapFolder and mapFolder.Parent then
		mapFolder:Destroy()
	end
end

Players.PlayerAdded:Connect(function(player)
	playerJoinedAt[player] = os.clock()
	ensureLeaderstats(player)
	MonetizationService.Init(player)
	player.CharacterAdded:Connect(function(character)
		if roundActive and not aliveSet[player] then
			character:PivotTo(CFrame.new(SPECTATOR_POSITION))
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	if player == bountyPlayer then
		clearBounty()
	end
	aliveSet[player] = nil
	playerCodes[player] = nil
	flashbangReadyAt[player] = nil
	empReadyAt[player] = nil
	stunReadyAt[player] = nil
	scannerReadyAt[player] = nil
	empBlockedUntil[player] = nil
	stunnedUntil[player] = nil
	roundKills[player] = nil
	playerJoinedAt[player] = nil
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
