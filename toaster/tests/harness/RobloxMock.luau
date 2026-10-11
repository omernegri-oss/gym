-- A headless, deterministic stand-in for the Roblox engine, good enough to run
-- TOASTER's real server code end to end:
--  * datatypes (Vector3, CFrame, Color3, UDim2, Enum, Random, ...)
--  * Instances with parenting, attributes, tags and signals; member names are
--    validated against the real API (ApiMembers) so typos error like Roblox
--  * a virtual-time task scheduler (task.spawn/defer/delay/wait, os.clock)
--  * services: Players, Workspace, RunService, DataStoreService, ...
--  * minimal physics: gravity for server-owned assemblies, flat floors
-- It is NOT a physics engine or a renderer; it exists to catch runtime errors
-- and logic bugs in the game loop without Roblox Studio.

local ApiMembers = require("./generated/ApiMembers")

local Mock = {}

local errors: { string } = {}
local warnings: { string } = {}
Mock.Errors = errors
Mock.Warnings = warnings

------------------------------------------------------------------ datatypes

-- typeof that understands the mock datatypes (they carry __type on their metatable)
local function typeOf(value: any): string
	local mt = getmetatable(value)
	if type(mt) == "table" and rawget(mt, "__type") then
		return mt.__type
	end
	return type(value)
end

local function typed(name: string, mt: any)
	mt.__type = name
	return mt
end

-- Vector3
local Vector3 = {}
local V3 = typed("Vector3", {})
local function v3(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" or k == "y" or k == "z" then
		return v[string.upper(k)]
	end
	local method = Vector3[k]
	if method == nil then
		error(`{k} is not a valid member of Vector3`, 2)
	end
	return method
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z)
end
function Vector3.new(x: number?, y: number?, z: number?)
	return v3(x or 0, y or 0, z or 0)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

-- CFrame: position + row-major rotation matrix
local CFrame = {}
local CF = typed("CFrame", {})
local function cf(x, y, z, m)
	return setmetatable({ x = x, y = y, z = z, m = m }, CF)
end
local IDENTITY_M = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mulM(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotate(m, v)
	return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then
		return v3(c.x, c.y, c.z)
	elseif k == "X" then
		return c.x
	elseif k == "Y" then
		return c.y
	elseif k == "Z" then
		return c.z
	elseif k == "LookVector" then
		return v3(-c.m[3], -c.m[6], -c.m[9])
	elseif k == "RightVector" then
		return v3(c.m[1], c.m[4], c.m[7])
	elseif k == "UpVector" then
		return v3(c.m[2], c.m[5], c.m[8])
	elseif k == "Rotation" then
		return cf(0, 0, 0, c.m)
	end
	local method = CFrame[k]
	if method == nil then
		error(`{k} is not a valid member of CFrame`, 2)
	end
	return method
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		local p = rotate(a.m, v3(b.x, b.y, b.z))
		return cf(a.x + p.X, a.y + p.Y, a.z + p.Z, mulM(a.m, b.m))
	end
	local p = rotate(a.m, b)
	return v3(a.x + p.X, a.y + p.Y, a.z + p.Z)
end
CF.__add = function(a, v)
	return cf(a.x + v.X, a.y + v.Y, a.z + v.Z, a.m)
end
CF.__sub = function(a, v)
	return cf(a.x - v.X, a.y - v.Y, a.z - v.Z, a.m)
end
CF.__tostring = function(c)
	return string.format("CFrame(%.2f, %.2f, %.2f)", c.x, c.y, c.z)
end
function CFrame.new(a, b, c)
	if a == nil then
		return cf(0, 0, 0, IDENTITY_M)
	elseif type(a) == "number" then
		return cf(a, b, c, IDENTITY_M)
	end
	return cf(a.X, a.Y, a.Z, IDENTITY_M)
end
local function rx(t)
	local c, s = math.cos(t), math.sin(t)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(t)
	local c, s = math.cos(t), math.sin(t)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(t)
	local c, s = math.cos(t), math.sin(t)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
function CFrame.Angles(x, y, z)
	return cf(0, 0, 0, mulM(mulM(rx(x), ry(y)), rz(z)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = (target - at).Unit
	local right = look:Cross(up).Unit
	local realUp = right:Cross(look)
	local back = -look
	return cf(at.X, at.Y, at.Z, { right.X, realUp.X, back.X, right.Y, realUp.Y, back.Y, right.Z, realUp.Z, back.Z })
end
function CFrame.Inverse(c)
	local t = transpose(c.m)
	local p = rotate(t, v3(-c.x, -c.y, -c.z))
	return cf(p.X, p.Y, p.Z, t)
end
function CFrame.Lerp(a, b, t)
	return cf(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, if t < 0.5 then a.m else b.m)
end
function CFrame.PointToWorldSpace(c, v)
	return c * v
end
CFrame.identity = cf(0, 0, 0, IDENTITY_M)

local function plainType(name, fields: { string })
	local lib = {}
	local mt = typed(name, {})
	mt.__index = function(_, k)
		error(`{k} is not a valid member of {name}`, 2)
	end
	function lib.new(...)
		local args = { ... }
		local obj = {}
		for i, field in fields do
			obj[field] = args[i]
		end
		return setmetatable(obj, mt)
	end
	lib.__mt = mt
	return lib
end

local Color3 = plainType("Color3", { "R", "G", "B" })
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
local UDim = plainType("UDim", { "Scale", "Offset" })
local UDim2 = plainType("UDim2", { "XScale", "XOffset", "YScale", "YOffset" })
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x or 0, 0, y or 0)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x or 0, 0, y or 0, 0)
end
local Vector2 = plainType("Vector2", { "X", "Y" })
local NumberSequence = plainType("NumberSequence", { "A", "B" })
local ColorSequence = plainType("ColorSequence", { "A", "B" })
local NumberRange = plainType("NumberRange", { "Min", "Max" })
local TweenInfo = plainType("TweenInfo", { "Time", "EasingStyle", "EasingDirection" })

local Random = {}
local RandomMT = typed("Random", {})
RandomMT.__index = Random
local rngState = 12345
local function nextRand()
	-- deterministic LCG so runs are reproducible
	rngState = (rngState * 1103515245 + 12345) % 2147483648
	return rngState / 2147483648
end
function Random.new(_seed)
	return setmetatable({}, RandomMT)
end
function Random.NextNumber(_self, a, b)
	a, b = a or 0, b or 1
	return a + (b - a) * nextRand()
end
function Random.NextInteger(_self, a, b)
	return math.floor(a + (b - a + 1) * nextRand())
end
Mock.random = nextRand

-- Enum: Enum.X.Y returns a stable item
local enumItems = {}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = enumItems[enumName]
		if not items then
			items = setmetatable({}, {
				__index = function(t, itemName)
					local item = setmetatable(
						{ Name = itemName, EnumType = enumName, Value = 0 },
						typed("EnumItem", {
							__tostring = function()
								return `Enum.{enumName}.{itemName}`
							end,
						})
					)
					rawset(t, itemName, item)
					return item
				end,
			})
			enumItems[enumName] = items
		end
		return items
	end,
})

