-- Sound hooks. Every gameplay moment plays a key from this table, so swapping
-- in real audio only means changing an Id here. The defaults are sounds that
-- ship inside the Roblox client (rbxasset://) so the game is audible out of
-- the box; replace them with uploaded audio for the final mix.

export type SoundSpec = { Id: string, Volume: number, Speed: number? }

local Sounds: { [string]: SoundSpec } = {
	RoundStart = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 0.8 },
	CrumbPickup = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Speed = 1.8 },
	GoldenCrumb = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Speed = 2.4 },
	ButterPickup = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.6, Speed = 1.4 },
	ButterShield = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.7, Speed = 1.2 },
	ButterExpire = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.5, Speed = 0.7 },
	HeatWarning = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 1 },
	ToasterClick = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.8, Speed = 0.6 },
	Lever = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 0.5 },
	HandAppear = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.8, Speed = 0.6 },
	CoilsOn = { Id = "rbxasset://sounds/action_falling.mp3", Volume = 0.4, Speed = 0.5 },
	Vibration = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.5, Speed = 0.4 },
	Countdown = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 1 },
	Launch = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.9, Speed = 1 },
	Landing = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.9, Speed = 0.9 },
	Score = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1.3 },
	Golden = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Speed = 2 },
	Burn = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.8, Speed = 0.8 },
	JamHit = { Id = "rbxasset://sounds/splat.wav", Volume = 0.8, Speed = 1 },
	Throw = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Speed = 1.4 },
	NutellaSlip = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7, Speed = 0.8 },
	Slip = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.5, Speed = 1.4 },
	Knock = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Speed = 1 },
	ForkWarning = { Id = "rbxasset://sounds/clickfast.wav", Volume = 1, Speed = 0.4 },
	ForkZap = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 1, Speed = 0.35 },
	Steam = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.6, Speed = 0.7 },
	Impact = { Id = "rbxasset://sounds/collide.wav", Volume = 0.6, Speed = 0.7 },
	Shake = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.8, Speed = 0.3 },
	SecretArea = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 0.5 },
	NpcTalk = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4, Speed = 1.6 },
	Ability = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7, Speed = 1 },
	Slam = { Id = "rbxasset://sounds/collide.wav", Volume = 1, Speed = 0.5 },
	Purchase = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1.5 },
	Error = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5, Speed = 0.8 },
}

return Sounds
