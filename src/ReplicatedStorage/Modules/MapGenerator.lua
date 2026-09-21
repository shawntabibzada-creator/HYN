-- Builds a fresh, randomly laid out town-block arena each round: a street
-- grid of lots, each becoming a building (walls + a doorway + roof), a
-- crate yard, or an open plaza, plus streetlights. Spawn points sit at the
-- street intersections so nobody spawns inside a wall.
local MapGenerator = {}

local GRID = 5
local LOT_SIZE = 26
local STREET_WIDTH = 12
local ARENA_SIZE = GRID * LOT_SIZE + (GRID + 1) * STREET_WIDTH
local BOUNDARY_HEIGHT = 24

local BUILDING_MATERIALS = {
	{ Material = Enum.Material.Brick, Color = Color3.fromRGB(146, 92, 68) },
	{ Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(120, 85, 55) },
	{ Material = Enum.Material.Concrete, Color = Color3.fromRGB(150, 150, 145) },
	{ Material = Enum.Material.Metal, Color = Color3.fromRGB(110, 115, 120) },
	{ Material = Enum.Material.Slate, Color = Color3.fromRGB(90, 95, 100) },
}

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

local function buildSidewalk(parent, centerX, centerZ, color)
	local pad = newPart({
		Name = "Sidewalk",
		Size = Vector3.new(LOT_SIZE, 0.4, LOT_SIZE),
		Position = Vector3.new(centerX, 0.2, centerZ),
		Color = color,
		Material = Enum.Material.Concrete,
	})
	pad.Parent = parent
end

