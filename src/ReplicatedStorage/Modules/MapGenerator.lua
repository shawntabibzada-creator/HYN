-- Builds a fresh, randomly laid out arena each round, from a choice of
-- map types:
--   Town     - a street grid of lots, each a building (walls + a doorway
--              + roof), a crate yard, or an open plaza, plus streetlights.
--   Compound - ground-level cover plus several elevated platforms reached
--              by ramps, for a map with real verticality.
--   Desert   - a big, completely open arena of rolling sand dunes (real
--              Terrain, not props), so elevation itself is the only cover.
local MapGenerator = {}

local Workspace = game:GetService("Workspace")

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

local function buildFloor(parent, size, color, material)
	local floor = newPart({
		Name = "Floor",
		Size = Vector3.new(size, 4, size),
		Position = Vector3.new(0, -2, 0),
		Color = color,
		Material = material,
	})
	floor.Parent = parent
end

local function buildBoundary(parent, size, height, color)
	local half = size / 2
	local specs = {
		{ Vector3.new(size + 4, height, 2), Vector3.new(0, height / 2, half) },
		{ Vector3.new(size + 4, height, 2), Vector3.new(0, height / 2, -half) },
		{ Vector3.new(2, height, size + 4), Vector3.new(half, height / 2, 0) },
		{ Vector3.new(2, height, size + 4), Vector3.new(-half, height / 2, 0) },
	}
	for _, spec in ipairs(specs) do
		local wall = newPart({
			Name = "Boundary",
			Size = spec[1],
			Position = spec[2],
			Color = color,
			Material = Enum.Material.Concrete,
		})
		wall.Parent = parent
	end
end

-- A flat inclined plank spanning exactly from basePos to topPos. Simpler
-- and less orientation-fragile than relying on WedgePart's local axis
-- convention, and just as walkable.
local function buildRamp(parent, basePos, topPos, width, thickness, color)
	local direction = topPos - basePos
	local length = direction.Magnitude
	local midPoint = basePos + direction * 0.5
	local cframe = CFrame.lookAt(midPoint, topPos, Vector3.new(0, 1, 0))
	local ramp = newPart({
		Name = "Ramp",
		Size = Vector3.new(width, thickness, length),
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.DiamondPlate,
	})
	ramp.Parent = parent
end

--------------------------------------------------------------------------
-- Town
--------------------------------------------------------------------------

local TOWN_GRID = 5
local TOWN_LOT_SIZE = 26
local TOWN_STREET_WIDTH = 12
local TOWN_ARENA_SIZE = TOWN_GRID * TOWN_LOT_SIZE + (TOWN_GRID + 1) * TOWN_STREET_WIDTH
local TOWN_BOUNDARY_HEIGHT = 24

local BUILDING_MATERIALS = {
	{ Material = Enum.Material.Brick, Color = Color3.fromRGB(146, 92, 68) },
	{ Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(120, 85, 55) },
	{ Material = Enum.Material.Concrete, Color = Color3.fromRGB(150, 150, 145) },
	{ Material = Enum.Material.Metal, Color = Color3.fromRGB(110, 115, 120) },
	{ Material = Enum.Material.Slate, Color = Color3.fromRGB(90, 95, 100) },
}

local function buildSidewalk(parent, centerX, centerZ, color)
	local pad = newPart({
		Name = "Sidewalk",
		Size = Vector3.new(TOWN_LOT_SIZE, 0.4, TOWN_LOT_SIZE),
		Position = Vector3.new(centerX, 0.2, centerZ),
		Color = color,
		Material = Enum.Material.Concrete,
	})
	pad.Parent = parent
end

