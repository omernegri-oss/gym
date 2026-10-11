-- Server-authoritative heat. A fixed-interval loop (not per-frame) raises
-- every in-round player's heat based on the zone they stand in, butter
-- shields, ability resistance and active hot spots. It also runs the
-- charcoal-touch proximity check and butter shield expiry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreadDefinitions = require(Shared.BreadDefinitions)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local HeatMath = require(Shared.HeatMath)

local HeatManager = {}

local ATTR = Constants.Attr
local HEAT = Config.Heat
local services
local heatActive = false
local blackenCooldowns: { [Player]: { [Player]: number } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function HeatManager.Init(registry)
	services = registry
end

function HeatManager.SetActive(active: boolean)
	heatActive = active
	services.RoundManager.SetRoundAttribute(Constants.RoundAttr.HeatActive, active)
end

function HeatManager.IsActive(): boolean
	return heatActive
end

local function replicate(session)
	local player = session.Player
	if math.abs(session.Heat - session.LastReplicatedHeat) >= HEAT.ReplicationStep or session.Heat >= HEAT.MaxHeat then
		session.LastReplicatedHeat = session.Heat
		player:SetAttribute(ATTR.Heat, math.floor(session.Heat * 10) / 10)
	end
	local bucket = math.floor(session.Heat / 5)
	if bucket ~= session.LastToastBucket then
		session.LastToastBucket = bucket
		services.PlayerManager.RefreshAppearance(session)
	end
end

local STATE_ORDER = { Normal = 0, Warm = 1, VeryHot = 2, Critical = 3, Burnt = 4 }

local STATE_MESSAGES = {
	Warm = { "♨️ You're getting warm...", "Warning" },
	VeryHot = { "🔥 VERY HOT! Find a cool spot or butter!", "Warning" },
	Critical = { "🚨 CRITICAL HEAT! MOVE!", "Danger" },
}

local function setState(session, state: string)
	if session.HeatState == state then
		return
	end
	local rising = (STATE_ORDER[state] or 0) > (STATE_ORDER[session.HeatState] or 0)
	session.HeatState = state
	session.Player:SetAttribute(ATTR.HeatState, state)
	services.PlayerManager.RefreshAppearance(session)
	local message = STATE_MESSAGES[state]
	if message and rising then
		services.Messaging.Notify(session.Player, message[1], message[2], 2)
		services.Messaging.Sound(session.Player, "HeatWarning")
	end
end

local function applyHeat(session, amount: number)
	if session.IsCharcoal or amount <= 0 then
		return
	end
	session.Heat = HeatMath.Clamp(session.Heat + amount, HEAT)
	local state = HeatMath.GetState(session.Heat, HEAT)
	if state == "Burnt" then
		services.PlayerManager.Burn(session)
		return
	end
	setState(session, state)
	replicate(session)
end

local function shieldMultiplier(session): number?
	if session.ShieldActive then
		return Config.Butter.HeatMultiplier
	end
	return nil
end

-- External heat (steam, fork zaps, charcoal touch). Shields still protect.
function HeatManager.AddHeat(session, amount: number)
	if not session.InRound or not heatActive then
		return
	end
	local mult = shieldMultiplier(session)
	applyHeat(session, amount * (mult or 1))
end

function HeatManager.ActivateShield(session): boolean
	if session.ButterCarried <= 0 or session.ShieldActive or session.IsCharcoal then
		return false
	end
	session.ButterCarried -= 1
	session.ShieldActive = true
	session.UsedButterThisRound = true
	session.ShieldEndsAt = now() + Config.Butter.Duration
	local player = session.Player
	player:SetAttribute(ATTR.ButterCarried, session.ButterCarried)
	player:SetAttribute(ATTR.ShieldEndsAt, session.ShieldEndsAt)
	services.PlayerManager.RefreshAppearance(session)
	local root = services.PlayerManager.GetBody(session)
	services.Messaging.Notify(player, "🧈 BUTTER SHIELD!", "Good", 2)
	services.Messaging.Sound(nil, "ButterShield", root and root.Position or nil)
	return true
end

local function expireShield(session)
	session.ShieldActive = false
	session.ShieldEndsAt = 0
	session.Player:SetAttribute(ATTR.ShieldEndsAt, 0)
	services.PlayerManager.RefreshAppearance(session)
	services.Messaging.Notify(session.Player, "🧈 Your butter melted!", "Warning", 1.8)
	services.Messaging.Sound(session.Player, "ButterExpire")
end

local function charcoalTouch(sessionList, positions, t: number)
	local cfg = Config.Charcoal
	for _, attacker in sessionList do
		local attackerPos = positions[attacker]
		if attacker.IsCharcoal and attackerPos then
			local cooldowns = blackenCooldowns[attacker.Player]
			if not cooldowns then
				cooldowns = {}
				blackenCooldowns[attacker.Player] = cooldowns
			end
			for _, victim in sessionList do
				local victimPos = positions[victim]
				if
					victim ~= attacker
					and not victim.IsCharcoal
					and victimPos
					and (victimPos - attackerPos).Magnitude <= cfg.TouchRadius
				then
					if t >= (cooldowns[victim.Player] or 0) then
						cooldowns[victim.Player] = t + cfg.TouchCooldown
						victim.BlackenedUntil = t + cfg.BlackenDuration
						attacker.RoundBlackens += 1
						services.PlayerManager.RefreshAppearance(victim)
						HeatManager.AddHeat(victim, cfg.BlackenHeat)
						services.Messaging.Notify(victim.Player, `🪨 {attacker.Player.DisplayName} blackened you!`, "Danger", 1.8)
						services.Messaging.Sound(nil, "Knock", victimPos)
						services.DataManager.Update(attacker.Player, function(data)
							data.Statistics.PlayersBlackened += 1
						end)
						services.AchievementManager.Evaluate(attacker.Player)
						task.delay(cfg.BlackenDuration + 0.1, function()
							if victim.BlackenedUntil <= workspace:GetServerTimeNow() then
								services.PlayerManager.RefreshAppearance(victim)
							end
						end)
					end
				end
			end
		end
	end
end

local function tick(dt: number)
	local t = now()
	local sessionList = services.PlayerManager.InRound()
	local positions = {}
	local info = services.MapBuilder.Info
	local center = info.ToasterCenter

	for _, session in sessionList do
		local root = services.PlayerManager.GetBody(session)
		if root then
			positions[session] = root.Position
		end
		if session.ShieldActive and t >= session.ShieldEndsAt then
			expireShield(session)
		end
		-- Stuck (jam) wears off here too.
		if session.StuckUntil > 0 and t >= session.StuckUntil then
			session.StuckUntil = 0
			services.PlayerManager.RefreshMovement(session)
			local character = session.Player.Character
			if character then
				character:SetAttribute(Constants.CharAttr.Stuck, false)
			end
		end
	end

	if heatActive then
		for _, session in sessionList do
			local pos = positions[session]
			if pos and not session.IsCharcoal and services.MapBuilder.IsInsideToaster(pos) then
				local zoneName, zoneMult = HeatMath.GetZone(pos.X - center.X, pos.Z - center.Z, Config.Map, Config.HeatZones)
				if zoneName ~= session.HeatZone then
					session.HeatZone = zoneName
					session.Player:SetAttribute(ATTR.HeatZone, zoneName)
				end
				local bread = BreadDefinitions.ById[services.PlayerManager.EquippedBread(session)]
				local delta = HeatMath.ComputeDelta(HEAT.BaseRate, dt, {
					zoneMultiplier = zoneMult,
					breadResistance = bread.HeatResistance,
					shieldMultiplier = shieldMultiplier(session),
					abilityResistance = if t < session.ResistUntil then session.ResistMultiplier else nil,
					hotSpotMultiplier = services.EventManager.HotSpotMultiplierAt(pos),
				})
				applyHeat(session, delta)
			end
		end
	end

	charcoalTouch(sessionList, positions, t)
end

function HeatManager.Start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(HEAT.TickInterval)
			local current = os.clock()
			local dt = math.min(current - last, HEAT.TickInterval * 4)
			last = current
			local ok, err = pcall(tick, dt)
			if not ok then
				warn("[HeatManager] tick failed:", err)
			end
		end
	end)
end

function HeatManager.ResetRound()
	table.clear(blackenCooldowns)
	HeatManager.SetActive(false)
end

return HeatManager
