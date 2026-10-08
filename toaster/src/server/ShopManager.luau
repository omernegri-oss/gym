-- Bread unlocks, cosmetics, titles and Robux purchases. Every request is
-- validated (rate limit, ownership, price, level, round state). Robux only
-- buys cosmetics: never breads, crumbs or anything competitive.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementDefinitions = require(Shared.AchievementDefinitions)
local BreadDefinitions = require(Shared.BreadDefinitions)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local CosmeticDefinitions = require(Shared.CosmeticDefinitions)
local DataSchema = require(Shared.DataSchema)
local Monetization = require(Shared.Monetization)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local RateLimiter = require(Shared.RateLimiter)

local ShopManager = {}

local PHASES = Constants.Phases
local services
local limiter = RateLimiter.new(Config.RateLimits.Interaction.Capacity, Config.RateLimits.Interaction.RefillPerSecond)
local vipOwners: { [Player]: boolean } = {}

local function level(data): number
	return Progression.LevelForXP(data.XP, Config.Progression.LevelXP)
end

local function availableTitles(player: Player, data): { string }
	local titles = {}
	for _, achievement in AchievementDefinitions.List do
		if data.Achievements[achievement.Id] then
			table.insert(titles, achievement.Title)
		end
	end
	if vipOwners[player] then
		table.insert(titles, Monetization.GamePasses.VIP.Title)
	end
	return titles
end

function ShopManager.SendProfile(player: Player)
	local data = services.DataManager.Get(player)
	if not data then
		return
	end
	local products = {}
	for key, product in Monetization.Products do
		if product.Id ~= 0 then
			products[key] = { DisplayName = product.DisplayName, Grants = product.Grants }
		end
	end
	services.Messaging.UI(player, "Profile", {
		Crumbs = data.Crumbs,
		XP = data.XP,
		Level = level(data),
		XPToNext = Progression.XPToNextLevel(data.XP, Config.Progression.LevelXP),
		UnlockedBreads = data.UnlockedBreads,
		EquippedBread = data.EquippedBread,
		UnlockedCosmetics = data.UnlockedCosmetics,
		EquippedCosmetics = data.EquippedCosmetics,
		Achievements = data.Achievements,
		EquippedTitle = data.EquippedTitle,
		Titles = availableTitles(player, data),
		Statistics = data.Statistics,
		VipAvailable = Monetization.GamePasses.VIP.Id ~= 0,
		VipOwned = vipOwners[player] == true,
		Products = products,
		Saving = player:GetAttribute(Constants.Attr.DataLoaded) == true,
	})
end

local function canChangeLoadout(session): boolean
	if not session.InRound then
		return true
	end
	local phase = services.RoundManager.GetPhase()
	return phase == PHASES.Lobby or phase == PHASES.Results or phase == PHASES.Rewards
end

local function rebuildIfAllowed(player: Player)
	local session = services.PlayerManager.Get(player)
	if session then
		services.PlayerManager.RebuildBread(session)
	end
end

local function fail(player: Player, reason: string)
	services.Messaging.Notify(player, reason, "Info", 2)
	services.Messaging.Sound(player, "Error")
end

local function grantCosmetics(player: Player, ids: { string })
	services.DataManager.Update(player, function(d)
		for _, id in ids do
			if CosmeticDefinitions.ById[id] then
				d.UnlockedCosmetics[id] = true
			end
		end
	end)
end

local HANDLERS = {}

function HANDLERS.RequestProfile(player: Player)
	ShopManager.SendProfile(player)
end

function HANDLERS.BuyBread(player: Player, breadId: any)
	local def = type(breadId) == "string" and BreadDefinitions.ById[breadId]
	local data = services.DataManager.Get(player)
	if not def or not data then
		return
	end
	local check = Progression.CanBuy(def.Price, def.RequiredLevel, data.Crumbs, level(data), data.UnlockedBreads[def.Id] == true)
	if not check.Ok then
		fail(player, check.Reason or "Can't buy that")
		return
	end
	if def.Price > 0 and not services.CurrencyManager.Spend(player, "Crumbs", def.Price, "Bread:" .. def.Id) then
		fail(player, "Not enough crumbs")
		return
	end
	services.DataManager.Update(player, function(d)
		d.UnlockedBreads[def.Id] = true
		if def.Id == "Waffle" then
			d.Statistics.WaffleUnlocked = 1
		end
	end)
	services.Messaging.Notify(player, `🎉 Unlocked {def.DisplayName}!`, "Legend", 3)
	services.Messaging.Sound(player, "Purchase")
	services.AchievementManager.Evaluate(player)
	HANDLERS.EquipBread(player, def.Id)
end

function HANDLERS.EquipBread(player: Player, breadId: any)
	local def = type(breadId) == "string" and BreadDefinitions.ById[breadId]
	local data = services.DataManager.Get(player)
	local session = services.PlayerManager.Get(player)
	if not def or not data or not session or not data.UnlockedBreads[def.Id] then
		return
	end
	if not canChangeLoadout(session) then
		fail(player, "Change your bread between rounds!")
		ShopManager.SendProfile(player)
		return
	end
	services.DataManager.Update(player, function(d)
		d.EquippedBread = def.Id
	end)
	rebuildIfAllowed(player)
	ShopManager.SendProfile(player)
