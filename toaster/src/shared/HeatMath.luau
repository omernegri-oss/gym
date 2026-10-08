--!strict
-- Pure heat calculations shared by the server (authoritative) and the client
-- (display only). No Roblox types, so it is unit-testable.

local HeatMath = {}

export type HeatConfig = {
	MaxHeat: number,
	WarmThreshold: number,
	VeryHotThreshold: number,
	CriticalThreshold: number,
	BurnThreshold: number,
}

export type ZoneConfig = {
	CenterMultiplier: number,
	CoilMultiplier: number,
	SafeMultiplier: number,
	CoilBand: number,
	SafeNookDepth: number,
	SafeNookHalfWidth: number,
}

export type MapConfig = {
	InteriorLength: number,
	InteriorWidth: number,
}

export type HeatModifiers = {
	zoneMultiplier: number,
	breadResistance: number,
	shieldMultiplier: number?, -- set while a Butter Shield is active
	abilityResistance: number?, -- e.g. Waffle Slam
	hotSpotMultiplier: number?, -- set while standing in an active hot spot
}

function HeatMath.GetState(heat: number, cfg: HeatConfig): string
	if heat >= cfg.BurnThreshold then
		return "Burnt"
	elseif heat >= cfg.CriticalThreshold then
		return "Critical"
	elseif heat >= cfg.VeryHotThreshold then
		return "VeryHot"
	elseif heat >= cfg.WarmThreshold then
		return "Warm"
	end
	return "Normal"
end

-- localX / localZ are relative to the toaster centre. Coils run along the two
-- long (±Z) walls; the cool "safe nooks" sit in the middle of the two end walls.
function HeatMath.GetZone(localX: number, localZ: number, map: MapConfig, zones: ZoneConfig): (string, number)
	local halfLength = map.InteriorLength / 2
	local halfWidth = map.InteriorWidth / 2

	if math.abs(localX) >= halfLength - zones.SafeNookDepth and math.abs(localZ) <= zones.SafeNookHalfWidth then
		return "Safe", zones.SafeMultiplier
	end
	if math.abs(localZ) >= halfWidth - zones.CoilBand then
		return "Coils", zones.CoilMultiplier
	end
	return "Center", zones.CenterMultiplier
end

function HeatMath.ComputeDelta(baseRate: number, dt: number, mods: HeatModifiers): number
	local rate = baseRate * mods.zoneMultiplier * mods.breadResistance
	if mods.hotSpotMultiplier then
		rate *= mods.hotSpotMultiplier
	end
	if mods.abilityResistance then
		rate *= mods.abilityResistance
	end
	if mods.shieldMultiplier then
		rate *= mods.shieldMultiplier
	end
	return math.max(0, rate * dt)
end

function HeatMath.Clamp(heat: number, cfg: HeatConfig): number
	return math.clamp(heat, 0, cfg.MaxHeat)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Toast colour ramp: raw -> golden -> brown -> charcoal. Returns 0-255 RGB.
local STOPS = {
	{ 0, 247, 226, 181 },
	{ 35, 242, 194, 107 },
	{ 70, 201, 121, 46 },
	{ 90, 110, 60, 26 },
	{ 100, 30, 22, 18 },
}

function HeatMath.ToastRGB(heat: number): (number, number, number)
	local h = math.clamp(heat, 0, 100)
	for i = 2, #STOPS do
		local hi = STOPS[i]
		if h <= hi[1] then
			local lo = STOPS[i - 1]
			local t = (h - lo[1]) / (hi[1] - lo[1])
			return lerp(lo[2], hi[2], t), lerp(lo[3], hi[3], t), lerp(lo[4], hi[4], t)
		end
	end
	local last = STOPS[#STOPS]
	return last[2], last[3], last[4]
end

-- Darken an RGB triple by `amount` (0 = unchanged, 1 = black).
function HeatMath.Darken(r: number, g: number, b: number, amount: number): (number, number, number)
	local k = 1 - math.clamp(amount, 0, 1)
	return r * k, g * k, b * k
end

return HeatMath
