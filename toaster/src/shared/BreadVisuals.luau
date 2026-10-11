-- Procedural bread bodies welded onto a standard humanoid character.
-- Built from primitive parts so no uploaded meshes are required. The server
-- builds and updates them; changes replicate to everyone.
--
-- Every bread has the same expressive face rig. Face parts are tagged with the
-- expressions they belong to and SetExpression shows/hides them, so a slice
-- smiles when fresh, sweats when hot, screams at critical heat and glares with
-- ember eyes as charcoal.

local Shared = script.Parent
local HeatMath = require(Shared.HeatMath)
local Theme = require(Shared.Theme)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)

local BreadVisuals = {}

local MODEL_NAME = "BreadVisual"

-- Per-bread colour offset on the toast ramp (bagels start darker, etc).
local HEAT_BIAS = {
	Bread = 0,
	Bagel = 30,
	Croissant = 25,
	Waffle = 20,
}

-- Height of the hat anchor above the root for each bread.
local TOP_Y = {
	Bread = 4.35,
	Bagel = 4.2,
	Croissant = 3.75,
	Waffle = 4.6,
}

-- Heat state -> facial expression.
BreadVisuals.ExpressionForState = {
	Normal = "Happy",
	Warm = "Uneasy",
	VeryHot = "Sweaty",
	Critical = "Panic",
	Burnt = "Charcoal",
	Golden = "Golden",
}

type PartSpec = {
	name: string,
	size: Vector3,
	offset: CFrame,
	tint: string?, -- "Body" | "Crust" | "Spot" | nil (fixed colour)
	color: Color3?,
	shape: Enum.PartType?,
	mesh: Vector3?, -- SpecialMesh sphere scale, for ellipsoids
	material: Enum.Material?,
	transparency: number?,
	expr: string?, -- comma list of expressions this part shows in (nil = always)
	shadow: boolean?,
}

local INK = Color3.fromRGB(58, 30, 16)
local MOUTH = Color3.fromRGB(70, 24, 18)
local TONGUE = Color3.fromRGB(232, 96, 110)
local BLUSH = Color3.fromRGB(255, 132, 132)
local SWEAT = Color3.fromRGB(150, 215, 255)
local EMBER = Color3.fromRGB(255, 120, 30)

-- Every visual part is welded to an invisible "BreadCore", which is joined to
-- the HumanoidRootPart by a single Weld ("BreadJoint"). Clients animate that
-- joint's C0 locally (e.g. the bagel roll) without touching physics.
local function makePart(root: BasePart, model: Model, spec: PartSpec): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Size = spec.size
	part.Shape = spec.shape or Enum.PartType.Block
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Color = spec.color or Theme.Colors.Crumb
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = spec.shadow ~= false
	part.CFrame = root.CFrame * spec.offset
	if spec.tint then
		part:SetAttribute("Tint", spec.tint)
	end
	if spec.expr then
		part:SetAttribute("Expr", "," .. spec.expr .. ",")
		part:SetAttribute("BaseTransparency", part.Transparency)
	end
	if spec.mesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = spec.mesh
		mesh.Parent = part
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local Z_AXIS = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z
local Y_AXIS = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis along Y

local function add(specs: { PartSpec }, spec: PartSpec)
	table.insert(specs, spec)
end

------------------------------------------------------------------ the face rig

type FaceLayout = {
	eyeY: number, -- eye centre height
	eyeX: number, -- half distance between the eyes
	z: number, -- the face surface (negative = front)
	mouthY: number,
	scale: number,
}

local EYES_OPEN = "Happy,Uneasy,Sweaty,Panic,Golden"

