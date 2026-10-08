-- Unlocks achievements (titles, sometimes a cosmetic) from saved statistics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementDefinitions = require(Shared.AchievementDefinitions)

local AchievementManager = {}

local services

function AchievementManager.Init(registry)
	services = registry
end

function AchievementManager.Evaluate(player: Player)
	local data = services.DataManager.Get(player)
	if not data then
		return
	end
	local unlocked = {}
	for _, achievement in AchievementDefinitions.List do
		if not data.Achievements[achievement.Id] and (data.Statistics[achievement.Stat] or 0) >= achievement.Goal then
			table.insert(unlocked, achievement)
		end
	end
	if #unlocked == 0 then
		return
	end
	services.DataManager.Update(player, function(d)
		for _, achievement in unlocked do
			d.Achievements[achievement.Id] = true
			if achievement.RewardCosmetic then
				d.UnlockedCosmetics[achievement.RewardCosmetic] = true
			end
			if d.EquippedTitle == "" then
				d.EquippedTitle = achievement.Title
			end
		end
	end)
	for _, achievement in unlocked do
		services.Messaging.Notify(player, `🏆 ACHIEVEMENT: {achievement.Title}`, "Legend", 3.5)
	end
	services.ShopManager.SendProfile(player)
end

return AchievementManager
