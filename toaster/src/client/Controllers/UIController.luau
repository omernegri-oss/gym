-- All in-game UI, built in code: timer, heat meter, butter shield, crumbs,
-- notifications, countdown, results, shop, Old Crumb dialogue, critical-heat
-- vignette and the action buttons (touch, mouse and gamepad friendly).
-- Server state is read from replicated attributes; one-shot messages arrive
-- through UIEvent / RoundEvent.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreadDefinitions = require(Shared.BreadDefinitions)
local AbilityDefinitions = require(Shared.AbilityDefinitions)
local Constants = require(Shared.Constants)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)
local UIUtil = require(script.Parent.UIUtil)

local UIController = {}

local create, corner, stroke, text, tween = UIUtil.create, UIUtil.corner, UIUtil.stroke, UIUtil.text, UIUtil.tween
local C = Theme.Colors
local F = Theme.Fonts
local ATTR = Constants.Attr
local RA = Constants.RoundAttr
local PHASES = Constants.Phases

local player = Players.LocalPlayer
local registry
local gui: ScreenGui
local refs: { [string]: any } = {}
local profile: any = nil
local activeNotifications: { Frame } = {}
local notificationCount = 0
local shopTab = "Breads"

local PHASE_NAMES = {
	[PHASES.Lobby] = "LOBBY",
	[PHASES.RoundStart] = "GET READY",
	[PHASES.Calm] = "CALM",
	[PHASES.Heating] = "TOASTER ON!",
	[PHASES.Launch] = "LAUNCH",
	[PHASES.Landing] = "LANDING",
	[PHASES.Rewards] = "REWARDS",
	[PHASES.Results] = "RESULTS",
}

local STYLE_COLORS = {
	Info = C.Cream,
	Good = Color3.fromRGB(150, 230, 140),
	Warning = C.Gold,
	Danger = C.Danger,
	Legend = C.Legend,
	Electric = C.Electric,
}

local ZONE_LABELS = {
	Coils = { "HOT ZONE ×2", C.Danger },
	Safe = { "COOL SPOT ×0.5", C.Safe },
	Center = { "CENTER ×1", C.CreamMuted },
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function panel(props: { [string]: any }): Frame
	local frame = create("Frame", {
		BackgroundColor3 = C.Charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	})
	for key, value in props do
		(frame :: any)[key] = value
	end
	corner(14).Parent = frame
	return frame
end

------------------------------------------------------------------ build

local function buildTimer()
	local frame = panel({
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(250, 66),
		Parent = gui,
	})
	stroke(C.Orange, 2).Parent = frame
	refs.PhaseLabel = text({
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 6),
		Font = F.Body,
		TextColor3 = C.Gold,
		Text = "LOBBY",
		Parent = frame,
	})
	refs.TimeLabel = text({
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 24),
		Font = F.Display,
		Text = "--",
		Parent = frame,
	})
	refs.StatusLabel = text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(460, 24),
		Font = F.Body,
		TextColor3 = C.Cream,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = gui,
	})
end

local function buildCrumbs()
	local frame = panel({
		Name = "Crumbs",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 64),
		Size = UDim2.fromOffset(190, 48),
		Parent = gui,
	})
	refs.CrumbLabel = text({
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 6),
		Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "🍞 0",
		Parent = frame,
	})
	refs.LevelLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 116),
		Size = UDim2.fromOffset(220, 20),
		Font = F.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.CreamMuted,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = gui,
	})
end

