-- Procedural bread bodies welded onto a standard humanoid character.
-- Built from primitive parts so no uploaded meshes are required. The server
-- builds and updates them; changes replicate to everyone.

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
	Bread = 4.6,
	Bagel = 4.4,
	Croissant = 3.4,
	Waffle = 3.8,
}

type PartSpec = {
	name: string,
	size: Vector3,
	offset: CFrame,
	tint: string?, -- "Body" | "Crust" | nil (fixed colour)
	color: Color3?,
	shape: Enum.PartType?,
	mesh: Vector3?, -- SpecialMesh sphere scale, for ellipsoids
	material: Enum.Material?,
}

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
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = true
	part.CFrame = root.CFrame * spec.offset
	if spec.tint then
		part:SetAttribute("Tint", spec.tint)
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

local SIDEWAYS = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along Z

local function face(specs: { PartSpec }, eyeY: number, eyeX: number, frontZ: number, mouthY: number)
	for _, side in { -1, 1 } do
		table.insert(specs, {
			name = "Eye",
			size = Vector3.new(0.95, 0.95, 0.95),
			offset = CFrame.new(side * eyeX, eyeY, frontZ),
			shape = Enum.PartType.Ball,
			color = Color3.new(1, 1, 1),
		})
		table.insert(specs, {
			name = "Pupil",
			size = Vector3.new(0.42, 0.42, 0.42),
			offset = CFrame.new(side * eyeX * 0.92, eyeY - 0.08, frontZ - 0.38),
			shape = Enum.PartType.Ball,
			color = Theme.Colors.Charcoal,
		})
		table.insert(specs, {
			name = "Brow",
			size = Vector3.new(0.7, 0.14, 0.12),
			offset = CFrame.new(side * eyeX, eyeY + 0.72, frontZ - 0.2) * CFrame.Angles(0, 0, math.rad(side * -14)),
			color = Color3.fromRGB(90, 52, 24),
		})
	end
	table.insert(specs, {
		name = "Mouth",
		size = Vector3.new(0.55, 0.55, 0.2),
		offset = CFrame.new(0, mouthY, frontZ - 0.05),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(90, 52, 24),
		mesh = Vector3.new(1, 1.3, 0.4),
	})
end

local BUILDERS: { [string]: () -> { PartSpec } } = {}

function BUILDERS.Bread(): { PartSpec }
	local specs: { PartSpec } = {
		{ name = "Crust", size = Vector3.new(4.6, 4.4, 1), offset = CFrame.new(0, 0.6, 0.1), tint = "Crust" },
		{ name = "Body", size = Vector3.new(4.1, 4.0, 1), offset = CFrame.new(0, 0.6, -0.05), tint = "Body" },
	}
	for _, side in { -1, 1 } do
		table.insert(specs, {
			name = "CrustLobe",
			size = Vector3.new(1, 3.1, 3.1),
			offset = CFrame.new(side * 1.05, 2.9, 0.1) * SIDEWAYS,
			shape = Enum.PartType.Cylinder,
			tint = "Crust",
		})
		table.insert(specs, {
			name = "BodyLobe",
			size = Vector3.new(1, 2.7, 2.7),
			offset = CFrame.new(side * 1.05, 2.9, -0.05) * SIDEWAYS,
			shape = Enum.PartType.Cylinder,
			tint = "Body",
		})
	end
	face(specs, 2.3, 0.8, -0.6, 1.1)
	return specs
end

function BUILDERS.Bagel(): { PartSpec }
	local specs: { PartSpec } = {}
	local ringRadius = 1.75
	for i = 0, 11 do
		local angle = (i / 12) * math.pi * 2
		table.insert(specs, {
			name = "Ring",
			size = Vector3.new(1.9, 1.9, 1.9),
			offset = CFrame.new(math.cos(angle) * ringRadius, 1.4 + math.sin(angle) * ringRadius, 0),
			shape = Enum.PartType.Ball,
			tint = if i % 2 == 0 then "Body" else "Crust",
		})
	end
	for i = 0, 5 do
		local angle = (i / 6) * math.pi * 2 + 0.3
		table.insert(specs, {
			name = "Sesame",
			size = Vector3.new(0.3, 0.15, 0.15),
			offset = CFrame.new(math.cos(angle) * 1.9, 1.4 + math.sin(angle) * 1.9, -0.95) * CFrame.Angles(0, 0, angle),
			color = Color3.fromRGB(247, 231, 198),
		})
	end
	face(specs, 2.95, 0.75, -0.85, -0.05)
	return specs
