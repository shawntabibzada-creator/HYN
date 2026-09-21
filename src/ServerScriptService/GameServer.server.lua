-- Code Duel: FFA round loop.
-- Every alive player wears a random 4-digit code above their head. Type
-- another player's code into the guess box to kill them; guess wrong (no
-- living player has that code) and you die instead. A flashbang is
-- available on a 6-second personal cooldown to blind nearby players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapGenerator = require(ReplicatedStorage.Modules.MapGenerator)
local CodeUtils = require(ReplicatedStorage.Modules.CodeUtils)

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
local FLASHBANG_RADIUS = 40
local FLASHBANG_DURATION = 2.2
local SPECTATOR_POSITION = Vector3.new(0, 300, 0)

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

local function attachCodeTag(character, code)
	local head = character:WaitForChild("Head", 5)
	if not head then
		return
	end

	local existing = head:FindFirstChild("CodeTag")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CodeTag"
	billboard.Size = UDim2.new(0, 110, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 90)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = code
	label.Parent = billboard
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

ThrowFlashbang.OnServerEvent:Connect(function(player)
	if not roundActive or not aliveSet[player] then
		return
	end

	local now = os.clock()
	if now < (flashbangReadyAt[player] or 0) then
		return
	end
	flashbangReadyAt[player] = now + FLASHBANG_COOLDOWN
	FlashbangCooldownRemote:FireClient(player, FLASHBANG_COOLDOWN)

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local origin = hrp.Position

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and aliveSet[other] then
			local otherCharacter = other.Character
			local otherHrp = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
			if otherHrp and (otherHrp.Position - origin).Magnitude <= FLASHBANG_RADIUS then
				FlashbangEffect:FireClient(other, FLASHBANG_DURATION)
			end
		end
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
			attachCodeTag(character, playerCodes[plr])
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
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