local function buildHeat()
	local frame = panel({
		Name = "Heat",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(420, 78),
		Visible = false,
		Parent = gui,
	})
	refs.HeatPanel = frame
	text({
		Size = UDim2.fromOffset(160, 24),
		Position = UDim2.fromOffset(14, 8),
		Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "🔥 HEAT",
		Parent = frame,
	})
	refs.HeatState = text({
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(220, 24),
		Position = UDim2.new(1, -14, 0, 8),
		Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "FRESH 0%",
		Parent = frame,
	})
	local track = create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 24),
		BackgroundColor3 = C.CharcoalSoft,
		BorderSizePixel = 0,
		Parent = frame,
	}, { corner(12) })
	refs.HeatFill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.HeatStateColors.Normal,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(12) })
	-- Threshold ticks
	for _, mark in { 50, 75, 90 } do
		create("Frame", {
			Position = UDim2.new(mark / 100, -1, 0, 0),
			Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = C.Charcoal,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = track,
		})
	end
	refs.ZoneChip = text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(170, 22),
		Font = F.Body,
		TextColor3 = C.CreamMuted,
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = frame,
	})

	local butter = panel({
		Name = "Butter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -124),
		Size = UDim2.fromOffset(300, 36),
		Visible = false,
		Parent = gui,
	})
	refs.ButterPanel = butter
	stroke(C.Butter, 2).Parent = butter
	refs.ButterFill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Butter,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Parent = butter,
	}, { corner(14) })
	refs.ButterLabel = text({
		Size = UDim2.new(1, -20, 1, -10),
		Position = UDim2.fromOffset(10, 5),
		Font = F.Display,
		Text = "",
		ZIndex = 2,
		Parent = butter,
	})
end

local function buildActionButtons()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local holder = create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -14, 1, -180) else UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(164, 164),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(76, 76),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	refs.Actions = holder
	refs.ActionButtons = {}

	local specs = {
		{ Key = "Ability", Icon = "✨", Label = "ABILITY", Hint = "Q", Color = C.Orange, Order = 1 },
		{ Key = "Butter", Icon = "🧈", Label = "BUTTER", Hint = "F", Color = C.Butter, Order = 2 },
		{ Key = "Jam", Icon = "🍓", Label = "JAM", Hint = "E", Color = C.Jam, Order = 3 },
		{ Key = "Nutella", Icon = "🍫", Label = "NUTELLA", Hint = "R", Color = Color3.fromRGB(150, 90, 50), Order = 4 },
	}
	for _, spec in specs do
		local button = create("TextButton", {
			Name = spec.Key,
			LayoutOrder = spec.Order,
			BackgroundColor3 = C.Charcoal,
			BackgroundTransparency = 0.1,
			AutoButtonColor = true,
			Text = "",
			Parent = holder,
		}, { corner(18), stroke(spec.Color, 3) })
		text({
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 8),
			Font = F.Display,
			Text = spec.Icon,
			Parent = button,
		})
		local label = text({
			Name = "Label",
			Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.fromOffset(4, 44),
			Font = F.Body,
			Text = spec.Label,
			Parent = button,
		})
		text({
			Name = "Hint",
			Size = UDim2.new(1, -8, 0, 12),
			Position = UDim2.fromOffset(4, 59),
			Font = F.Regular,
			TextColor3 = C.CreamMuted,
			Text = if touch then "" else spec.Hint,
			Parent = button,
		})
		local overlay = create("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = button,
		}, { corner(18) })
		local cdText = text({
			Name = "CooldownText",
			Size = UDim2.fromScale(1, 0.5),
			Position = UDim2.fromScale(0, 0.25),
			Font = F.Display,
			Text = "",
			ZIndex = 5,
			Parent = button,
		})
		button.Activated:Connect(function()
			registry.InputController.Request(spec.Key)
		end)
		refs.ActionButtons[spec.Key] = { Button = button, Overlay = overlay, CooldownText = cdText, Label = label }
	end
end

local function buildNotifications()
	refs.Notifications = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(560, 260),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
end

local function buildCountdown()
	refs.Countdown = text({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(420, 180),
		Font = F.Display,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = C.Charcoal,
		Visible = false,
		Parent = gui,
	})
end

local function buildVignette()
	local vignette = create("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	local edges = {
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 },
	}
	for _, edge in edges do
		create("Frame", {
			Size = edge[1],
			Position = edge[2],
			BackgroundColor3 = C.Danger,
			BorderSizePixel = 0,
			Parent = vignette,
		}, {
			create("UIGradient", {
				Rotation = edge[3],
				Transparency = NumberSequence.new(0.35, 1),
			}),
		})
	end
	refs.Vignette = vignette
