--!strict
-- Achievements unlock titles (and occasionally a cosmetic). Each check reads the
-- saved statistics, so evaluation is a pure function of player data.

export type Achievement = {
	Id: string,
	Title: string,
	Description: string,
	Stat: string,
	Goal: number,
	RewardCosmetic: string?,
}

local list: { Achievement } = {
	{ Id = "Rookie", Title = "TOAST ROOKIE", Description = "Play your first round.", Stat = "RoundsPlayed", Goal = 1 },
	{
		Id = "ButterSurvivor",
		Title = "BUTTER SURVIVOR",
		Description = "Survive a round while a Butter Shield was used.",
		Stat = "ButterSurvivals",
		Goal = 1,
		RewardCosmetic = "ButterTrail",
	},
	{ Id = "CrumbCollector", Title = "CRUMB COLLECTOR", Description = "Earn 1,000 crumbs in total.", Stat = "TotalCrumbs", Goal = 1000 },
	{ Id = "MasterToast", Title = "MASTER TOAST", Description = "Survive 10 rounds golden.", Stat = "RoundsSurvived", Goal = 10 },
	{
		Id = "CharcoalMenace",
		Title = "CHARCOAL MENACE",
		Description = "Blacken 10 players as charcoal.",
		Stat = "PlayersBlackened",
		Goal = 10,
	},
	{ Id = "WaffleLegend", Title = "WAFFLE LEGEND", Description = "Unlock the Legendary Waffle.", Stat = "WaffleUnlocked", Goal = 1 },
	{
		Id = "Archaeologist",
		Title = "CRUMB ARCHAEOLOGIST",
		Description = "Find Old Crumb's three vintage crumbs.",
		Stat = "VintageQuestDone",
		Goal = 1,
	},
}

local byId: { [string]: Achievement } = {}
for _, achievement in list do
	byId[achievement.Id] = achievement
end

return {
	List = list,
	ById = byId,
}