local function buildBuilding(parent, rng, centerX, centerZ)
	local width = rng:NextNumber(TOWN_LOT_SIZE * 0.55, TOWN_LOT_SIZE * 0.85)
	local depth = rng:NextNumber(TOWN_LOT_SIZE * 0.55, TOWN_LOT_SIZE * 0.85)
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
		local x = centerX + rng:NextNumber(-TOWN_LOT_SIZE / 2 + 4, TOWN_LOT_SIZE / 2 - 4)
		local z = centerZ + rng:NextNumber(-TOWN_LOT_SIZE / 2 + 4, TOWN_LOT_SIZE / 2 - 4)
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

local function generateTown(mapFolder)
	local rng = Random.new()
	local half = TOWN_ARENA_SIZE / 2

	buildFloor(mapFolder, TOWN_ARENA_SIZE, Color3.fromRGB(58, 58, 60), Enum.Material.Asphalt)
	buildBoundary(mapFolder, TOWN_ARENA_SIZE, TOWN_BOUNDARY_HEIGHT, Color3.fromRGB(32, 32, 38))

	for i = 0, TOWN_GRID - 1 do
		for j = 0, TOWN_GRID - 1 do
			local centerX = -half + TOWN_STREET_WIDTH + TOWN_LOT_SIZE / 2 + i * (TOWN_LOT_SIZE + TOWN_STREET_WIDTH)
			local centerZ = -half + TOWN_STREET_WIDTH + TOWN_LOT_SIZE / 2 + j * (TOWN_LOT_SIZE + TOWN_STREET_WIDTH)

			local roll = rng:NextNumber()
			if roll < 0.6 then
				buildBuilding(mapFolder, rng, centerX, centerZ)
			elseif roll < 0.82 then
				buildCrateYard(mapFolder, rng, centerX, centerZ)
			else
				buildPlaza(mapFolder, rng, centerX, centerZ)
			end

			if rng:NextNumber() < 0.5 then
				local lampX = centerX - TOWN_LOT_SIZE / 2 - TOWN_STREET_WIDTH / 2
				local lampZ = centerZ - TOWN_LOT_SIZE / 2 - TOWN_STREET_WIDTH / 2
				buildStreetLamp(mapFolder, lampX, lampZ)
			end
		end
	end

	local spawnPoints = {}
	for i = 0, TOWN_GRID do
		for j = 0, TOWN_GRID do
			local x = -half + i * (TOWN_LOT_SIZE + TOWN_STREET_WIDTH) + TOWN_STREET_WIDTH / 2
			local z = -half + j * (TOWN_LOT_SIZE + TOWN_STREET_WIDTH) + TOWN_STREET_WIDTH / 2
			table.insert(spawnPoints, CFrame.new(x, 5, z))
		end
	end

	return spawnPoints
end

--------------------------------------------------------------------------
-- Compound (two full levels: a ground floor and a raised deck covering
-- half the arena, joined by ramps at both ends - a Dust2-mid-ramp shape
-- rather than a handful of floating islands)
--------------------------------------------------------------------------

local COMPOUND_ARENA_SIZE = 190
local COMPOUND_BOUNDARY_HEIGHT = 26
local COMPOUND_PLATFORM_HEIGHT = 14
local COMPOUND_PLATFORM_X_MIN = 6 -- leaves the lower half fully open, deck starts here
local COMPOUND_RAMP_WIDTH = 10