end

local function buildDialogue()
	local frame = panel({
		Name = "Dialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -190),
		Size = UDim2.fromOffset(560, 104),
		Visible = false,
		Parent = gui,
	})
	stroke(C.Gold, 2).Parent = frame
	refs.Dialogue = frame
	refs.DialogueSpeaker = text({
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.fromOffset(16, 8),
		Font = F.Display,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	refs.DialogueText = text({
		Size = UDim2.new(1, -32, 0, 60),
		Position = UDim2.fromOffset(16, 34),
		Font = F.Body,
		TextScaled = false,
		TextSize = 20,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = frame,
	})
	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		Font = F.Display,
		TextSize = 22,
		TextColor3 = C.CreamMuted,
		Text = "✕",
		Parent = frame,
	})
	close.Activated:Connect(function()
		frame.Visible = false
	end)
end

local function buildResults()
	local frame = panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 420),
		Visible = false,
		Parent = gui,
	})
	stroke(C.Gold, 3).Parent = frame
	refs.Results = frame
	refs.ResultsTitle = text({
		Size = UDim2.new(1, -40, 0, 44),
		Position = UDim2.fromOffset(20, 14),
		Font = F.Display,
		TextColor3 = C.Gold,
		Text = "RESULTS",
		Parent = frame,
	})
	refs.ResultsList = create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -40, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
end

local function buildShop()
	local open = create("TextButton", {
		Name = "ShopButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(70, 70),
		BackgroundColor3 = C.Charcoal,
		BackgroundTransparency = 0.1,
		Text = "",
		Parent = gui,
	}, { corner(18), stroke(C.Gold, 2) })
	text({ Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 8), Font = F.Display, Text = "🛒", Parent = open })
	text({ Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 46), Font = F.Body, Text = "SHOP", Parent = open })

	local frame = panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(660, 460),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	stroke(C.Gold, 3).Parent = frame
	refs.Shop = frame
	text({
		Size = UDim2.fromOffset(240, 40),
		Position = UDim2.fromOffset(20, 12),
		Font = F.Display,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "BREAD SHOP",
		Parent = frame,
	})
	refs.ShopCrumbs = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 16),
		Size = UDim2.fromOffset(220, 30),
		Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = frame,
	})
	local close = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = C.CharcoalSoft,
		Font = F.Display,
		TextSize = 22,
		TextColor3 = C.Cream,
		Text = "✕",
		Parent = frame,
	}, { corner(12) })

	local tabs = create("Frame", {
		Position = UDim2.fromOffset(20, 62),
		Size = UDim2.new(1, -40, 0, 40),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		create(
			"UIListLayout",
			{ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})
	refs.ShopTabs = {}
	for order, name in { "Breads", "Cosmetics", "Titles" } do
		local tab = create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(130, 40),
			BackgroundColor3 = C.CharcoalSoft,
			Font = F.Display,
			TextSize = 18,
			TextColor3 = C.Cream,
			Text = string.upper(name),
			Parent = tabs,
		}, { corner(10) })
		tab.Activated:Connect(function()
			shopTab = name
			UIController.RenderShop()
		end)
		refs.ShopTabs[name] = tab
	end
	refs.ShopList = create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 112),
		Size = UDim2.new(1, -40, 1, -128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
	})

	local function toggle(visible: boolean)
		frame.Visible = visible
		if visible then
			Net.InteractionEvent:FireServer("RequestProfile")
			UIController.RenderShop()
		end
	end
	open.Activated:Connect(function()
		toggle(not frame.Visible)
	end)
	close.Activated:Connect(function()
		toggle(false)
	end)
	refs.ToggleShop = toggle
end

------------------------------------------------------------------ shop rendering

