--!strict
-- Tuning for bread abilities. Spreads (Jam / Nutella) live in Config.Spreads
-- because every bread can throw them.

return {
	Roll = {
		DisplayName = "ROLL",
		Cooldown = 7,
		Duration = 2.5,
		Speed = 34, -- forward speed while rolling
		TurnRate = 2.2, -- radians per second of steering (reduced control)
		BumpRadius = 5,
		BumpForce = 55,
	},
	FlakeTrail = {
		DisplayName = "FLAKE TRAIL",
		Cooldown = 10,
		Duration = 3,
		DropInterval = 0.25,
		FlakeLifetime = 4,
		FlakeRadius = 3.5,
		SlipDuration = 1.2,
		SlipCooldown = 2, -- per victim
	},
	WaffleSlam = {
		DisplayName = "WAFFLE SLAM",
		Cooldown = 14,
		JumpVelocity = 60,
		SlamDelay = 0.65,
		Radius = 15,
		Knockback = 75,
		HeatResistDuration = 4,
		HeatResistMultiplier = 0.25,
	},
}
