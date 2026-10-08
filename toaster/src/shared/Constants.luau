--!strict
-- Names shared between server and client: phases, attributes, tags and
-- collision groups. Using constants keeps typos from silently desyncing.

return {
	Phases = {
		Lobby = "LOBBY",
		RoundStart = "ROUND_START",
		Calm = "CALM_PHASE",
		Heating = "HEATING_PHASE",
		Launch = "LAUNCH_PHASE",
		Landing = "LANDING_PHASE",
		Rewards = "REWARDS",
		Results = "RESULTS",
	},

	-- Player attributes (server writes, client reads)
	Attr = {
		InRound = "InRound",
		Heat = "Heat",
		HeatState = "HeatState",
		HeatZone = "HeatZone",
		ButterCarried = "ButterCarried",
		ShieldEndsAt = "ShieldEndsAt",
		Crumbs = "Crumbs",
		RoundCrumbs = "RoundCrumbs",
		Bread = "Bread",
		IsCharcoal = "IsCharcoal",
		Level = "Level",
		XP = "XP",
		Title = "Title",
		DataLoaded = "DataLoaded",
		CooldownPrefix = "CD_", -- CD_Ability, CD_Jam, CD_Nutella (server time)
	},

	-- Character attributes (visible to every client for local VFX)
	CharAttr = {
		Rolling = "Rolling",
		Golden = "Golden",
		Stuck = "Stuck",
	},

	-- RoundState folder attributes
	RoundAttr = {
		Phase = "Phase",
		PhaseStartedAt = "PhaseStartedAt",
		PhaseEndsAt = "PhaseEndsAt",
		RoundNumber = "RoundNumber",
		ForkActive = "ForkActive",
		PlayersInRound = "PlayersInRound",
		HeatActive = "HeatActive",
	},

	Tags = {
		Coil = "ToasterCoil",
		LeverKnob = "ToasterLeverKnob",
		HandPart = "GiantHandPart",
		PopPad = "PopPad",
		Pickup = "Pickup",
	},

	CollisionGroups = {
		Players = "Players",
		Launched = "Launched",
		Toaster = "Toaster",
		ToasterCeiling = "ToasterCeiling",
		Pickups = "Pickups",
	},
}
