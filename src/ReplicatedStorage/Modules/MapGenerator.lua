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

-- Four walls forming a box with a door gap in one side (doorSide:
-- 1=+Z front, 2=-Z back, 3=+X right, 4=-X left). wallPart(sizeX, sizeZ,
-- offsetX, offsetZ) is supplied by the caller, already carrying its own
-- centerX/centerZ/height/color/material/parent closure - this function
-- only works out each wall segment's size and offset. Shared by Town's
-- buildings and Compound's bunkers so the door-gap math isn't duplicated.
local function buildWalledBox(width, depth, wallThickness, doorWidth, doorSide, wallPart)
	local halfW, halfD = width / 2, depth / 2

	if doorSide == 1 then
		local segLen = math.max((width - doorWidth) / 2, 1)
		wallPart(segLen, wallThickness, -(width - segLen) / 2, halfD)
		wallPart(segLen, wallThickness, (width - segLen) / 2, halfD)
	else
		wallPart(width, wallThickness, 0, halfD)
	end

	if doorSide == 2 then
		local segLen = math.max((width - doorWidth) / 2, 1)
		wallPart(segLen, wallThickness, -(width - segLen) / 2, -halfD)
		wallPart(segLen, wallThickness, (width - segLen) / 2, -halfD)
	else
		wallPart(width, wallThickness, 0, -halfD)
	end

	if doorSide == 3 then
		local segLen = math.max((depth - doorWidth) / 2, 1)
		wallPart(wallThickness, segLen, halfW, -(depth - segLen) / 2)
		wallPart(wallThickness, segLen, halfW, (depth - segLen) / 2)
	else
		wallPart(wallThickness, depth, halfW, 0)
	end

	if doorSide == 4 then
		local segLen = math.max((depth - doorWidth) / 2, 1)
		wallPart(wallThickness, segLen, -halfW, -(depth - segLen) / 2)
		wallPart(wallThickness, segLen, -halfW, (depth - segLen) / 2)
	else
		wallPart(wallThickness, depth, -halfW, 0)
	end
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

	buildWalledBox(width, depth, wallThickness, doorWidth, doorSide, wallPart)

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

