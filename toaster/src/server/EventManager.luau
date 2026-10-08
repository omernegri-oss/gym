-- Heating-phase chaos: random telegraphed events (falling food, hot spots,
-- steam bursts, toaster shakes, falling butter) and the rare Giant Fork boss.
-- Every hazard is announced to clients before it can affect anyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local ForkPath = require(Shared.ForkPath)

local EventManager = {}

local EVENTS = Config.Events
local FORK = Config.Fork
local services
local rng = Random.new()

type HotSpot = { Position: Vector3, Radius: number, StartsAt: number, EndsAt: number }

local heatingToken = 0
local hotSpots: { HotSpot } = {}
local roundsSinceFork = 0
local forkThisRound = false

local function now(): number
	return workspace:GetServerTimeNow()
end

function EventManager.Init(registry)
	services = registry
end

local function info()
	return services.MapBuilder.Info
end

local function randomFloorPoint(margin: number): Vector3
	local i = info()
	return Vector3.new(
		rng:NextNumber(-i.HalfLength + margin, i.HalfLength - margin),
		i.FloorY,
		rng:NextNumber(-i.HalfWidth + margin, i.HalfWidth - margin)
	)
end

-- Runs `fn` after `delay` seconds unless heating ended in the meantime.
local function later(delay: number, fn: () -> ())
	local token = heatingToken
	task.delay(delay, function()
		if token == heatingToken then
			fn()
		end
	end)
end

local function sessionsNear(position: Vector3, radius: number): { any }
	local result = {}
	for _, session in services.PlayerManager.InRound() do
		local root = services.PlayerManager.GetBody(session)
		if root then
			local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
			if flat.Magnitude <= radius and math.abs(root.Position.Y - position.Y) < 12 then
				table.insert(result, { Session = session, Root = root })
			end
		end
	end
	return result
end

local function pushAway(center: Vector3, root: BasePart, force: number, lift: number): Vector3
	local flat = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit
	return dir * force + Vector3.new(0, lift, 0)
end

------------------------------------------------------------------ events

local RUNNERS = {}

local function dropItem(kind: string, position: Vector3)
	local cfg = EVENTS.FallingFood
	local impactIn = EVENTS.WarningTime + cfg.FallTime
	services.Messaging.Effect(nil, "FallingItem", {
		Kind = kind,
		Position = position,
		ImpactAt = now() + impactIn,
		FallTime = cfg.FallTime,
	})
	later(impactIn, function()
		services.Messaging.Effect(nil, "Impact", { Position = position, Kind = kind })
		if kind == "Junk" then
			for _, hit in sessionsNear(position, cfg.ImpactRadius) do
				services.AbilityManager.Push(hit.Session, pushAway(position, hit.Root, cfg.JunkKnockback, 30))
				services.Messaging.Notify(hit.Session.Player, "💥 BONK! Kitchen junk!", "Danger", 1.4)
			end
			services.Messaging.Sound(nil, "Impact", position)
		else
			services.PickupManager.SpawnAt(kind, position + Vector3.new(0, 1, 0), 12)
		end
	end)
end

function RUNNERS.FallingFood()
	local cfg = EVENTS.FallingFood
	services.Messaging.Notify(nil, "🍞 Food is falling from the sky!", "Warning", 2)
	for _ = 1, rng:NextInteger(cfg.CountMin, cfg.CountMax) do
		local roll = rng:NextNumber()
		local kind = if roll < cfg.JunkChance then "Junk" elseif roll < cfg.JunkChance + 0.1 then "GoldenCrumb" else "Crumb"
		dropItem(kind, randomFloorPoint(6))
	end
end

function RUNNERS.FallingButter()
	services.Messaging.Notify(nil, "🧈 BUTTER INCOMING! Look for the shadow!", "Good", 2.5)
	dropItem("Butter", randomFloorPoint(10))
end

function RUNNERS.HotSpot()
	local cfg = EVENTS.HotSpot
	local spot: HotSpot = {
		Position = randomFloorPoint(cfg.Radius),
		Radius = cfg.Radius,
		StartsAt = now() + EVENTS.WarningTime,
		EndsAt = now() + EVENTS.WarningTime + cfg.Duration,
	}
	table.insert(hotSpots, spot)
	services.Messaging.Effect(nil, "HotSpot", spot)
	services.Messaging.Notify(nil, "⚠️ HOT ZONE! Get out of the red circle!", "Danger", 2)
end

function RUNNERS.SteamBurst()
	local cfg = EVENTS.SteamBurst
	local i = info()
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local position = Vector3.new(rng:NextNumber(-i.HalfLength + 10, i.HalfLength - 10), i.FloorY, side * (i.HalfWidth - cfg.Radius))
	services.Messaging.Effect(nil, "SteamWarning", { Position = position, Radius = cfg.Radius, At = now() + EVENTS.WarningTime })
	later(EVENTS.WarningTime, function()
		services.Messaging.Effect(nil, "Steam", { Position = position, Radius = cfg.Radius })
		services.Messaging.Sound(nil, "Steam", position)
		for _, hit in sessionsNear(position, cfg.Radius) do
			services.AbilityManager.Push(hit.Session, Vector3.new(0, cfg.Lift, 0))
			services.HeatManager.AddHeat(hit.Session, cfg.Heat)
			services.Messaging.Notify(hit.Session.Player, "♨️ STEAMED!", "Danger", 1.4)
		end
	end)
end

