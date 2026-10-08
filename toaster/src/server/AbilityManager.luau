-- Validates and resolves every player action request: bread abilities
-- (Roll / Flake Trail / Waffle Slam), the Butter Shield and thrown spreads
-- (Jam / Nutella). The client only asks; the server checks rate limits,
-- round state, ownership, cooldowns and arguments, then decides the outcome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityDefinitions = require(Shared.AbilityDefinitions)
local BreadDefinitions = require(Shared.BreadDefinitions)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)
local RateLimiter = require(Shared.RateLimiter)

local AbilityManager = {}

local PHASES = Constants.Phases
local ATTR = Constants.Attr
local services
local limiter = RateLimiter.new(Config.RateLimits.Ability.Capacity, Config.RateLimits.Ability.RefillPerSecond)

type Hazard = {
	Kind: string, -- "Flake" | "Puddle"
	Position: Vector3,
	Radius: number,
	ExpiresAt: number,
	Owner: Player?,
}

local hazards: { Hazard } = {}
local slipCooldowns: { [Player]: number } = {}
local hazardLoop: thread? = nil
local roundToken = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

function AbilityManager.Init(registry)
	services = registry
end

-- Knockback is applied by the victim's own client (it owns its physics).
function AbilityManager.Push(session, velocity: Vector3)
	services.Messaging.Effect(session.Player, "Knockback", { Velocity = velocity })
end

local function reject(player: Player, message: string)
	services.Messaging.Notify(player, message, "Info", 1.6)
	services.Messaging.Sound(player, "Error")
end

local function startCooldown(session, key: string, duration: number)
	local endsAt = now() + duration
	session.Cooldowns[key] = endsAt
	session.Player:SetAttribute(ATTR.CooldownPrefix .. key, endsAt)
end

local function onCooldown(session, key: string): boolean
	return now() < (session.Cooldowns[key] or 0)
end

local function otherSessionsNear(position: Vector3, radius: number, exclude: Player?): { any }
	local result = {}
	for _, session in services.PlayerManager.InRound() do
		if session.Player ~= exclude then
			local root = services.PlayerManager.GetBody(session)
			if root and (root.Position - position).Magnitude <= radius then
				table.insert(result, { Session = session, Root = root })
			end
		end
	end
	return result
end

local function outward(from: Vector3, to: Vector3, force: number, lift: number): Vector3
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local dir = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(1, 0, 0)
	return dir * force + Vector3.new(0, lift, 0)
end

local function slip(victim, kind: string, duration: number, position: Vector3)
	local player = victim.Player
	local t = now()
	if t < (slipCooldowns[player] or 0) then
		return
	end
	slipCooldowns[player] = t + duration + 0.6
	if kind == "Puddle" then
		services.Messaging.Effect(player, "Slide", { Duration = duration })
		services.Messaging.Sound(nil, "NutellaSlip", position)
	else
		services.Messaging.Effect(player, "Slip", { Duration = duration })
		services.Messaging.Notify(player, "🥐 You slipped on a flake!", "Info", 1.5)
		services.Messaging.Sound(nil, "Slip", position)
	end
end

local function stepHazards()
	local t = now()
	for i = #hazards, 1, -1 do
		if t >= hazards[i].ExpiresAt then
			table.remove(hazards, i)
		end
	end
	if #hazards == 0 then
		return false
	end
	for _, session in services.PlayerManager.InRound() do
		local root = services.PlayerManager.GetBody(session)
		if root then
			for _, hazard in hazards do
				local flat = Vector3.new(root.Position.X - hazard.Position.X, 0, root.Position.Z - hazard.Position.Z)
				if
					hazard.Owner ~= session.Player
					and flat.Magnitude <= hazard.Radius
					and math.abs(root.Position.Y - hazard.Position.Y) < 5
				then
					if hazard.Kind == "Puddle" then
						slip(session, "Puddle", Config.Spreads.Nutella.SlideDuration, root.Position)
					else
						slip(session, "Flake", AbilityDefinitions.FlakeTrail.SlipDuration, root.Position)
					end
					break
				end
			end
		end
	end
	return true
end

-- Runs only while hazards exist.
local function ensureHazardLoop()
	if hazardLoop then
		return
	end
	hazardLoop = task.defer(function()
		while stepHazards() do
			task.wait(0.1)
		end
		hazardLoop = nil
	end)
end

local function addHazard(hazard: Hazard)
	table.insert(hazards, hazard)
	ensureHazardLoop()
end

------------------------------------------------------------------ abilities

local ABILITIES = {}