local function face(specs: { PartSpec }, f: FaceLayout)
	local s = f.scale
	local z = f.z
	for _, side in { -1, 1 } do
		local ex = side * f.eyeX
		-- eyes
		add(specs, {
			name = "Eye",
			size = Vector3.one * 1.05 * s,
			offset = CFrame.new(ex, f.eyeY, z),
			shape = Enum.PartType.Ball,
			color = Color3.new(1, 1, 1),
			expr = EYES_OPEN,
		})
		add(specs, {
			name = "Pupil",
			size = Vector3.one * 0.5 * s,
			offset = CFrame.new(ex * 0.94, f.eyeY - 0.05 * s, z - 0.4 * s),
			shape = Enum.PartType.Ball,
			color = Theme.Colors.Charcoal,
			expr = "Happy,Uneasy,Sweaty,Golden",
		})
		add(specs, {
			name = "PupilTiny",
			size = Vector3.one * 0.26 * s,
			offset = CFrame.new(ex * 0.98, f.eyeY, z - 0.5 * s),
			shape = Enum.PartType.Ball,
			color = Theme.Colors.Charcoal,
			expr = "Panic",
		})
		add(specs, {
			name = "Glint",
			size = Vector3.one * 0.17 * s,
			offset = CFrame.new(ex * 0.94 + 0.13 * s, f.eyeY + 0.12 * s, z - 0.6 * s),
			shape = Enum.PartType.Ball,
			color = Color3.new(1, 1, 1),
			material = Enum.Material.Neon,
			expr = "Happy,Uneasy,Sweaty,Golden",
			shadow = false,
		})
		-- brows: calm (raised), worried (inner ends up), angry (inner ends down)
		local browY = f.eyeY + 0.78 * s
		add(specs, {
			name = "Brow",
			size = Vector3.new(0.78, 0.16, 0.14) * s,
			offset = CFrame.new(ex, browY + 0.08 * s, z - 0.15 * s) * CFrame.Angles(0, 0, math.rad(side * -6)),
			color = INK,
			expr = "Happy,Golden",
		})
		add(specs, {
			name = "Brow",
			size = Vector3.new(0.8, 0.17, 0.14) * s,
			offset = CFrame.new(ex, browY, z - 0.15 * s) * CFrame.Angles(0, 0, math.rad(side * -20)),
			color = INK,
			expr = "Uneasy,Sweaty,Panic",
		})
		add(specs, {
			name = "Brow",
			size = Vector3.new(0.85, 0.2, 0.14) * s,
			offset = CFrame.new(ex, browY - 0.12 * s, z - 0.15 * s) * CFrame.Angles(0, 0, math.rad(side * 24)),
			color = Color3.fromRGB(10, 8, 7),
			expr = "Charcoal",
		})
		-- charcoal: glowing ember slits instead of eyes
		add(specs, {
			name = "EmberEye",
			size = Vector3.new(0.85, 0.24, 0.15) * s,
			offset = CFrame.new(ex, f.eyeY - 0.05 * s, z - 0.12 * s) * CFrame.Angles(0, 0, math.rad(side * 14)),
			color = EMBER,
			material = Enum.Material.Neon,
			expr = "Charcoal",
			shadow = false,
		})
		-- blush
		add(specs, {
			name = "Blush",
			size = Vector3.new(0.7, 0.36, 0.12) * s,
			offset = CFrame.new(side * (f.eyeX + 0.3 * s), f.mouthY + 0.32 * s, z - 0.02),
			color = BLUSH,
			mesh = Vector3.one,
			transparency = 0.35,
			expr = "Happy,Golden,Uneasy",
			shadow = false,
		})
	end

	-- mouths
	for i = -2, 2 do -- smile: an arc of beads, ends up
		local x = i * 0.24 * s
		add(specs, {
			name = "Smile",
			size = Vector3.one * 0.24 * s,
			offset = CFrame.new(x, f.mouthY + (i * i) * 0.045 * s, z - 0.06),
			shape = Enum.PartType.Ball,
			color = MOUTH,
			expr = "Happy",
		})
	end
	add(specs, { -- golden: open grin with teeth
		name = "Grin",
		size = Vector3.new(1.15, 0.62, 0.2) * s,
		offset = CFrame.new(0, f.mouthY - 0.05 * s, z - 0.05),
		color = MOUTH,
		mesh = Vector3.one,
		expr = "Golden",
	})
	add(specs, {
		name = "Teeth",
		size = Vector3.new(0.8, 0.16, 0.1) * s,
		offset = CFrame.new(0, f.mouthY + 0.13 * s, z - 0.13),
		color = Color3.new(1, 1, 1),
		expr = "Golden",
	})
	for i = -2, 2 do -- uneasy: a wobbly line
		add(specs, {
			name = "Wobble",
			size = Vector3.one * 0.2 * s,
			offset = CFrame.new(i * 0.2 * s, f.mouthY + (if i % 2 == 0 then 0.06 else -0.06) * s, z - 0.06),
			shape = Enum.PartType.Ball,
			color = MOUTH,
			expr = "Uneasy",
		})
	end
	add(specs, { -- sweaty: a nervous "o"
		name = "MouthO",
		size = Vector3.new(0.5, 0.66, 0.2) * s,
		offset = CFrame.new(0, f.mouthY - 0.05 * s, z - 0.05),
		color = MOUTH,
		mesh = Vector3.one,
		expr = "Sweaty",
	})
	add(specs, { -- panic: a full scream
		name = "Scream",
		size = Vector3.new(0.95, 1.3, 0.2) * s,
		offset = CFrame.new(0, f.mouthY - 0.25 * s, z - 0.05),
		color = MOUTH,
		mesh = Vector3.one,
		expr = "Panic",
	})
	add(specs, {
		name = "Tongue",
		size = Vector3.new(0.6, 0.38, 0.12) * s,
		offset = CFrame.new(0, f.mouthY - 0.62 * s, z - 0.12),
		color = TONGUE,
		mesh = Vector3.one,
		expr = "Panic",
	})
	for i = -1, 1 do -- charcoal: a grumpy frown
		add(specs, {
			name = "Frown",
			size = Vector3.one * 0.24 * s,
			offset = CFrame.new(i * 0.3 * s, f.mouthY - math.abs(i) * 0.14 * s, z - 0.06),
			shape = Enum.PartType.Ball,
			color = Color3.fromRGB(10, 8, 7),
			expr = "Charcoal",
		})
	end
	-- sweat drops
	add(specs, {
		name = "Sweat",
		size = Vector3.new(0.34, 0.5, 0.3) * s,
		offset = CFrame.new(f.eyeX + 0.85 * s, f.eyeY + 0.75 * s, z - 0.1),
		color = SWEAT,
		material = Enum.Material.Glass,
		mesh = Vector3.one,
		transparency = 0.15,
		expr = "Sweaty,Panic",
	})
	add(specs, {
		name = "Sweat",
		size = Vector3.new(0.3, 0.44, 0.3) * s,
		offset = CFrame.new(-f.eyeX - 0.8 * s, f.eyeY + 0.55 * s, z - 0.1),
		color = SWEAT,
		material = Enum.Material.Glass,
		mesh = Vector3.one,
		transparency = 0.15,
		expr = "Panic",
	})