function RUNNERS.ToasterShake()
	local cfg = EVENTS.ToasterShake
	services.Messaging.Notify(nil, "📳 THE TOASTER IS SHAKING!", "Warning", 2)
	services.Messaging.Effect(nil, "Shake", { Intensity = 0.4, Duration = EVENTS.WarningTime })
	services.Messaging.Sound(nil, "Shake")
	later(EVENTS.WarningTime, function()
		services.Messaging.Effect(nil, "Shake", { Intensity = 1.2, Duration = cfg.Duration })
		for _, session in services.PlayerManager.InRound() do
			local angle = rng:NextNumber(0, math.pi * 2)
			services.AbilityManager.Push(session, Vector3.new(math.cos(angle) * cfg.Shove, 18, math.sin(angle) * cfg.Shove))
		end
	end)
end

local function pickEvent(): string
	local total = 0
	for _, weight in EVENTS.Weights do
		total += weight
	end
	local roll = rng:NextNumber(0, total)
	for name, weight in EVENTS.Weights do
		roll -= weight
		if roll <= 0 then
			return name
		end
	end
	return "FallingFood"
end

------------------------------------------------------------------ fork boss

local function zap(position: Vector3)
	services.Messaging.Effect(nil, "ForkZap", { Position = position, Radius = FORK.ZapRadius })
	services.Messaging.Sound(nil, "ForkZap", position)
	for _, hit in sessionsNear(position, FORK.ZapRadius) do
		services.HeatManager.AddHeat(hit.Session, FORK.ZapHeat)
		services.AbilityManager.Push(hit.Session, pushAway(position, hit.Root, FORK.ZapKnockback, 40))
		services.Messaging.Notify(hit.Session.Player, "⚡ ZAPPED BY THE FORK!", "Electric", 1.6)
	end
end

local function startFork()
	local startAt = now() + FORK.WarningDuration
	local endAt = startAt + FORK.Duration
	local center = info().ToasterCenter
	services.RoundManager.SetRoundAttribute(Constants.RoundAttr.ForkActive, true)
	services.Messaging.Notify(nil, "⚠️ WARNING\nTHE FORK IS HERE!", "Electric", 3)
	services.Messaging.Sound(nil, "ForkWarning")
	services.Messaging.Effect(nil, "Fork", {
		StartAt = startAt,
		EndAt = endAt,
		Center = center,
		PathRadiusX = FORK.PathRadiusX,
		PathRadiusZ = FORK.PathRadiusZ,
		LapTime = FORK.LapTime,
	})

	later(FORK.WarningDuration, function()
		services.Messaging.Notify(nil, "⚡ ELECTRICAL EVENT ACTIVE", "Electric", 2.5)
	end)

	-- Schedule zaps: each one is announced ZapWarning seconds ahead at the
	-- spot the fork will be when it strikes.
	local zapTime = startAt + FORK.ZapInterval
	while zapTime < endAt do
		local strikeAt = zapTime
		local warnDelay = math.max(0, strikeAt - FORK.ZapWarning - now())
		later(warnDelay, function()
			local ox, oz = ForkPath.Offset(strikeAt - startAt, FORK)
			local position = center + Vector3.new(ox, 0, oz)
			services.Messaging.Effect(nil, "ForkZapWarning", { Position = position, Radius = FORK.ZapRadius, At = strikeAt })
			later(math.max(0, strikeAt - now()), function()
				zap(position)
			end)
		end)
		zapTime += FORK.ZapInterval
	end

	later(endAt - now(), function()
		services.RoundManager.SetRoundAttribute(Constants.RoundAttr.ForkActive, false)
		services.Messaging.Notify(nil, "🍴 The fork has left the toaster.", "Info", 2)
	end)
end

------------------------------------------------------------------ lifecycle

function EventManager.PrepareRound(_roundNumber: number)
	roundsSinceFork += 1
	forkThisRound = FORK.ForceEveryRound
		or (roundsSinceFork >= FORK.MinRoundsBetween and (rng:NextNumber() < FORK.Chance or roundsSinceFork >= FORK.GuaranteeAfter))
	if forkThisRound then
		roundsSinceFork = 0
	end
end

function EventManager.StartHeating()
	heatingToken += 1
	local token = heatingToken
	if forkThisRound then
		later(FORK.StartDelay, startFork)
	end
	task.spawn(function()
		task.wait(EVENTS.FirstEventDelay)
		while token == heatingToken do
			local name = pickEvent()
			local ok, err = pcall(RUNNERS[name])
			if not ok then
				warn("[EventManager] event", name, "failed:", err)
			end
			task.wait(rng:NextNumber(EVENTS.IntervalMin, EVENTS.IntervalMax))
		end
	end)
end

function EventManager.StopHeating()
	heatingToken += 1
	table.clear(hotSpots)
	services.RoundManager.SetRoundAttribute(Constants.RoundAttr.ForkActive, false)
	services.Messaging.Effect(nil, "ClearHazards", {})
end

function EventManager.Cleanup()
	EventManager.StopHeating()
	forkThisRound = false
end

function EventManager.HotSpotMultiplierAt(position: Vector3): number?
	if #hotSpots == 0 then
		return nil
	end
	local t = now()
	local best: number? = nil
	for i = #hotSpots, 1, -1 do
		local spot = hotSpots[i]
		if t >= spot.EndsAt then
			table.remove(hotSpots, i)
		elseif t >= spot.StartsAt then
			local flat = Vector3.new(position.X - spot.Position.X, 0, position.Z - spot.Position.Z)
			if flat.Magnitude <= spot.Radius then
				best = Config.HeatZones.HotSpotMultiplier
			end
		end
	end
	return best
end

return EventManager