end

function HANDLERS.BuyCosmetic(player: Player, cosmeticId: any)
	local cosmetic = type(cosmeticId) == "string" and CosmeticDefinitions.ById[cosmeticId]
	local data = services.DataManager.Get(player)
	if not cosmetic or not data or data.UnlockedCosmetics[cosmetic.Id] then
		return
	end
	if cosmetic.Source == "Crumbs" then
		if not services.CurrencyManager.Spend(player, "Crumbs", cosmetic.Price, "Cosmetic:" .. cosmetic.Id) then
			fail(player, "Not enough crumbs")
			return
		end
		grantCosmetics(player, { cosmetic.Id })
		services.Messaging.Notify(player, `🎉 Unlocked {cosmetic.DisplayName}!`, "Good", 2.5)
		services.Messaging.Sound(player, "Purchase")
		HANDLERS.EquipCosmetic(player, cosmetic.Slot, cosmetic.Id)
	elseif cosmetic.Source == "GamePass" then
		local pass = Monetization.GamePasses.VIP
		if pass.Id ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		else
			fail(player, "VIP isn't available yet")
		end
	elseif cosmetic.Source == "Product" then
		for _, product in Monetization.Products do
			if product.Id ~= 0 and table.find(product.Grants, cosmetic.Id) then
				MarketplaceService:PromptProductPurchase(player, product.Id)
				return
			end
		end
		fail(player, "Not for sale yet")
	else
		fail(player, "Unlocked by an achievement")
	end
end

function HANDLERS.EquipCosmetic(player: Player, slot: any, cosmeticId: any)
	if type(slot) ~= "string" or not table.find(CosmeticDefinitions.Slots, slot) then
		return
	end
	local data = services.DataManager.Get(player)
	if not data then
		return
	end
	if cosmeticId == nil or cosmeticId == "" then
		services.DataManager.Update(player, function(d)
			d.EquippedCosmetics[slot] = nil
		end)
	else
		local cosmetic = type(cosmeticId) == "string" and CosmeticDefinitions.ById[cosmeticId]
		if not cosmetic or cosmetic.Slot ~= slot or not data.UnlockedCosmetics[cosmetic.Id] then
			return
		end
		services.DataManager.Update(player, function(d)
			d.EquippedCosmetics[slot] = cosmetic.Id
		end)
	end
	rebuildIfAllowed(player)
	ShopManager.SendProfile(player)
end

function HANDLERS.EquipTitle(player: Player, title: any)
	local data = services.DataManager.Get(player)
	if not data or type(title) ~= "string" then
		return
	end
	if title ~= "" and not table.find(availableTitles(player, data), title) then
		return
	end
	services.DataManager.Update(player, function(d)
		d.EquippedTitle = title
	end)
	ShopManager.SendProfile(player)
end

local function checkVip(player: Player)
	local pass = Monetization.GamePasses.VIP
	if pass.Id == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
	end)
	if ok and owns then
		vipOwners[player] = true
		grantCosmetics(player, pass.Grants)
		ShopManager.SendProfile(player)
	end
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = services.DataManager.Get(player)
	if not data or player:GetAttribute(Constants.Attr.DataLoaded) ~= true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if DataSchema.HasReceipt(data, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, product in Monetization.Products do
		if product.Id ~= 0 and product.Id == receipt.ProductId then
			grantCosmetics(player, product.Grants)
			services.DataManager.Update(player, function(d)
				DataSchema.RememberReceipt(d, receipt.PurchaseId)
			end)
			services.DataManager.Save(player, true)
			services.Messaging.Notify(player, `🎉 Thanks! {product.DisplayName} unlocked.`, "Legend", 3)
			ShopManager.SendProfile(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function ShopManager.Init(registry)
	services = registry
end

function ShopManager.Start()
	Net.InteractionEvent.OnServerEvent:Connect(function(player, action, arg1, arg2)
		if type(action) ~= "string" or not HANDLERS[action] or not limiter:Allow(player) then
			return
		end
		if not services.DataManager.Get(player) then
			return
		end
		local ok, err = pcall(HANDLERS[action], player, arg1, arg2)
		if not ok then
			warn("[ShopManager]", action, "failed:", err)
		end
	end)

	services.DataManager.OnLoaded(function(player)
		ShopManager.SendProfile(player)
		task.spawn(checkVip, player)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Monetization.GamePasses.VIP.Id and passId ~= 0 then
			vipOwners[player] = true
			grantCosmetics(player, Monetization.GamePasses.VIP.Grants)
			services.Messaging.Notify(player, "👑 Welcome to VIP!", "Legend", 3)
			ShopManager.SendProfile(player)
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerRemoving:Connect(function(player)
		vipOwners[player] = nil
		limiter:Forget(player)
	end)
end

return ShopManager
