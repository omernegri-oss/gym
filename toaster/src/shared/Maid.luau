-- Owns cleanup for connections, instances, threads and callbacks so every
-- event connection has an explicit lifecycle.

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { [any]: any } }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {} }, Maid)
end

local function cleanupTask(job: any)
	local kind = typeof(job)
	if kind == "RBXScriptConnection" then
		job:Disconnect()
	elseif kind == "Instance" then
		job:Destroy()
	elseif kind == "function" then
		job()
	elseif kind == "thread" then
		if coroutine.status(job) ~= "dead" then
			pcall(task.cancel, job)
		end
	elseif kind == "table" and type(job.Destroy) == "function" then
		job:Destroy()
	end
end

-- Adds a task; returns it for convenience.
function Maid.Give<T>(self: Maid, job: T): T
	table.insert(self._tasks, job)
	return job
end

-- Named task: replacing a name cleans the previous task.
function Maid.Set(self: Maid, name: string, job: any)
	local previous = self._tasks[name]
	self._tasks[name] = job
	if previous ~= nil and previous ~= job then
		cleanupTask(previous)
	end
end

function Maid.Clean(self: Maid)
	local tasks = self._tasks
	self._tasks = {}
	for _, job in tasks do
		cleanupTask(job)
	end
end

Maid.Destroy = Maid.Clean

return Maid
