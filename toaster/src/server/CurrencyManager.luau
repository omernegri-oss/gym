-- Reusable currency system. Every grant/spend is validated server-side;
-- add a new currency by listing it in CURRENCIES and in DataSchema.

local CurrencyManager = {}

local CURRENCIES = {
	Crumbs = { StatKey = "TotalCrumbs" },
}

local services

function CurrencyManager.Init(registry)
	services = registry
end

local function validAmount(amount: number): boolean
	return type(amount) == "number" and amount == amount and amount > 0 and amount < 1e7 and math.floor(amount) == amount
end

function CurrencyManager.Get(player: Player, currency: string): number
	local data = services.DataManager.Get(player)
	if not data or not CURRENCIES[currency] then
		return 0
	end
	return data[currency] or 0
end

-- Returns true if granted.
function CurrencyManager.Add(player: Player, currency: string, amount: number, _reason: string?): boolean
	local def = CURRENCIES[currency]
	if not def or not validAmount(amount) or not services.DataManager.Get(player) then
		return false
	end
	services.DataManager.Update(player, function(data)
		data[currency] += amount
		if def.StatKey then
			data.Statistics[def.StatKey] += amount
		end
	end)
	return true
end

-- Returns true only if the player could afford it.
function CurrencyManager.Spend(player: Player, currency: string, amount: number, _reason: string?): boolean
	if not CURRENCIES[currency] or not validAmount(amount) then
		return false
	end
	local data = services.DataManager.Get(player)
	if not data or data[currency] < amount then
		return false
	end
	services.DataManager.Update(player, function(d)
		d[currency] -= amount
	end)
	return true
end

return CurrencyManager
