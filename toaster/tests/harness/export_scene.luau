-- Boots the real server in the mock, plays into the heating phase with four
-- bots (one per bread), poses the hand on the lever, and prints the whole
-- world as JSON for the 3D preview.
local Mock = require("./RobloxMock")
local Sources = require("./generated/Sources")
local Instance, game, workspace, data, task = Mock.Instance, Mock.game, Mock.workspace, Mock.data, Mock.task

local scriptKeys, cache = {}, {}
local function newScript(className, name, key, parent)
	local s = Instance.new(className)
	s.Name = name
	scriptKeys[s] = key
	s.Parent = parent
	return s
end
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local RS, SSS = game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService")
local shared, server, remotes = folder("Shared", RS), folder("Server", SSS), folder("Remotes", RS)
for _, n in { "RoundEvent", "UIEvent", "AbilityEvent", "InteractionEvent", "EffectEvent" } do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
local roundState = folder("RoundState", RS)
folder("Assets", RS)
for key in Sources do
	local dir, file = string.match(key, "^(%w+)/([%w_]+)%.luau$")
	if dir == "shared" then
		newScript("ModuleScript", file, key, shared)
	elseif dir == "server" then
		newScript("ModuleScript", file, key, server)
	end
end
local boot = newScript("Script", "Bootstrap", "Bootstrap.server.luau", SSS)
local function req(inst)
	local key = scriptKeys[inst]
	if cache[key] ~= nil then
		return cache[key]
	end
	local fn = assert(loadstring(Sources[key], "=" .. key))
	setfenv(fn, Mock.Environment(inst, req))
	cache[key] = fn()
	return cache[key]
end
local Config = req(shared.Config)
Config.Fork.ForceEveryRound = true
Config.Fork.StartDelay = 4
local store = {}
Mock.Stores["ToasterPlayerData_v1"] = store
local breads = { "Waffle", "Bagel", "Croissant", "Bread", "Bread" }
local hats = { "Crown", "PartyHat", "ChefHat", nil, nil }
for i, bread in breads do
	store["player_" .. (1000 + i)] = {
		Crumbs = 900,
		XP = 3000,
		EquippedBread = bread,
		UnlockedBreads = { Bread = true, [bread] = true },
		UnlockedCosmetics = if hats[i] then { [hats[i]] = true } else {},
		EquippedCosmetics = if hats[i] then { Hat = hats[i] } else {},
	}
end
task.spawn(function()
	local fn = assert(loadstring(Sources["Bootstrap.server.luau"], "=Bootstrap"))
	setfenv(fn, Mock.Environment(boot, req))
	fn()
end)
Mock.BuildCollisionGrid()
local Vector3 = Mock.Environment(nil, req).Vector3
local CFrame = Mock.Environment(nil, req).CFrame
local names = { "Waffle Wendy", "Bagel Ben", "Croissant Cleo", "Toast Tom", "Burnt Bob" }
local players = {}
for _, n in names do
	table.insert(players, Mock.AddPlayer(n))
end
local spots = { Vector3.new(4, 0, 2), Vector3.new(-16, 0, -8), Vector3.new(22, 0, 10), Vector3.new(-60, 0, 2), Vector3.new(-10, 0, 30) }
task.spawn(function()
	while true do
		local ph = roundState:GetAttribute("Phase")
		if ph == "CALM_PHASE" or ph == "HEATING_PHASE" then
			for i, p in players do
				Mock.MoveTo(p, spots[i])
			end
		end
		task.wait(0.25)
	end
end)
local guard = 0
while roundState:GetAttribute("Phase") ~= "HEATING_PHASE" and guard < 400 do
	Mock.Advance(0.5)
	guard += 1
end
Mock.Advance(21)

-- client-side state, posed for the picture
local CollectionService = game:GetService("CollectionService")
for _, coil in CollectionService:GetTagged("ToasterCoil") do
	coil.Material = Mock.Environment(nil, req).Enum.Material.Neon
	coil.Color = Mock.Environment(nil, req).Color3.fromRGB(255, 106, 26)
end
local knob = CollectionService:GetTagged("ToasterLeverKnob")[1]
local downY = knob:GetAttribute("DownY")
knob.CFrame = CFrame.new(knob.Position.X, downY, knob.Position.Z)
local hand = workspace.EventObjects.GiantHand
local face = CFrame.Angles(0, math.rad(180), 0)
hand:PivotTo(CFrame.new(Vector3.new(knob.Position.X, downY + 2.5, knob.Position.Z + 2)) * face)
local fork = workspace.EventObjects.GiantFork
fork:PivotTo(CFrame.new(Vector3.new(38, Config.Map.FloorY + 6, -16)) * CFrame.Angles(0, 0.4, 0))

-- serialise
local out = {}
local function num(x)
	return string.format("%.3f", x)