local function generateCompound(mapFolder)
	local rng = Random.new()
	local half = COMPOUND_ARENA_SIZE / 2

	buildFloor(mapFolder, COMPOUND_ARENA_SIZE, Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	buildBoundary(mapFolder, COMPOUND_ARENA_SIZE, COMPOUND_BOUNDARY_HEIGHT, Color3.fromRGB(35, 36, 40))

	-- Upper level: one full deck spanning the +X half of the arena and
	-- nearly its whole depth, walkable end to end. It relies on the
	-- arena's own boundary walls for containment on 3 sides; its inner
	-- edge (facing the lower half) is deliberately left open so you can
	-- see and drop straight down into the lower level.
	local platformXMax = half - 4
	local platformWidth = platformXMax - COMPOUND_PLATFORM_X_MIN
	local platformDepth = COMPOUND_ARENA_SIZE - 8
	local platformCenterX = (COMPOUND_PLATFORM_X_MIN + platformXMax) / 2

	local platform = newPart({
		Name = "Platform",
		Size = Vector3.new(platformWidth, 1.5, platformDepth),
		Position = Vector3.new(platformCenterX, COMPOUND_PLATFORM_HEIGHT, 0),
		Color = Color3.fromRGB(90, 92, 98),
		Material = Enum.Material.DiamondPlate,
	})
	platform.Parent = mapFolder

	-- Two ramps up, at opposite ends of the deck, so there's more than one
	-- way to rotate between levels.
	for _, z in ipairs({ -half * 0.55, half * 0.55 }) do
		local basePoint = Vector3.new(-8, 0.2, z)
		local topPoint = Vector3.new(COMPOUND_PLATFORM_X_MIN + 14, COMPOUND_PLATFORM_HEIGHT, z)
		buildRamp(mapFolder, basePoint, topPoint, COMPOUND_RAMP_WIDTH, 1, Color3.fromRGB(90, 92, 98))
	end

	-- Ground-level cover, including the shaded area underneath the deck.
	local groundCrateCount = rng:NextInteger(8, 12)
	for _ = 1, groundCrateCount do
		local x = rng:NextNumber(-half + 10, half - 10)
		local z = rng:NextNumber(-half + 10, half - 10)
		if Vector2.new(x, z).Magnitude > 12 then
			local size = rng:NextNumber(5, 9)
			local crate = newPart({
				Name = "Crate",
				Size = Vector3.new(size, size, size),
				Position = Vector3.new(x, size / 2, z),
				Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
				Color = Color3.fromRGB(120, 120, 130),
				Material = Enum.Material.Metal,
			})
			crate.Parent = mapFolder
		end
	end

	-- Cover up on the deck too.
	local platformCrateCount = rng:NextInteger(5, 9)
	for _ = 1, platformCrateCount do
		local x = rng:NextNumber(COMPOUND_PLATFORM_X_MIN + 6, platformXMax - 6)
		local z = rng:NextNumber(-platformDepth / 2 + 10, platformDepth / 2 - 10)
		local size = rng:NextNumber(4, 6)
		local crate = newPart({
			Name = "Crate",
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x, COMPOUND_PLATFORM_HEIGHT + 0.75 + size / 2, z),
			Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
			Color = Color3.fromRGB(150, 110, 65),
			Material = Enum.Material.WoodPlanks,
		})
		crate.Parent = mapFolder
	end

	local spawnPoints = {}

	-- Ground-level spawns spread across the whole lower footprint,
	-- including under the deck.
	local groundSpawnCount = 16
	for i = 1, groundSpawnCount do
		local angle = (i / groundSpawnCount) * math.pi * 2
		local radius = half - 10
		table.insert(spawnPoints, CFrame.new(math.cos(angle) * radius, 3, math.sin(angle) * radius))
	end

	-- Deck-level spawns spread along its length.
	local platformSpawnCount = 10
	for i = 1, platformSpawnCount do
		local t = (i - 0.5) / platformSpawnCount
		local z = -platformDepth / 2 + t * platformDepth
		table.insert(spawnPoints, CFrame.new(platformCenterX, COMPOUND_PLATFORM_HEIGHT + 3, z))
	end

	return spawnPoints
end

--------------------------------------------------------------------------
-- Desert (open, rolling sand dunes via real Terrain - no props/cover)
--------------------------------------------------------------------------

local DESERT_ARENA_SIZE = 200
local DESERT_BOUNDARY_HEIGHT = 55
local DESERT_CELL_SIZE = 10
local DESERT_MAX_DUNE_HEIGHT = 26
local DESERT_MIN_DUNE_HEIGHT = 3
local DESERT_NOISE_SCALE = 0.02
local DESERT_TERRAIN_FLOOR_Y = -12 -- how deep each terrain column's base sits

