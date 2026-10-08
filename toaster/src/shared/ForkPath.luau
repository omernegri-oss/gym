--!strict
-- Deterministic figure-eight path for the Giant Fork. Server (zaps) and
-- clients (rendering) evaluate the same function on the shared server clock,
-- so the fork looks smooth everywhere without streaming positions.

local ForkPath = {}

export type PathConfig = { PathRadiusX: number, PathRadiusZ: number, LapTime: number }

-- Returns the XZ offset from the toaster centre `elapsed` seconds into the event.
function ForkPath.Offset(elapsed: number, cfg: PathConfig): (number, number)
	local u = (elapsed / cfg.LapTime) * math.pi * 2
	return math.sin(u) * cfg.PathRadiusX, math.sin(u * 2) * cfg.PathRadiusZ
end

return ForkPath
