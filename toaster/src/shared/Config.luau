--!strict
-- Central tuning for TOASTER. Every timer, rate and reward lives here so the
-- rest of the codebase never carries magic numbers. Kept free of Roblox types
-- so it can be required by plain-Luau unit tests.

local Config = {}

Config.Round = {
	MinimumPlayers = 1,
	IntermissionDuration = 10, -- LOBBY
	RoundStartDuration = 3, -- teleport + "ROUND STARTED!"
	CalmDuration = 45,
	CalmWarningLead = 10, -- seconds before heating when the toaster starts "clicking"
	HeatingDuration = 25,
	HandSequenceDuration = 3.5, -- heat starts rising once the lever is down
	LaunchDuration = 4, -- 3..2..1..POP countdown
	LandingDuration = 7,
	RewardsDuration = 2,
	ResultsDuration = 8,
}

Config.Heat = {
	MaxHeat = 100,
	BaseRate = 3.2, -- heat per second at 1.0x
	TickInterval = 0.25,
	WarmThreshold = 50,
	VeryHotThreshold = 75,
	CriticalThreshold = 90,
	BurnThreshold = 100,
	ReplicationStep = 0.5, -- only replicate heat when it moved at least this much
}

Config.HeatZones = {
	CenterMultiplier = 1.0,
	CoilMultiplier = 2.0,
	SafeMultiplier = 0.5,
	HotSpotMultiplier = 3.0,
	CoilBand = 12, -- studs from a coil wall that count as "near coils"
	SafeNookDepth = 16, -- studs from an end wall
	SafeNookHalfWidth = 12,
}

Config.Butter = {
	Duration = 10,
	HeatMultiplier = 0, -- 0 = heat completely frozen while shielded
	MaxCarried = 1,
	SpawnCount = 3,
	RespawnTime = 20,
}

Config.Crumbs = {
	SpawnCount = 36,
	Value = 1,
	GoldenChance = 0.06,
	GoldenValue = 10,
	RespawnTime = 8,
	PickupRadius = 8, -- server-side proximity validation
}

Config.Launch = {
	FlightTime = 2.8,
	OffsetScale = 2.2, -- distance from toaster centre -> distance from bullseye
	RandomSpread = 6,
	PadRadius = 8,
	PadSpread = 9, -- on the pad you always land PERFECT or better; JACKPOT is luck
	SpinMax = 9,
	GroundedHeight = 4.5, -- root height above the field that counts as "landed"
	MinAirTime = 0.6,
	LandingTimeout = 6, -- physics fallback
}

Config.Landing = {
	-- Ordered from best to worst. Radius is measured from the bullseye on the XZ plane.
	Zones = {
		{ Id = "Jackpot", Name = "JACKPOT", Radius = 5, Points = 500 },
		{ Id = "Perfect", Name = "PERFECT LANDING", Radius = 14, Points = 100 },
		{ Id = "Great", Name = "GREAT LANDING", Radius = 28, Points = 50 },
		{ Id = "Good", Name = "GOOD LANDING", Radius = 48, Points = 25 },
		{ Id = "Safe", Name = "SAFE LANDING", Radius = math.huge, Points = 10 },
	},
}

Config.Rewards = {
	SurvivalBonus = 250, -- points
	SurvivalCrumbs = 25,
	PointsToCrumbs = 0.2, -- landing + survival points converted into crumbs
	ParticipationXP = 10,
	SurvivalXP = 15,
	LandingXPDivisor = 10,
	GoldenDuration = 12,
}

Config.Charcoal = {
	WalkSpeed = 11,
	ExtraRounds = 1, -- burnt players stay charcoal for the next round too
	TouchRadius = 5,
	TouchCooldown = 3, -- per victim
	BlackenDuration = 5,
	BlackenHeat = 6,
}

Config.Movement = {
	WalkSpeed = 18,
	JumpHeight = 7.5,
	RespawnDelay = 2,
}

Config.Spreads = {
	Jam = {
		Cooldown = 8,
		Range = 70,
		HitRadius = 3.5,
		ProjectileSpeed = 110,
		StuckDuration = 2.5,
	},
	Nutella = {
		Cooldown = 10,
		Range = 45,
		PuddleRadius = 9,
		PuddleDuration = 8,
		SlideDuration = 1.4,
		SlideCooldown = 1.6, -- per victim
	},
}

Config.Events = {
	FirstEventDelay = 5, -- after the lever is pulled
	IntervalMin = 5,
	IntervalMax = 8,
	WarningTime = 1.6,
	Weights = {
		FallingFood = 3,
		HotSpot = 3,
		SteamBurst = 2,
		ToasterShake = 1,
		FallingButter = 1,
	},
	FallingFood = { CountMin = 4, CountMax = 7, FallTime = 1.4, JunkChance = 0.35, JunkKnockback = 45, ImpactRadius = 5 },
	HotSpot = { Radius = 10, Duration = 6 },
	SteamBurst = { Radius = 8, Heat = 12, Lift = 70 },
	ToasterShake = { Duration = 1.5, Shove = 22 },
}

Config.Fork = {
	ForceEveryRound = false, -- handy for testing the boss in Studio
	MinRoundsBetween = 2,
	Chance = 0.4,
	GuaranteeAfter = 4, -- rounds without a fork
	StartDelay = 6, -- seconds into heating
	WarningDuration = 2.5,
	Duration = 14,
	ZapInterval = 2.6,
	ZapWarning = 1.2,
	ZapRadius = 11,
	ZapHeat = 18,
	ZapKnockback = 60,
	PathRadiusX = 45,
	PathRadiusZ = 18,
	LapTime = 9,
}

Config.Map = {
	-- Toaster interior, centred on the world origin.
	InteriorLength = 140, -- X
	InteriorWidth = 70, -- Z
	WallHeight = 70,
	WallThickness = 12,
	FloorY = 12, -- top surface of the toaster floor
	LobbyCenterX = -240,
	LobbyRadius = 60,
	FieldCenterX = 330,
	FieldRadius = 120,
	CrumbWorldY = -220,
	SpawnSpacing = 8,
}

Config.Data = {
	StoreName = "ToasterPlayerData_v1",
	AutosaveInterval = 120,
	MaxRetries = 4,
	RetryDelay = 2,
}

Config.RateLimits = {
	Ability = { Capacity = 6, RefillPerSecond = 3 },
	Interaction = { Capacity = 8, RefillPerSecond = 2 },
}

Config.Progression = {
	-- XP needed to reach level N is LevelXP[N].
	LevelXP = { 0, 60, 150, 280, 450, 680, 960, 1300, 1700, 2200, 2800, 3500 },
}

Config.CrumbWorld = {
	OpenDuringCalmOnly = true,
	VintageCrumbReward = 150,
}

return Config