local function shopRow(
	order: number,
	title: string,
	subtitle: string,
	buttonText: string,
	buttonColor: Color3,
	enabled: boolean,
	onClick: (() -> ())?
)
	local row = create("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 72),
		BackgroundColor3 = C.CharcoalSoft,
		BorderSizePixel = 0,
		Parent = refs.ShopList,
	}, { corner(12) })
	text({
		Size = UDim2.new(1, -200, 0, 28),
		Position = UDim2.fromOffset(14, 8),
		Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		Parent = row,
	})
	text({
		Size = UDim2.new(1, -200, 0, 28),
		Position = UDim2.fromOffset(14, 38),
		Font = F.Regular,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.CreamMuted,
		Text = subtitle,
		Parent = row,
	})
	local button = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(170, 48),
		BackgroundColor3 = buttonColor,
		BackgroundTransparency = if enabled then 0 else 0.6,
		AutoButtonColor = enabled,
		Font = F.Display,
		TextSize = 18,
		TextColor3 = C.Charcoal,
		Text = buttonText,
		Parent = row,
	}, { corner(10) })
	if enabled and onClick then
		button.Activated:Connect(onClick)
	end
end

function UIController.RenderShop()
	if not refs.Shop or not refs.Shop.Visible then
		return
	end
	for name, tab in refs.ShopTabs do
		tab.BackgroundColor3 = if name == shopTab then C.Orange else C.CharcoalSoft
	end
	for _, child in refs.ShopList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not profile then
		shopRow(1, "Loading...", "", "...", C.CreamMuted, false)
		return
	end
	refs.ShopCrumbs.Text = "🍞 " .. UIUtil.formatNumber(profile.Crumbs)

	if shopTab == "Breads" then
		for order, def in BreadDefinitions.Ordered do
			local owned = profile.UnlockedBreads[def.Id] == true
			local equipped = profile.EquippedBread == def.Id
			local subtitle = `{def.Rarity} • {def.Description}`
			if equipped then
				shopRow(order, def.DisplayName, subtitle, "EQUIPPED", C.Gold, false)
			elseif owned then
				shopRow(order, def.DisplayName, subtitle, "EQUIP", C.Butter, true, function()
					Net.InteractionEvent:FireServer("EquipBread", def.Id)
				end)
			elseif profile.Level < def.RequiredLevel then
				shopRow(order, def.DisplayName, subtitle, `LEVEL {def.RequiredLevel}`, C.CreamMuted, false)
			else
				local affordable = profile.Crumbs >= def.Price
				shopRow(order, def.DisplayName, subtitle, `BUY {UIUtil.formatNumber(def.Price)} 🍞`, C.Orange, affordable, function()
					Net.InteractionEvent:FireServer("BuyBread", def.Id)
				end)
			end
		end
	elseif shopTab == "Cosmetics" then
		for order, cosmetic in CosmeticDefinitions.List do
			local owned = profile.UnlockedCosmetics[cosmetic.Id] == true
			local equipped = profile.EquippedCosmetics[cosmetic.Slot] == cosmetic.Id
			local subtitle = `{cosmetic.Slot} • cosmetic only`
			if equipped then
				shopRow(order, cosmetic.DisplayName, subtitle, "UNEQUIP", C.Gold, true, function()
					Net.InteractionEvent:FireServer("EquipCosmetic", cosmetic.Slot, "")
				end)
			elseif owned then
				shopRow(order, cosmetic.DisplayName, subtitle, "EQUIP", C.Butter, true, function()
					Net.InteractionEvent:FireServer("EquipCosmetic", cosmetic.Slot, cosmetic.Id)
				end)
			elseif cosmetic.Source == "Crumbs" then
				shopRow(
					order,
					cosmetic.DisplayName,
					subtitle,
					`BUY {cosmetic.Price} 🍞`,
					C.Orange,
					profile.Crumbs >= cosmetic.Price,
					function()
						Net.InteractionEvent:FireServer("BuyCosmetic", cosmetic.Id)
					end
				)
			elseif cosmetic.Source == "GamePass" then
				shopRow(order, cosmetic.DisplayName, subtitle .. " • VIP", "👑 VIP", C.Legend, profile.VipAvailable, function()
					Net.InteractionEvent:FireServer("BuyCosmetic", cosmetic.Id)
				end)
			else
				shopRow(order, cosmetic.DisplayName, subtitle, "🏆 ACHIEVEMENT", C.CreamMuted, false)
			end
		end
	else
		shopRow(
			0,
			"No title",
			"Hide your title",
			if profile.EquippedTitle == "" then "EQUIPPED" else "EQUIP",
			C.Butter,
			profile.EquippedTitle ~= "",
			function()
				Net.InteractionEvent:FireServer("EquipTitle", "")
			end
		)
		for order, title in profile.Titles do
			local equipped = profile.EquippedTitle == title
			shopRow(
				order,
				title,
				"Shown above your bread",
				if equipped then "EQUIPPED" else "EQUIP",
				if equipped then C.Gold else C.Butter,
				not equipped,
				function()
					Net.InteractionEvent:FireServer("EquipTitle", title)
				end
			)
		end
		if #profile.Titles == 0 then
			shopRow(1, "Earn titles", "Play rounds, survive and explore to unlock achievements.", "LOCKED", C.CreamMuted, false)
		end
	end