-- The single source of truth for dune height at a point: used both to
-- fill the terrain and to place spawn points, so spawns always land
-- exactly on the surface that was actually built (no raycasting against
-- freshly-generated terrain, which can miss before its collision mesh is
-- ready and silently drop a spawn point below the sand).
local function duneHeightAt(x, z, seed)
	local sample = (math.noise(x * DESERT_NOISE_SCALE, z * DESERT_NOISE_SCALE, seed) + 1) / 2
	return DESERT_MIN_DUNE_HEIGHT + sample * (DESERT_MAX_DUNE_HEIGHT - DESERT_MIN_DUNE_HEIGHT)
end

local function generateDesert(mapFolder)
	local rng = Random.new()
	local half = DESERT_ARENA_SIZE / 2
	local seed = rng:NextNumber(0, 1000)

	buildBoundary(mapFolder, DESERT_ARENA_SIZE, DESERT_BOUNDARY_HEIGHT, Color3.fromRGB(150, 130, 95))

	local terrain = Workspace.Terrain
	local x = -half
	while x < half do
		local z = -half
		while z < half do
			local topY = duneHeightAt(x, z, seed)
			local blockHeight = topY - DESERT_TERRAIN_FLOOR_Y
			local centerY = (topY + DESERT_TERRAIN_FLOOR_Y) / 2
			terrain:FillBlock(
				CFrame.new(x + DESERT_CELL_SIZE / 2, centerY, z + DESERT_CELL_SIZE / 2),
				Vector3.new(DESERT_CELL_SIZE, blockHeight, DESERT_CELL_SIZE),
				Enum.Material.Sand
			)
			z += DESERT_CELL_SIZE
		end
		x += DESERT_CELL_SIZE
	end

	-- Smooth Terrain blends neighboring FillBlock columns into curved
	-- dunes rather than sharp steps, so the real surface at an arbitrary
	-- (x, z) can sit a few studs off from what duneHeightAt() alone would
	-- suggest - worse the bigger the height difference between
	-- neighboring cells. Rather than chase an exact match, spawn well
	-- above the formula height and let gravity settle the character onto
	-- whatever the actual surface turns out to be (there's no fall damage
	-- in this game, so the extra drop costs nothing).
	local spawnPoints = {}
	local spawnCount = 24
	for i = 1, spawnCount do
		local angle = (i / spawnCount) * math.pi * 2
		local radius = half - 10
		local sx, sz = math.cos(angle) * radius, math.sin(angle) * radius
		table.insert(spawnPoints, CFrame.new(sx, duneHeightAt(sx, sz, seed) + 15, sz))
	end

	return spawnPoints
end

--------------------------------------------------------------------------

local GENERATORS = {
	Town = generateTown,
	Compound = generateCompound,
	Desert = generateDesert,
}

-- Ordered for display in the shop; keys match ShopConfig's "Pick next
-- map" developer products' mapKey field.
MapGenerator.Choices = {
	{ key = "Town", name = "Town" },
	{ key = "Compound", name = "Compound" },
	{ key = "Desert", name = "Desert" },
}

function MapGenerator.RandomKey()
	local choice = MapGenerator.Choices[math.random(1, #MapGenerator.Choices)]
	return choice.key
end

function MapGenerator.Generate(mapKey, parent)
	local generator = GENERATORS[mapKey] or generateTown

	-- Terrain (the Desert map's dunes) lives outside any Folder we can
	-- just destroy, so clear it unconditionally before every generation -
	-- otherwise a previous Desert round's dunes would linger into a Town
	-- or Compound round.
	Workspace.Terrain:Clear()

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "GeneratedMap"

	local spawnPoints = generator(mapFolder)

	mapFolder.Parent = parent
	return mapFolder, spawnPoints
end

return MapGenerator
