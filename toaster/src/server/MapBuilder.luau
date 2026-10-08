-- Builds the whole world from primitive parts at server start: the kitchen
-- counter, the giant toaster (coils, lever, POP pad, heat zones, secret crack),
-- the lobby plate, the landing target, the giant hand, the fork and Crumb World.
-- Everything is generated so the place file needs no hand-made models; tweak
-- dimensions in Config.Map.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Theme = require(Shared.Theme)

local MapBuilder = {}

local MAP = Config.Map
local GROUPS = Constants.CollisionGroups
local C = Theme.Colors

export type MapInfo = {
	ToasterCenter: Vector3,
	FloorY: number,
	HalfLength: number,
	HalfWidth: number,
	ToasterSpawns: { Vector3 },
	CrumbArea: { minX: number, maxX: number, minZ: number, maxZ: number },
	ButterSpots: { Vector3 },
	LobbyCenter: Vector3,
	LobbySpawnRadius: number,
	FieldCenter: Vector3,
	FieldGroundY: number,
	LeverKnob: BasePart,
	KnobUpY: number,
	KnobDownY: number,
	Hand: Model,
	Fork: Model,
	SecretSensor: BasePart,
	CrumbWorld: {
		Entry: Vector3,
		Floor: number,
		ReturnPad: BasePart,
		NpcPrompt: ProximityPrompt,
		NpcHead: BasePart,
		VintageCrumbs: { BasePart },
		Bounds: { minY: number, maxY: number },
	},
	Folders: { [string]: Folder },
}

type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
	Group: string?,
	Wedge: boolean?,
}

local function part(parent: Instance, props: PartProps): BasePart
	local p: BasePart
	if props.Wedge then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = props.Shape or Enum.PartType.Block
		p = block
	end
	p.Name = props.Name or "Part"
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or C.Chrome
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	p.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	p.CanTouch = if props.CanTouch == nil then false else props.CanTouch
	p.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Group then
		p.CollisionGroup = props.Group
	end
	p.Parent = parent
	return p
end

local UP_AXIS = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis along Y
local Z_AXIS = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z

