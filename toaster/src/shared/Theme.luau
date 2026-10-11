-- Colours and fonts shared by the map, bread visuals and UI.

local Theme = {}

Theme.Colors = {
	Charcoal = Color3.fromRGB(28, 23, 20),
	CharcoalSoft = Color3.fromRGB(42, 36, 32),
	Panel = Color3.fromRGB(34, 28, 24),
	Cream = Color3.fromRGB(245, 235, 221),
	CreamMuted = Color3.fromRGB(201, 184, 166),
	Orange = Color3.fromRGB(255, 122, 26),
	Gold = Color3.fromRGB(255, 181, 71),
	Legend = Color3.fromRGB(255, 212, 71),
	Butter = Color3.fromRGB(246, 226, 122),
	Jam = Color3.fromRGB(194, 37, 59),
	Nutella = Color3.fromRGB(90, 47, 23),
	Electric = Color3.fromRGB(127, 212, 255),
	Danger = Color3.fromRGB(255, 77, 46),
	Crust = Color3.fromRGB(154, 90, 43),
	Crumb = Color3.fromRGB(217, 163, 95),
	Chrome = Color3.fromRGB(190, 197, 204),
	ChromeDark = Color3.fromRGB(110, 117, 124),
	CoilCold = Color3.fromRGB(70, 52, 44),
	CoilHot = Color3.fromRGB(255, 106, 26),
	CoilWarn = Color3.fromRGB(150, 70, 30),
	Skin = Color3.fromRGB(227, 169, 126),
	SkinNail = Color3.fromRGB(246, 210, 186),
	Counter = Color3.fromRGB(196, 160, 118),
	Tile = Color3.fromRGB(226, 220, 205),
	Safe = Color3.fromRGB(110, 170, 210),
	HotFloor = Color3.fromRGB(120, 58, 40),
}

Theme.ZoneColors = {
	Jackpot = Color3.fromRGB(255, 212, 71),
	Perfect = Color3.fromRGB(255, 122, 26),
	Great = Color3.fromRGB(96, 196, 110),
	Good = Color3.fromRGB(88, 150, 230),
	Safe = Color3.fromRGB(201, 184, 166),
}

Theme.HeatStateColors = {
	Normal = Color3.fromRGB(242, 221, 176),
	Warm = Color3.fromRGB(242, 181, 68),
	VeryHot = Color3.fromRGB(230, 120, 50),
	Critical = Color3.fromRGB(255, 77, 46),
	Burnt = Color3.fromRGB(90, 80, 75),
}

Theme.Fonts = {
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	Regular = Enum.Font.GothamMedium,
}

return Theme