end

function BUILDERS.Croissant(): { PartSpec }
	local specs: { PartSpec } = {
		{ name = "Lobe", size = Vector3.new(2.6, 3.2, 2.3), offset = CFrame.new(0, 1.2, 0), tint = "Body", mesh = Vector3.new(1, 1, 1) },
	}
	for _, side in { -1, 1 } do
		table.insert(specs, {
			name = "Lobe",
			size = Vector3.new(2, 2.6, 2),
			offset = CFrame.new(side * 1.6, 0.85, 0.05) * CFrame.Angles(0, 0, math.rad(side * 28)),
			tint = "Crust",
			mesh = Vector3.new(1, 1, 1),
		})
		table.insert(specs, {
			name = "Tip",
			size = Vector3.new(1.4, 2, 1.5),
			offset = CFrame.new(side * 2.75, 0.1, 0.1) * CFrame.Angles(0, 0, math.rad(side * 50)),
			tint = "Body",
			mesh = Vector3.new(1, 1, 1),
		})
	end
	face(specs, 1.75, 0.55, -1.0, 0.55)
	return specs
end

function BUILDERS.Waffle(): { PartSpec }
	local specs: { PartSpec } = {
		{ name = "Body", size = Vector3.new(4.4, 4.4, 1), offset = CFrame.new(0, 1.1, 0), tint = "Body" },
	}
	for i = -1, 1 do
		table.insert(specs, {
			name = "RidgeV",
			size = Vector3.new(0.35, 4.2, 0.3),
			offset = CFrame.new(i * 1.4, 1.1, -0.55),
			tint = "Crust",
		})
		table.insert(specs, {
			name = "RidgeH",
			size = Vector3.new(4.2, 0.35, 0.3),
			offset = CFrame.new(0, 1.1 + i * 1.4, -0.55),
			tint = "Crust",
		})
	end
	for i = -1, 1 do
		table.insert(specs, {
			name = "CrownSpike",
			size = Vector3.new(0.6, if i == 0 then 1.3 else 0.9, 0.6),
			offset = CFrame.new(i * 0.9, 3.75 + (if i == 0 then 0.2 else 0), 0) * CFrame.Angles(0, math.rad(45), 0),
			color = Theme.Colors.Legend,
			material = Enum.Material.Neon,
		})
	end
	table.insert(specs, {
		name = "CrownBand",
		size = Vector3.new(2.6, 0.45, 0.8),
		offset = CFrame.new(0, 3.4, 0),
		color = Theme.Colors.Legend,
		material = Enum.Material.Metal,
	})
	face(specs, 1.95, 0.7, -0.75, 0.6)
	return specs
end

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
				offset = CFrame.new(0, topY + 0.2 + i * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)),
				shape = Enum.PartType.Cylinder,
				color = if i % 2 == 0 then color else Theme.Colors.Butter,
			})
		end
	elseif cosmeticId == "ChefHat" then
		makePart(root, model, {
			name = "Hat",
			size = Vector3.new(1, 1.7, 1.7),
			offset = CFrame.new(0, topY + 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)),
			shape = Enum.PartType.Cylinder,
			color = color,
		})
		makePart(root, model, {
			name = "Hat",
			size = Vector3.new(2.4, 1.6, 2.4),
			offset = CFrame.new(0, topY + 1.3, 0),
			color = color,
			mesh = Vector3.new(1, 1, 1),
		})
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
	makePart(root, model, {
		name = "ButterShield",
		size = Vector3.new(7.5, 7.5, 7.5),
		offset = CFrame.new(0, 1, 0),
		shape = Enum.PartType.Ball,
		color = Theme.Colors.Butter,
		material = Enum.Material.ForceField,
	}).Transparency =
		1

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
	return model
end

function BreadVisuals.Get(character: Model?): Model?
	if not character then
		return nil
	end
	return character:FindFirstChild(MODEL_NAME) :: Model?
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
	local material = Enum.Material.SmoothPlastic
	if mode == "Golden" then
		body, crust = GOLD, GOLD_CRUST
		material = Enum.Material.Foil
	elseif mode == "Charcoal" then
		body, crust = CHARCOAL_BODY, CHARCOAL_CRUST
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
			end
		end
	end
end

local function effectAnchor(model: Model): BasePart?
	local anchor = model:FindFirstChild("Body") or model:FindFirstChild("Lobe") or model:FindFirstChild("Ring")
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