local function buildBuilding(parent, rng, centerX, centerZ)
	local width = rng:NextNumber(LOT_SIZE * 0.55, LOT_SIZE * 0.85)
	local depth = rng:NextNumber(LOT_SIZE * 0.55, LOT_SIZE * 0.85)
	local height = rng:NextNumber(14, 26)
	local wallThickness = 1.5
	local doorWidth = 6.5
	local matInfo = BUILDING_MATERIALS[rng:NextInteger(1, #BUILDING_MATERIALS)]
	local doorSide = rng:NextInteger(1, 4)
	local halfW, halfD = width / 2, depth / 2

	local function wallPart(sizeX, sizeZ, offsetX, offsetZ)
		local part = newPart({
			Name = "BuildingWall",
			Size = Vector3.new(sizeX, height, sizeZ),
			Position = Vector3.new(centerX + offsetX, height / 2, centerZ + offsetZ),
			Color = matInfo.Color,
			Material = matInfo.Material,
		})
		part.Parent = parent
	end

	-- Front (+Z)
	if doorSide == 1 then
		local segLen = math.max((width - doorWidth) / 2, 1)
		wallPart(segLen, wallThickness, -(width - segLen) / 2, halfD)
		wallPart(segLen, wallThickness, (width - segLen) / 2, halfD)
	else
		wallPart(width, wallThickness, 0, halfD)
	end

	-- Back (-Z)
	if doorSide == 2 then
		local segLen = math.max((width - doorWidth) / 2, 1)
		wallPart(segLen, wallThickness, -(width - segLen) / 2, -halfD)
		wallPart(segLen, wallThickness, (width - segLen) / 2, -halfD)
	else
		wallPart(width, wallThickness, 0, -halfD)
	end

	-- Right (+X)
	if doorSide == 3 then
		local segLen = math.max((depth - doorWidth) / 2, 1)
		wallPart(wallThickness, segLen, halfW, -(depth - segLen) / 2)
		wallPart(wallThickness, segLen, halfW, (depth - segLen) / 2)
	else
		wallPart(wallThickness, depth, halfW, 0)
	end

	-- Left (-X)
	if doorSide == 4 then
		local segLen = math.max((depth - doorWidth) / 2, 1)
		wallPart(wallThickness, segLen, -halfW, -(depth - segLen) / 2)
		wallPart(wallThickness, segLen, -halfW, (depth - segLen) / 2)
	else
		wallPart(wallThickness, depth, -halfW, 0)
	end

	local roof = newPart({
		Name = "Roof",
		Size = Vector3.new(width + 1.5, 1, depth + 1.5),
		Position = Vector3.new(centerX, height + 0.5, centerZ),
		Color = Color3.fromRGB(55, 55, 60),
		Material = Enum.Material.Slate,
	})
	roof.Parent = parent

	buildSidewalk(parent, centerX, centerZ, Color3.fromRGB(165, 165, 160))
end

local function buildCrateYard(parent, rng, centerX, centerZ)
	buildSidewalk(parent, centerX, centerZ, Color3.fromRGB(150, 140, 120))

	local crateCount = rng:NextInteger(4, 8)
	for _ = 1, crateCount do
		local size = rng:NextNumber(4, 7)
		local x = centerX + rng:NextNumber(-LOT_SIZE / 2 + 4, LOT_SIZE / 2 - 4)
		local z = centerZ + rng:NextNumber(-LOT_SIZE / 2 + 4, LOT_SIZE / 2 - 4)
		local crate = newPart({
			Name = "Crate",
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x, size / 2, z),
			Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
			Color = Color3.fromRGB(150, 110, 65),
			Material = Enum.Material.WoodPlanks,
		})
		crate.Parent = parent
	end
end

local function buildPlaza(parent, rng, centerX, centerZ)
	buildSidewalk(parent, centerX, centerZ, Color3.fromRGB(180, 178, 170))

	local benchCount = rng:NextInteger(0, 2)
	for i = 1, benchCount do
		local bench = newPart({
			Name = "Bench",
			Size = Vector3.new(5, 1.4, 1.6),
			Position = Vector3.new(centerX + (i == 1 and -6 or 6), 0.9, centerZ),
			Color = Color3.fromRGB(90, 60, 40),
			Material = Enum.Material.Wood,
		})
		bench.Parent = parent
	end
end

local function buildStreetLamp(parent, x, z)
	local pole = newPart({
		Name = "LampPost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(8, 0.6, 0.6),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(x, 4, z),
		Color = Color3.fromRGB(40, 40, 42),
		Material = Enum.Material.Metal,
	})
	pole.Parent = parent

	local lamp = newPart({
		Name = "LampHead",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = Vector3.new(x, 8, z),
		Color = Color3.fromRGB(255, 244, 200),
		Material = Enum.Material.Neon,
	})
	lamp.Parent = parent

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 235, 180)
	light.Range = 20
	light.Brightness = 1.5
	light.Parent = lamp
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
		Color = Color3.fromRGB(58, 58, 60),
		Material = Enum.Material.Asphalt,
	})
	floor.Parent = mapFolder

	local wallSpecs = {
		{ Vector3.new(ARENA_SIZE + 4, BOUNDARY_HEIGHT, 2), Vector3.new(0, BOUNDARY_HEIGHT / 2, half) },
		{ Vector3.new(ARENA_SIZE + 4, BOUNDARY_HEIGHT, 2), Vector3.new(0, BOUNDARY_HEIGHT / 2, -half) },
		{ Vector3.new(2, BOUNDARY_HEIGHT, ARENA_SIZE + 4), Vector3.new(half, BOUNDARY_HEIGHT / 2, 0) },
		{ Vector3.new(2, BOUNDARY_HEIGHT, ARENA_SIZE + 4), Vector3.new(-half, BOUNDARY_HEIGHT / 2, 0) },
	}
	for _, spec in ipairs(wallSpecs) do
		local wall = newPart({
			Name = "Boundary",
			Size = spec[1],
			Position = spec[2],
			Color = Color3.fromRGB(32, 32, 38),
			Material = Enum.Material.Concrete,
		})
		wall.Parent = mapFolder
	end

	for i = 0, GRID - 1 do
		for j = 0, GRID - 1 do
			local centerX = -half + STREET_WIDTH + LOT_SIZE / 2 + i * (LOT_SIZE + STREET_WIDTH)
			local centerZ = -half + STREET_WIDTH + LOT_SIZE / 2 + j * (LOT_SIZE + STREET_WIDTH)

			local roll = rng:NextNumber()
			if roll < 0.6 then
				buildBuilding(mapFolder, rng, centerX, centerZ)
			elseif roll < 0.82 then
				buildCrateYard(mapFolder, rng, centerX, centerZ)
			else
				buildPlaza(mapFolder, rng, centerX, centerZ)
			end

			if rng:NextNumber() < 0.5 then
				local lampX = centerX - LOT_SIZE / 2 - STREET_WIDTH / 2
				local lampZ = centerZ - LOT_SIZE / 2 - STREET_WIDTH / 2
				buildStreetLamp(mapFolder, lampX, lampZ)
			end
		end
	end

	local spawnPoints = {}
	for i = 0, GRID do
		for j = 0, GRID do
			local x = -half + i * (LOT_SIZE + STREET_WIDTH) + STREET_WIDTH / 2
			local z = -half + j * (LOT_SIZE + STREET_WIDTH) + STREET_WIDTH / 2
			table.insert(spawnPoints, CFrame.new(x, 5, z))
		end
	end

	mapFolder.Parent = parent
	return mapFolder, spawnPoints
end

return MapGenerator