function ABILITIES.Roll(session, root: BasePart)
	local def = AbilityDefinitions.Roll
	local player = session.Player
	local character = player.Character :: Model
	character:SetAttribute(Constants.CharAttr.Rolling, true)
	services.Messaging.Effect(player, "Roll", { Duration = def.Duration, Speed = def.Speed, TurnRate = def.TurnRate })
	services.Messaging.Sound(nil, "Ability", root.Position)
	local token = roundToken
	task.spawn(function()
		local bumped = {}
		local deadline = os.clock() + def.Duration
		while os.clock() < deadline and token == roundToken do
			local currentRoot = services.PlayerManager.GetBody(session)
			if not currentRoot then
				break
			end
			for _, hit in otherSessionsNear(currentRoot.Position, def.BumpRadius, player) do
				if not bumped[hit.Session] then
					bumped[hit.Session] = true
					AbilityManager.Push(hit.Session, outward(currentRoot.Position, hit.Root.Position, def.BumpForce, 25))
					services.Messaging.Sound(nil, "Knock", hit.Root.Position)
				end
			end
			task.wait(0.1)
		end
		if character.Parent then
			character:SetAttribute(Constants.CharAttr.Rolling, false)
		end
	end)
end

function ABILITIES.FlakeTrail(session, root: BasePart)
	local def = AbilityDefinitions.FlakeTrail
	services.Messaging.Sound(nil, "Ability", root.Position)
	local token = roundToken
	task.spawn(function()
		local deadline = os.clock() + def.Duration
		while os.clock() < deadline and token == roundToken do
			local currentRoot = services.PlayerManager.GetBody(session)
			if not currentRoot then
				break
			end
			local drop = currentRoot.Position - currentRoot.CFrame.LookVector * 2.5 - Vector3.new(0, 2.6, 0)
			addHazard({
				Kind = "Flake",
				Position = drop,
				Radius = def.FlakeRadius,
				ExpiresAt = now() + def.FlakeLifetime,
				Owner = session.Player,
			})
			services.Messaging.Effect(nil, "Flake", { Position = drop, Lifetime = def.FlakeLifetime })
			task.wait(def.DropInterval)
		end
	end)
end

function ABILITIES.WaffleSlam(session, root: BasePart)
	local def = AbilityDefinitions.WaffleSlam
	local player = session.Player
	services.Messaging.Effect(player, "SlamJump", { Velocity = def.JumpVelocity })
	services.Messaging.Sound(nil, "Ability", root.Position)
	local token = roundToken
	task.delay(def.SlamDelay, function()
		if token ~= roundToken then
			return
		end
		local currentRoot = services.PlayerManager.GetBody(session)
		if not currentRoot then
			return
		end
		local center = currentRoot.Position
		session.ResistUntil = now() + def.HeatResistDuration
		session.ResistMultiplier = def.HeatResistMultiplier
		for _, hit in otherSessionsNear(center, def.Radius, player) do
			AbilityManager.Push(hit.Session, outward(center, hit.Root.Position, def.Knockback, 35))
		end
		services.Messaging.Effect(nil, "Shockwave", { Position = center - Vector3.new(0, 2.5, 0), Radius = def.Radius })
		services.Messaging.Sound(nil, "Slam", center)
		services.Messaging.Notify(player, "🧇 WAFFLE SLAM! Heat resistance up!", "Legend", 1.8)
	end)
end

------------------------------------------------------------------ spreads

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { services.MapBuilder.Info.Folders.Pickups, services.MapBuilder.Info.Folders.EventObjects }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

local function throwJam(session, root: BasePart, direction: Vector3)
	local cfg = Config.Spreads.Jam
	local origin = root.Position + Vector3.new(0, 1.5, 0)

	-- Closest target along the throw line within the hit radius.
	local best, bestDistance = nil, math.huge
	for _, hit in otherSessionsNear(origin, cfg.Range, session.Player) do
		local offset = hit.Root.Position - origin
		local along = offset:Dot(direction)
		if along > 0 and along < bestDistance then
			local perpendicular = (offset - direction * along).Magnitude
			if perpendicular <= cfg.HitRadius then
				best, bestDistance = hit, along
			end
		end
	end

	local params = rayParams()
	local travelDistance = if best then bestDistance else cfg.Range
	local wall = workspace:Raycast(origin, direction * travelDistance, params)
	local endPoint = origin + direction * travelDistance
	if wall then
		best = nil -- a wall is in the way
		endPoint = wall.Position
	end

	local flightTime = (endPoint - origin).Magnitude / cfg.ProjectileSpeed
	services.Messaging.Effect(nil, "Projectile", { Kind = "Jam", From = origin, To = endPoint, Duration = flightTime })
	services.Messaging.Sound(nil, "Throw", origin)

	local token = roundToken
	task.delay(flightTime, function()
		if token ~= roundToken then
			return
		end
		services.Messaging.Effect(nil, "Splat", { Kind = "Jam", Position = endPoint })
		if not best then
			return
		end
		local victim = best.Session
		if not victim.InRound or not services.PlayerManager.GetBody(victim) then
			return
		end
		victim.StuckUntil = now() + cfg.StuckDuration
		services.PlayerManager.RefreshMovement(victim)
		local character = victim.Player.Character
		if character then
			character:SetAttribute(Constants.CharAttr.Stuck, true)
		end
		services.Messaging.Notify(victim.Player, `🍓 {session.Player.DisplayName} JAMMED you!`, "Danger", 1.8)
		services.Messaging.Notify(session.Player, `🍓 Direct hit on {victim.Player.DisplayName}!`, "Good", 1.5)
		services.Messaging.Sound(nil, "JamHit", endPoint)
	end)
