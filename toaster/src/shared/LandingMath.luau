--!strict
-- Pure launch + landing maths. The launch is a controlled ballistic shot:
-- each player gets a landing target derived from where they stood in the
-- toaster, and we solve the exact velocity that reaches it in FlightTime.

local LandingMath = {}

export type Zone = { Id: string, Name: string, Radius: number, Points: number }

export type LaunchConfig = {
	FlightTime: number,
	OffsetScale: number,
	RandomSpread: number,
	PadRadius: number,
	PadSpread: number,
}

-- Velocity that moves a projectile from p to t in `flightTime` seconds under `gravity`.
function LandingMath.SolveVelocity(
	px: number,
	py: number,
	pz: number,
	tx: number,
	ty: number,
	tz: number,
	flightTime: number,
	gravity: number
): (number, number, number)
	assert(flightTime > 0, "flightTime must be positive")
	local vx = (tx - px) / flightTime
	local vz = (tz - pz) / flightTime
	local vy = (ty - py + 0.5 * gravity * flightTime * flightTime) / flightTime
	return vx, vy, vz
end

-- Position along the arc after `t` seconds. Used for tests and fallbacks.
function LandingMath.PositionAt(
	px: number,
	py: number,
	pz: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number,
	t: number
): (number, number, number)
	return px + vx * t, py + vy * t - 0.5 * gravity * t * t, pz + vz * t
end

-- Landing offset from the bullseye. Standing near the toaster centre lands you
-- near the bullseye; the POP pad tightens the random spread.
-- `randAngle` and `randRadius` are in [0, 1) so callers control randomness.
function LandingMath.TargetOffset(
	localX: number,
	localZ: number,
	cfg: LaunchConfig,
	randAngle: number,
	randRadius: number
): (number, number)
	local distFromCentre = math.sqrt(localX * localX + localZ * localZ)
	local onPad = distFromCentre <= cfg.PadRadius
	local spread = if onPad then cfg.PadSpread else cfg.RandomSpread
	local angle = randAngle * math.pi * 2
	local radius = math.sqrt(randRadius) * spread
	local scale = if onPad then 0 else cfg.OffsetScale
	return localX * scale + math.cos(angle) * radius, localZ * scale + math.sin(angle) * radius
end

function LandingMath.IsOnPad(localX: number, localZ: number, cfg: LaunchConfig): boolean
	return math.sqrt(localX * localX + localZ * localZ) <= cfg.PadRadius
end

-- Zones must be ordered best -> worst with increasing radius.
function LandingMath.ZoneForDistance(distance: number, zones: { Zone }): Zone
	for _, zone in zones do
		if distance <= zone.Radius then
			return zone
		end
	end
	return zones[#zones]
end

return LandingMath