end

-- Glowing cracks for charcoal and a shine streak for golden toast.
local function surfaceMarks(specs: { PartSpec }, width: number, height: number, centerY: number, z: number)
	local cracks = {
		{ -0.32, 0.3, 0.5, 35 },
		{ 0.3, -0.25, 0.42, -40 },
		{ 0.18, 0.38, 0.28, 70 },
		{ -0.28, -0.32, 0.3, -15 },
	}
	for _, c in cracks do
		add(specs, {
			name = "Crack",
			size = Vector3.new(width * c[3], 0.1, 0.08),
			offset = CFrame.new(width * c[1], centerY + height * c[2], z - 0.02) * CFrame.Angles(0, 0, math.rad(c[4])),
			color = EMBER,
			material = Enum.Material.Neon,
			expr = "Charcoal",
			shadow = false,
		})
	end
	add(specs, {
		name = "Shine",
		size = Vector3.new(width * 0.55, 0.22, 0.06),
		offset = CFrame.new(-width * 0.12, centerY + height * 0.3, z - 0.03) * CFrame.Angles(0, 0, math.rad(32)),
		color = Color3.new(1, 1, 1),
		material = Enum.Material.Neon,
		transparency = 0.25,
		expr = "Golden",
		shadow = false,
	})
end

local function mittens(specs: { PartSpec }, x: number, y: number, z: number)
	for _, side in { -1, 1 } do
		add(specs, {
			name = "Mitten",
			size = Vector3.new(0.95, 1.05, 0.95),
			offset = CFrame.new(side * x, y, z) * CFrame.Angles(0, 0, math.rad(side * -20)),
			tint = "Crust",
			mesh = Vector3.one,
		})
	end
