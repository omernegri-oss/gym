-- Unit tests for the pure gameplay modules. Run with the Luau CLI:
--   luau tests/run.luau
-- (These modules avoid Roblox APIs so they can be tested outside Studio.)

local Config = require("../src/shared/Config")
local HeatMath = require("../src/shared/HeatMath")
local LandingMath = require("../src/shared/LandingMath")
local DataSchema = require("../src/shared/DataSchema")
local Progression = require("../src/shared/Progression")
local RateLimiter = require("../src/shared/RateLimiter")
local ForkPath = require("../src/shared/ForkPath")
local BreadDefinitions = require("../src/shared/BreadDefinitions")
local AbilityDefinitions = require("../src/shared/AbilityDefinitions")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local function near(actual: number, expected: number, eps: number, label: string?)
	if math.abs(actual - expected) > eps then
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

------------------------------------------------------------------ config sanity

test("round timings are consistent", function()
	local r = Config.Round
	truthy(r.CalmWarningLead < r.CalmDuration, "warning lead must fit in calm")
	truthy(r.HandSequenceDuration < r.HeatingDuration, "hand sequence must fit in heating")
	local loop = r.RoundStartDuration + r.CalmDuration + r.HeatingDuration + r.LaunchDuration + r.LandingDuration
	truthy(loop >= 80 and loop <= 100, `core round should be ~90s, got {loop}`)
end)

