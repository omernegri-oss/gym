--!strict
-- Cosmetics are purely visual: nothing here may change gameplay stats.
-- Source "Crumbs" = bought with crumbs, "GamePass"/"Product" = Robux (see Monetization),
-- "Achievement" = unlocked by an achievement.

export type Cosmetic = {
	Id: string,
	Slot: string, -- "Hat" | "Trail"
	DisplayName: string,
	Source: string,
	Price: number,
	Color: { number }, -- RGB 0-255, used by the procedural builders
}

local list: { Cosmetic } = {
	{ Id = "PartyHat", Slot = "Hat", DisplayName = "Party Hat", Source = "Crumbs", Price = 250, Color = { 255, 90, 140 } },
	{ Id = "ChefHat", Slot = "Hat", DisplayName = "Chef Hat", Source = "Crumbs", Price = 400, Color = { 245, 240, 230 } },
	{ Id = "Crown", Slot = "Hat", DisplayName = "Golden Crown", Source = "GamePass", Price = 0, Color = { 255, 212, 71 } },
	{ Id = "CrumbTrail", Slot = "Trail", DisplayName = "Crumb Trail", Source = "Crumbs", Price = 200, Color = { 217, 163, 95 } },
	{ Id = "FlameTrail", Slot = "Trail", DisplayName = "Flame Trail", Source = "Crumbs", Price = 600, Color = { 255, 122, 26 } },
	{ Id = "ButterTrail", Slot = "Trail", DisplayName = "Butter Trail", Source = "Achievement", Price = 0, Color = { 246, 226, 122 } },
	{ Id = "GoldenTrail", Slot = "Trail", DisplayName = "Golden Trail", Source = "GamePass", Price = 0, Color = { 255, 212, 71 } },
}

local byId: { [string]: Cosmetic } = {}
for _, cosmetic in list do
	byId[cosmetic.Id] = cosmetic
end

return {
	List = list,
	ById = byId,
	Slots = { "Hat", "Trail" },
}