end

------------------------------------------------------------------ bodies

local BUILDERS: { [string]: () -> { PartSpec } } = {}

function BUILDERS.Bread(): { PartSpec }
	local specs: { PartSpec } = {
		{ name = "Crust", size = Vector3.new(4.6, 4.2, 1.05), offset = CFrame.new(0, 0.5, 0.1), tint = "Crust" },
		{ name = "Body", size = Vector3.new(4.1, 3.8, 1.0), offset = CFrame.new(0, 0.45, -0.05), tint = "Body" },
	}
	for _, side in { -1, 1 } do
		add(specs, {
			name = "CrustLobe",
			size = Vector3.new(1.05, 3.2, 3.2),
			offset = CFrame.new(side * 1.05, 2.75, 0.1) * Z_AXIS,
			shape = Enum.PartType.Cylinder,
			tint = "Crust",
		})
		add(specs, {
			name = "BodyLobe",
			size = Vector3.new(1.0, 2.78, 2.78),
			offset = CFrame.new(side * 1.05, 2.75, -0.05) * Z_AXIS,
			shape = Enum.PartType.Cylinder,
			tint = "Body",
		})
	end
	-- browned toast spots and the pores of the crumb
	local spots = {
		{ -1.45, -0.95, 0.42 },
		{ 1.5, -1.1, 0.36 },
		{ -1.55, 1.55, 0.3 },
		{ 1.65, 2.95, 0.34 },
		{ -0.6, 3.35, 0.28 },
		{ 0.9, -0.45, 0.22 },
	}
	for _, spot in spots do
		add(specs, {
			name = "Spot",
			size = Vector3.new(0.06, spot[3], spot[3]),
			offset = CFrame.new(spot[1], spot[2], -0.56) * Z_AXIS,
			shape = Enum.PartType.Cylinder,
			tint = "Spot",
			shadow = false,
		})
	end
	mittens(specs, 2.45, 0.35, -0.1)
	face(specs, { eyeY = 2.15, eyeX = 0.82, z = -0.6, mouthY = 0.95, scale = 1 })
	surfaceMarks(specs, 3.8, 3.8, 1.2, -0.6)
	return specs
end

function BUILDERS.Bagel(): { PartSpec }
	local specs: { PartSpec } = {}
	local ringRadius, center = 1.8, 1.4
	for i = 0, 15 do
		local angle = (i / 16) * math.pi * 2
		add(specs, {
			name = "Ring",
			size = Vector3.one * 1.95,
			offset = CFrame.new(math.cos(angle) * ringRadius, center + math.sin(angle) * ringRadius, 0),
			shape = Enum.PartType.Ball,
			tint = if i % 2 == 0 then "Body" else "Crust",
		})
	end
	-- inner hole edge, slightly darker
	for i = 0, 7 do
		local angle = (i / 8) * math.pi * 2 + 0.2
		add(specs, {
			name = "Inner",
			size = Vector3.one * 0.9,
			offset = CFrame.new(math.cos(angle) * 1.05, center + math.sin(angle) * 1.05, 0.1),
			shape = Enum.PartType.Ball,
			tint = "Spot",
		})
	end
	for i = 0, 11 do
		local angle = (i / 12) * math.pi * 2 + 0.3
		local r = 1.8 + (if i % 2 == 0 then 0.35 else -0.3)
		add(specs, {
			name = "Sesame",
			size = Vector3.new(0.32, 0.16, 0.16),
			offset = CFrame.new(math.cos(angle) * r, center + math.sin(angle) * r, -0.98) * CFrame.Angles(0, 0, angle),
			color = Color3.fromRGB(247, 231, 198),
			shadow = false,
		})
	end
	mittens(specs, 3.1, 0.9, -0.1)
	face(specs, { eyeY = 3.05, eyeX = 0.78, z = -0.92, mouthY = -0.2, scale = 0.95 })
	surfaceMarks(specs, 3.6, 3.6, 1.4, -1.0)
	return specs
end

function BUILDERS.Croissant(): { PartSpec }
	local specs: { PartSpec } = {}
	local arcRadius, center = 2.0, 0.5
	for i = -3, 3 do
		local angle = math.rad(90 - i * 26)
		local s = 1 - math.abs(i) * 0.15
		add(specs, {
			name = "Lobe",
			size = Vector3.new(2.1 * s, 2.9 * s, 2.3 * s),
			offset = CFrame.new(
				math.cos(angle) * arcRadius * 1.25,
				center + math.sin(angle) * arcRadius - (if math.abs(i) == 3 then 0.4 else 0),
				0
			) * CFrame.Angles(0, 0, angle - math.rad(90)),
			tint = if i % 2 == 0 then "Body" else "Crust",
			mesh = Vector3.one,
		})
		-- flaky layer seams
		if i ~= 0 then
			add(specs, {
				name = "Seam",
				size = Vector3.new(0.18 * s, 2.5 * s, 2.36 * s),
				offset = CFrame.new(math.cos(angle) * arcRadius * 1.25, center + math.sin(angle) * arcRadius, 0)
					* CFrame.Angles(0, 0, angle - math.rad(90)),
				tint = "Spot",
				mesh = Vector3.one,
				shadow = false,
			})
		end
	end
	face(specs, { eyeY = 2.95, eyeX = 0.55, z = -1.08, mouthY = 1.95, scale = 0.8 })
	surfaceMarks(specs, 2.0, 2.4, 2.4, -1.1)
	return specs
end

function BUILDERS.Waffle(): { PartSpec }
	local specs: { PartSpec } = {
		{ name = "Body", size = Vector3.new(4.4, 4.4, 1.0), offset = CFrame.new(0, 1.1, 0), tint = "Body" },
	}
	-- raised crust frame
	for _, edge in { { 0, 3.2, 4.6, 0.4 }, { 0, -1.0, 4.6, 0.4 }, { -2.2, 1.1, 0.4, 4.6 }, { 2.2, 1.1, 0.4, 4.6 } } do
		add(specs, { name = "Frame", size = Vector3.new(edge[3], edge[4], 1.15), offset = CFrame.new(edge[1], edge[2], 0), tint = "Crust" })
	end
	-- the grid of pockets
	for row = 0, 2 do
		for col = 0, 2 do
			add(specs, {
				name = "Pocket",
				size = Vector3.new(1.05, 1.05, 0.12),
				offset = CFrame.new(-1.35 + col * 1.35, -0.25 + row * 1.35, -0.52),
				tint = "Spot",
				shadow = false,
			})
		end
	end
	-- butter pat and syrup
	add(specs, {
		name = "Butter",
		size = Vector3.new(1.5, 0.4, 1.0),
		offset = CFrame.new(0.4, 3.55, -0.05) * CFrame.Angles(0, 0.3, 0),
		color = Theme.Colors.Butter,
	})
	for i, drip in { { -1.9, 2.4, 1.2 }, { 1.95, 1.9, 1.8 }, { 2.05, 0.4, 0.9 } } do
		add(specs, {
			name = "Syrup",
			size = Vector3.new(0.34, drip[3], 0.34),
			offset = CFrame.new(drip[1], drip[2], -0.52 - i * 0.01),
			color = Color3.fromRGB(150, 70, 20),
			material = Enum.Material.Glass,
			transparency = 0.1,
			mesh = Vector3.one,
		})
	end
	-- the legendary crown
	add(specs, {
		name = "CrownBand",
		size = Vector3.new(2.6, 0.45, 0.8),
		offset = CFrame.new(0, 3.85, 0.25),
		color = Theme.Colors.Legend,
		material = Enum.Material.Metal,
	})
	for i = -1, 1 do
		add(specs, {
			name = "CrownSpike",
			size = Vector3.new(0.6, if i == 0 then 1.2 else 0.85, 0.6),
			offset = CFrame.new(i * 0.9, 4.35 + (if i == 0 then 0.18 else 0), 0.25) * CFrame.Angles(0, math.rad(45), 0),
			color = Theme.Colors.Legend,
			material = Enum.Material.Neon,
		})
	end
	add(specs, {
		name = "Jewel",
		size = Vector3.one * 0.32,
		offset = CFrame.new(0, 3.85, -0.17),
		shape = Enum.PartType.Ball,
		color = Theme.Colors.Jam,
		material = Enum.Material.Neon,
	})
	mittens(specs, 2.75, 0.6, -0.1)
	face(specs, { eyeY = 1.85, eyeX = 0.8, z = -0.66, mouthY = 0.45, scale = 1 })
	surfaceMarks(specs, 4.0, 4.0, 1.1, -0.66)
	return specs
