--!strict
-- Pure progression rules: levels, round rewards and unlock checks.

local Progression = {}

export type RoundResult = {
	Participated: boolean,
	Survived: boolean,
	LandingPoints: number,
	CollectedCrumbs: number,
	Streak: number?, -- consecutive rounds survived, including this one
	Awards: number?, -- end-of-round awards won
}

export type RewardConfig = {
	SurvivalBonus: number,
	SurvivalCrumbs: number,
	PointsToCrumbs: number,
	ParticipationXP: number,
	SurvivalXP: number,
	LandingXPDivisor: number,
	StreakBonusPerRound: number,
	StreakMaxSteps: number,
	AwardCrumbs: number,
}

export type RoundReward = {
	Points: number,
	Crumbs: number,
	XP: number,
	StreakMultiplier: number,
}

-- 1.0 for a first survival, +StreakBonusPerRound for every round after it.
function Progression.StreakMultiplier(streak: number, cfg: RewardConfig): number
	local steps = math.clamp(streak - 1, 0, cfg.StreakMaxSteps)
	return 1 + steps * cfg.StreakBonusPerRound
end

function Progression.LevelForXP(xp: number, thresholds: { number }): number
	local level = 1
	for i, required in thresholds do
		if xp >= required then
			level = i
		else
			break
		end
	end
	return level
end

-- XP still needed for the next level, or nil at max level.
function Progression.XPToNextLevel(xp: number, thresholds: { number }): number?
	local level = Progression.LevelForXP(xp, thresholds)
	local nextRequired = thresholds[level + 1]
	if nextRequired == nil then
		return nil
	end
	return nextRequired - xp
end

-- Crumbs picked up during the round are granted live, so they are not
-- counted again here.
function Progression.RoundReward(result: RoundResult, cfg: RewardConfig): RoundReward
	if not result.Participated then
		return { Points = 0, Crumbs = 0, XP = 0, StreakMultiplier = 1 }
	end
	local points = result.LandingPoints
	local crumbs = 0
	local xp = cfg.ParticipationXP + math.floor(result.LandingPoints / cfg.LandingXPDivisor)
	if result.Survived then
		points += cfg.SurvivalBonus
		crumbs += cfg.SurvivalCrumbs
		xp += cfg.SurvivalXP
	end
	crumbs += math.floor(points * cfg.PointsToCrumbs)
	local multiplier = if result.Survived then Progression.StreakMultiplier(result.Streak or 1, cfg) else 1
	crumbs = math.floor(crumbs * multiplier) + (result.Awards or 0) * cfg.AwardCrumbs
	return { Points = points, Crumbs = crumbs, XP = xp, StreakMultiplier = multiplier }
end

export type UnlockCheck = { Ok: boolean, Reason: string? }

function Progression.CanBuy(price: number, requiredLevel: number, crumbs: number, level: number, owned: boolean): UnlockCheck
	if owned then
		return { Ok = false, Reason = "Already owned" }
	end
	if level < requiredLevel then
		return { Ok = false, Reason = `Reach level {requiredLevel}` }
	end
	if crumbs < price then
		return { Ok = false, Reason = "Not enough crumbs" }
	end
	return { Ok = true }
end

return Progression