local function disc(
	parent: Instance,
	name: string,
	center: Vector3,
	radius: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(parent, {
		Name = name,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * UP_AXIS,
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Material = material,
	})
end

-- A SurfaceGui label on one face of a part.
local function label(target: BasePart, face: Enum.NormalId, text: string, color: Color3?, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 20
	gui.LightInfluence = 0.2
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Theme.Fonts.Display
	text_.TextScaled = true
	text_.TextColor3 = color or C.Cream
	text_.Text = text
	text_.Parent = gui
	gui.Parent = target
end

local function billboard(parent: BasePart, text: string, color: Color3, size: UDim2, offset: Vector3?, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset or Vector3.zero
	gui.MaxDistance = maxDistance or 400
	gui.LightInfluence = 0
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Theme.Fonts.Display
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0.3
	text_.Text = text
	text_.Parent = gui
	gui.Parent = parent
end

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(90, 80, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 135, 120)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
end

local function buildKitchen(world: Folder)
	part(world, {
		Name = "Counter",
		Size = Vector3.new(1600, 20, 1000),
		CFrame = CFrame.new(0, -10, 0),
		Color = C.Counter,
		Material = Enum.Material.WoodPlanks,
	})
	part(world, {
		Name = "Backsplash",
		Size = Vector3.new(1600, 320, 8),
		CFrame = CFrame.new(0, 160, -504),
		Color = C.Tile,
		Material = Enum.Material.Marble,
	})
	-- Giant props for scale.
	local jar = disc(world, "JamJar", Vector3.new(180, 45, -260), 30, 90, C.Jam, Enum.Material.Glass)
	jar.Transparency = 0.15
	disc(world, "JamLid", Vector3.new(180, 93, -260), 31, 8, C.Cream)
	disc(world, "Mug", Vector3.new(-120, 40, -300), 34, 80, Color3.fromRGB(88, 150, 230))
	part(world, {
		Name = "ButterDish",
		Size = Vector3.new(90, 14, 60),
		CFrame = CFrame.new(-120, 7, 260),
		Color = C.Cream,
	})
	part(world, {
		Name = "GiantButter",
		Size = Vector3.new(70, 22, 40),
		CFrame = CFrame.new(-120, 25, 260),
		Color = C.Butter,
	})
end

local function buildLobby(folders: { [string]: Folder }): (Vector3, number)
	local lobby = folders.Lobby
	local center = Vector3.new(MAP.LobbyCenterX, 0, 0)
	disc(lobby, "Plate", center + Vector3.new(0, 1, 0), MAP.LobbyRadius, 2, C.Cream, Enum.Material.Marble)
	disc(lobby, "PlateRim", center + Vector3.new(0, 0.8, 0), MAP.LobbyRadius + 6, 1.6, Color3.fromRGB(88, 150, 230))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, 2.5, 0))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C.Gold
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.2
	spawn.Parent = lobby

	local sign = part(lobby, {
		Name = "LobbySign",
		Size = Vector3.new(60, 20, 2),
		CFrame = CFrame.new(center + Vector3.new(0, 26, -MAP.LobbyRadius + 4)),
		Color = C.Charcoal,
	})
	label(sign, Enum.NormalId.Back, "TOASTER 🍞", C.Orange)
	label(sign, Enum.NormalId.Front, "TOASTER 🍞", C.Orange)
	part(lobby, {
		Name = "SignPost",
		Size = Vector3.new(3, 18, 3),
		CFrame = CFrame.new(center + Vector3.new(0, 9, -MAP.LobbyRadius + 4)),
		Color = C.CharcoalSoft,
	})
	local tip = part(lobby, {
		Name = "TipSign",
		Size = Vector3.new(36, 8, 1),
		CFrame = CFrame.new(center + Vector3.new(MAP.LobbyRadius - 12, 6, 0)) * CFrame.Angles(0, math.rad(-90), 0),
		Color = C.Panel,
	})
	label(tip, Enum.NormalId.Front, "Stand near the CENTRE at POP for the best landing!", C.Cream)
	label(tip, Enum.NormalId.Back, "Stand near the CENTRE at POP for the best landing!", C.Cream)
	return center + Vector3.new(0, 5, 0), MAP.LobbyRadius - 15
end

local function buildToaster(folders: { [string]: Folder }): any
	local toaster = folders.Toaster
	local L, W, H, T = MAP.InteriorLength, MAP.InteriorWidth, MAP.WallHeight, MAP.WallThickness
	local floorY = MAP.FloorY
	local halfL, halfW = L / 2, W / 2
	local outerL, outerW = halfL + T, halfW + T
	local topY = floorY + H
	local midY = floorY + H / 2

	local function chrome(name: string, size: Vector3, cf: CFrame, color: Color3?): BasePart
		return part(toaster, {
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color or C.Chrome,
			Material = Enum.Material.Metal,
			Reflectance = 0.12,
			Group = GROUPS.Toaster,
		})
	end

	-- Feet + floor
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(toaster, {
				Name = "Foot",
				Size = Vector3.new(14, 2, 14),
				CFrame = CFrame.new(sx * (outerL - 10), 1, sz * (outerW - 10)),
				Color = C.Charcoal,
				Group = GROUPS.Toaster,
			})
		end
	end
	chrome("Base", Vector3.new(outerL * 2, floorY - 2, outerW * 2), CFrame.new(0, (floorY + 2) / 2, 0), C.ChromeDark)
	part(toaster, {
		Name = "InteriorFloor",
		Size = Vector3.new(L, 0.4, W),
		CFrame = CFrame.new(0, floorY - 0.2, 0),
		Color = Color3.fromRGB(72, 60, 52),
		Material = Enum.Material.Slate,
		Group = GROUPS.Toaster,
	})

	-- End walls (cool) and the solid long wall
	chrome("WallWest", Vector3.new(T, H, outerW * 2), CFrame.new(-(halfL + T / 2), midY, 0))
	chrome("WallEast", Vector3.new(T, H, outerW * 2), CFrame.new(halfL + T / 2, midY, 0))
	chrome("WallNorth", Vector3.new(L, H, T), CFrame.new(0, midY, -(halfW + T / 2)))

	-- Long wall with the window (lever side, +Z)
	local windowBottom, windowTop = floorY + 40, topY - 6
	local windowHalf = 40
	local southZ = halfW + T / 2
	chrome("WallSouthLow", Vector3.new(L, windowBottom - floorY, T), CFrame.new(0, (floorY + windowBottom) / 2, southZ))
	chrome("WallSouthTop", Vector3.new(L, topY - windowTop, T), CFrame.new(0, (windowTop + topY) / 2, southZ))
	for _, side in { -1, 1 } do
		local width = halfL - windowHalf
		chrome(
			"WallSouthSide",
			Vector3.new(width, windowTop - windowBottom, T),
			CFrame.new(side * (windowHalf + width / 2), (windowBottom + windowTop) / 2, southZ)
		)
	end
	part(toaster, {
		Name = "Window",
		Size = Vector3.new(windowHalf * 2, windowTop - windowBottom, 1),
		CFrame = CFrame.new(0, (windowBottom + windowTop) / 2, southZ),
		Color = Color3.fromRGB(200, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		Group = GROUPS.Toaster,
	})

	-- Rim around the slot
	for _, sz in { -1, 1 } do
		chrome("Rim", Vector3.new(outerL * 2, 3, T), CFrame.new(0, topY + 1.5, sz * southZ), C.ChromeDark)
	end
	for _, sx in { -1, 1 } do
		chrome("Rim", Vector3.new(T, 3, outerW * 2), CFrame.new(sx * (halfL + T / 2), topY + 1.5, 0), C.ChromeDark)
	end

	-- Invisible lid: keeps bread inside but lets launched bread through.
	part(toaster, {
		Name = "Ceiling",
		Size = Vector3.new(L, 2, W),
		CFrame = CFrame.new(0, topY + 1, 0),
		Transparency = 1,
		CanQuery = false,
		CastShadow = false,
		Group = GROUPS.ToasterCeiling,
	})

	-- Mica liners and heating coils on both long walls
	for _, sz in { -1, 1 } do
		local wallZ = sz * (halfW - 0.3)
		part(toaster, {
			Name = "Mica",
			Size = Vector3.new(L, windowBottom - floorY - 2, 0.6),
			CFrame = CFrame.new(0, (floorY + windowBottom) / 2, wallZ),
			Color = Color3.fromRGB(60, 48, 40),
			Material = Enum.Material.Slate,
			Group = GROUPS.Toaster,
		})
		for row = 0, 5 do
			local coil = part(toaster, {
				Name = "Coil",
				Size = Vector3.new(L - 12, 1.4, 1.4),
				CFrame = CFrame.new(0, floorY + 4 + row * 6, sz * (halfW - 1.4)),
				Shape = Enum.PartType.Cylinder,
				Color = C.CoilCold,
				CanCollide = false,
				Group = GROUPS.Toaster,
			})
			CollectionService:AddTag(coil, Constants.Tags.Coil)
		end
		for i = -2, 2 do
			part(toaster, {
				Name = "CoilBracket",
				Size = Vector3.new(1, 34, 2.4),
				CFrame = CFrame.new(i * 30, floorY + 19, sz * (halfW - 1.4)),
				Color = C.ChromeDark,
				Group = GROUPS.Toaster,
			})
		end
	end

	-- Heat zone floor markings (purely visual; HeatMath decides the real zones)
	local zones = Config.HeatZones
	for _, sz in { -1, 1 } do
		local strip = part(toaster, {
			Name = "HotZone",
			Size = Vector3.new(L, 0.1, zones.CoilBand),
			CFrame = CFrame.new(0, floorY + 0.05, sz * (halfW - zones.CoilBand / 2)),
			Color = C.HotFloor,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		label(strip, Enum.NormalId.Top, "HOT ZONE ×2      HOT ZONE ×2      HOT ZONE ×2", Color3.fromRGB(255, 160, 110), 6)
	end
	for _, sx in { -1, 1 } do
		local nook = part(toaster, {
			Name = "CoolSpot",
			Size = Vector3.new(zones.SafeNookDepth, 0.1, zones.SafeNookHalfWidth * 2),
			CFrame = CFrame.new(sx * (halfL - zones.SafeNookDepth / 2), floorY + 0.06, 0),
			Color = C.Safe,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		label(nook, Enum.NormalId.Top, "COOL\n×0.5", Color3.new(1, 1, 1), 8)
	end
	local pad = disc(toaster, "PopPad", Vector3.new(0, floorY + 0.08, 0), Config.Launch.PadRadius, 0.12, Color3.fromRGB(150, 70, 30))
	pad.CanCollide = false
	pad.CanQuery = false
	CollectionService:AddTag(pad, Constants.Tags.PopPad)
	local padLabel = part(toaster, {
		Name = "PopPadLabel",
		Size = Vector3.new(10, 0.1, 4),
		CFrame = CFrame.new(0, floorY + 0.16, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	label(padLabel, Enum.NormalId.Top, "POP PAD", C.Cream, 10)

	-- Lever on the outside of the window wall
	local leverX = halfL - 18
	local outerZ = halfW + T
	local knobUpY, knobDownY = topY - 8, floorY + 14
	part(toaster, {
		Name = "LeverTrack",
		Size = Vector3.new(3, knobUpY - knobDownY + 8, 1),
		CFrame = CFrame.new(leverX, (knobUpY + knobDownY) / 2, outerZ + 0.5),
		Color = C.Charcoal,
		Group = GROUPS.Toaster,
	})
	local knob = part(toaster, {
		Name = "LeverKnob",
		Size = Vector3.new(12, 5, 14),
		CFrame = CFrame.new(leverX, knobUpY, outerZ + 7),
		Color = C.Charcoal,
		Material = Enum.Material.SmoothPlastic,
		Group = GROUPS.Toaster,
	})
	CollectionService:AddTag(knob, Constants.Tags.LeverKnob)
	knob:SetAttribute("UpY", knobUpY)
	knob:SetAttribute("DownY", knobDownY)
	local dial = disc(toaster, "Dial", Vector3.new(-leverX, floorY + 22, outerZ + 1), 6, 2, C.Charcoal)
	dial.CFrame = CFrame.new(-leverX, floorY + 22, outerZ + 1) * Z_AXIS
	local brand = part(toaster, {
		Name = "Brand",
		Size = Vector3.new(50, 10, 0.2),
		CFrame = CFrame.new(0, floorY + 18, outerZ + 0.1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	label(brand, Enum.NormalId.Back, "TOASTMASTER 3000", C.Charcoal)

	-- Secret crack in the floor (Crumb World entrance)
	part(toaster, {
		Name = "SecretCrack",
		Size = Vector3.new(5, 0.12, 1.2),
		CFrame = CFrame.new(-44, floorY + 0.1, 16) * CFrame.Angles(0, math.rad(20), 0),
		Color = Color3.fromRGB(12, 9, 8),
		CanCollide = false,
		CanQuery = false,
	})
	for i = 1, 5 do
		part(toaster, {
			Name = "CrumbHint",
			Size = Vector3.new(0.8, 0.5, 0.7),
			CFrame = CFrame.new(-44 + math.cos(i) * 3.5, floorY + 0.25, 16 + math.sin(i) * 3.5) * CFrame.Angles(0, i, 0),
			Color = C.Crumb,
			CanCollide = false,
			CanQuery = false,
		})
	end
	local sensor = part(toaster, {
		Name = "SecretSensor",
		Size = Vector3.new(5, 3, 2.5),
		CFrame = CFrame.new(-44, floorY + 1.5, 16) * CFrame.Angles(0, math.rad(20), 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
	})

	-- Spawn markers (also used to avoid stacking players)
	local spawns: { Vector3 } = {}
	local step = MAP.SpawnSpacing
	local x = -halfL + 14
	while x <= halfL - 14 do
		local z = -halfW + 15
		while z <= halfW - 15 do
			if math.sqrt(x * x + z * z) > Config.Launch.PadRadius + 2 then
				local pos = Vector3.new(x, floorY + 4, z)
				table.insert(spawns, pos)
				part(folders.SpawnPoints, {
					Name = "ToasterSpawn",
					Size = Vector3.new(1, 1, 1),
					CFrame = CFrame.new(pos),
					Transparency = 1,
					CanCollide = false,
					CanQuery = false,
				})
			end
			z += step
		end
		x += step
	end

	local butterSpots = {
		Vector3.new(-30, floorY + 1.2, -12),
		Vector3.new(30, floorY + 1.2, 12),
		Vector3.new(0, floorY + 1.2, -26),
		Vector3.new(-58, floorY + 1.2, 20),
		Vector3.new(58, floorY + 1.2, -20),
		Vector3.new(12, floorY + 1.2, 27),
	}

	return {
		spawns = spawns,
		butterSpots = butterSpots,
		knob = knob,
		knobUpY = knobUpY,
		knobDownY = knobDownY,
		sensor = sensor,
	}
end

local function buildField(folders: { [string]: Folder }): Vector3
	local zonesFolder = folders.LandingZones
	local center = Vector3.new(MAP.FieldCenterX, 0, 0)
	disc(
		zonesFolder,
		"Board",
		center + Vector3.new(0, 0.1, 0),
		MAP.FieldRadius,
		0.2,
		Color3.fromRGB(176, 128, 82),
		Enum.Material.WoodPlanks
	)
	local zones = Config.Landing.Zones
	for i = #zones, 1, -1 do
		local zone = zones[i]
		if zone.Radius ~= math.huge then
			local ring = disc(
				zonesFolder,
				zone.Id .. "Zone",
				center + Vector3.new(0, 0.25 + (#zones - i) * 0.05, 0),
				zone.Radius,
				0.1,
				Theme.ZoneColors[zone.Id],
				if zone.Id == "Jackpot" then Enum.Material.Neon else Enum.Material.SmoothPlastic
			)
			ring.CanCollide = false
			local marker = part(zonesFolder, {
				Name = zone.Id .. "Label",
				Size = Vector3.new(1, 1, 1),
				CFrame = CFrame.new(center + Vector3.new(-zone.Radius + 2, 3, 0)),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
			})
			billboard(marker, `{zone.Name}\n{zone.Points}`, Theme.ZoneColors[zone.Id], UDim2.fromOffset(160, 56))
		end
	end
	local sign = part(zonesFolder, {
		Name = "FieldSign",
		Size = Vector3.new(70, 18, 2),
		CFrame = CFrame.new(center + Vector3.new(MAP.FieldRadius + 10, 22, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = C.Charcoal,
	})
	label(sign, Enum.NormalId.Front, "LANDING ZONE 🎯", C.Gold)
	label(sign, Enum.NormalId.Back, "LANDING ZONE 🎯", C.Gold)
	return center
end

-- Two enormous fingers and a bit of palm. Pivot = fingertips. Clients animate it.
local function buildHand(folders: { [string]: Folder }): Model
	local hand = Instance.new("Model")
	hand.Name = "GiantHand"
	local pivot = CFrame.new(0, 2000, 0) -- parked far above the world until needed

	local function handPart(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): BasePart
		local p = part(hand, {
			Name = name,
			Size = size,
			CFrame = pivot * offset,
			Color = color,
			Shape = shape,
			CanCollide = false,
			CanQuery = false,
			CastShadow = true,
		})
		CollectionService:AddTag(p, Constants.Tags.HandPart)
		return p
	end

	for i, fx in { -6.5, 6.5 } do
		local lift = if i == 2 then 2 else 0
		handPart("Finger", Vector3.new(44, 11, 11), CFrame.new(fx, 22 + lift, 0) * UP_AXIS, C.Skin, Enum.PartType.Cylinder)
		handPart("Fingertip", Vector3.new(11, 11, 11), CFrame.new(fx, 0.5 + lift, 0), C.Skin, Enum.PartType.Ball)
		handPart("Nail", Vector3.new(7, 9, 1), CFrame.new(fx, 3 + lift, -5.3), C.SkinNail)
		handPart("Knuckle", Vector3.new(8, 0.6, 1), CFrame.new(fx, 26 + lift, -5.4), Color3.fromRGB(184, 122, 82))
		handPart("Knuckle", Vector3.new(8, 0.6, 1), CFrame.new(fx, 28 + lift, -5.4), Color3.fromRGB(184, 122, 82))
	end
	handPart("Palm", Vector3.new(36, 26, 22), CFrame.new(0, 54, 4), C.Skin)
	handPart("PalmEdge", Vector3.new(22, 30, 20), CFrame.new(-14, 60, 8) * CFrame.Angles(0, 0, math.rad(12)), C.Skin)
	local primary = handPart("Pivot", Vector3.new(1, 1, 1), CFrame.new(), C.Skin)
	primary.Transparency = 1
	hand.PrimaryPart = primary
	hand.Parent = folders.EventObjects
	return hand
end

-- The boss fork. Pivot = tine tips. Clients animate it on a shared clock.
local function buildFork(folders: { [string]: Folder }): Model
	local fork = Instance.new("Model")
	fork.Name = "GiantFork"
	local pivot = CFrame.new(0, 2200, 0)
	local metal = Color3.fromRGB(210, 216, 222)
	local function forkPart(name: string, size: Vector3, offset: CFrame, shape: Enum.PartType?): BasePart
		return part(fork, {
			Name = name,
			Size = size,
			CFrame = pivot * offset,
			Color = metal,
			Material = Enum.Material.Metal,
			Reflectance = 0.3,
			Shape = shape,
			CanCollide = false,
			CanQuery = false,
		})
	end
	for i = -1.5, 1.5 do
		forkPart("Tine", Vector3.new(26, 2.2, 2.2), CFrame.new(i * 3.2, 13, 0) * UP_AXIS, Enum.PartType.Cylinder)
	end
	forkPart("Head", Vector3.new(14, 8, 2.6), CFrame.new(0, 29, 0))
	forkPart("Neck", Vector3.new(6, 10, 2.4), CFrame.new(0, 37, 0))
	forkPart("Handle", Vector3.new(70, 5, 5), CFrame.new(0, 76, 0) * UP_AXIS, Enum.PartType.Cylinder)
	local glow = forkPart("Arc", Vector3.new(16, 30, 4), CFrame.new(0, 14, 0))
	glow.Color = Theme.Colors.Electric
	glow.Material = Enum.Material.ForceField
	glow.Reflectance = 0
	local light = Instance.new("PointLight")
	light.Color = Theme.Colors.Electric
	light.Range = 30
	light.Brightness = 4
	light.Parent = glow
	local primary = forkPart("Pivot", Vector3.new(1, 1, 1), CFrame.new())
	primary.Transparency = 1
	fork.PrimaryPart = primary
	fork.Parent = folders.EventObjects
	return fork
end

local function buildCrumbWorld(folders: { [string]: Folder }): any
	local area = folders.SecretArea
	local floorY = MAP.CrumbWorldY
	local halfX, halfZ, height = 80, 50, 60
	local base = Vector3.new(0, floorY, 0)
	local wallColor = Color3.fromRGB(60, 42, 30)

	part(area, {
		Name = "Floor",
		Size = Vector3.new(halfX * 2, 4, halfZ * 2),
		CFrame = CFrame.new(base - Vector3.new(0, 2, 0)),
		Color = Color3.fromRGB(110, 76, 46),
		Material = Enum.Material.Sand,
	})
	part(area, {
		Name = "Ceiling",
		Size = Vector3.new(halfX * 2, 4, halfZ * 2),
		CFrame = CFrame.new(base + Vector3.new(0, height + 2, 0)),
		Color = wallColor,
		Material = Enum.Material.Slate,
	})
	for _, sx in { -1, 1 } do
		part(area, {
			Name = "Wall",
			Size = Vector3.new(4, height, halfZ * 2),
			CFrame = CFrame.new(base + Vector3.new(sx * (halfX + 2), height / 2, 0)),
			Color = wallColor,
			Material = Enum.Material.Slate,
		})
	end
	for _, sz in { -1, 1 } do
		part(area, {
			Name = "Wall",
			Size = Vector3.new(halfX * 2, height, 4),
			CFrame = CFrame.new(base + Vector3.new(0, height / 2, sz * (halfZ + 2))),
			Color = wallColor,
			Material = Enum.Material.Slate,
		})
	end

	-- Warm lamps
	for _, x in { -50, 0, 50 } do
		local lamp = part(area, {
			Name = "Lamp",
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(base + Vector3.new(x, height - 4, 0)),
			Shape = Enum.PartType.Ball,
			Color = C.Gold,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Range = 60
		light.Brightness = 2
		light.Color = Color3.fromRGB(255, 200, 140)
		light.Parent = lamp
	end

	-- Crumb piles (deterministic so every server looks the same)
	local rng = Random.new(1987)
	for _ = 1, 70 do
		local size = rng:NextNumber(0.8, 2.6)
		part(area, {
			Name = "Crumb",
			Size = Vector3.new(size, size * 0.7, size * 0.9),
			CFrame = CFrame.new(
				base + Vector3.new(rng:NextNumber(-halfX + 4, halfX - 4), size * 0.3, rng:NextNumber(-halfZ + 4, halfZ - 4))
			) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0),
			Color = if rng:NextNumber() > 0.5 then C.Crumb else C.Crust,
			CanCollide = false,
		})
	end

	-- Tiny buildings
	local buildings = {
		{ x = -55, z = -30, name = "CRUMB BANK", color = Color3.fromRGB(200, 150, 90) },
		{ x = -20, z = -34, name = "TOAST MUSEUM\nEST. 1987", color = Color3.fromRGB(170, 110, 70) },
		{ x = 25, z = -32, name = "BUTTER INN", color = C.Butter },
		{ x = 66, z = -28, name = "LOST & FOUND", color = Color3.fromRGB(150, 120, 100) },
	}
	for _, b in buildings do
		part(area, {
			Name = "House",
			Size = Vector3.new(16, 12, 12),
			CFrame = CFrame.new(base + Vector3.new(b.x, 6, b.z)),
			Color = b.color,
			Material = Enum.Material.Brick,
		})
		for _, side in { -1, 1 } do
			part(area, {
				Name = "Roof",
				Size = Vector3.new(16, 5, 6),
				CFrame = CFrame.new(base + Vector3.new(b.x, 14.5, b.z + side * 3))
					* CFrame.Angles(0, if side == 1 then math.rad(180) else 0, 0),
				Color = C.Crust,
				Wedge = true,
			})
		end
		part(area, {
			Name = "Door",
			Size = Vector3.new(4, 6, 0.4),
			CFrame = CFrame.new(base + Vector3.new(b.x, 3, b.z + 6.1)),
			Color = C.Charcoal,
		})
		local sign = part(area, {
			Name = "HouseSign",
			Size = Vector3.new(12, 3.5, 0.4),
			CFrame = CFrame.new(base + Vector3.new(b.x, 9.5, b.z + 6.2)),
			Color = C.Panel,
		})
		label(sign, Enum.NormalId.Back, b.name, C.Cream)
	end

	-- Sugar-cube steps up to the Butter Inn roof (a vintage crumb hides up there).
	for i, stepHeight in { 4, 8, 12 } do
		local cube = part(area, {
			Name = "SugarCube",
			Size = Vector3.new(6, stepHeight, 6),
			CFrame = CFrame.new(base + Vector3.new(36 + (3 - i) * 6, stepHeight / 2, -32)),
			Color = Color3.fromRGB(250, 248, 240),
			Material = Enum.Material.Sand,
		})
		if i == 1 then
			label(cube, Enum.NormalId.Front, "SUGAR", Theme.Colors.CreamMuted)
		end
	end

	local function signPost(text: string, pos: Vector3, yaw: number)
		local board = part(area, {
			Name = "Sign",
			Size = Vector3.new(16, 6, 0.6),
			CFrame = CFrame.new(base + pos + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(yaw), 0),
			Color = Color3.fromRGB(107, 58, 30),
			Material = Enum.Material.Wood,
		})
		label(board, Enum.NormalId.Front, text, Color3.fromRGB(242, 201, 135))
		label(board, Enum.NormalId.Back, text, Color3.fromRGB(242, 201, 135))
		part(area, {
			Name = "Post",
			Size = Vector3.new(1, 6, 1),
			CFrame = CFrame.new(base + pos + Vector3.new(0, 3, 0)),
			Color = Color3.fromRGB(74, 40, 20),
		})
	end
	signPost("WELCOME TO CRUMB WORLD\nPOPULATION: CRUMBS", Vector3.new(-62, 0, 10), 90)
	signPost("PLEASE DO NOT\nTOAST THE LOCALS", Vector3.new(10, 0, 30), 180)
	signPost("NO BREAD BEYOND\nTHIS POINT (JK)", Vector3.new(60, 0, 20), -90)

	-- Old Crumb
	local npc = Instance.new("Model")
	npc.Name = "OldCrumb"
	local npcBase = base + Vector3.new(0, 0, -8)
	local crumbBody = part(npc, {
		Name = "Body",
		Size = Vector3.new(5, 4.5, 4),
		CFrame = CFrame.new(npcBase + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0.15, 0.3, 0.1),
		Color = Color3.fromRGB(196, 138, 72),
		Material = Enum.Material.Sand,
	})
	part(npc, {
		Name = "Chunk",
		Size = Vector3.new(3.5, 3, 3.5),
		CFrame = CFrame.new(npcBase + Vector3.new(1.2, 4.2, 0.3)) * CFrame.Angles(0.4, 0.8, 0.2),
		Color = Color3.fromRGB(184, 128, 64),
		Material = Enum.Material.Sand,
	})
	for _, side in { -1, 1 } do
		part(npc, {
			Name = "Lens",
			Size = Vector3.new(0.3, 1.6, 1.6),
			CFrame = CFrame.new(npcBase + Vector3.new(side * 1, 3.6, 2.3)) * Z_AXIS,
			Shape = Enum.PartType.Cylinder,
			Color = Color3.fromRGB(20, 20, 20),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			CanCollide = false,
		})
	end
	part(npc, {
		Name = "Mustache",
		Size = Vector3.new(3.4, 0.7, 0.6),
		CFrame = CFrame.new(npcBase + Vector3.new(0, 2.5, 2.25)),
		Color = C.Cream,
		CanCollide = false,
	})
	part(npc, {
		Name = "Cane",
		Size = Vector3.new(0.4, 5, 0.4),
		CFrame = CFrame.new(npcBase + Vector3.new(3.2, 2.5, 1)),
		Color = Color3.fromRGB(107, 58, 30),
		CanCollide = false,
	})
	billboard(crumbBody, "OLD CRUMB\n(since 1987)", C.Gold, UDim2.fromOffset(180, 50), Vector3.new(0, 5, 0), 80)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Old Crumb"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = crumbBody
	npc.PrimaryPart = crumbBody
	npc.Parent = area

	-- Three vintage crumbs hidden around the world
	local vintage: { BasePart } = {}
	local spots = {
		Vector3.new(-55, 1.2, -42), -- behind the bank
		Vector3.new(25, 17.5, -32), -- on the inn roof
		Vector3.new(74, 1.2, 44), -- far corner
	}
	for i, pos in spots do
		local crumb = part(area, {
			Name = "VintageCrumb" .. i,
			Size = Vector3.new(1.6, 1.2, 1.4),
			CFrame = CFrame.new(base + pos) * CFrame.Angles(0.3, i, 0.2),
			Color = C.Legend,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanTouch = true,
		})
		crumb:SetAttribute("VintageId", "V" .. i)
		local sparkle = Instance.new("Sparkles")
		sparkle.SparkleColor = C.Legend
		sparkle.Parent = crumb
		table.insert(vintage, crumb)
	end

	local returnPad = part(area, {
		Name = "ReturnPad",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(base + Vector3.new(68, 0.5, 0)),
		Color = C.Orange,
		Material = Enum.Material.Neon,
		CanTouch = true,
	})
	billboard(returnPad, "⬆ BACK TO THE TOASTER", C.Orange, UDim2.fromOffset(220, 40), Vector3.new(0, 5, 0), 120)

	return {
		Entry = base + Vector3.new(-50, 18, 0),
		Floor = floorY,
		ReturnPad = returnPad,
		NpcPrompt = prompt,
		NpcHead = crumbBody,
		VintageCrumbs = vintage,
		Bounds = { minY = floorY - 10, maxY = floorY + height + 10 },
	}
end

local function setupCollisionGroups()
	local PhysicsService = game:GetService("PhysicsService")
	for _, name in GROUPS do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	-- Launched bread flies through the toaster, the lid and each other.
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Launched, GROUPS.Launched, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Launched, GROUPS.Toaster, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Launched, GROUPS.ToasterCeiling, false)
	PhysicsService:CollisionGroupSetCollidable(GROUPS.Launched, GROUPS.Players, false)
	-- The invisible lid only stops players.
	PhysicsService:CollisionGroupSetCollidable(GROUPS.ToasterCeiling, "Default", false)
end

MapBuilder.Info = nil :: MapInfo?

function MapBuilder.Build(): MapInfo
	setupCollisionGroups()
	setupLighting()

	local folders: { [string]: Folder } = {}
	for _, name in { "Lobby", "Toaster", "SpawnPoints", "LandingZones", "SecretArea", "EventObjects", "Kitchen", "Pickups" } do
		folders[name] = folder(workspace, name)
	end

	buildKitchen(folders.Kitchen)
	local lobbyCenter, lobbyRadius = buildLobby(folders)
	local toaster = buildToaster(folders)
	local fieldCenter = buildField(folders)
	local hand = buildHand(folders)
	local fork = buildFork(folders)
	local crumbWorld = buildCrumbWorld(folders)

	local halfL, halfW = MAP.InteriorLength / 2, MAP.InteriorWidth / 2
	local info: MapInfo = {
		ToasterCenter = Vector3.new(0, MAP.FloorY, 0),
		FloorY = MAP.FloorY,
		HalfLength = halfL,
		HalfWidth = halfW,
		ToasterSpawns = toaster.spawns,
		CrumbArea = { minX = -halfL + 4, maxX = halfL - 4, minZ = -halfW + 4, maxZ = halfW - 4 },
		ButterSpots = toaster.butterSpots,
		LobbyCenter = lobbyCenter,
		LobbySpawnRadius = lobbyRadius,
		FieldCenter = fieldCenter,
		FieldGroundY = 0,
		LeverKnob = toaster.knob,
		KnobUpY = toaster.knobUpY,
		KnobDownY = toaster.knobDownY,
		Hand = hand,
		Fork = fork,
		SecretSensor = toaster.sensor,
		CrumbWorld = crumbWorld,
		Folders = folders,
	}
	MapBuilder.Info = info
	return info
end

-- Is a world position inside the toaster's interior volume?
function MapBuilder.IsInsideToaster(position: Vector3): boolean
	local info = MapBuilder.Info
	if not info then
		return false
	end
	return math.abs(position.X) <= info.HalfLength
		and math.abs(position.Z) <= info.HalfWidth
		and position.Y >= info.FloorY - 2
		and position.Y <= info.FloorY + MAP.WallHeight + 4
end

function MapBuilder.IsInCrumbWorld(position: Vector3): boolean
	local info = MapBuilder.Info
	if not info then
		return false
	end
	local bounds = info.CrumbWorld.Bounds
	return position.Y >= bounds.minY and position.Y <= bounds.maxY
end

return MapBuilder
