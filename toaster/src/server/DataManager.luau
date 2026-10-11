-- Persistent player data with safe DataStore patterns:
--  * load with retries; on failure the session is marked unsaveable so valid
--    saved data is never overwritten with defaults
--  * every load is reconciled/sanitised (corruption protection)
--  * UpdateAsync saves with retries, on leave, on autosave and on shutdown
--  * saves only when something changed

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local DataSchema = require(Shared.DataSchema)
local Progression = require(Shared.Progression)

local DataManager = {}

type Profile = {
	Data: any,
	Loaded: boolean, -- true only when the stored value was read successfully
	Dirty: boolean,
	Saving: boolean,
}

local profiles: { [Player]: Profile } = {}
local loadedSignal = Instance.new("BindableEvent")
local store: DataStore? = nil
local services

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- Errors that will never succeed on retry (e.g. Studio without API access).
local function isPermanent(err: any): boolean
	local message = tostring(err)
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "403", 1, true) ~= nil
		or string.find(message, "must publish", 1, true) ~= nil
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	local cfg = Config.Data
	for attempt = 1, cfg.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataManager] {label} failed (attempt {attempt}/{cfg.MaxRetries}): {result}`)
		if isPermanent(result) then
			break
		end
		if attempt < cfg.MaxRetries then
			task.wait(cfg.RetryDelay * attempt)
		end
	end
	return false, nil
end

local function publishAttributes(player: Player, data: any)
	player:SetAttribute(Constants.Attr.Crumbs, data.Crumbs)
	player:SetAttribute(Constants.Attr.XP, data.XP)
	player:SetAttribute(Constants.Attr.Level, Progression.LevelForXP(data.XP, Config.Progression.LevelXP))
	player:SetAttribute(Constants.Attr.Bread, data.EquippedBread)
	player:SetAttribute(Constants.Attr.Title, data.EquippedTitle)
	player:SetAttribute(Constants.Attr.Streak, data.Statistics.SurvivalStreak)
end

function DataManager.Init(registry)
	services = registry
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataManager] DataStores unavailable; progress will not be saved this session:", result)
	end
end

function DataManager.Load(player: Player)
	local profile: Profile = { Data = DataSchema.Default(), Loaded = false, Dirty = false, Saving = false }
	profiles[player] = profile

	if store then
		local key = keyFor(player)
		local ok, raw = withRetries("Load " .. key, function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok then
			local data, recognised = DataSchema.Reconcile(raw)
			if raw ~= nil and not recognised then
				-- Corrupt value: keep a copy under a backup key before we ever overwrite it.
				warn("[DataManager] Unrecognised save for", key, "- backing it up")
				pcall(function()
					(store :: DataStore):SetAsync(key .. "_corrupt_" .. os.time(), raw)
				end)
			end
			profile.Data = data
			profile.Loaded = true
		end
	end

	if player.Parent ~= Players then
		profiles[player] = nil
		return
	end

	-- Achievement-linked flags are derived from data so they stay consistent.
	if profile.Data.UnlockedBreads.Waffle then
		profile.Data.Statistics.WaffleUnlocked = 1
	end
	publishAttributes(player, profile.Data)
	player:SetAttribute(Constants.Attr.DataLoaded, true)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local crumbs = Instance.new("IntValue")
	crumbs.Name = "Crumbs"
	crumbs.Value = profile.Data.Crumbs
	crumbs.Parent = leaderstats
	local best = Instance.new("IntValue")
	best.Name = "Best"
	best.Value = profile.Data.Statistics.BestLandingScore
	best.Parent = leaderstats
	leaderstats.Parent = player

	if not profile.Loaded and store then
		services.Messaging.Notify(player, "⚠️ Couldn't load your save. Progress this session won't be saved.", "Warning", 6)
	end
	loadedSignal:Fire(player)
end

function DataManager.Get(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data
end

function DataManager.IsLoaded(player: Player): boolean
	return player:GetAttribute(Constants.Attr.DataLoaded) == true
end

-- All mutations go through Update so the profile is marked dirty and
-- replicated attributes stay in sync.
function DataManager.Update(player: Player, mutator: (data: any) -> ())
	local profile = profiles[player]
	if not profile then
		return
	end
	mutator(profile.Data)
	profile.Dirty = true
	publishAttributes(player, profile.Data)
	local leaderstats: any = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Crumbs.Value = profile.Data.Crumbs
		leaderstats.Best.Value = profile.Data.Statistics.BestLandingScore
	end
end

function DataManager.Save(player: Player, force: boolean?)
	local profile = profiles[player]
	if not profile or not store then
		return
	end
	if not profile.Loaded then
		return -- never overwrite real data with defaults after a failed load
	end
	if (not profile.Dirty and not force) or profile.Saving then
		return
	end
	profile.Saving = true
	profile.Dirty = false
	local snapshot = deepCopy(profile.Data)
	local key = keyFor(player)
	local ok = withRetries("Save " .. key, function()
		return (store :: DataStore):UpdateAsync(key, function(_old)
			return snapshot
		end)
	end)
	if not ok then
		profile.Dirty = true
	end
	profile.Saving = false
end

function DataManager.OnLoaded(callback: (Player) -> ()): RBXScriptConnection
	return loadedSignal.Event:Connect(callback)
end

function DataManager.Release(player: Player)
	DataManager.Save(player)
	profiles[player] = nil
end

function DataManager.Start()
	Players.PlayerRemoving:Connect(function(player)
		DataManager.Release(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in profiles do
				task.spawn(DataManager.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataManager.Save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataManager
