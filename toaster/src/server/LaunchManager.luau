-- The POP. A controlled ballistic launch: each player's landing target comes
-- from where they stood (centre = bullseye, POP pad = tight spread), and we
-- solve the exact velocity to reach it. During flight the server owns the
-- character's physics so the landing is authoritative, and launched bread
-- does not collide with the toaster or with each other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local LandingMath = require(Shared.LandingMath)
local Theme = require(Shared.Theme)

local LaunchManager = {}

local LAUNCH = Config.Launch
local GROUPS = Constants.CollisionGroups
local services
local rng = Random.new()

type Flight = {
	Session: any,
	LaunchedAt: number,
	Target: Vector3,
}

local flights: { [Player]: Flight } = {}
local heartbeat: RBXScriptConnection? = nil

function LaunchManager.Init(registry)
	services = registry
end

local function restoreControl(session)
	local root, humanoid = services.PlayerManager.GetBody(session)
	local character = session.Player.Character
	if character then
		services.PlayerManager.SetCollisionGroup(character, GROUPS.Players)
	end
	if root and humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		root.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			root:SetNetworkOwner(session.Player)
		end)
	end
end

local function scoreLanding(session, position: Vector3)
	if session.Landed then
		return
	end
	session.Landed = true
	local info = services.MapBuilder.Info
	local offset = Vector3.new(position.X - info.FieldCenter.X, 0, position.Z - info.FieldCenter.Z)
	local zone = LandingMath.ZoneForDistance(offset.Magnitude, Config.Landing.Zones)
	session.LandingZoneId = zone.Id
	session.LandingZoneName = zone.Name
	session.LandingPoints = zone.Points

	local player = session.Player
	local color = Theme.ZoneColors[zone.Id]
	services.Messaging.FloatingText(nil, position + Vector3.new(0, 6, 0), `{zone.Name}\n+{zone.Points}`, color)
	services.Messaging.Effect(nil, "Landing", { Position = position, Zone = zone.Id })
	services.Messaging.Effect(player, "Shake", { Intensity = 0.8, Duration = 0.4 })
	if zone.Id == "Jackpot" then
		services.Messaging.Notify(nil, `💰 {player.DisplayName} HIT THE JACKPOT!`, "Legend", 3)
	elseif zone.Id == "Perfect" then
		services.Messaging.Notify(player, "🏆 PERFECT LANDING!", "Legend", 2.5)
	else
		services.Messaging.Notify(player, `🎯 {zone.Name}! +{zone.Points}`, "Good", 2)
	end
end

local function finishFlight(player: Player, landedAt: Vector3)
	local flight = flights[player]
	if not flight then
		return
	end
	flights[player] = nil
	scoreLanding(flight.Session, landedAt)
	task.delay(0.7, function()
		if player.Parent == Players then
			restoreControl(flight.Session)
		end
	end)
end

local function stepFlights()
	local t = os.clock()
	local groundY = services.MapBuilder.Info.FieldGroundY
	for player, flight in flights do
		local root = services.PlayerManager.GetBody(flight.Session)
		if not root or player.Parent ~= Players then
			flights[player] = nil
		else
			local airTime = t - flight.LaunchedAt
			local pos = root.Position
			if airTime > LAUNCH.MinAirTime and pos.Y <= groundY + LAUNCH.GroundedHeight and root.AssemblyLinearVelocity.Y <= 1 then
				finishFlight(player, pos)
			elseif airTime > LAUNCH.FlightTime + LAUNCH.LandingTimeout or pos.Y < groundY - 30 then
				-- Physics fallback: put them on their intended target.
				root.AssemblyLinearVelocity = Vector3.zero
				local character = player.Character
				if character then
					character:PivotTo(CFrame.new(flight.Target + Vector3.new(0, 3, 0)))
				end
				finishFlight(player, flight.Target)
			end
		end
	end
	if next(flights) == nil and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

