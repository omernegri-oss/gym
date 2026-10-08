--!strict
-- Pure progression rules: levels, round rewards and unlock checks.

local Progression = {}

export type RoundResult = {
	Participated: boolean,
	Survived: boolean,
	LandingPoints: number,
	CollectedCrumbs: number,
}

export type RewardConfig = {
	SurvivalBonus: number,
	SurvivalCrumbs: number,
	PointsToCrumbs: number,
	ParticipationXP: number,
	SurvivalXP: number,
	LandingXPDivisor: number,
}

export type RoundReward = {
	Points: number,
	Crumbs: number,
	XP: number,
}

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
		return { Points = 0, Crumbs = 0, XP = 0 }
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
	return { Points = points, Crumbs = crumbs, XP = xp }
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
