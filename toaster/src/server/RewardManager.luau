-- End-of-round rewards. Each player is rewarded exactly once per round
-- (RewardGranted guard) and the results table is built from the same data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Theme = require(Shared.Theme)

local RewardManager = {}

local services

function RewardManager.Init(registry)
	services = registry
end

local function grant(session)
	if session.RewardGranted then
		return
	end
	session.RewardGranted = true
	local player = session.Player
	local reward = Progression.RoundReward({
		Participated = true,
		Survived = session.Survived,
		LandingPoints = session.LandingPoints,
		CollectedCrumbs = session.RoundCrumbs,
	}, Config.Rewards)
	session.Reward = reward

	local data = services.DataManager.Get(player)
	if not data then
		return
	end
	local levelBefore = Progression.LevelForXP(data.XP, Config.Progression.LevelXP)
	if reward.Crumbs > 0 then
		services.CurrencyManager.Add(player, "Crumbs", reward.Crumbs, "RoundReward")
	end
	services.DataManager.Update(player, function(d)
		d.XP += reward.XP
		d.BreadLevel = Progression.LevelForXP(d.XP, Config.Progression.LevelXP)
		local stats = d.Statistics
		stats.RoundsPlayed += 1
		if session.Survived then
			stats.RoundsSurvived += 1
			if session.UsedButterThisRound then
				stats.ButterSurvivals += 1
			end
		end
		stats.BestLandingScore = math.max(stats.BestLandingScore, reward.Points)
	end)
	local levelAfter = Progression.LevelForXP(data.XP, Config.Progression.LevelXP)

	local root = services.PlayerManager.GetBody(session)
	if root then
		services.Messaging.FloatingText(
			player,
			root.Position + Vector3.new(0, 9, 0),
			`+{reward.Crumbs} 🍞   +{reward.XP} XP`,
			Theme.Colors.Gold
		)
	end
	services.Messaging.Sound(player, "Score")
	if levelAfter > levelBefore then
		services.Messaging.Notify(player, `⭐ LEVEL UP! You're level {levelAfter}`, "Legend", 3)
	end
	services.AchievementManager.Evaluate(player)
end

function RewardManager.GrantRound()
	for _, session in services.PlayerManager.InRound() do
		local ok, err = pcall(grant, session)
		if not ok then
			warn("[RewardManager] reward failed for", session.Player.Name, err)
		end
	end
end

function RewardManager.BuildResults(): { any }
	local rows = {}
	for _, session in services.PlayerManager.InRound() do
		local reward = session.Reward or { Points = 0, Crumbs = 0, XP = 0 }
		table.insert(rows, {
			UserId = session.Player.UserId,
			Name = session.Player.DisplayName,
			Zone = session.LandingZoneName or "MISSED",
			ZoneId = session.LandingZoneId or "Safe",
			LandingPoints = session.LandingPoints,
			Survived = session.Survived,
			Points = reward.Points,
			Crumbs = reward.Crumbs + session.RoundCrumbs,
			XP = reward.XP,
		})
	end
	table.sort(rows, function(a, b)
		return a.Points > b.Points
	end)
	return rows
end

return RewardManager