test("landing zones are ordered best to worst", function()
	local zones = Config.Landing.Zones
	for i = 2, #zones do
		truthy(zones[i].Radius > zones[i - 1].Radius, "radius must increase")
		truthy(zones[i].Points < zones[i - 1].Points, "points must decrease")
	end
	eq(zones[#zones].Radius, math.huge, "last zone catches everything")
end)

test("breads: default is free and abilities exist", function()
	eq(BreadDefinitions.ById[BreadDefinitions.Default].Price, 0)
	for _, def in BreadDefinitions.Ordered do
		if def.Ability then
			truthy(AbilityDefinitions[def.Ability] ~= nil, `missing ability {def.Ability}`)
		end
	end
	eq(BreadDefinitions.Ordered[1].Id, "Bread")
	eq(BreadDefinitions.Ordered[4].Id, "Waffle")
end)

------------------------------------------------------------------ heat

test("heat states follow thresholds", function()
	local h = Config.Heat
	eq(HeatMath.GetState(0, h), "Normal")
	eq(HeatMath.GetState(49.9, h), "Normal")
	eq(HeatMath.GetState(50, h), "Warm")
	eq(HeatMath.GetState(75, h), "VeryHot")
	eq(HeatMath.GetState(90, h), "Critical")
	eq(HeatMath.GetState(99.9, h), "Critical")
	eq(HeatMath.GetState(100, h), "Burnt")
end)

test("heat zones: centre, coils, safe nooks", function()
	local name, mult = HeatMath.GetZone(0, 0, Config.Map, Config.HeatZones)
	eq(name, "Center")
	eq(mult, 1)
	name, mult = HeatMath.GetZone(10, 30, Config.Map, Config.HeatZones)
	eq(name, "Coils")
	eq(mult, 2)
	name, mult = HeatMath.GetZone(-10, -24, Config.Map, Config.HeatZones)
	eq(name, "Coils", "negative side")
	name, mult = HeatMath.GetZone(65, 0, Config.Map, Config.HeatZones)
	eq(name, "Safe")
	eq(mult, 0.5)
	name = HeatMath.GetZone(-60, 5, Config.Map, Config.HeatZones)
	eq(name, "Safe", "west nook")
end)

test("butter shield freezes heat; hot spots multiply", function()
	local base = { zoneMultiplier = 1, breadResistance = 1 }
	near(HeatMath.ComputeDelta(4, 0.5, base), 2, 1e-9)
	near(
		HeatMath.ComputeDelta(4, 0.5, { zoneMultiplier = 2, breadResistance = 1, shieldMultiplier = Config.Butter.HeatMultiplier }),
		0,
		1e-9
	)
	near(HeatMath.ComputeDelta(4, 0.5, { zoneMultiplier = 1, breadResistance = 1, hotSpotMultiplier = 3 }), 6, 1e-9)
	near(HeatMath.ComputeDelta(4, 1, { zoneMultiplier = 1, breadResistance = 1, abilityResistance = 0.25 }), 1, 1e-9)
end)

test("balance: centre survives a quiet round, coils burn", function()
	local heatingTime = Config.Round.HeatingDuration - Config.Round.HandSequenceDuration
	local function simulate(mult: number): number
		local heat, t = 0, 0
		local dt = Config.Heat.TickInterval
		while t < heatingTime do
			heat = HeatMath.Clamp(
				heat + HeatMath.ComputeDelta(Config.Heat.BaseRate, dt, { zoneMultiplier = mult, breadResistance = 1 }),
				Config.Heat
			)
			t += dt
		end
		return heat
	end
	local centre = simulate(Config.HeatZones.CenterMultiplier)
	local coils = simulate(Config.HeatZones.CoilMultiplier)
	local safe = simulate(Config.HeatZones.SafeMultiplier)
	truthy(centre < Config.Heat.BurnThreshold and centre >= Config.Heat.WarmThreshold, `centre should end warm but alive, got {centre}`)
	eq(coils, Config.Heat.MaxHeat, "camping the coils burns you")
	truthy(safe < Config.Heat.WarmThreshold, `safe nook should stay cool, got {safe}`)
end)

test("toast colour ramps from pale to dark", function()
	local r0 = HeatMath.ToastRGB(0)
	local r100 = HeatMath.ToastRGB(100)
	truthy(r0 > r100, "toast should darken")
	local r, g, b = HeatMath.ToastRGB(250)
	truthy(r >= 0 and g >= 0 and b >= 0, "clamped above 100")
end)

------------------------------------------------------------------ launch / landing

test("solved launch velocity hits the target exactly", function()
	local g = 196.2
	local vx, vy, vz = LandingMath.SolveVelocity(-40, 15, 12, 330, 3, -20, Config.Launch.FlightTime, g)
	local x, y, z = LandingMath.PositionAt(-40, 15, 12, vx, vy, vz, g, Config.Launch.FlightTime)
	near(x, 330, 1e-6, "x")
	near(y, 3, 1e-6, "y")
	near(z, -20, 1e-6, "z")
	truthy(vy > 0, "launch goes up")
end)

test("arc clears the toaster walls", function()
	local g = 196.2
	local wallTop = Config.Map.FloorY + Config.Map.WallHeight
	-- Worst case: standing at the east wall, landing at the bullseye.
	local startX = Config.Map.InteriorLength / 2 - 2
	local vx, vy, vz =
		LandingMath.SolveVelocity(startX, Config.Map.FloorY + 3, 0, Config.Map.FieldCenterX, 3, 0, Config.Launch.FlightTime, g)
	local apexT = vy / g
	local _, apexY = LandingMath.PositionAt(startX, Config.Map.FloorY + 3, 0, vx, vy, vz, g, apexT)
	truthy(apexY > wallTop + 50, `apex {apexY} should tower over the toaster`)
end)

test("POP pad always lands PERFECT or better", function()
	local perfect = Config.Landing.Zones[2]
	for i = 0, 50 do
		local ox, oz = LandingMath.TargetOffset(2, -3, Config.Launch, i / 50, (50 - i) / 50)
		local zone = LandingMath.ZoneForDistance(math.sqrt(ox * ox + oz * oz), Config.Landing.Zones)
		truthy(zone.Points >= perfect.Points, `pad landing scored {zone.Name}`)
	end
end)

test("standing far from the centre lands far from the bullseye", function()
	local ox, oz = LandingMath.TargetOffset(60, 0, Config.Launch, 0, 0)
	eq(LandingMath.ZoneForDistance(math.sqrt(ox * ox + oz * oz), Config.Landing.Zones).Id, "Safe")
	ox, oz = LandingMath.TargetOffset(12, 0, Config.Launch, 0, 0)
	eq(LandingMath.ZoneForDistance(math.sqrt(ox * ox + oz * oz), Config.Landing.Zones).Id, "Great")
	truthy(not LandingMath.IsOnPad(12, 0, Config.Launch), "12 studs is off the pad")
	truthy(LandingMath.IsOnPad(3, 3, Config.Launch), "near centre is on the pad")
end)

test("zone boundaries", function()
	local zones = Config.Landing.Zones
	eq(LandingMath.ZoneForDistance(0, zones).Id, "Jackpot")
	eq(LandingMath.ZoneForDistance(5, zones).Id, "Jackpot")
	eq(LandingMath.ZoneForDistance(5.01, zones).Id, "Perfect")
	eq(LandingMath.ZoneForDistance(48, zones).Id, "Good")
	eq(LandingMath.ZoneForDistance(400, zones).Id, "Safe")
end)

------------------------------------------------------------------ data

test("reconcile: nil gives defaults and is unrecognised", function()
	local data, recognised = DataSchema.Reconcile(nil)
	eq(recognised, false)
	eq(data.Crumbs, 0)
	eq(data.EquippedBread, "Bread")
	eq(data.UnlockedBreads.Bread, true)
	eq(data.Statistics.RoundsPlayed, 0)
end)

test("reconcile: corrupt fields are sanitised, valid ones kept", function()
	local data, recognised = DataSchema.Reconcile({
		Crumbs = -50,
		XP = 0 / 0,
		BreadLevel = "seven",
		UnlockedBreads = { Bagel = true, Waffle = "yes", [5] = true },
		EquippedBread = "Waffle", -- not actually unlocked
		UnlockedCosmetics = { PartyHat = true },
		EquippedCosmetics = { Hat = "PartyHat", Trail = "FlameTrail" },
		Statistics = { RoundsPlayed = 12, TotalCrumbs = math.huge },
		ProcessedReceipts = { "a", 5, "b" },
	})
	eq(recognised, true)
	eq(data.Crumbs, 0, "negative clamped")
	eq(data.XP, 0, "NaN replaced")
	eq(data.BreadLevel, 1, "wrong type replaced")
	eq(data.UnlockedBreads.Bagel, true)
	eq(data.UnlockedBreads.Waffle, nil, "non-boolean dropped")
	eq(data.UnlockedBreads.Bread, true, "default bread always unlocked")
	eq(data.EquippedBread, "Bread", "can't equip a locked bread")
	eq(data.EquippedCosmetics.Hat, "PartyHat")
	eq(data.EquippedCosmetics.Trail, nil, "can't equip a locked cosmetic")
	eq(data.Statistics.RoundsPlayed, 12)
	eq(data.Statistics.TotalCrumbs, 0, "infinite replaced")
	eq(#data.ProcessedReceipts, 2)
end)

test("receipts are remembered and capped", function()
	local data = DataSchema.Default()
	for i = 1, DataSchema.MaxReceipts + 10 do
		DataSchema.RememberReceipt(data, "r" .. i)
	end
	eq(#data.ProcessedReceipts, DataSchema.MaxReceipts)
	truthy(DataSchema.HasReceipt(data, "r" .. (DataSchema.MaxReceipts + 10)), "newest kept")
	truthy(not DataSchema.HasReceipt(data, "r1"), "oldest evicted")
end)

------------------------------------------------------------------ progression

test("levels from XP", function()
	local t = Config.Progression.LevelXP
	eq(Progression.LevelForXP(0, t), 1)
	eq(Progression.LevelForXP(59, t), 1)
	eq(Progression.LevelForXP(60, t), 2)
	eq(Progression.LevelForXP(10 ^ 9, t), #t)
	eq(Progression.XPToNextLevel(0, t), 60)
	eq(Progression.XPToNextLevel(10 ^ 9, t), nil)
end)

test("round rewards: survivors earn the golden bonus", function()
	local survived =
		Progression.RoundReward({ Participated = true, Survived = true, LandingPoints = 100, CollectedCrumbs = 7 }, Config.Rewards)
	eq(survived.Points, 100 + Config.Rewards.SurvivalBonus)
	eq(survived.Crumbs, Config.Rewards.SurvivalCrumbs + math.floor(survived.Points * Config.Rewards.PointsToCrumbs))
	local burnt =
		Progression.RoundReward({ Participated = true, Survived = false, LandingPoints = 100, CollectedCrumbs = 7 }, Config.Rewards)
	eq(burnt.Points, 100)
	truthy(burnt.XP < survived.XP, "burnt earns less XP")
	local none =
		Progression.RoundReward({ Participated = false, Survived = true, LandingPoints = 500, CollectedCrumbs = 0 }, Config.Rewards)
	eq(none.Points, 0)
end)

test("survival streaks boost crumbs, capped", function()
	local base = { Participated = true, Survived = true, LandingPoints = 100, CollectedCrumbs = 0 }
	local first = Progression.RoundReward(base, Config.Rewards)
	local third = Progression.RoundReward(
		{ Participated = true, Survived = true, LandingPoints = 100, CollectedCrumbs = 0, Streak = 3 },
		Config.Rewards
	)
	eq(first.StreakMultiplier, 1)
	near(third.StreakMultiplier, 1 + 2 * Config.Rewards.StreakBonusPerRound, 1e-9)
	truthy(third.Crumbs > first.Crumbs, "streak pays more")
	local capped = Progression.StreakMultiplier(99, Config.Rewards)
	near(capped, 1 + Config.Rewards.StreakMaxSteps * Config.Rewards.StreakBonusPerRound, 1e-9)
	local burnt = Progression.RoundReward(
		{ Participated = true, Survived = false, LandingPoints = 100, CollectedCrumbs = 0, Streak = 5 },
		Config.Rewards
	)
	eq(burnt.StreakMultiplier, 1, "no streak bonus when burnt")
	local awarded = Progression.RoundReward(
		{ Participated = true, Survived = true, LandingPoints = 100, CollectedCrumbs = 0, Awards = 2 },
		Config.Rewards
	)
	eq(awarded.Crumbs, first.Crumbs + 2 * Config.Rewards.AwardCrumbs, "awards add flat crumbs")
end)

test("buy checks: owned, level, price", function()
	eq(Progression.CanBuy(300, 2, 1000, 5, true).Ok, false)
	eq(Progression.CanBuy(300, 2, 1000, 1, false).Ok, false)
	eq(Progression.CanBuy(300, 2, 100, 5, false).Ok, false)
	eq(Progression.CanBuy(300, 2, 300, 2, false).Ok, true)
end)

------------------------------------------------------------------ misc

test("rate limiter blocks spam and refills", function()
	local clock = 0
	local limiter = RateLimiter.new(3, 2, function()
		return clock
	end)
	local key = {}
	eq(limiter:Allow(key), true)
	eq(limiter:Allow(key), true)
	eq(limiter:Allow(key), true)
	eq(limiter:Allow(key), false, "4th request in the same instant")
	clock = 0.5
	eq(limiter:Allow(key), true, "refilled one token")
	eq(limiter:Allow(key), false)
	eq(limiter:Allow({}), true, "other keys unaffected")
end)

test("fork path stays inside the toaster", function()
	for i = 0, 200 do
		local x, z = ForkPath.Offset(i * 0.1, Config.Fork)
		truthy(math.abs(x) <= Config.Map.InteriorLength / 2 - Config.Fork.ZapRadius * 0.5, `x out of bounds: {x}`)
		truthy(math.abs(z) <= Config.Map.InteriorWidth / 2, `z out of bounds: {z}`)
	end
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed")
end
