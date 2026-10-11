-- End-of-round rewards. Each player is rewarded exactly once per round
-- (RewardGranted guard) and the results table is built from the same data.
-- Surviving rounds in a row multiplies crumbs, and four awards go to the
-- standout players of the round.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Theme = require(Shared.Theme)

local RewardManager = {}

local services
local lastAwards: { { Title: string, Name: string, UserId: number } } = {}

function RewardManager.Init(registry)
	services = registry
end

type Award = { Title: string, Pick: (sessions: { any }) -> any? }

local function best(sessions: { any }, score: (any) -> number?, higherIsBetter: boolean): any?
	local winner, winnerScore = nil, nil
	for _, session in sessions do
		local value = score(session)
		if value ~= nil and (winnerScore == nil or (if higherIsBetter then value > winnerScore else value < winnerScore)) then
			winner, winnerScore = session, value
		end
	end
	return winner
end

local AWARDS: { Award } = {
	{
		Title = "🍞 MOST CRUMBS",
		Pick = function(sessions)
			return best(sessions, function(s)
				return if s.RoundCrumbs > 0 then s.RoundCrumbs else nil
			end, true)
		end,
	},
	{
		Title = "🎯 BULLSEYE",
		Pick = function(sessions)
			return best(sessions, function(s)
				return if s.LandingPoints >= Config.Rewards.BullseyeMinPoints then s.LandingPoints else nil
			end, true)
		end,
	},
	{
		Title = "🪨 CHARCOAL MENACE",
		Pick = function(sessions)
			return best(sessions, function(s)
				return if s.RoundBlackens > 0 then s.RoundBlackens else nil
			end, true)
		end,
	},
	{
		Title = "🧊 COOLEST HEAD",
		Pick = function(sessions)
			return best(sessions, function(s)
				return if s.Survived then s.LaunchHeat else nil
			end, false)
		end,
	},
}

local function assignAwards(sessions: { any })
	table.clear(lastAwards)
	if #sessions < 2 then
		return -- awards only mean something with company
	end
	for _, award in AWARDS do
		local winner = award.Pick(sessions)
		if winner then
			table.insert(winner.Awards, award.Title)
			table.insert(lastAwards, { Title = award.Title, Name = winner.Player.DisplayName, UserId = winner.Player.UserId })
		end
	end
end

local function grant(session)
	if session.RewardGranted then
		return
	end
	session.RewardGranted = true
	local player = session.Player
	local data = services.DataManager.Get(player)
	local streak = if session.Survived and data then data.Statistics.SurvivalStreak + 1 else 0
	local reward = Progression.RoundReward({
		Participated = true,
		Survived = session.Survived,
		LandingPoints = session.LandingPoints,
		CollectedCrumbs = session.RoundCrumbs,
		Streak = streak,
		Awards = #session.Awards,
	}, Config.Rewards)
	reward.Streak = streak
	session.Reward = reward

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
		stats.SurvivalStreak = streak
		stats.BestStreak = math.max(stats.BestStreak, streak)
		stats.AwardsWon += #session.Awards
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
	if streak >= 2 then
		local bonus = math.floor((reward.StreakMultiplier - 1) * 100 + 0.5)
		services.Messaging.Notify(player, `🔥 SURVIVAL STREAK x{streak}! +{bonus}% crumbs`, "Legend", 3)
	end
	for _, title in session.Awards do
		services.Messaging.Notify(player, `🏅 {title}! +{Config.Rewards.AwardCrumbs} 🍞`, "Good", 3)
	end
	if levelAfter > levelBefore then
		services.Messaging.Notify(player, `⭐ LEVEL UP! You're level {levelAfter}`, "Legend", 3)
	end
	services.AchievementManager.Evaluate(player)
end

function RewardManager.GrantRound()
	local sessions = services.PlayerManager.InRound()
	assignAwards(sessions)
	for _, session in sessions do
		local ok, err = pcall(grant, session)
		if not ok then
			warn("[RewardManager] reward failed for", session.Player.Name, err)
		end
	end
end

function RewardManager.BuildResults(): { any }
	local rows = {}
	for _, session in services.PlayerManager.InRound() do
		local reward = session.Reward or { Points = 0, Crumbs = 0, XP = 0, Streak = 0 }
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
			Streak = reward.Streak or 0,
			Awards = #session.Awards,
		})
	end
	table.sort(rows, function(a, b)
		return a.Points > b.Points
	end)
	return rows
end

function RewardManager.LastAwards(): { any }
	return table.clone(lastAwards)
end

return RewardManager