end

------------------------------------------------------------------ cosmetics

local function buildHat(root: BasePart, model: Model, cosmeticId: string, topY: number)
	local cosmetic = CosmeticDefinitions.ById[cosmeticId]
	if not cosmetic then
		return
	end
	local color = Color3.fromRGB(cosmetic.Color[1], cosmetic.Color[2], cosmetic.Color[3])
	if cosmeticId == "PartyHat" then
		for i = 0, 3 do
			local width = 1.6 - i * 0.38
			makePart(root, model, {
				name = "Hat",
				size = Vector3.new(0.45, width, width),
				offset = CFrame.new(0, topY + 0.2 + i * 0.42, 0) * Y_AXIS,
				shape = Enum.PartType.Cylinder,
				color = if i % 2 == 0 then color else Theme.Colors.Butter,
			})
		end
		makePart(root, model, {
			name = "Hat",
			size = Vector3.one * 0.45,
			offset = CFrame.new(0, topY + 1.95, 0),
			shape = Enum.PartType.Ball,
			color = Theme.Colors.Butter,
			material = Enum.Material.Neon,
		})
	elseif cosmeticId == "ChefHat" then
		makePart(root, model, {
			name = "Hat",
			size = Vector3.new(1, 1.7, 1.7),
			offset = CFrame.new(0, topY + 0.45, 0) * Y_AXIS,
			shape = Enum.PartType.Cylinder,
			color = color,
		})
		for _, x in { -0.55, 0, 0.55 } do
			makePart(root, model, {
				name = "Hat",
				size = Vector3.new(1.4, 1.3, 1.6),
				offset = CFrame.new(x, topY + 1.3 + (if x == 0 then 0.2 else 0), 0),
				color = color,
				mesh = Vector3.one,
			})
		end
	elseif cosmeticId == "Crown" then
		makePart(root, model, {
			name = "Hat",
			size = Vector3.new(1.9, 0.5, 1.9),
			offset = CFrame.new(0, topY + 0.25, 0),
			color = color,
			material = Enum.Material.Metal,
		})
		for _, x in { -0.65, 0, 0.65 } do
			makePart(root, model, {
				name = "Hat",
				size = Vector3.new(0.45, 0.7, 0.45),
				offset = CFrame.new(x, topY + 0.8, 0) * CFrame.Angles(0, math.rad(45), 0),
				color = color,
				material = Enum.Material.Neon,
			})
		end
	end
end

local function buildTrail(root: BasePart, model: Model, cosmeticId: string)
	local cosmetic = CosmeticDefinitions.ById[cosmeticId]
	if not cosmetic then
		return
	end
	local color = Color3.fromRGB(cosmetic.Color[1], cosmetic.Color[2], cosmetic.Color[3])
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 1.2, 0.6)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -1.2, 0.6)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.5
	trail.LightEmission = if cosmeticId == "FlameTrail" or cosmeticId == "GoldenTrail" then 0.8 else 0
	trail.Parent = model
	-- Attachments live on the root; destroy them with the model.
	model.Destroying:Connect(function()
		a0:Destroy()
		a1:Destroy()
	end)