local RaycastParams = {}
function RaycastParams.new()
	return setmetatable({ FilterType = nil, FilterDescendantsInstances = {} }, typed("RaycastParams", {}))
end

------------------------------------------------------------------ scheduler

local clock = 0
local sequence = 0
local queue: { any } = {}
local cancelled: { [thread]: boolean } = {}

local function report(thread: thread, err: any)
	local message = tostring(err) .. "\n" .. debug.traceback(thread)
	table.insert(errors, message)
	print("SCRIPT ERROR: " .. message)
end

local function resume(thread: thread, ...)
	if cancelled[thread] or coroutine.status(thread) == "dead" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		report(thread, err)
	end
end

local function schedule(at: number, thread: thread, args: { any }?)
	sequence += 1
	table.insert(queue, { at = at, seq = sequence, thread = thread, args = args or {} })
end

local task = {}
function task.spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock, thread, { ... })
	return thread
end
function task.delay(seconds, fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	schedule(clock + (seconds or 0), thread, { ... })
	return thread
end
function task.wait(seconds)
	local thread = coroutine.running()
	local start = clock
	schedule(clock + math.max(seconds or 0, 1 / 60), thread)
	coroutine.yield()
	return clock - start
end
function task.cancel(thread)
	cancelled[thread] = true
end
Mock.task = task

function Mock.Now(): number
	return clock
end

-- Runs everything due at or before `untilTime`, firing Heartbeat every step.
local heartbeatStep: ((number) -> ())? = nil
function Mock.Advance(seconds: number, step: number?)
	local dt = step or 1 / 30
	local target = clock + seconds
	while clock < target - 1e-9 do
		local nextTime = math.min(clock + dt, target)
		-- run due threads in time order
		while true do
			local bestIndex, best = nil, nil
			for i, item in queue do
				if item.at <= nextTime + 1e-9 and (not best or item.at < best.at or (item.at == best.at and item.seq < best.seq)) then
					bestIndex, best = i, item
				end
			end
			if not bestIndex then
				break
			end
			table.remove(queue, bestIndex)
			clock = math.max(clock, best.at)
			resume(best.thread, table.unpack(best.args))
		end
		local elapsed = nextTime - clock
		clock = nextTime
		if heartbeatStep then
			heartbeatStep(math.max(elapsed, dt))
		end
	end
end

------------------------------------------------------------------ signals

local Connection = typed("RBXScriptConnection", {})
Connection.__index = Connection
function Connection.Disconnect(self)
	self.Connected = false
	local list = self.signal.handlers
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local Signal = typed("RBXScriptSignal", {})
Signal.__index = Signal
local function newSignal()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end
function Signal.Connect(self, fn)
	local connection = setmetatable({ Connected = true, signal = self, fn = fn }, Connection)
	table.insert(self.handlers, connection)
	return connection
end
function Signal.Once(self, fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end
function Signal.Wait(self)
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function Signal.Fire(self, ...)
	for _, connection in table.clone(self.handlers) do
		if connection.Connected then
			task.spawn(connection.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		resume(thread, ...)
	end
end
Mock.newSignal = newSignal

------------------------------------------------------------------ instances

local classInfo = ApiMembers
local memberCache: { [string]: { [string]: boolean } } = {}
local function membersOf(className: string): { [string]: boolean }
	local cached = memberCache[className]
	if cached then
		return cached
	end
	local set = {}
	local current = className
	while current do
		local info = classInfo[current]
		if not info then
			break
		end
		for _, member in info.Members do
			set[member] = true
		end
		current = info.Parent
	end
	memberCache[className] = set
	return set
end

local function isA(className: string, target: string): boolean
	local current = className
	while current do
		if current == target then
			return true
		end
		local info = classInfo[current]
		current = info and info.Parent
	end
	return false
end

local SIGNAL_MEMBERS = {
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	Destroying = true,
	AncestryChanged = true,
	Changed = true,
	Touched = true,
	TouchEnded = true,
	Died = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	CharacterAppearanceLoaded = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Event = true,
	Triggered = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
	PromptGamePassPurchaseFinished = true,
	Activated = true,
	MouseButton1Click = true,
	InputBegan = true,
}

local DEFAULTS: { [string]: any } = {
	Transparency = 0,
	Anchored = false,
	CanCollide = true,
	CanQuery = true,
	CanTouch = true,
	CollisionGroup = "Default",
	Massless = false,
	Health = 100,
	MaxHealth = 100,
	WalkSpeed = 16,
	JumpHeight = 7.2,
	PlatformStand = false,
	UseJumpPower = false,
	Enabled = true,
	MaxActivationDistance = 10,
	Reflectance = 0,
	Value = 0,
	Visible = true,
	FieldOfView = 70,
}

local Instance = {}
local InstanceMT = typed("Instance", {})
local instanceData: { [any]: any } = setmetatable({}, { __mode = "k" })
local tags: { [string]: { any } } = {}
local touchParts: { [any]: boolean } = {}
Mock.TouchParts = touchParts

local methods = {}

local function data(inst)
	return instanceData[inst]
end

InstanceMT.__index = function(inst, key)
	local d = data(inst)
	local props = d.props
	if props[key] ~= nil then
		return props[key]
	end
	if key == "Parent" then
		return nil
	end
	if SIGNAL_MEMBERS[key] then
		local signal = newSignal()
		props[key] = signal
		if key == "Touched" then
			touchParts[inst] = true
		end
		return signal
	end
	local special = d.getters and d.getters[key]
	if special then
		return special(inst)
	end
	local method = methods[key]
	if method then
		return method
	end
	-- child lookup by name, like Roblox
	for _, child in d.children do
		if data(child).props.Name == key then
			return child
		end
	end
	if membersOf(d.className)[key] or d.extra[key] then
		return DEFAULTS[key]
	end
	error(`{key} is not a valid member of {d.className} "{props.Name}"`, 2)
end

local function fireAncestorsDescendantAdded(parent, descendant)
	local current = parent
	while current do
		local props = data(current).props
		if rawget(props, "DescendantAdded") or props.DescendantAdded then
			props.DescendantAdded:Fire(descendant)
		end
		current = props.Parent
	end
end

local function setParent(inst, newParent)
	local d = data(inst)
	if d.destroyed then
		error(`The Parent property of {d.props.Name} is locked`, 3)
	end
	local old = d.props.Parent
	if old == newParent then
		return
	end
	if old then
		local siblings = data(old).children
		local index = table.find(siblings, inst)
		if index then
			table.remove(siblings, index)
		end
	end
	d.props.Parent = newParent
	if newParent then
		table.insert(data(newParent).children, inst)
		fireAncestorsDescendantAdded(newParent, inst)
		for _, descendant in methods.GetDescendants(inst) do
			fireAncestorsDescendantAdded(newParent, descendant)
		end
	end
end

local ALLOWED_ATTRIBUTE_TYPES = {
	string = true,
	number = true,
	boolean = true,
	Vector3 = true,
	Color3 = true,
	CFrame = true,
	UDim2 = true,
	UDim = true,
	Vector2 = true,
}

InstanceMT.__newindex = function(inst, key, value)
	local d = data(inst)
	if key == "Parent" then
		setParent(inst, value)
		return
	end
	if d.setters and d.setters[key] then
		d.setters[key](inst, value)
		return
	end
	if not membersOf(d.className)[key] and not d.extra[key] then
		error(`{key} is not a valid member of {d.className} "{d.props.Name}"`, 2)
	end
	if key == "CollisionGroup" and not Mock.CollisionGroups[value] and value ~= "Default" then
		error(`Collision group "{value}" is not registered`, 2)
	end
	d.props[key] = value
end

InstanceMT.__tostring = function(inst)
	return data(inst).props.Name
end

local function partGetters()
	return {
		Position = function(inst)
			local c = data(inst).props.CFrame
			return c.Position
		end,
	}
end

local function partSetters()
	return {
		Position = function(inst, value)
			local d = data(inst)
			local c = d.props.CFrame
			d.props.CFrame = cf(value.X, value.Y, value.Z, c.m)
		end,
	}
end

function Instance.new(className: string, parent: any?)
	if not classInfo[className] then
		error(`Unable to create an Instance of type "{className}"`, 2)
	end
	local inst = setmetatable({}, InstanceMT)
	local d = {
		className = className,
		props = { Name = className, ClassName = className },
		children = {},
		attributes = {},
		attributeSignals = {},
		extra = {},
	}
	instanceData[inst] = d
	if isA(className, "BasePart") then
		d.props.CFrame = CFrame.new()
		d.props.Size = Vector3.new(4, 1, 2)
		d.props.AssemblyLinearVelocity = Vector3.zero
		d.props.AssemblyAngularVelocity = Vector3.zero
		d.props.Color = Color3.new(0.6, 0.6, 0.6)
		d.getters = partGetters()
		d.setters = partSetters()
	end
	if className == "Humanoid" then
		d.props.MoveDirection = Vector3.zero
		d.props.CameraOffset = Vector3.zero
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
Mock.Instance = Instance
Mock.data = data

function methods.IsA(inst, className)
	return isA(data(inst).className, className)
end
function methods.GetChildren(inst)
	return table.clone(data(inst).children)
end
function methods.GetDescendants(inst)
	local result = {}
	local function walk(node)
		for _, child in data(node).children do
			table.insert(result, child)
			walk(child)
		end
	end
	walk(inst)
	return result
end
function methods.FindFirstChild(inst, name)
	for _, child in data(inst).children do
		if data(child).props.Name == name then
			return child
		end
	end
	return nil
end
function methods.FindFirstChildOfClass(inst, className)
	for _, child in data(inst).children do
		if data(child).className == className then
			return child
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(inst, className)
	for _, child in data(inst).children do
		if isA(data(child).className, className) then
			return child
		end
	end
	return nil
end
function methods.FindFirstAncestorOfClass(inst, className)
	local current = data(inst).props.Parent
	while current do
		if data(current).className == className then
			return current
		end
		current = data(current).props.Parent
	end
	return nil
end
function methods.IsDescendantOf(inst, ancestor)
	local current = data(inst).props.Parent
	while current do
		if current == ancestor then
			return true
		end
		current = data(current).props.Parent
	end
	return false
end
function methods.WaitForChild(inst, name, timeout)
	local deadline = clock + (timeout or 60)
	while true do
		local child = methods.FindFirstChild(inst, name)
		if child then
			return child
		end
		if clock >= deadline then
			return nil
		end
		task.wait(0.05)
	end
end
function methods.Destroy(inst)
	local d = data(inst)
	if d.destroyed then
		return
	end
	if rawget(d.props, "Destroying") then
		d.props.Destroying:Fire()
	end
	for _, child in table.clone(d.children) do
		methods.Destroy(child)
	end
	setParent(inst, nil)
	d.destroyed = true
	touchParts[inst] = nil
	for tag, list in tags do
		local index = table.find(list, inst)
		if index then
			table.remove(list, index)
		end
	end
end
function methods.ClearAllChildren(inst)
	for _, child in table.clone(data(inst).children) do
		methods.Destroy(child)
	end
end
function methods.Clone(inst)
	local d = data(inst)
	local copy = Instance.new(d.className)
	for key, value in d.props do
		if key ~= "Parent" and getmetatable(value) ~= Signal then
			data(copy).props[key] = value
		end
	end
	for _, child in d.children do
		methods.Clone(child).Parent = copy
	end
	return copy
end
function methods.SetAttribute(inst, name, value)
	if type(name) ~= "string" or #name > 100 or not string.match(name, "^[%w_]+$") then
		error(`Invalid attribute name "{name}"`, 2)
	end
	if value ~= nil and not ALLOWED_ATTRIBUTE_TYPES[typeOf(value)] then
		error(`{typeOf(value)} is not a supported attribute type ({name})`, 2)
	end
	local d = data(inst)
	local old = d.attributes[name]
	d.attributes[name] = value
	if old ~= value and d.attributeSignals[name] then
		d.attributeSignals[name]:Fire()
	end
end
function methods.GetAttribute(inst, name)
	return data(inst).attributes[name]
end
function methods.GetAttributes(inst)
	return table.clone(data(inst).attributes)
end
function methods.GetAttributeChangedSignal(inst, name)
	local d = data(inst)
	local signal = d.attributeSignals[name]
	if not signal then
		signal = newSignal()
		d.attributeSignals[name] = signal
	end
	return signal
end
function methods.GetPropertyChangedSignal(_inst, _name)
	return newSignal()
end
function methods.GetFullName(inst)
	local names = {}
	local current = inst
	while current do
		table.insert(names, 1, data(current).props.Name)
		current = data(current).props.Parent
	end
	return table.concat(names, ".")
end

-- Model pivots: move every BasePart descendant rigidly.
local function pivotOf(inst)
	local d = data(inst)
	if isA(d.className, "BasePart") then
		return d.props.CFrame
	end
	local primary = d.props.PrimaryPart or methods.FindFirstChild(inst, "HumanoidRootPart")
	if primary then
		return data(primary).props.CFrame
	end
	for _, descendant in methods.GetDescendants(inst) do
		if isA(data(descendant).className, "BasePart") then
			return data(descendant).props.CFrame
		end
	end
	return CFrame.new()
end
function methods.GetPivot(inst)
	return pivotOf(inst)
end
function methods.PivotTo(inst, target)
	local current = pivotOf(inst)
	local delta = target * CFrame.Inverse(current)
	local d = data(inst)
	if isA(d.className, "BasePart") then
		d.props.CFrame = target
		return
	end
	for _, descendant in methods.GetDescendants(inst) do
		local dd = data(descendant)
		if isA(dd.className, "BasePart") then
			dd.props.CFrame = delta * dd.props.CFrame
		end
	end
end
-- Parts welded to a root follow it (good enough for characters).
function methods.SetNetworkOwner(inst, owner)
	data(inst).networkOwner = owner or false
end
function methods.SetNetworkOwnershipAuto(inst)
	data(inst).networkOwner = nil
end
function methods.GetNetworkOwner(inst)
	return data(inst).networkOwner
end
function methods.ChangeState(inst, state)
	data(inst).lastState = state
end
function methods.Emit(_inst, _count) end
function methods.Play(_inst) end
function methods.Stop(_inst) end

------------------------------------------------------------------ remotes

local remoteLog: { any } = {}
Mock.RemoteLog = remoteLog

local function validatePayload(value: any, path: string, depth: number)
	local kind = typeOf(value)
	if kind == "function" or kind == "thread" or kind == "userdata" then
		error(`cannot send {kind} over a remote ({path})`, 4)
	end
	if kind == "table" then
		assert(depth < 20, "payload too deep")
		local hasArray, hasHash = #value > 0, false
		for k, v in value do
			if type(k) ~= "number" then
				hasHash = true
			end
			validatePayload(v, path .. "." .. tostring(k), depth + 1)
		end
		if hasArray and hasHash then
			error(`mixed table sent over a remote at {path} (Roblox drops one half)`, 4)
		end
	end
end

local attachedClients: { [any]: boolean } = {}
local localPlayerRef: { player: any } = { player = nil }
Mock.AttachedClients = attachedClients

local function deliver(remote, player, args)
	if attachedClients[player] then
		-- deferred, like real replication
		local copy = table.clone(args)
		task.defer(function()
			remote.OnClientEvent:Fire(table.unpack(copy))
		end)
	end
end

function methods.FireClient(remote, player, ...)
	if not player or not isA(data(player).className, "Player") then
		error("FireClient: argument 1 must be a Player", 2)
	end
	local args = { ... }
	for i, arg in args do
		validatePayload(arg, data(remote).props.Name .. "#" .. i, 0)
	end
	table.insert(remoteLog, { remote = data(remote).props.Name, player = player, args = args, time = clock })
	deliver(remote, player, args)
end
function methods.FireAllClients(remote, ...)
	local args = { ... }
	for i, arg in args do
		validatePayload(arg, data(remote).props.Name .. "#" .. i, 0)
	end
	table.insert(remoteLog, { remote = data(remote).props.Name, player = "all", args = args, time = clock })
	for player in attachedClients do
		deliver(remote, player, args)
	end
end
function methods.FireServer(remote, ...)
	local player = localPlayerRef.player
	local args = { ... }
	for i, arg in args do
		validatePayload(arg, data(remote).props.Name .. "#" .. i, 0)
	end
	task.defer(function()
		remote.OnServerEvent:Fire(player, table.unpack(args))
	end)
end
function methods.Fire(bindable, ...)
	bindable.Event:Fire(...)
end

------------------------------------------------------------------ services

local game = Instance.new("DataModel")
game.Name = "Game"
Mock.game = game

local workspace = Instance.new("Workspace")
workspace.Name = "Workspace"
workspace.Parent = game
data(workspace).props.Gravity = 196.2
Mock.workspace = workspace
do
	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	data(camera).props.CFrame = CFrame.new()
	data(camera).props.FieldOfView = 70
	data(camera).props.ViewportSize = Vector2.new(1280, 720)
	camera.Parent = workspace
	data(workspace).props.CurrentCamera = camera
end

local services: { [string]: any } = { Workspace = workspace }

local function service(name: string, className: string?): any
	local inst = Instance.new(className or "Folder")
	inst.Name = name
	inst.Parent = game
	services[name] = inst
	return inst
end

local Players = service("Players", "Players")
local players: { any } = {}
data(Players).extra.LocalPlayer = true
function methods.GetPlayers(_)
	return table.clone(players)
end
function methods.GetPlayerFromCharacter(_, character)
	for _, player in players do
		if data(player).props.Character == character then
			return player
		end
	end
	return nil
end
function methods.GetPlayerByUserId(_, userId)
	for _, player in players do
		if data(player).props.UserId == userId then
			return player
		end
	end
	return nil
end

service("ReplicatedStorage")
service("ServerScriptService")
service("ServerStorage")
service("StarterPlayer")
service("SoundService")
service("Lighting", "Lighting")

-- CollectionService
local CollectionService = { Name = "CollectionService" }
function CollectionService.AddTag(_, inst, tag)
	tags[tag] = tags[tag] or {}
	if not table.find(tags[tag], inst) then
		table.insert(tags[tag], inst)
	end
end
function CollectionService.GetTagged(_, tag)
	return table.clone(tags[tag] or {})
end
function CollectionService.HasTag(_, inst, tag)
	return tags[tag] ~= nil and table.find(tags[tag], inst) ~= nil
end
services.CollectionService = CollectionService

-- PhysicsService
Mock.CollisionGroups = { Default = true }
Mock.Collidable = {}
local PhysicsService = {}
function PhysicsService.RegisterCollisionGroup(_, name)
	Mock.CollisionGroups[name] = true
end
function PhysicsService.IsCollisionGroupRegistered(_, name)
	return Mock.CollisionGroups[name] == true
end
function PhysicsService.CollisionGroupSetCollidable(_, a, b, collidable)
	assert(Mock.CollisionGroups[a] and Mock.CollisionGroups[b], `unregistered collision group {a}/{b}`)
	Mock.Collidable[a .. "|" .. b] = collidable
	Mock.Collidable[b .. "|" .. a] = collidable
end
services.PhysicsService = PhysicsService

-- RunService
local heartbeat = newSignal()
local RunService = { Heartbeat = heartbeat, Stepped = newSignal() }
function RunService.IsStudio(_)
	return true
end
function RunService.IsServer(_)
	return true
end
function RunService.IsClient(_)
	return false
end
services.RunService = RunService

-- Debris
local Debris = {}
function Debris.AddItem(_, inst, lifetime)
	task.delay(lifetime or 10, function()
		methods.Destroy(inst)
	end)
end
services.Debris = Debris

-- DataStoreService (in-memory, JSON-like validation)
Mock.DataStoreFailures = 0 -- number of upcoming calls that should fail
Mock.Stores = {}
local function validateStorable(value: any, path: string)
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`cannot store NaN/inf at {path}`)
		end
	elseif kind == "table" then
		local hasArray, hasHash = #value > 0, false
		for k, v in value do
			if type(k) ~= "number" then
				hasHash = true
			end
			if type(k) ~= "string" and type(k) ~= "number" then
				error(`invalid key at {path}`)
			end
			validateStorable(v, path .. "." .. tostring(k))
		end
		if hasArray and hasHash then
			error(`mixed table cannot be stored at {path}`)
		end
	elseif kind ~= "string" and kind ~= "boolean" and kind ~= "nil" then
		error(`cannot store {kind} at {path}`)
	end
end
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end
local function maybeFail()
	if Mock.DataStoreFailures > 0 then
		Mock.DataStoreFailures -= 1
		error("502: simulated DataStore outage")
	end
	task.wait(0.05)
end
local DataStoreService = {}
function DataStoreService.GetDataStore(_, name)
	local backing = Mock.Stores[name] or {}
	Mock.Stores[name] = backing
	local store = {}
	function store.GetAsync(_, key)
		maybeFail()
		return deepCopy(backing[key])
	end
	function store.SetAsync(_, key, value)
		maybeFail()
		validateStorable(value, key)
		backing[key] = deepCopy(value)
	end
	function store.UpdateAsync(_, key, transform)
		maybeFail()
		local result = transform(deepCopy(backing[key]))
		if result ~= nil then
			validateStorable(result, key)
			backing[key] = deepCopy(result)
		end
		return result
	end
	return store
end
services.DataStoreService = DataStoreService

-- MarketplaceService
local MarketplaceService = { PromptGamePassPurchaseFinished = newSignal(), Prompts = {} }
function MarketplaceService.PromptGamePassPurchase(_, player, id)
	table.insert(MarketplaceService.Prompts, { player = player, id = id })
end
function MarketplaceService.PromptProductPurchase(_, player, id)
	table.insert(MarketplaceService.Prompts, { player = player, id = id })
end
function MarketplaceService.UserOwnsGamePassAsync(_, _userId, _id)
	return false
end
services.MarketplaceService = MarketplaceService

-- TweenService: applies the goal when the tween finishes and fires Completed.
local TweenService = {}
function TweenService.Create(_, inst, info, goal)
	for k in goal do
		local _ = inst[k] -- validates the property exists
	end
	local tween = { Completed = newSignal(), cancelled = false }
	function tween.Play(_self)
		task.delay(info and info.Time or 0, function()
			if tween.cancelled then
				return
			end
			if not data(inst).destroyed then
				for k, v in goal do
					inst[k] = v
				end
			end
			tween.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel(_self)
		tween.cancelled = true
	end
	return tween
end
services.TweenService = TweenService

-- Client-side services
local renderStepped = newSignal()
local renderBindings: { [string]: (number) -> () } = {}
RunService.RenderStepped = renderStepped
function RunService.BindToRenderStep(_, name, _priority, fn)
	renderBindings[name] = fn
end
function RunService.UnbindFromRenderStep(_, name)
	renderBindings[name] = nil
end
local UserInputService = { TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false, InputBegan = newSignal() }
services.UserInputService = UserInputService
local boundActions: { [string]: any } = {}
Mock.BoundActions = boundActions
local ContextActionService = {}
function ContextActionService.BindAction(_, name, fn, _touch, ...)
	boundActions[name] = { fn = fn, keys = { ... } }
end
function ContextActionService.UnbindAction(_, name)
	boundActions[name] = nil
end
services.ContextActionService = ContextActionService
function methods.PlayLocalSound(_, sound)
	assert(sound ~= nil, "PlayLocalSound needs a sound")
end

local bindToClose: { () -> () } = {}
Mock.BindToClose = bindToClose
function methods.GetService(_, name)
	local s = services[name]
	if not s then
		error(`mock has no service {name}`, 2)
	end
	return s
end
function methods.BindToClose(_, fn)
	table.insert(bindToClose, fn)
end

-- workspace methods
function methods.GetServerTimeNow(_)
	return clock + 1000
end

-- Ray vs rotated part AABBs
function methods.Raycast(_, origin, direction, params)
	local excluded = {}
	if params and params.FilterDescendantsInstances then
		for _, inst in params.FilterDescendantsInstances do
			excluded[inst] = true
		end
	end
	local function isExcluded(inst)
		local current = inst
		while current do
			if excluded[current] then
				return true
			end
			current = data(current).props.Parent
		end
		return false
	end
	local bestT, bestPart = math.huge, nil
	for _, inst in methods.GetDescendants(workspace) do
		local d = data(inst)
		if isA(d.className, "BasePart") and d.props.CanQuery ~= false and d.props.Transparency ~= 1 and not isExcluded(inst) then
			local c, size = d.props.CFrame, d.props.Size
			local m = c.m
			local hx = math.abs(m[1]) * size.X / 2 + math.abs(m[2]) * size.Y / 2 + math.abs(m[3]) * size.Z / 2
			local hy = math.abs(m[4]) * size.X / 2 + math.abs(m[5]) * size.Y / 2 + math.abs(m[6]) * size.Z / 2
			local hz = math.abs(m[7]) * size.X / 2 + math.abs(m[8]) * size.Y / 2 + math.abs(m[9]) * size.Z / 2
			local tmin, tmax = 0, 1
			local ok = true
			for _, axis in { { origin.X, direction.X, c.x, hx }, { origin.Y, direction.Y, c.y, hy }, { origin.Z, direction.Z, c.z, hz } } do
				local o, dir, center, half = axis[1], axis[2], axis[3], axis[4]
				if math.abs(dir) < 1e-9 then
					if o < center - half or o > center + half then
						ok = false
					end
				else
					local t1 = (center - half - o) / dir
					local t2 = (center + half - o) / dir
					if t1 > t2 then
						t1, t2 = t2, t1
					end
					tmin = math.max(tmin, t1)
					tmax = math.min(tmax, t2)
					if tmin > tmax then
						ok = false
					end
				end
			end
			if ok and tmin < bestT then
				bestT, bestPart = tmin, inst
			end
		end
	end
	if not bestPart then
		return nil
	end
	return { Position = origin + direction * bestT, Instance = bestPart, Distance = direction.Magnitude * bestT }
end

------------------------------------------------------------------ players & characters

local nextUserId = 1000
local function buildCharacter(player)
	local character = Instance.new("Model")
	character.Name = data(player).props.Name
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = character
	for _, name in { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" } do
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(1, 1, 1)
		p.Parent = character
		if name == "Head" then
			local face = Instance.new("Decal")
			face.Name = "face"
			face.Parent = p
		end
	end
	character.PrimaryPart = root
	-- spawn at the SpawnLocation
	local spawnPosition = Vector3.new(0, 5, 0)
	for _, inst in methods.GetDescendants(workspace) do
		if data(inst).className == "SpawnLocation" then
			spawnPosition = data(inst).props.CFrame.Position + Vector3.new(0, 3, 0)
		end
	end
	methods.PivotTo(character, CFrame.new(spawnPosition))
	return character
end

local function loadCharacter(player)
	task.wait(0.1) -- yields like the real API
	local d = data(player)
	local old = d.props.Character
	if old then
		player.CharacterRemoving:Fire(old)
		methods.Destroy(old)
	end
	local character = buildCharacter(player)
	d.props.Character = character
	character.Parent = workspace
	player.CharacterAdded:Fire(character)
end
function methods.LoadCharacterWithHumanoidDescriptionAsync(player, description)
	assert(description ~= nil and isA(data(description).className, "HumanoidDescription"), "description required")
	loadCharacter(player)
end
function methods.LoadCharacterAsync(player)
	loadCharacter(player)
end
function methods.Kick(player)
	Mock.RemovePlayer(player)
end

function Mock.AddPlayer(name: string): any
	nextUserId += 1
	local player = Instance.new("Player")
	local d = data(player)
	d.props.Name = name
	d.props.DisplayName = name
	d.props.UserId = nextUserId
	d.props.Character = nil
	d.extra.Character = true
	player.Parent = Players
	table.insert(players, player)
	Players.PlayerAdded:Fire(player)
	return player
end

function Mock.AttachClient(player: any)
	attachedClients[player] = true
	localPlayerRef.player = player
	data(services.Players).props.LocalPlayer = player
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	local scripts = Instance.new("PlayerScripts")
	scripts.Name = "PlayerScripts"
	scripts.Parent = player
	return scripts
end

function Mock.RemovePlayer(player: any)
	local index = table.find(players, player)
	if not index then
		return
	end
	attachedClients[player] = nil
	Players.PlayerRemoving:Fire(player)
	table.remove(players, index)
	local character = data(player).props.Character
	player.Parent = nil
	if character then
		methods.Destroy(character)
	end
end

function Mock.Kill(player: any)
	local character = data(player).props.Character
	local humanoid = character and methods.FindFirstChildOfClass(character, "Humanoid")
	if humanoid then
		data(humanoid).props.Health = 0
		humanoid.Died:Fire()
	end
end

------------------------------------------------------------------ minimal physics + touch

local contacts: { [any]: { [any]: boolean } } = {}

-- Static collision geometry: anchored, collidable parts bucketed in a grid.
local CELL = 16
local grid: { [string]: { any } } = {}
local gridBuilt = false
local CLIMB = 7.5 -- a humanoid can jump onto anything this high

local function partBox(d)
	local c, size = d.props.CFrame, d.props.Size
	local m = c.m
	local hx = math.abs(m[1]) * size.X / 2 + math.abs(m[2]) * size.Y / 2 + math.abs(m[3]) * size.Z / 2
	local hy = math.abs(m[4]) * size.X / 2 + math.abs(m[5]) * size.Y / 2 + math.abs(m[6]) * size.Z / 2
	local hz = math.abs(m[7]) * size.X / 2 + math.abs(m[8]) * size.Y / 2 + math.abs(m[9]) * size.Z / 2
	return {
		minX = c.x - hx,
		maxX = c.x + hx,
		minY = c.y - hy,
		maxY = c.y + hy,
		minZ = c.z - hz,
		maxZ = c.z + hz,
		group = d.props.CollisionGroup or "Default",
	}
end

function Mock.BuildCollisionGrid()
	table.clear(grid)
	for _, inst in methods.GetDescendants(workspace) do
		local d = data(inst)
		if isA(d.className, "BasePart") and d.props.Anchored == true and d.props.CanCollide ~= false then
			local box = partBox(d)
			for cx = math.floor(box.minX / CELL), math.floor(box.maxX / CELL) do
				for cz = math.floor(box.minZ / CELL), math.floor(box.maxZ / CELL) do
					local key = cx .. ":" .. cz
					grid[key] = grid[key] or {}
					table.insert(grid[key], box)
				end
			end
		end
	end
	gridBuilt = true
end

local function collides(a: string, b: string): boolean
	return Mock.Collidable[a .. "|" .. b] ~= false
end

-- Highest walkable surface under (x, z) that a body with feet at `feetY`
-- can stand on (at most CLIMB above the feet). Returns floor, blocked.
local function surfaceAt(x: number, z: number, feetY: number, group: string, climb: number): (number, boolean)
	local best = -math.huge
	local blocked = false
	local cell = grid[math.floor(x / CELL) .. ":" .. math.floor(z / CELL)]
	if cell then
		for _, box in cell do
			if x >= box.minX and x <= box.maxX and z >= box.minZ and z <= box.maxZ and collides(group, box.group) then
				if box.maxY <= feetY + climb then
					if box.maxY > best then
						best = box.maxY
					end
				elseif box.minY < feetY + 5 then
					blocked = true -- a wall in the way
				end
			end
		end
	end
	return best, blocked
end

local function floorAt(p, group)
	if not gridBuilt then
		return 0
	end
	local floor = surfaceAt(p.X, p.Z, p.Y - 3, group, 3)
	return if floor == -math.huge then -500 else floor
end
Mock.FloorAt = floorAt

local function stepPhysics(dt: number)
	for _, player in players do
		local character = data(player).props.Character
		local root = character and methods.FindFirstChild(character, "HumanoidRootPart")
		if root then
			local rd = data(root)
			local humanoid = methods.FindFirstChildOfClass(character, "Humanoid")
			local pos = rd.props.CFrame.Position
			local vel = rd.props.AssemblyLinearVelocity
			local group = rd.props.CollisionGroup or "Default"
			if rd.networkOwner == false then
				-- server-simulated (launched): ballistic
				vel = vel - Vector3.new(0, workspace.Gravity * dt, 0)
				local nextPos = pos + vel * dt
				-- sweep the whole step so fast falls can't tunnel through floors
				local floor = surfaceAt(nextPos.X, nextPos.Z, nextPos.Y - 1, group, math.max(1, pos.Y - nextPos.Y + 1))
				if nextPos.Y <= floor + 1 and vel.Y < 0 then
					nextPos = Vector3.new(nextPos.X, floor + 1, nextPos.Z)
					vel = Vector3.zero
				end
				methods.PivotTo(character, CFrame.new(nextPos))
				rd.props.AssemblyLinearVelocity = vel
			else
				-- client-simulated: bots steer towards a target at WalkSpeed
				local target = data(player).moveTarget
				local speed = humanoid and data(humanoid).props.WalkSpeed or 16
				local feet = pos.Y - 3
				if target and speed > 0 then
					local flat = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
					local dist = flat.Magnitude
					if dist > 0.5 then
						local nextPos = pos + flat.Unit * math.min(dist, speed * dt)
						local floor, blocked = surfaceAt(nextPos.X, nextPos.Z, feet, group, CLIMB)
						if not blocked and floor > -math.huge then
							pos = nextPos
						end
					end
				end
				local floor = surfaceAt(pos.X, pos.Z, feet, group, CLIMB)
				if floor == -math.huge then
					floor = feet - 2 -- nothing below: fall
				end
				methods.PivotTo(character, CFrame.new(Vector3.new(pos.X, math.max(floor, feet - 40 * dt) + 3, pos.Z)))
				rd.props.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end

	-- Touch detection: character roots vs parts with Touched listeners
	for part in touchParts do
		local pd = data(part)
		if pd.destroyed or pd.props.CanTouch == false or not methods.IsDescendantOf(part, workspace) then
			contacts[part] = nil
		else
			local c, size = pd.props.CFrame, pd.props.Size
			local inside = {}
			for _, player in players do
				local character = data(player).props.Character
				local root = character and methods.FindFirstChild(character, "HumanoidRootPart")
				if root then
					local p = data(root).props.CFrame.Position
					local touching = math.abs(p.X - c.x) <= size.X / 2 + 1.5
						and math.abs(p.Y - c.y) <= size.Y / 2 + 3
						and math.abs(p.Z - c.z) <= size.Z / 2 + 1.5
					if touching then
						inside[root] = true
						if not (contacts[part] and contacts[part][root]) then
							pd.props.Touched:Fire(root)
						end
					end
				end
			end
			contacts[part] = inside
		end
	end
end

heartbeatStep = function(dt)
	stepPhysics(dt)
	heartbeat:Fire(dt)
	if next(attachedClients) then
		renderStepped:Fire(dt)
		for _, fn in renderBindings do
			task.spawn(fn, dt)
		end
	end
end

function Mock.MoveTo(player: any, target: Vector3?)
	data(player).moveTarget = target
end

function Mock.Teleport(player: any, position: Vector3)
	local character = data(player).props.Character
	if character then
		methods.PivotTo(character, CFrame.new(position))
	end
	data(player).moveTarget = nil
end

------------------------------------------------------------------ environment

local typeof_ = typeOf
Mock.typeof = typeOf

local osProxy = setmetatable({
	clock = function()
		return clock
	end,
}, { __index = os })

function Mock.Environment(scriptInstance: any, requireFn: (any) -> any)
	return setmetatable({
		game = game,
		workspace = workspace,
		script = scriptInstance,
		require = requireFn,
		task = task,
		os = osProxy,
		typeof = typeof_,
		warn = function(...)
			local parts = {}
			for _, v in { ... } do
				table.insert(parts, tostring(v))
			end
			local message = table.concat(parts, " ")
			table.insert(warnings, message)
			print("WARN: " .. message)
		end,
		print = function(...)
			print(...)
		end,
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		Color3 = Color3,
		UDim = UDim,
		UDim2 = UDim2,
		NumberSequence = NumberSequence,
		ColorSequence = ColorSequence,
		NumberRange = NumberRange,
		TweenInfo = TweenInfo,
		Random = Random,
		Enum = Enum,
		RaycastParams = RaycastParams,
	}, { __index = _G })
end

return Mock