end

local function throwNutella(session, root: BasePart, direction: Vector3)
	local cfg = Config.Spreads.Nutella
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local params = rayParams()
	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	flatDir = if flatDir.Magnitude > 0.01 then flatDir.Unit else root.CFrame.LookVector
	local reach = cfg.Range
	local wall = workspace:Raycast(origin, flatDir * reach, params)
	if wall then
		reach = math.max(0, (wall.Position - origin).Magnitude - cfg.PuddleRadius * 0.5)
	end
	local above = origin + flatDir * reach
	local ground = workspace:Raycast(above, Vector3.new(0, -60, 0), params)
	local landing = if ground then ground.Position else above - Vector3.new(0, 4, 0)

	local flightTime = math.max(0.3, (landing - origin).Magnitude / Config.Spreads.Jam.ProjectileSpeed)
	services.Messaging.Effect(nil, "Projectile", { Kind = "Nutella", From = origin, To = landing, Duration = flightTime })
	services.Messaging.Sound(nil, "Throw", origin)
	local token = roundToken
	task.delay(flightTime, function()
		if token ~= roundToken then
			return
		end
		addHazard({
			Kind = "Puddle",
			Position = landing,
			Radius = cfg.PuddleRadius,
			ExpiresAt = now() + cfg.PuddleDuration,
			Owner = nil,
		})
		services.Messaging.Effect(nil, "Puddle", { Position = landing, Radius = cfg.PuddleRadius, Duration = cfg.PuddleDuration })
	end)
end

------------------------------------------------------------------ request handling

local ACTION_PHASES = {
	[PHASES.Calm] = true,
	[PHASES.Heating] = true,
}

local function validDirection(value: any): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z or v.Magnitude < 0.1 or v.Magnitude > 1e4 then
		return nil
	end
	return v.Unit
end

local function handle(player: Player, action: any, arg1: any, arg2: any)
	if type(action) ~= "string" or not limiter:Allow(player) then
		return
	end
	local session = services.PlayerManager.Get(player)
	if not session or not session.InRound then
		return
	end
	local root = services.PlayerManager.GetBody(session)
	if not root then
		return
	end
	local phase = services.RoundManager.GetPhase()

	if action == "Butter" then
		if phase ~= PHASES.Heating then
			reject(player, "🧈 Save your butter for when the toaster is ON!")
		elseif session.ButterCarried <= 0 then
			reject(player, "🧈 You don't have any butter.")
		elseif not services.HeatManager.ActivateShield(session) then
			reject(player, "🧈 Shield already active.")
		end
		return
	end

	if not ACTION_PHASES[phase] then
		return
	end
	if session.IsCharcoal then
		reject(player, "🪨 Charcoal can't do that... but your touch blackens others!")
		return
	end
	if now() < session.StuckUntil then
		return
	end

	if action == "Ability" then
		local bread = BreadDefinitions.ById[services.PlayerManager.EquippedBread(session)]
		local abilityName = bread and bread.Ability
		if not abilityName or not ABILITIES[abilityName] then
			reject(player, "🍞 Bread slices have no ability. Unlock a Bagel in the shop!")
			return
		end
		if onCooldown(session, "Ability") then
			return
		end
		startCooldown(session, "Ability", AbilityDefinitions[abilityName].Cooldown)
		ABILITIES[abilityName](session, root)
	elseif action == "Spread" then
		local kind = arg1
		local direction = validDirection(arg2)
		if (kind ~= "Jam" and kind ~= "Nutella") or not direction then
			return
		end
		if onCooldown(session, kind) then
			return
		end
		startCooldown(session, kind, Config.Spreads[kind].Cooldown)
		if kind == "Jam" then
			throwJam(session, root, direction)
		else
			throwNutella(session, root, direction)
		end
	end
end

function AbilityManager.Start()
	Net.AbilityEvent.OnServerEvent:Connect(function(player, action, arg1, arg2)
		local ok, err = pcall(handle, player, action, arg1, arg2)
		if not ok then
			warn("[AbilityManager] request failed:", err)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
		slipCooldowns[player] = nil
	end)
end

function AbilityManager.ResetRound()
	roundToken += 1
	table.clear(hazards)
	table.clear(slipCooldowns)
end

return AbilityManager