end

------------------------------------------------------------------ public API

-- Strip the default avatar look so only the bread (plus tiny arms and legs) shows.
function BreadVisuals.PrepareCharacter(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
	for _, name in { "Head", "UpperTorso", "LowerTorso", "Torso" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Transparency = 1
			local faceDecal = part:FindFirstChildOfClass("Decal")
			if faceDecal then
				faceDecal:Destroy()
			end
		end
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "HumanoidRootPart" then
			part.Color = Theme.Colors.Crust
		end
	end
end

-- Builds (or rebuilds) the bread body on a character.
function BreadVisuals.Apply(character: Model, breadId: string, cosmetics: { [string]: string }?): Model?
	local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot or not humanoidRoot:IsA("BasePart") then
		return nil
	end
	local existing = character:FindFirstChild(MODEL_NAME)
	if existing then
		existing:Destroy()
	end

	local builder = BUILDERS[breadId] or BUILDERS.Bread
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("BreadId", breadId)
	model:SetAttribute("HeatBias", HEAT_BIAS[breadId] or 0)

	local root = Instance.new("Part")
	root.Name = "BreadCore"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.CFrame = humanoidRoot.CFrame
	root.Parent = model
	local joint = Instance.new("Weld")
	joint.Name = "BreadJoint"
	joint.Part0 = humanoidRoot
	joint.Part1 = root
	joint.Parent = root

	for _, spec in builder() do
		makePart(root, model, spec)
	end

	-- Butter shield bubble, hidden until needed.
	local shield = makePart(root, model, {
		name = "ButterShield",
		size = Vector3.new(7.5, 7.5, 7.5),
		offset = CFrame.new(0, 1, 0),
		shape = Enum.PartType.Ball,
		color = Theme.Colors.Butter,
		material = Enum.Material.ForceField,
		shadow = false,
	})
	shield.Transparency = 1

	local topY = TOP_Y[breadId] or TOP_Y.Bread
	if cosmetics then
		if cosmetics.Hat then
			buildHat(root, model, cosmetics.Hat, topY)
		end
		if cosmetics.Trail then
			buildTrail(humanoidRoot, model, cosmetics.Trail)
		end
	end

	model.Parent = character
	BreadVisuals.SetToast(model, 0, "Normal")
	BreadVisuals.SetExpression(model, "Happy")
	return model
end

function BreadVisuals.Get(character: Model?): Model?
	if not character then
		return nil
	end
	return character:FindFirstChild(MODEL_NAME) :: Model?
end

-- Shows the face parts for `expression` and hides every other variant.
function BreadVisuals.SetExpression(model: Model, expression: string)
	if model:GetAttribute("Expression") == expression then
		return
	end
	model:SetAttribute("Expression", expression)
	local needle = "," .. expression .. ","
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local tags = part:GetAttribute("Expr")
			if type(tags) == "string" then
				local visible = string.find(tags, needle, 1, true) ~= nil
				part.Transparency = if visible then (part:GetAttribute("BaseTransparency") or 0) else 1
			end
		end
	end
end

local GOLD = Color3.fromRGB(255, 200, 60)
local GOLD_CRUST = Color3.fromRGB(214, 150, 30)
local CHARCOAL_BODY = Color3.fromRGB(34, 27, 24)
local CHARCOAL_CRUST = Color3.fromRGB(16, 12, 10)

-- mode: "Normal" | "Golden" | "Charcoal" | "Blackened"
function BreadVisuals.SetToast(model: Model, heat: number, mode: string)
	local bias = model:GetAttribute("HeatBias") or 0
	local r, g, b = HeatMath.ToastRGB(math.min(100, heat + bias * (1 - heat / 100)))
	if mode == "Blackened" then
		r, g, b = HeatMath.Darken(r, g, b, 0.55)
	end
	local body = Color3.fromRGB(r, g, b)
	local cr, cg, cb = HeatMath.Darken(r, g, b, 0.35)
	local crust = Color3.fromRGB(cr, cg, cb)
	-- toast spots darken faster than the rest of the slice
	local sr, sg, sb = HeatMath.Darken(r, g, b, 0.28 + heat / 250)
	local spot = Color3.fromRGB(sr, sg, sb)
	local material = Enum.Material.SmoothPlastic
	if mode == "Golden" then
		body, crust, spot = GOLD, GOLD_CRUST, GOLD_CRUST
		material = Enum.Material.Foil
	elseif mode == "Charcoal" then
		body, crust, spot = CHARCOAL_BODY, CHARCOAL_CRUST, CHARCOAL_CRUST
		material = Enum.Material.Slate
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local tint = part:GetAttribute("Tint")
			if tint == "Body" then
				part.Color = body
				part.Material = material
			elseif tint == "Crust" then
				part.Color = crust
				part.Material = material
			elseif tint == "Spot" then
				part.Color = spot
			end
		end
	end
end

local function effectAnchor(model: Model): BasePart?
	local anchor = model:FindFirstChild("BreadCore")
	if anchor and anchor:IsA("BasePart") then
		return anchor
	end
	return nil
end

local function clearEffects(anchor: BasePart)
	for _, child in anchor:GetChildren() do
		if child:GetAttribute("BreadEffect") then
			child:Destroy()
		end
	end
end

local function tagged<T>(instance: T & Instance, parent: Instance): T
	instance:SetAttribute("BreadEffect", true)
	instance.Parent = parent
	return instance
end

-- Heat-state particles. Uses legacy Smoke/Fire/Sparkles which need no textures.
-- state: HeatState value or "Golden".
function BreadVisuals.SetEffects(model: Model, state: string)
	BreadVisuals.SetExpression(model, BreadVisuals.ExpressionForState[state] or "Happy")
	local anchor = effectAnchor(model)
	if not anchor then
		return
	end
	if anchor:GetAttribute("EffectState") == state then
		return
	end
	anchor:SetAttribute("EffectState", state)
	clearEffects(anchor)

	if state == "Warm" or state == "VeryHot" then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(240, 240, 240)
		smoke.Opacity = if state == "Warm" then 0.08 else 0.2
		smoke.Size = if state == "Warm" then 1.5 else 3
		smoke.RiseVelocity = 4
		tagged(smoke, anchor)
	elseif state == "Critical" then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(120, 110, 100)
		smoke.Opacity = 0.3
		smoke.Size = 4
		smoke.RiseVelocity = 6
		tagged(smoke, anchor)
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Color = Theme.Colors.Orange
		fire.SecondaryColor = Theme.Colors.Danger
		tagged(fire, anchor)
	elseif state == "Burnt" then
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(40, 36, 34)
		smoke.Opacity = 0.35
		smoke.Size = 3
		smoke.RiseVelocity = 3
		tagged(smoke, anchor)
		local embers = Instance.new("ParticleEmitter")
		embers.Color = ColorSequence.new(Theme.Colors.Orange, Theme.Colors.Danger)
		embers.LightEmission = 1
		embers.Size = NumberSequence.new(0.25, 0)
		embers.Lifetime = NumberRange.new(0.6, 1.2)
		embers.Rate = 6
		embers.Speed = NumberRange.new(2, 4)
		embers.SpreadAngle = Vector2.new(40, 40)
		embers.Acceleration = Vector3.new(0, 4, 0)
		tagged(embers, anchor)
		local glow = Instance.new("PointLight")
		glow.Color = EMBER
		glow.Brightness = 1.2
		glow.Range = 8
		tagged(glow, anchor)
	elseif state == "Golden" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Theme.Colors.Legend
		tagged(sparkles, anchor)
		local light = Instance.new("PointLight")
		light.Color = Theme.Colors.Legend
		light.Brightness = 2
		light.Range = 12
		tagged(light, anchor)
	end
end

function BreadVisuals.SetShield(model: Model, active: boolean)
	local shield = model:FindFirstChild("ButterShield") :: BasePart?
	if shield then
		shield.Transparency = if active then 0.35 else 1
	end
end

return BreadVisuals
