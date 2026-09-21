-- Reveals a player's code tag to a viewer when any of these hold:
--   1. The viewer is close AND roughly in front of the target, like
--      reading a sign held at chest height (the normal case).
--   2. The target is within a recent scanner pulse's reveal radius,
--      regardless of the viewer's own position or facing.
--   3. The target is the viewer's teammate in Duos mode.
-- Everyone else sees nothing floating above their head. This is a
-- client-side visual restriction (each client independently toggles what
-- it renders); it is not a server-enforced secret.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ScannerEffect = Remotes:WaitForChild("ScannerEffect")

local VISIBLE_DISTANCE = 26
local FRONT_DOT_THRESHOLD = 0.35 -- roughly a 70-degree cone in front of the target

local scannerOverride -- { position: Vector3, radius: number, expiresAt: number }

ScannerEffect.OnClientEvent:Connect(function(position, radius, duration)
	scannerOverride = {
		position = position,
		radius = radius,
		expiresAt = os.clock() + duration,
	}
end)

local function getViewerPosition()
	local character = localPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		return hrp.Position
	end
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

RunService.Heartbeat:Connect(function()
	local viewerPos = getViewerPosition()
	if not viewerPos then
		return
	end

	local scannerLive = scannerOverride and os.clock() < scannerOverride.expiresAt
	local myTeamId = localPlayer:GetAttribute("TeamId")

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= localPlayer then
			local character = plr.Character
			local head = character and character:FindFirstChild("Head")
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local billboard = head and head:FindFirstChild("CodeTag")

			if billboard and hrp then
				-- Duos teammates always see each other's sign. myTeamId must
				-- be non-nil, or two FFA players (both nil) would match.
				if myTeamId and plr:GetAttribute("TeamId") == myTeamId then
					billboard.Enabled = true
				elseif scannerLive and (hrp.Position - scannerOverride.position).Magnitude <= scannerOverride.radius then
					billboard.Enabled = true
				else
					local toViewer = viewerPos - hrp.Position
					local distance = toViewer.Magnitude

					if distance <= VISIBLE_DISTANCE then
						local flatToViewer = Vector3.new(toViewer.X, 0, toViewer.Z)
						if flatToViewer.Magnitude > 0.001 then
							local targetLook = hrp.CFrame.LookVector
							local flatLook = Vector3.new(targetLook.X, 0, targetLook.Z).Unit
							local dot = flatLook:Dot(flatToViewer.Unit)
							billboard.Enabled = dot >= FRONT_DOT_THRESHOLD
						else
							billboard.Enabled = true
						end
					else
						billboard.Enabled = false
					end
				end
			end
		end
	end
end)
