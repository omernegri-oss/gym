--!strict
-- Robux products. IDs of 0 mean "not configured yet": the shop hides them and
-- the server ignores them. Everything sold here is cosmetic or convenience only.

return {
	GamePasses = {
		VIP = {
			Id = 0, -- set to your VIP game pass id
			DisplayName = "VIP",
			Grants = { "Crown", "GoldenTrail" },
			Title = "VIP TOAST",
		},
	},
	Products = {
		-- Developer products. Grants are cosmetics only (never crumbs or breads),
		-- so nothing competitive can be bought.
		FlameTrailPack = {
			Id = 0,
			DisplayName = "Flame Trail",
			Grants = { "FlameTrail" },
		},
	},
}
