--!strict
-- Saved player data: defaults, reconciliation and corruption protection.
-- Pure Luau so it can be unit tested outside Roblox.

local DataSchema = {}

DataSchema.Version = 1
DataSchema.MaxReceipts = 50

local function defaultStatistics()
	return {
		RoundsPlayed = 0,
		RoundsSurvived = 0,
		TotalCrumbs = 0,
		BestLandingScore = 0,
		ButterSurvivals = 0,
		PlayersBlackened = 0,
		WaffleUnlocked = 0,
		VintageQuestDone = 0,
		SurvivalStreak = 0,
		BestStreak = 0,
		AwardsWon = 0,
	}
end

function DataSchema.Default()
	return {
		Version = DataSchema.Version,
		Crumbs = 0,
		XP = 0,
		BreadLevel = 1,
		UnlockedBreads = { Bread = true },
		UnlockedCosmetics = {},
		EquippedBread = "Bread",
		EquippedCosmetics = {},
		EquippedTitle = "",
		Achievements = {},
		VintageCrumbsFound = {},
		ProcessedReceipts = {},
		Statistics = defaultStatistics(),
	}
end

local function sanitizeNumber(value: any, fallback: number, minValue: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	if minValue and value < minValue then
		return minValue
	end
	return value
end

local function sanitizeString(value: any, fallback: string): string
	if type(value) ~= "string" or #value > 64 then
		return fallback
	end
	return value
end

-- Sets of ids are stored as { [id] = true }. Anything else is dropped.
local function sanitizeSet(value: any): { [string]: boolean }
	local result = {}
	if type(value) ~= "table" then
		return result
	end
	for key, flag in value do
		if type(key) == "string" and flag == true then
			result[key] = true
		end
	end
	return result
end

local function sanitizeStringMap(value: any): { [string]: string }
	local result = {}
	if type(value) ~= "table" then
		return result
	end
	for key, item in value do
		if type(key) == "string" and type(item) == "string" then
			result[key] = item
		end
	end
	return result
end

-- Returns a fully valid copy of `raw` (which may be nil, partial or corrupt)
-- plus a flag saying whether the input was a recognisable save at all.
function DataSchema.Reconcile(raw: any): (any, boolean)
	local data = DataSchema.Default()
	if type(raw) ~= "table" then
		return data, false
	end

	data.Crumbs = math.floor(sanitizeNumber(raw.Crumbs, 0, 0))
	data.XP = math.floor(sanitizeNumber(raw.XP, 0, 0))
	data.BreadLevel = math.floor(sanitizeNumber(raw.BreadLevel, 1, 1))
	data.UnlockedBreads = sanitizeSet(raw.UnlockedBreads)
	data.UnlockedBreads.Bread = true
	data.UnlockedCosmetics = sanitizeSet(raw.UnlockedCosmetics)
	data.EquippedBread = sanitizeString(raw.EquippedBread, "Bread")
	if not data.UnlockedBreads[data.EquippedBread] then
		data.EquippedBread = "Bread"
	end
	data.EquippedCosmetics = sanitizeStringMap(raw.EquippedCosmetics)
	for slot, cosmeticId in data.EquippedCosmetics do
		if not data.UnlockedCosmetics[cosmeticId] then
			data.EquippedCosmetics[slot] = nil
		end
	end
	data.EquippedTitle = sanitizeString(raw.EquippedTitle, "")
	data.Achievements = sanitizeSet(raw.Achievements)
	data.VintageCrumbsFound = sanitizeSet(raw.VintageCrumbsFound)

	if type(raw.ProcessedReceipts) == "table" then
		for _, receiptId in raw.ProcessedReceipts do
			if type(receiptId) == "string" and #data.ProcessedReceipts < DataSchema.MaxReceipts then
				table.insert(data.ProcessedReceipts, receiptId)
			end
		end
	end

	local stats = defaultStatistics()
	if type(raw.Statistics) == "table" then
		for key, fallback in stats do
			stats[key] = math.floor(sanitizeNumber(raw.Statistics[key], fallback :: number, 0))
		end
	end
	data.Statistics = stats

	return data, true
end

function DataSchema.RememberReceipt(data: any, receiptId: string)
	table.insert(data.ProcessedReceipts, receiptId)
	while #data.ProcessedReceipts > DataSchema.MaxReceipts do
		table.remove(data.ProcessedReceipts, 1)
	end
end

function DataSchema.HasReceipt(data: any, receiptId: string): boolean
	return table.find(data.ProcessedReceipts, receiptId) ~= nil
end

return DataSchema
