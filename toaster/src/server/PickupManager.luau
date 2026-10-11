-- Crumbs and Butter inside the toaster. Pickups are anchored, non-colliding
-- parts; the server listens to Touched and validates proximity, availability
-- and round state before granting anything. Respawning reuses the same part
-- (pooling) instead of destroying and recreating it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Theme = require(Shared.Theme)

local PickupManager = {}

local ATTR = Constants.Attr
local services
local rng = Random.new()

type Pickup = {
	Id: number,
	Kind: string, -- "Crumb" | "GoldenCrumb" | "Butter"
	Part: BasePart,
	Available: boolean,
	Respawns: boolean,
	SpotIndex: number?,
	Connection: RBXScriptConnection?,
}

local pickups: { [number]: Pickup } = {}
local nextId = 0
local roundToken = 0
local butterSpotsUsed: { [number]: boolean } = {}
local fullWarnings: { [Player]: number } = {}

function PickupManager.Init(registry)
	services = registry
end

local function randomFloorPosition(): Vector3
	local info = services.MapBuilder.Info
	local area = info.CrumbArea
	return Vector3.new(rng:NextNumber(area.minX, area.maxX), info.FloorY + 1, rng:NextNumber(area.minZ, area.maxZ))
end

local function styleAs(pickup: Pickup)
	local p = pickup.Part
	for _, child in p:GetChildren() do
		child:Destroy()
	end
	if pickup.Kind == "Butter" then
		p.Size = Vector3.new(2.6, 1.1, 1.8)
		p.Color = Theme.Colors.Butter
		p.Material = Enum.Material.SmoothPlastic
		local light = Instance.new("PointLight")
		light.Color = Theme.Colors.Butter
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = p
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(60, 30)
		gui.StudsOffset = Vector3.new(0, 2.4, 0)
		gui.MaxDistance = 90
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Theme.Fonts.Display
		text.TextScaled = true
		text.TextColor3 = Theme.Colors.Butter
		text.TextStrokeTransparency = 0.3
		text.Text = "🧈 BUTTER"
		text.Parent = gui
		gui.Parent = p
	elseif pickup.Kind == "GoldenCrumb" then
		p.Size = Vector3.new(1.6, 1.2, 1.4)
		p.Color = Theme.Colors.Legend
		p.Material = Enum.Material.Neon
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Theme.Colors.Legend
		sparkles.Parent = p
	else
		p.Size = Vector3.new(1.3, 0.9, 1.1)
		p.Color = Theme.Colors.Crumb
		p.Material = Enum.Material.Sand
	end
end

local function setAvailable(pickup: Pickup, available: boolean)
	pickup.Available = available
	pickup.Part.Transparency = if available then 0 else 1
	pickup.Part.CanTouch = available
	for _, child in pickup.Part:GetChildren() do
		if child:IsA("BillboardGui") or child:IsA("Light") then
			(child :: any).Enabled = available
		elseif child:IsA("Sparkles") then
			child.Enabled = available
		end
	end
end

local function chooseButterSpot(): number?
	local info = services.MapBuilder.Info
	local free = {}
	for index in info.ButterSpots do
		if not butterSpotsUsed[index] then
			table.insert(free, index)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

local function place(pickup: Pickup)
	local position
	if pickup.Kind == "Butter" and pickup.Respawns then
		local spot = chooseButterSpot()
		if not spot then
			return false
		end
		pickup.SpotIndex = spot
		butterSpotsUsed[spot] = true
		position = services.MapBuilder.Info.ButterSpots[spot]
	else
		if pickup.Respawns then
			pickup.Kind = if rng:NextNumber() < Config.Crumbs.GoldenChance then "GoldenCrumb" else "Crumb"
			styleAs(pickup)
		end
		position = randomFloorPosition()
	end
	pickup.Part.CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 0.5), rng:NextNumber(0, 6.28), 0)
	setAvailable(pickup, true)
	return true
end

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function grant(session, pickup: Pickup): boolean
	local player = session.Player
	local position = pickup.Part.Position
	if pickup.Kind == "Butter" then
		if session.IsCharcoal then
			return false
		end
		if session.ButterCarried >= Config.Butter.MaxCarried then
			local t = os.clock()
			if t - (fullWarnings[player] or 0) > 3 then
				fullWarnings[player] = t
				services.Messaging.Notify(player, "🧈 You can only carry one butter. Use it first!", "Info", 2)
			end
			return false
		end
		session.ButterCarried += 1
		player:SetAttribute(ATTR.ButterCarried, session.ButterCarried)
		services.Messaging.Notify(player, "🧈 Butter collected! Use it when the heat is on.", "Good", 2.5)
		services.Messaging.Sound(nil, "ButterPickup", position)
	else
		local value = if pickup.Kind == "GoldenCrumb" then Config.Crumbs.GoldenValue else Config.Crumbs.Value
		if not services.CurrencyManager.Add(player, "Crumbs", value, "Pickup") then
			return false
		end
		session.RoundCrumbs += value
		player:SetAttribute(ATTR.RoundCrumbs, session.RoundCrumbs)
		if pickup.Kind == "GoldenCrumb" then
			services.Messaging.FloatingText(player, position, `+{value} 🍞`, Theme.Colors.Legend)
		end
		services.Messaging.Sound(player, if pickup.Kind == "GoldenCrumb" then "GoldenCrumb" else "CrumbPickup")
	end
	services.Messaging.Effect(nil, "Pickup", { Position = position, Kind = pickup.Kind })
	return true
end

local function onTouched(pickup: Pickup, hit: BasePart)
	if not pickup.Available then
		return
	end
	local player = playerFromHit(hit)
	if not player then
		return
	end
	local session = services.PlayerManager.Get(player)
	if not session or not session.InRound then
		return
	end
	local root = services.PlayerManager.GetBody(session)
	if not root or (root.Position - pickup.Part.Position).Magnitude > Config.Crumbs.PickupRadius then
		return -- proximity validation
	end
	if not grant(session, pickup) then
		return
	end
	setAvailable(pickup, false)
	if pickup.Kind == "Butter" and pickup.SpotIndex then
		butterSpotsUsed[pickup.SpotIndex] = false
	end
	if pickup.Respawns then
		local token = roundToken
		local delay = if pickup.Kind == "Butter" then Config.Butter.RespawnTime else Config.Crumbs.RespawnTime
		task.delay(delay, function()
			if token == roundToken and pickups[pickup.Id] then
				place(pickup)
			end
		end)
	else
		pickups[pickup.Id] = nil
		if pickup.Connection then
			pickup.Connection:Disconnect()
		end
		pickup.Part:Destroy()
	end
end

local function create(kind: string, respawns: boolean): Pickup
	nextId += 1
	local p = Instance.new("Part")
	p.Name = kind
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.CollisionGroup = Constants.CollisionGroups.Pickups
	local pickup: Pickup = {
		Id = nextId,
		Kind = kind,
		Part = p,
		Available = false,
		Respawns = respawns,
	}
	styleAs(pickup)
	pickup.Connection = p.Touched:Connect(function(hit)
		onTouched(pickup, hit)
	end)
	CollectionService:AddTag(p, Constants.Tags.Pickup)
	p.Parent = services.MapBuilder.Info.Folders.Pickups
	pickups[nextId] = pickup
	return pickup
end

function PickupManager.SpawnRoundPickups()
	for _ = 1, Config.Crumbs.SpawnCount do
		place(create("Crumb", true))
	end
	for _ = 1, Config.Butter.SpawnCount do
		local pickup = create("Butter", true)
		if not place(pickup) then
			pickup.Part:Destroy()
			pickups[pickup.Id] = nil
		end
	end
end

-- One-off pickup (e.g. dropped by a falling-food event). Despawns after lifetime.
function PickupManager.SpawnAt(kind: string, position: Vector3, lifetime: number?)
	local pickup = create(kind, false)
	pickup.Part.CFrame = CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	setAvailable(pickup, true)
	local token = roundToken
	task.delay(lifetime or 15, function()
		if token == roundToken and pickups[pickup.Id] then
			pickups[pickup.Id] = nil
			pickup.Part:Destroy()
		end
	end)
end

function PickupManager.ClearRoundPickups()
	roundToken += 1
	for _, pickup in pickups do
		if pickup.Connection then
			pickup.Connection:Disconnect()
		end
		pickup.Part:Destroy()
	end
	table.clear(pickups)
	table.clear(butterSpotsUsed)
	table.clear(fullWarnings)
end

return PickupManager
