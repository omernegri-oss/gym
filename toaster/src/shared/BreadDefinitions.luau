--!strict
-- Every playable bread form. Stats here are the only gameplay difference
-- between breads; cosmetics never touch them.

export type BreadDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number, -- crumbs
	RequiredLevel: number,
	WalkSpeed: number,
	JumpHeight: number,
	HeatResistance: number, -- multiplier on heat gain (1 = normal)
	Ability: string?,
	Rarity: string,
	Description: string,
}

local BreadDefinitions: { [string]: BreadDefinition } = {
	Bread = {
		Id = "Bread",
		DisplayName = "Bread Slice",
		Order = 1,
		Price = 0,
		RequiredLevel = 1,
		WalkSpeed = 18,
		JumpHeight = 7.5,
		HeatResistance = 1,
		Ability = nil,
		Rarity = "Common",
		Description = "Easy and reliable. No ability, no drama.",
	},
	Bagel = {
		Id = "Bagel",
		DisplayName = "Bagel",
		Order = 2,
		Price = 300,
		RequiredLevel = 2,
		WalkSpeed = 18,
		JumpHeight = 7,
		HeatResistance = 1,
		Ability = "Roll",
		Rarity = "Rare",
		Description = "ROLL: zoom across the toaster and bump other bread.",
	},
	Croissant = {
		Id = "Croissant",
		DisplayName = "Croissant",
		Order = 3,
		Price = 900,
		RequiredLevel = 4,
		WalkSpeed = 18,
		JumpHeight = 7.5,
		HeatResistance = 1,
		Ability = "FlakeTrail",
		Rarity = "Epic",
		Description = "FLAKE TRAIL: leave slippery flakes behind you.",
	},
	Waffle = {
		Id = "Waffle",
		DisplayName = "LEGENDARY WAFFLE",
		Order = 4,
		Price = 2500,
		RequiredLevel = 7,
		WalkSpeed = 17,
		JumpHeight = 7.5,
		HeatResistance = 0.95,
		Ability = "WaffleSlam",
		Rarity = "Legendary",
		Description = "WAFFLE SLAM: jump, slam, shockwave. Brief heat resistance.",
	},
}

local ordered: { BreadDefinition } = {}
for _, def in BreadDefinitions do
	table.insert(ordered, def)
end
table.sort(ordered, function(a, b)
	return a.Order < b.Order
end)

return {
	ById = BreadDefinitions,
	Ordered = ordered,
	Default = "Bread",
}