function LaunchManager.LaunchAll()
	local info = services.MapBuilder.Info
	local gravity = workspace.Gravity
	local center = info.ToasterCenter
	local bullseye = info.FieldCenter

	for _, session in services.PlayerManager.InRound() do
		local root, humanoid = services.PlayerManager.GetBody(session)
		local character = session.Player.Character
		if root and humanoid and character then
			-- Survival is decided at the moment of the POP.
			session.Survived = not session.IsCharcoal
			if session.Survived then
				session.Golden = true
				character:SetAttribute(Constants.CharAttr.Golden, true)
				services.PlayerManager.RefreshAppearance(session)
				services.Messaging.Notify(session.Player, `✨ SURVIVED! +{Config.Rewards.SurvivalBonus} BONUS`, "Legend", 3)
				services.Messaging.Sound(nil, "Golden", root.Position)
			end

			if not services.MapBuilder.IsInsideToaster(root.Position) then
				services.PlayerManager.TeleportToToaster(session)
			end
			local localPos = root.Position - center
			local ox, oz = LandingMath.TargetOffset(localPos.X, localPos.Z, LAUNCH, rng:NextNumber(), rng:NextNumber())
			local target = Vector3.new(bullseye.X + ox, info.FieldGroundY + 3, bullseye.Z + oz)
			local start = root.Position
			local vx, vy, vz =
				LandingMath.SolveVelocity(start.X, start.Y, start.Z, target.X, target.Y, target.Z, LAUNCH.FlightTime, gravity)

			session.StuckUntil = 0
			character:SetAttribute(Constants.CharAttr.Stuck, false)
			character:SetAttribute(Constants.CharAttr.Rolling, false)
			services.PlayerManager.SetCollisionGroup(character, GROUPS.Launched)
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			humanoid.PlatformStand = true
			root.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
			root.AssemblyAngularVelocity = Vector3.new(
				rng:NextNumber(-LAUNCH.SpinMax, LAUNCH.SpinMax),
				rng:NextNumber(-LAUNCH.SpinMax, LAUNCH.SpinMax),
				rng:NextNumber(-LAUNCH.SpinMax, LAUNCH.SpinMax)
			)
			flights[session.Player] = { Session = session, LaunchedAt = os.clock(), Target = target }
			services.Messaging.Round(session.Player, "Launched", { FlightTime = LAUNCH.FlightTime })
		end
	end

	services.Messaging.Sound(nil, "Launch", center + Vector3.new(0, 40, 0))
	services.Messaging.Effect(nil, "Pop", { Position = center + Vector3.new(0, Config.Map.WallHeight, 0) })
	if not heartbeat and next(flights) ~= nil then
		heartbeat = RunService.Heartbeat:Connect(stepFlights)
	end
end

function LaunchManager.AllLanded(): boolean
	return next(flights) == nil
end

-- Anyone still airborne (or who reset during landing) lands where they are,
-- or at their target as a safe fallback.
function LaunchManager.FallbackLand(session)
	local player = session.Player
	local flight = flights[player]
	local root = services.PlayerManager.GetBody(session)
	local info = services.MapBuilder.Info
	local spot = if flight then flight.Target else info.FieldCenter + Vector3.new(rng:NextNumber(-60, 60), 3, rng:NextNumber(-60, 60))
	if root and player.Character then
		root.AssemblyLinearVelocity = Vector3.zero
		player.Character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0)))
	end
	if flight then
		finishFlight(player, spot)
	elseif not session.Landed then
		scoreLanding(session, spot)
		restoreControl(session)
	end
end

function LaunchManager.FinalizeAll()
	for _, session in services.PlayerManager.InRound() do
		if not session.Landed then
			LaunchManager.FallbackLand(session)
		end
	end
end

function LaunchManager.Reset()
	for _, flight in flights do
		restoreControl(flight.Session)
	end
	table.clear(flights)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

return LaunchManager