end

------------------------------------------------------------------ dynamic behaviour

function UIController.Notify(message: string, style: string?, duration: number?)
	local color = STYLE_COLORS[style or "Info"] or C.Cream
	notificationCount += 1
	local frame = panel({
		Size = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = notificationCount,
		Parent = refs.Notifications,
	})
	local outline = stroke(color, 2, 1)
	outline.Parent = frame
	create("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }).Parent = frame
	local label = text({
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = F.Display,
		TextScaled = false,
		TextSize = 24,
		TextColor3 = color,
		TextTransparency = 1,
		Text = message,
		Parent = frame,
	})
	create("UIScale", { Scale = 0.6 }).Parent = frame
	local scale = frame:FindFirstChildOfClass("UIScale")
	tween(frame, 0.2, { BackgroundTransparency = 0.12 })
	tween(outline, 0.2, { Transparency = 0 })
	tween(label, 0.2, { TextTransparency = 0 })
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	table.insert(activeNotifications, frame)
	while #activeNotifications > 4 do
		local oldest = table.remove(activeNotifications, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(duration or 2.5, function()
		if not frame.Parent then
			return
		end
		tween(frame, 0.3, { BackgroundTransparency = 1 })
		tween(outline, 0.3, { Transparency = 1 })
		tween(label, 0.3, { TextTransparency = 1 })
		task.delay(0.32, function()
			local index = table.find(activeNotifications, frame)
			if index then
				table.remove(activeNotifications, index)
			end
			frame:Destroy()
		end)
	end)
end

function UIController.FloatingText(position: Vector3, message: string, color: Color3?)
	local anchor = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Parent = workspace,
	})
	local billboard = create("BillboardGui", {
		Size = UDim2.fromOffset(260, 80),
		AlwaysOnTop = true,
		MaxDistance = 300,
		LightInfluence = 0,
		Parent = anchor,
	})
	local label = text({
		Size = UDim2.fromScale(1, 1),
		Font = F.Display,
		TextColor3 = color or C.Gold,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = C.Charcoal,
		Text = message,
		Parent = billboard,
	})
	tween(billboard, 1.8, { StudsOffset = Vector3.new(0, 6, 0) })
	task.delay(1.1, function()
		tween(label, 0.7, { TextTransparency = 1, TextStrokeTransparency = 1 })
	end)
	Debris:AddItem(anchor, 2)
end

