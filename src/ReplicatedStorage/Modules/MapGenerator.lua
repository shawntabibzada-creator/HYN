-- Builds a fresh, randomly laid out FFA arena each round: a bounded floor,
-- boundary walls, a scatter of non-overlapping cover blocks, and a ring of
-- spawn points around the edge.
local MapGenerator = {}

local ARENA_SIZE = 140
local WALL_HEIGHT = 20
local OBSTACLE_MIN, OBSTACLE_MAX = 16, 26
local OBSTACLE_MIN_SPACING = 14
local SPAWN_COUNT = 24

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		p[key] = value
	end
	return p
end

function MapGenerator.Generate(parent)
	local rng = Random.new()
	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "GeneratedMap"

	local half = ARENA_SIZE / 2

	local floor = newPart({
		Name = "Floor",
		Size = Vector3.new(ARENA_SIZE, 4, ARENA_SIZE),
		Position = Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(60, 60, 66),
		Material = Enum.Material.Concrete,
	})
	floor.Parent = mapFolder

	local wallSpecs = {
		{ Vector3.new(ARENA_SIZE + 4, WALL_HEIGHT, 2), Vector3.new(0, WALL_HEIGHT / 2, half) },
		{ Vector3.new(ARENA_SIZE + 4, WALL_HEIGHT, 2), Vector3.new(0, WALL_HEIGHT / 2, -half) },
		{ Vector3.new(2, WALL_HEIGHT, ARENA_SIZE + 4), Vector3.new(half, WALL_HEIGHT / 2, 0) },
		{ Vector3.new(2, WALL_HEIGHT, ARENA_SIZE + 4), Vector3.new(-half, WALL_HEIGHT / 2, 0) },
	}
	for _, spec in ipairs(wallSpecs) do
		local wall = newPart({
			Name = "Boundary",
			Size = spec[1],
			Position = spec[2],
			Color = Color3.fromRGB(32, 32, 38),
			Material = Enum.Material.Slate,
		})
		wall.Parent = mapFolder
	end

	local obstacleCount = rng:NextInteger(OBSTACLE_MIN, OBSTACLE_MAX)
	local placed = {}
	local attempts = 0
	while #placed < obstacleCount and attempts < obstacleCount * 10 do
		attempts += 1
		local x = rng:NextNumber(-half + 10, half - 10)
		local z = rng:NextNumber(-half + 10, half - 10)

		local tooClose = false
		for _, other in ipairs(placed) do
			if (Vector2.new(x, z) - Vector2.new(other.x, other.z)).Magnitude < OBSTACLE_MIN_SPACING then
				tooClose = true
				break
			end
		end

		if not tooClose then
			table.insert(placed, { x = x, z = z })
			local sizeX = rng:NextNumber(6, 16)
			local sizeZ = rng:NextNumber(6, 16)
			local sizeY = rng:NextNumber(6, 14)
			local block = newPart({
				Name = "Obstacle",
				Size = Vector3.new(sizeX, sizeY, sizeZ),
				Position = Vector3.new(x, sizeY / 2, z),
				Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
				Color = Color3.fromRGB(rng:NextInteger(80, 150), rng:NextInteger(80, 150), rng:NextInteger(80, 150)),
				Material = Enum.Material.Concrete,
			})
			block.Parent = mapFolder
		end
	end

	local spawnPoints = {}
	for i = 1, SPAWN_COUNT do
		local angle = (i / SPAWN_COUNT) * math.pi * 2
		local radius = half - 8
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		table.insert(spawnPoints, CFrame.new(x, 5, z))
	end

	mapFolder.Parent = parent
	return mapFolder, spawnPoints
end

return MapGenerator