end
local function color(c)
	return string.format("[%d,%d,%d]", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function esc(s)
	return (string.gsub(string.gsub(s, "\\", "\\\\"), '[\n"]', function(ch)
		return if ch == "\n" then "\\n" else '\\"'
	end))
end
local parts, labels, signs = {}, {}, {}
local index = 0
local function isA(inst, cls)
	return inst:IsA(cls)
end
local function addPart(p, cfOverride, sizeOverride, colorOverride, labelsOnly)
	local d = data(p)
	local c = cfOverride or d.props.CFrame
	local size = sizeOverride or d.props.Size
	local shape = "Block"
	if d.className == "WedgePart" then
		shape = "Wedge"
	elseif d.props.Shape then
		shape = d.props.Shape.Name
	end
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	local m = c.m
	local material = d.props.Material and d.props.Material.Name or "SmoothPlastic"
	if p:IsA("SpawnLocation") then
		material = "SmoothPlastic"
	end
	if labelsOnly then
		-- invisible anchor: keep its text, drop its geometry (sign index -1 = free-floating)
		table.insert(
			parts,
			string.format(
				'{"s":[%s,%s,%s],"p":[%s,%s,%s],"r":[%s],"c":[0,0,0],"m":"SmoothPlastic","t":1,"h":"Block"}',
				num(size.X),
				num(size.Y),
				num(size.Z),
				num(c.x),
				num(c.y),
				num(c.z),
				table.concat({ num(m[1]), num(m[2]), num(m[3]), num(m[4]), num(m[5]), num(m[6]), num(m[7]), num(m[8]), num(m[9]) }, ",")
			)
		)
	else
		table.insert(
			parts,
			string.format(
				'{"s":[%s,%s,%s],"p":[%s,%s,%s],"r":[%s],"c":%s,"m":"%s","t":%s,"h":"%s"%s}',
				num(size.X),
				num(size.Y),
				num(size.Z),
				num(c.x),
				num(c.y),
				num(c.z),
				table.concat({ num(m[1]), num(m[2]), num(m[3]), num(m[4]), num(m[5]), num(m[6]), num(m[7]), num(m[8]), num(m[9]) }, ","),
				color(colorOverride or d.props.Color),
				material,
				num(d.props.Transparency or 0),
				shape,
				if mesh then ',"e":1' else ""
			)
		)
	end
	index += 1
	for _, gui in p:GetChildren() do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChildOfClass("TextLabel")
			if label and label.Text ~= "" then
				table.insert(
					signs,
					string.format('{"i":%d,"f":"%s","x":"%s","c":%s}', index - 1, gui.Face.Name, esc(label.Text), color(label.TextColor3))
				)
			end
		elseif gui:IsA("BillboardGui") then
			local label = gui:FindFirstChildOfClass("TextLabel")
			if label then
				local off = gui.StudsOffset or Vector3.zero
				table.insert(
					labels,
					string.format(
						'{"p":[%s,%s,%s],"x":"%s","c":%s}',
						num(c.x + off.X),
						num(c.y + off.Y + 1),
						num(c.z + off.Z),
						esc(label.Text),
						color(label.TextColor3)
					)
				)
			end
		end
	end
end
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") then
		local d = data(inst)
		local model = inst:FindFirstAncestorOfClass("Model")
		local isCharacterLimb = model and model:FindFirstChildOfClass("Humanoid") and inst.Parent == model
		local hidden = (d.props.Transparency or 0) >= 1
		if not isCharacterLimb and not hidden then
			addPart(inst)
		elseif not isCharacterLimb and inst:FindFirstChildWhichIsA("LayerCollector") then
			addPart(inst, nil, nil, nil, true)
		elseif isCharacterLimb and inst.Name == "HumanoidRootPart" then
			-- tiny legs under each bread
			local root = d.props.CFrame
			local crust = Mock.Environment(nil, req).Color3.fromRGB(110, 64, 30)
			for _, sx in { -0.6, 0.6 } do
				addPart(inst, root * CFrame.new(sx, -2, 0), Vector3.new(0.7, 2, 0.7), crust)
			end
		end
	end
end
-- name tags
for _, p in players do
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local pos = root.Position
		local tag = p.Name .. (if p:GetAttribute("IsCharcoal") then " (charcoal)" else "")
		table.insert(
			labels,
			string.format('{"p":[%s,%s,%s],"x":"%s","c":[245,235,221],"small":1}', num(pos.X), num(pos.Y + 7), num(pos.Z), esc(tag))
		)
	end
end
local heat = {}
for _, p in players do
	table.insert(
		heat,
		string.format(
			'{"n":"%s","h":%s,"s":"%s","b":"%s"}',
			esc(p.Name),
			num(p:GetAttribute("Heat") or 0),
			p:GetAttribute("HeatState") or "",
			p:GetAttribute("Bread") or ""
		)
	)
end
print(
	"{"
		.. '"parts":['
		.. table.concat(parts, ",")
		.. '],"labels":['
		.. table.concat(labels, ",")
		.. '],"signs":['
		.. table.concat(signs, ",")
		.. '],"players":['
		.. table.concat(heat, ",")
		.. "]}"
)