function UIController.ShowDialogue(speaker: string, message: string)
	refs.DialogueSpeaker.Text = speaker
	refs.DialogueText.Text = message
	refs.DialogueText.MaxVisibleGraphemes = 0
	refs.Dialogue.Visible = true
	tween(refs.DialogueText, math.min(2, #message * 0.03), { MaxVisibleGraphemes = utf8.len(message) or #message }, Enum.EasingStyle.Linear)
	local token = os.clock()
	refs.DialogueToken = token
	task.delay(7, function()
		if refs.DialogueToken == token then
			refs.Dialogue.Visible = false
		end
	end)
end

function UIController.ShowCountdown(popAt: number)
	local label = refs.Countdown
	label.Visible = true
	task.spawn(function()
		local last = nil
		while now() < popAt do
			local remaining = math.ceil(popAt - now())
			if remaining ~= last and remaining <= 3 then
				last = remaining
				label.Text = tostring(remaining) .. "..."
				label.TextColor3 = C.Gold
				label.Size = UDim2.fromOffset(300, 140)
				tween(label, 0.4, { Size = UDim2.fromOffset(420, 180) }, Enum.EasingStyle.Back)
				registry.SoundController.Play("Countdown")
			elseif remaining > 3 then
				label.Text = "GET READY!"
			end
			task.wait(0.05)
		end
		label.Text = "POP!"
		label.TextColor3 = C.Orange
		label.Size = UDim2.fromOffset(300, 140)
		tween(label, 0.3, { Size = UDim2.fromOffset(520, 220) }, Enum.EasingStyle.Back)
		task.wait(0.9)
		label.Visible = false
	end)
end

function UIController.ShowResults(payload: any)
	refs.ResultsTitle.Text = `ROUND {payload.Round} RESULTS`
	for _, child in refs.ResultsList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for rank, row in payload.Rows do
		local isMe = row.UserId == player.UserId
		local frame = create("Frame", {
			LayoutOrder = rank,
			Size = UDim2.new(1, -8, 0, 46),
			BackgroundColor3 = if isMe then Color3.fromRGB(74, 46, 24) else C.CharcoalSoft,
			BorderSizePixel = 0,
			Parent = refs.ResultsList,
		}, { corner(10) })
		local zoneColor = Theme.ZoneColors[row.ZoneId] or C.Cream
		local cells = {
			{ `#{rank}`, 0, 0.08, C.Gold },
			{ row.Name, 0.08, 0.3, C.Cream },
			{ if row.Survived then "✨ GOLDEN" else "🪨 BURNT", 0.38, 0.18, if row.Survived then C.Legend else C.CreamMuted },
			{ row.Zone, 0.56, 0.22, zoneColor },
			{ `{row.Points} pts`, 0.78, 0.12, C.Cream },
			{ `+{row.Crumbs}🍞`, 0.9, 0.1, C.Gold },
		}
		for _, cell in cells do
			text({
				Position = UDim2.new(cell[2], 8, 0, 8),
				Size = UDim2.new(cell[3], -10, 1, -16),
				Font = F.Body,
				TextColor3 = cell[4],
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = cell[1],
				Parent = frame,
			})
		end
	end
	refs.Results.Visible = true
	refs.Results.Size = UDim2.fromOffset(540, 380)
	tween(refs.Results, 0.35, { Size = UDim2.fromOffset(600, 420) }, Enum.EasingStyle.Back)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function heatStateText(state: string, heat: number): string
	local names = { Normal = "FRESH", Warm = "WARM", VeryHot = "VERY HOT", Critical = "CRITICAL!", Burnt = "BURNT" }
	return `{names[state] or state} {math.floor(heat)}%`
end

local function refreshHeat()
	local heat = player:GetAttribute(ATTR.Heat) or 0
	local state = player:GetAttribute(ATTR.HeatState) or "Normal"
	local color = Theme.HeatStateColors[state] or C.Cream
	tween(refs.HeatFill, 0.25, { Size = UDim2.fromScale(math.clamp(heat / 100, 0, 1), 1), BackgroundColor3 = color })
	refs.HeatState.Text = heatStateText(state, heat)
	refs.HeatState.TextColor3 = color
	refs.Vignette.Visible = state == "Critical"
	local zone = ZONE_LABELS[player:GetAttribute(ATTR.HeatZone) or "Center"]
	local heatActive = Net.RoundState:GetAttribute(RA.HeatActive) == true
	refs.ZoneChip.Text = if heatActive and zone and state ~= "Burnt" then zone[1] else ""
	refs.ZoneChip.TextColor3 = if zone then zone[2] else C.CreamMuted
end

local function refreshCrumbs()
	refs.CrumbLabel.Text = "🍞 " .. UIUtil.formatNumber(player:GetAttribute(ATTR.Crumbs) or 0)
	local level = player:GetAttribute(ATTR.Level) or 1
	local title = player:GetAttribute(ATTR.Title) or ""
	refs.LevelLabel.Text = if title ~= "" then `LVL {level} • {title}` else `LVL {level}`
end

local function refreshAbilityLabel()
	local bread = BreadDefinitions.ById[player:GetAttribute(ATTR.Bread) or "Bread"]
	local ability = bread and bread.Ability and AbilityDefinitions[bread.Ability]
	local entry = refs.ActionButtons.Ability
	entry.Label.Text = if ability then ability.DisplayName else "NO ABILITY"
end

-- 10 Hz refresh for clocks and cooldowns (cheap, no per-frame work).
local function tick()
	local phase = Net.RoundState:GetAttribute(RA.Phase) or PHASES.Lobby
	local endsAt = Net.RoundState:GetAttribute(RA.PhaseEndsAt) or 0
	local inRound = player:GetAttribute(ATTR.InRound) == true
	refs.PhaseLabel.Text = PHASE_NAMES[phase] or phase
	refs.PhaseLabel.TextColor3 = if phase == PHASES.Heating then C.Danger else C.Gold
	if endsAt > 0 then
		refs.TimeLabel.Text = "TIME: " .. formatTime(endsAt - now())
	else
		refs.TimeLabel.Text = "WAITING..."
	end

	if phase == PHASES.Lobby then
		refs.StatusLabel.Text = if endsAt > 0 then "Next round is about to start!" else "Waiting for players..."
	elseif not inRound then
		refs.StatusLabel.Text = "👀 Spectating. You'll join the next round!"
	elseif player:GetAttribute(ATTR.IsCharcoal) == true and (phase == PHASES.Calm or phase == PHASES.Heating) then
		refs.StatusLabel.Text = "🪨 You're charcoal: touch other bread to blacken them!"
	elseif phase == PHASES.Calm then
		refs.StatusLabel.Text = "Collect crumbs 🍞 and grab butter 🧈"
	elseif phase == PHASES.Heating then
		refs.StatusLabel.Text = "Survive the heat! Cool spots are at the ends."
	elseif phase == PHASES.Launch then
		refs.StatusLabel.Text = "Get to the POP PAD in the centre!"
	else
		refs.StatusLabel.Text = ""
	end

	local showRound = inRound and (phase == PHASES.RoundStart or phase == PHASES.Calm or phase == PHASES.Heating or phase == PHASES.Launch)
	refs.HeatPanel.Visible = showRound
	refs.Actions.Visible = inRound and (phase == PHASES.Calm or phase == PHASES.Heating)

	-- Butter panel
	local shieldEnds = player:GetAttribute(ATTR.ShieldEndsAt) or 0
	local carried = player:GetAttribute(ATTR.ButterCarried) or 0
	local remaining = shieldEnds - now()
	if showRound and remaining > 0 then
		refs.ButterPanel.Visible = true
		refs.ButterFill.Size = UDim2.fromScale(math.clamp(remaining / 10, 0, 1), 1)
		refs.ButterLabel.Text = string.format("🧈 BUTTER SHIELD  %.1fs", remaining)
	elseif showRound and carried > 0 then
		refs.ButterPanel.Visible = true
		refs.ButterFill.Size = UDim2.fromScale(0, 1)
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		refs.ButterLabel.Text = if phase == PHASES.Heating
			then (if touch then "🧈 BUTTER READY: tap 🧈" else "🧈 BUTTER READY: press F")
			else "🧈 BUTTER saved for the heat"
	else
		refs.ButterPanel.Visible = false
	end

	-- Cooldowns
	for key, entry in refs.ActionButtons do
		local endsCd = player:GetAttribute(ATTR.CooldownPrefix .. key) or 0
		local left = endsCd - now()
		local total = registry.InputController.CooldownDuration(key)
		if left > 0 and total > 0 then
			entry.Overlay.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
			entry.CooldownText.Text = string.format("%d", math.ceil(left))
		else
			entry.Overlay.Size = UDim2.fromScale(1, 0)
			entry.CooldownText.Text = ""
		end
		local disabled = (key == "Butter" and (carried <= 0 or phase ~= PHASES.Heating))
			or (key ~= "Butter" and player:GetAttribute(ATTR.IsCharcoal) == true)
		entry.Button.BackgroundTransparency = if disabled then 0.6 else 0.1
	end

	if refs.Vignette.Visible then
		local pulse = (math.sin(os.clock() * 8) + 1) / 2
		for _, edge in refs.Vignette:GetChildren() do
			(edge :: Frame).BackgroundTransparency = pulse * 0.5
		end
	end
	if phase ~= PHASES.Results and refs.Results.Visible then
		refs.Results.Visible = false
	end
end

local function updateScale(uiScale: UIScale)
	local camera = workspace.CurrentCamera
	local viewport = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 1150, viewport.Y / 680), 0.55, 1.2)