-- A plaza is never just a bare pad: a tree at the center plus at least one
-- bench, so it reads as a built park rather than an empty gap in the grid.
local function buildPlaza(parent, rng, centerX, centerZ)
	buildSidewalk(parent, centerX, centerZ, Color3.fromRGB(180, 178, 170))

	local trunk = newPart({
		Name = "TreeTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 1, 1),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(centerX, 3, centerZ),
		Color = Color3.fromRGB(90, 60, 40),
		Material = Enum.Material.Wood,
	})
	trunk.Parent = parent

	local foliage = newPart({
		Name = "TreeFoliage",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 9, 9),
		Position = Vector3.new(centerX, 8, centerZ),
		Color = Color3.fromRGB(50, 110, 55),
		Material = Enum.Material.Grass,
	})
	foliage.Parent = parent

	local benchCount = rng:NextInteger(1, 3)
	for i = 1, benchCount do
		local angle = (i / benchCount) * math.pi * 2
		local bench = newPart({
			Name = "Bench",
			Size = Vector3.new(5, 1.4, 1.6),
			Position = Vector3.new(centerX + math.cos(angle) * 8, 0.9, centerZ + math.sin(angle) * 8),
			Orientation = Vector3.new(0, math.deg(angle) + 90, 0),
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
			if roll < 0.75 then
				buildBuilding(mapFolder, rng, centerX, centerZ)
			elseif roll < 0.9 then
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
-- Compound (three tiers: an open ground floor with small bunkers, a mid
-- deck spanning most of one half of the arena, and a smaller top deck
-- stacked above its far end - real king-of-the-hill high ground, reached
-- only by climbing through the mid deck first)
--------------------------------------------------------------------------

local COMPOUND_ARENA_SIZE = 200
local COMPOUND_BOUNDARY_HEIGHT = 32
local COMPOUND_MID_HEIGHT = 10
local COMPOUND_TOP_HEIGHT = 20
local COMPOUND_MID_X_MIN = 8 -- leaves the open ground half fully clear
local COMPOUND_TOP_WIDTH = 26
local COMPOUND_TOP_Z_HALF = 30
local COMPOUND_RAMP_WIDTH = 10
local COMPOUND_RAMP_RUN = 16
local COMPOUND_BUNKER_SIZE = 16

local COMPOUND_BUNKER_MATERIALS = {
	{ Material = Enum.Material.Concrete, Color = Color3.fromRGB(95, 97, 100) },
	{ Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 84, 90) },
	{ Material = Enum.Material.CorrodedMetal, Color = Color3.fromRGB(90, 78, 60) },
}

local function buildBunker(parent, rng, centerX, centerZ, size)
	local height = 11
	local wallThickness = 1.5
	local doorWidth = 5
	local doorSide = rng:NextInteger(1, 4)
	local matInfo = COMPOUND_BUNKER_MATERIALS[rng:NextInteger(1, #COMPOUND_BUNKER_MATERIALS)]

	local function wallPart(sizeX, sizeZ, offsetX, offsetZ)
		local part = newPart({
			Name = "BunkerWall",
			Size = Vector3.new(sizeX, height, sizeZ),
			Position = Vector3.new(centerX + offsetX, height / 2, centerZ + offsetZ),
			Color = matInfo.Color,
			Material = matInfo.Material,
		})
		part.Parent = parent
	end

	buildWalledBox(size, size, wallThickness, doorWidth, doorSide, wallPart)

	local roof = newPart({
		Name = "BunkerRoof",
		Size = Vector3.new(size + 1, 1, size + 1),
		Position = Vector3.new(centerX, height + 0.5, centerZ),
		Color = Color3.fromRGB(60, 62, 66),
		Material = Enum.Material.Metal,
	})
	roof.Parent = parent
end

local function generateCompound(mapFolder)
	local rng = Random.new()
	local half = COMPOUND_ARENA_SIZE / 2

	buildFloor(mapFolder, COMPOUND_ARENA_SIZE, Color3.fromRGB(70, 72, 76), Enum.Material.Concrete)
	buildBoundary(mapFolder, COMPOUND_ARENA_SIZE, COMPOUND_BOUNDARY_HEIGHT, Color3.fromRGB(35, 36, 40))

	-- Mid deck: spans most of the +X half of the arena end to end. Its
	-- inner edge (facing the open ground half) is deliberately left open
	-- so you can see and drop down; the far edge sits flush against the
	-- arena's own boundary wall for containment.
	local midXMax = half - 4
	local midWidth = midXMax - COMPOUND_MID_X_MIN
	local midDepth = COMPOUND_ARENA_SIZE - 16
	local midCenterX = (COMPOUND_MID_X_MIN + midXMax) / 2

	local midDeck = newPart({
		Name = "MidDeck",
		Size = Vector3.new(midWidth, 1.5, midDepth),
		Position = Vector3.new(midCenterX, COMPOUND_MID_HEIGHT, 0),
		Color = Color3.fromRGB(90, 92, 98),
		Material = Enum.Material.DiamondPlate,
	})
	midDeck.Parent = mapFolder

	-- Top deck: a smaller box stacked above the mid deck's far end,
	-- sharing its far edge (and the boundary wall behind it) and reached
	-- only by climbing a second set of ramps up from the mid deck itself.
	local topXMin = midXMax - COMPOUND_TOP_WIDTH
	local topDepth = COMPOUND_TOP_Z_HALF * 2
	local topCenterX = (topXMin + midXMax) / 2

	local topDeck = newPart({
		Name = "TopDeck",
		Size = Vector3.new(COMPOUND_TOP_WIDTH, 1.5, topDepth),
		Position = Vector3.new(topCenterX, COMPOUND_TOP_HEIGHT, 0),
		Color = Color3.fromRGB(110, 100, 95),
		Material = Enum.Material.DiamondPlate,
	})
	topDeck.Parent = mapFolder

	-- Ground -> mid ramps at opposite ends of the deck. The top point
	-- lands exactly on the deck's real edge (COMPOUND_MID_X_MIN), not
	-- somewhere under the slab.
	for _, z in ipairs({ -half * 0.55, half * 0.55 }) do
		local basePoint = Vector3.new(COMPOUND_MID_X_MIN - COMPOUND_RAMP_RUN, 0.2, z)
		local topPoint = Vector3.new(COMPOUND_MID_X_MIN, COMPOUND_MID_HEIGHT, z)
		buildRamp(mapFolder, basePoint, topPoint, COMPOUND_RAMP_WIDTH, 1, Color3.fromRGB(90, 92, 98))
	end

	-- Mid -> top ramps, climbing from the mid deck's own surface up to
	-- the top deck's real edge (topXMin).
	for _, z in ipairs({ -COMPOUND_TOP_Z_HALF * 0.5, COMPOUND_TOP_Z_HALF * 0.5 }) do
		local basePoint = Vector3.new(topXMin - COMPOUND_RAMP_RUN, COMPOUND_MID_HEIGHT, z)
		local topPoint = Vector3.new(topXMin, COMPOUND_TOP_HEIGHT, z)
		buildRamp(mapFolder, basePoint, topPoint, COMPOUND_RAMP_WIDTH, 1, Color3.fromRGB(120, 110, 100))
	end

	-- Ground level: small enclosed bunkers on the open side for real
	-- cover, not just crates, plus scattered crates elsewhere.
	local bunkerX = -half + 32
	local bunkerZs = { -half * 0.55, 0, half * 0.55 }
	for _, z in ipairs(bunkerZs) do
		buildBunker(mapFolder, rng, bunkerX, z, COMPOUND_BUNKER_SIZE)
	end

	local groundCrateCount = rng:NextInteger(6, 10)
	for _ = 1, groundCrateCount do
		local x = rng:NextNumber(-half + 10, COMPOUND_MID_X_MIN - 4)
		local z = rng:NextNumber(-half + 10, half - 10)
		local nearBunker = false
		for _, bz in ipairs(bunkerZs) do
			if Vector2.new(x - bunkerX, z - bz).Magnitude < 14 then
				nearBunker = true
				break
			end
		end
		if not nearBunker then
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

	-- Mid deck cover.
	local midCrateCount = rng:NextInteger(5, 8)
	for _ = 1, midCrateCount do
		local x = rng:NextNumber(COMPOUND_MID_X_MIN + 6, midXMax - 6)
		local z = rng:NextNumber(-midDepth / 2 + 10, midDepth / 2 - 10)
		local size = rng:NextNumber(4, 6)
		local crate = newPart({
			Name = "Crate",
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x, COMPOUND_MID_HEIGHT + 0.75 + size / 2, z),
			Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
			Color = Color3.fromRGB(150, 110, 65),
			Material = Enum.Material.WoodPlanks,
		})
		crate.Parent = mapFolder
	end

	-- Top deck cover - tight, so a couple of crates is plenty.
	local topCrateCount = rng:NextInteger(2, 4)
	for _ = 1, topCrateCount do
		local x = rng:NextNumber(topXMin + 5, midXMax - 5)
		local z = rng:NextNumber(-COMPOUND_TOP_Z_HALF + 6, COMPOUND_TOP_Z_HALF - 6)
		local size = rng:NextNumber(4, 5)
		local crate = newPart({
			Name = "Crate",
			Size = Vector3.new(size, size, size),
			Position = Vector3.new(x, COMPOUND_TOP_HEIGHT + 0.75 + size / 2, z),
			Orientation = Vector3.new(0, rng:NextInteger(0, 359), 0),
			Color = Color3.fromRGB(150, 110, 65),
			Material = Enum.Material.WoodPlanks,
		})
		crate.Parent = mapFolder
	end

	local spawnPoints = {}

	-- Ground-level spawns around the whole lower footprint.
	local groundSpawnCount = 16
	for i = 1, groundSpawnCount do
		local angle = (i / groundSpawnCount) * math.pi * 2
		local radius = half - 10
		table.insert(spawnPoints, CFrame.new(math.cos(angle) * radius, 3, math.sin(angle) * radius))
	end

	-- Mid deck spawns along its length.
	local midSpawnCount = 8
	for i = 1, midSpawnCount do
		local t = (i - 0.5) / midSpawnCount
		local z = -midDepth / 2 + t * midDepth
		table.insert(spawnPoints, CFrame.new(midCenterX, COMPOUND_MID_HEIGHT + 3, z))
	end

	-- Top deck spawns.
	local topSpawnCount = 4
	for i = 1, topSpawnCount do
		local t = (i - 0.5) / topSpawnCount
		local z = -COMPOUND_TOP_Z_HALF + t * topDepth
		table.insert(spawnPoints, CFrame.new(topCenterX, COMPOUND_TOP_HEIGHT + 3, z))
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