end

function UIController.Init(reg)
	registry = reg
end

function UIController.Start()
	gui = create("ScreenGui", {
		Name = "MainUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local uiScale = create("UIScale", { Parent = gui })
	updateScale(uiScale)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateScale(uiScale)
	end)

	buildVignette()
	buildTimer()
	buildCrumbs()
	buildHeat()
	buildActionButtons()
	buildNotifications()
	buildCountdown()
	buildDialogue()
	buildResults()
	buildShop()

	for _, name in { ATTR.Heat, ATTR.HeatState, ATTR.HeatZone } do
		player:GetAttributeChangedSignal(name):Connect(refreshHeat)
	end
	Net.RoundState:GetAttributeChangedSignal(RA.HeatActive):Connect(refreshHeat)
	for _, name in { ATTR.Crumbs, ATTR.Level, ATTR.Title } do
		player:GetAttributeChangedSignal(name):Connect(refreshCrumbs)
	end
	player:GetAttributeChangedSignal(ATTR.Bread):Connect(refreshAbilityLabel)
	player:GetAttributeChangedSignal(ATTR.HeatState):Connect(function()
		if player:GetAttribute(ATTR.HeatState) == "Burnt" then
			refs.Vignette.Visible = false
		end
	end)
	refreshHeat()
	refreshCrumbs()
	refreshAbilityLabel()

	Net.UIEvent.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Notify" then
			UIController.Notify(payload.Text, payload.Style, payload.Duration)
		elseif kind == "FloatingText" then
			UIController.FloatingText(payload.Position, payload.Text, payload.Color)
		elseif kind == "Dialogue" then
			UIController.ShowDialogue(payload.Speaker, payload.Text)
		elseif kind == "Profile" then
			profile = payload
			UIController.RenderShop()
		end
	end)

	Net.RoundEvent.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "Countdown" then
			UIController.ShowCountdown(payload.PopAt)
		elseif kind == "Results" then
			UIController.ShowResults(payload)
		end
	end)

	task.spawn(function()
		while gui.Parent do
			local ok, err = pcall(tick)
			if not ok then
				warn("[UIController] tick failed:", err)
			end
			task.wait(0.1)
		end
	end)

	Net.InteractionEvent:FireServer("RequestProfile")
end

function UIController.ToggleShop()
	if refs.ToggleShop then
		refs.ToggleShop(not refs.Shop.Visible)
	end
end

return UIController
