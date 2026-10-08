-- Owns per-player session state, character spawning/respawning, bread
-- appearance and movement stats, and teleports between lobby/toaster/field.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BreadDefinitions = require(Shared.BreadDefinitions)
local BreadVisuals = require(Shared.BreadVisuals)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Maid = require(Shared.Maid)
local Theme = require(Shared.Theme)

local PlayerManager = {}

local ATTR = Constants.Attr
local PHASES = Constants.Phases

export type Session = {
	Player: Player,
	Maid: any, -- character-scoped connections
	InRound: boolean,
	Heat: number,
	HeatState: string,
	HeatZone: string,
	LastReplicatedHeat: number,
	LastToastBucket: number,
	IsCharcoal: boolean,
	CharcoalRoundsLeft: number,
	BurntThisRound: boolean,
	ButterCarried: number,
	ShieldEndsAt: number,
	ShieldActive: boolean,
	UsedButterThisRound: boolean,
	ResistUntil: number,
	ResistMultiplier: number,
	BlackenedUntil: number,
	StuckUntil: number,
	RoundCrumbs: number,
	Survived: boolean,
	Golden: boolean,
	Landed: boolean,
	LandingZoneId: string?,
	LandingZoneName: string?,
	LandingPoints: number,
	RewardGranted: boolean,
	Reward: any?,
	Cooldowns: { [string]: number },
}

local sessions: { [Player]: Session } = {}
local services
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function newSession(player: Player): Session
	return {
		Player = player,
		Maid = Maid.new(),
		InRound = false,
		Heat = 0,
		HeatState = "Normal",
		HeatZone = "Center",
		LastReplicatedHeat = -1,
		LastToastBucket = -1,
		IsCharcoal = false,
		CharcoalRoundsLeft = 0,
		BurntThisRound = false,
		ButterCarried = 0,
		ShieldEndsAt = 0,
		ShieldActive = false,
		UsedButterThisRound = false,
		ResistUntil = 0,
		ResistMultiplier = 1,
		BlackenedUntil = 0,
		StuckUntil = 0,
		RoundCrumbs = 0,
		Survived = false,
		Golden = false,
		Landed = false,
		LandingZoneId = nil,
		LandingZoneName = nil,
		LandingPoints = 0,
		RewardGranted = false,
		Reward = nil,
		Cooldowns = {},
	}
end

function PlayerManager.Init(registry)
	services = registry
end

function PlayerManager.Get(player: Player): Session?
	return sessions[player]
end

function PlayerManager.All(): { [Player]: Session }
	return sessions
end

function PlayerManager.InRound(): { Session }
	local list = {}
	for _, session in sessions do
		if session.InRound then
			table.insert(list, session)
		end
	end
	return list
end

function PlayerManager.CountInRound(): number
	local count = 0
	for _, session in sessions do
		if session.InRound then
			count += 1
		end
	end
	return count
end

-- Root + humanoid if the character is alive, else nil.
function PlayerManager.GetBody(session: Session): (BasePart?, Humanoid?)
	local character = session.Player.Character
	if not character then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

function PlayerManager.ReadyPlayers(): { Player }
	local list = {}
	for player, session in sessions do
		if services.DataManager.IsLoaded(player) and PlayerManager.GetBody(session) then
			table.insert(list, player)
		end
	end
	return list
end

function PlayerManager.SetAttr(session: Session, name: string, value: any)
	session.Player:SetAttribute(name, value)
end

function PlayerManager.EquippedBread(session: Session): string
	local data = services.DataManager.Get(session.Player)
	local breadId = data and data.EquippedBread or BreadDefinitions.Default
	if not BreadDefinitions.ById[breadId] then
		breadId = BreadDefinitions.Default
	end
	return breadId
end

function PlayerManager.RefreshMovement(session: Session)
	local _, humanoid = PlayerManager.GetBody(session)
	if not humanoid then
		return
	end
	local def = BreadDefinitions.ById[PlayerManager.EquippedBread(session)]
	humanoid.UseJumpPower = false
	if now() < session.StuckUntil then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
	elseif session.IsCharcoal then
		humanoid.WalkSpeed = Config.Charcoal.WalkSpeed
		humanoid.JumpHeight = def.JumpHeight * 0.8
	else
		humanoid.WalkSpeed = def.WalkSpeed
		humanoid.JumpHeight = def.JumpHeight
	end
end

-- Colours, particles and shield bubble from the current session state.
function PlayerManager.RefreshAppearance(session: Session)
	local model = BreadVisuals.Get(session.Player.Character)
	if not model then
		return
	end
	local mode = "Normal"
	local effect = session.HeatState
	if session.IsCharcoal then
		mode, effect = "Charcoal", "Burnt"
	elseif session.Golden then
		mode, effect = "Golden", "Golden"
	elseif now() < session.BlackenedUntil then
		mode = "Blackened"
	end
	BreadVisuals.SetToast(model, session.Heat, mode)
	BreadVisuals.SetEffects(model, effect)
	BreadVisuals.SetShield(model, session.ShieldActive)
end

function PlayerManager.RebuildBread(session: Session)
	local character = session.Player.Character
	if not character then
		return
	end
	local data = services.DataManager.Get(session.Player)
	local breadId = PlayerManager.EquippedBread(session)
	BreadVisuals.Apply(character, breadId, data and data.EquippedCosmetics or nil)
	session.Player:SetAttribute(ATTR.Bread, breadId)
	PlayerManager.RefreshAppearance(session)
	PlayerManager.RefreshMovement(session)
end

function PlayerManager.SetCollisionGroup(character: Model, group: string)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

local function placeCharacter(session: Session, position: Vector3)
	local root = PlayerManager.GetBody(session)
	local character = session.Player.Character
	if not root or not character then
		return
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
end

function PlayerManager.TeleportToLobby(session: Session)
	local info = services.MapBuilder.Info
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0, info.LobbySpawnRadius)
	placeCharacter(session, info.LobbyCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
end

-- Picks the toaster spawn farthest from every other player, so nobody stacks.
function PlayerManager.TeleportToToaster(session: Session, spawnPosition: Vector3?)
	local info = services.MapBuilder.Info
	local target = spawnPosition
	if not target then
		local others = {}
		for _, other in sessions do
			if other ~= session then
				local root = PlayerManager.GetBody(other)
				if root then
					table.insert(others, root.Position)
				end
			end
		end
		local best, bestScore = info.ToasterSpawns[1], -1
		for _, candidate in info.ToasterSpawns do
			local nearest = math.huge
			for _, pos in others do
				nearest = math.min(nearest, (pos - candidate).Magnitude)
			end
			local score = nearest + rng:NextNumber(0, 2)
			if score > bestScore then
				best, bestScore = candidate, score
			end
		end
		target = best
	end
	placeCharacter(session, target :: Vector3)
end

function PlayerManager.ResetRoundState(session: Session)
	session.Heat = if session.IsCharcoal then Config.Heat.MaxHeat else 0
	session.HeatState = if session.IsCharcoal then "Burnt" else "Normal"
	session.HeatZone = "Center"
	session.LastReplicatedHeat = -1
	session.LastToastBucket = -1
	session.BurntThisRound = false
	session.ButterCarried = 0
	session.ShieldEndsAt = 0
	session.ShieldActive = false
	session.UsedButterThisRound = false
	session.ResistUntil = 0
	session.BlackenedUntil = 0
	session.StuckUntil = 0
	session.RoundCrumbs = 0
	session.Survived = false
	session.Golden = false
	session.Landed = false
	session.LandingZoneId = nil
	session.LandingZoneName = nil
	session.LandingPoints = 0
	session.RewardGranted = false
	session.Reward = nil
	table.clear(session.Cooldowns)

	local player = session.Player
	player:SetAttribute(ATTR.Heat, session.Heat)
	player:SetAttribute(ATTR.HeatState, session.HeatState)
	player:SetAttribute(ATTR.HeatZone, session.HeatZone)
	player:SetAttribute(ATTR.ButterCarried, 0)
	player:SetAttribute(ATTR.ShieldEndsAt, 0)
	player:SetAttribute(ATTR.RoundCrumbs, 0)
	player:SetAttribute(ATTR.IsCharcoal, session.IsCharcoal)
	for _, key in { "Ability", "Jam", "Nutella" } do
		player:SetAttribute(ATTR.CooldownPrefix .. key, 0)
	end
	local character = player.Character
	if character then
		character:SetAttribute(Constants.CharAttr.Golden, false)
		character:SetAttribute(Constants.CharAttr.Stuck, false)
		character:SetAttribute(Constants.CharAttr.Rolling, false)
	end
end

-- Puts every given player into the round, each on a distinct spawn.
function PlayerManager.BeginRound(players: { Player })
	local spawns = table.clone(services.MapBuilder.Info.ToasterSpawns)
	for i = #spawns, 2, -1 do
		local j = rng:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end
	for index, player in players do
		local session = sessions[player]
		if session then
			session.InRound = true
			player:SetAttribute(ATTR.InRound, true)
			PlayerManager.ResetRoundState(session)
			PlayerManager.RebuildBread(session)
			local spawnPos = spawns[((index - 1) % #spawns) + 1]
			if index > #spawns then
				spawnPos += Vector3.new(rng:NextNumber(-2, 2), 2, rng:NextNumber(-2, 2))
			end
			PlayerManager.TeleportToToaster(session, spawnPos)
		end
	end
end

function PlayerManager.EndRound()
	for player, session in sessions do
		if session.InRound then
			if session.IsCharcoal and not session.BurntThisRound then
				session.CharcoalRoundsLeft -= 1
				if session.CharcoalRoundsLeft <= 0 then
					session.IsCharcoal = false
				end
			end
		end
		session.InRound = false
		player:SetAttribute(ATTR.InRound, false)
		PlayerManager.ResetRoundState(session)
		local character = player.Character
		if character then
			PlayerManager.SetCollisionGroup(character, Constants.CollisionGroups.Players)
		end
		local root, humanoid = PlayerManager.GetBody(session)
		if root and humanoid then
			humanoid.PlatformStand = false
			pcall(function()
				root:SetNetworkOwner(player)
			end)
			PlayerManager.RefreshAppearance(session)
			PlayerManager.RefreshMovement(session)
			PlayerManager.TeleportToLobby(session)
		end
	end
end

function PlayerManager.Burn(session: Session)
	if session.IsCharcoal then
		return
	end
	session.IsCharcoal = true
	session.BurntThisRound = true
	session.CharcoalRoundsLeft = Config.Charcoal.ExtraRounds
	session.Heat = Config.Heat.MaxHeat
	session.HeatState = "Burnt"
	session.ShieldActive = false
	session.ShieldEndsAt = 0
	local player = session.Player
	player:SetAttribute(ATTR.Heat, session.Heat)
	player:SetAttribute(ATTR.HeatState, "Burnt")
	player:SetAttribute(ATTR.IsCharcoal, true)
	player:SetAttribute(ATTR.ShieldEndsAt, 0)
	PlayerManager.RefreshAppearance(session)
	PlayerManager.RefreshMovement(session)

	local root = PlayerManager.GetBody(session)
	services.Messaging.Notify(player, "🔥 YOU'RE BURNT! You're charcoal now: touch others to blacken them.", "Danger", 4)
	services.Messaging.Notify(nil, `🔥 {player.DisplayName} got burnt!`, "Danger", 2)
	services.Messaging.Sound(nil, "Burn", root and root.Position or nil)
	services.Messaging.Effect(player, "Shake", { Intensity = 0.6, Duration = 0.6 })
end

local function humanoidDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local color = Theme.Colors.Crust
	desc.HeadColor = color
	desc.TorsoColor = color
	desc.LeftArmColor = color
	desc.RightArmColor = color
	desc.LeftLegColor = color
	desc.RightLegColor = color
	return desc
end

local function spawnCharacter(player: Player)
	if player.Parent ~= Players then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescriptionAsync(humanoidDescription())
	end)
	if not ok then
		warn("[PlayerManager] LoadCharacterWithHumanoidDescriptionAsync failed, falling back:", err)
		pcall(function()
			player:LoadCharacterAsync()
		end)
	end
end

local ACTIVE_ARENA_PHASES = {
	[PHASES.RoundStart] = true,
	[PHASES.Calm] = true,
	[PHASES.Heating] = true,
	[PHASES.Launch] = true,
}

local function onCharacterAdded(session: Session, character: Model)
	session.Maid:Clean()
	local player = session.Player
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or player.Character ~= character then
		return
	end

	humanoid.BreakJointsOnDeath = false
	BreadVisuals.PrepareCharacter(character)
	PlayerManager.SetCollisionGroup(character, Constants.CollisionGroups.Players)
	session.Maid:Give(character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.CollisionGroup == "Default" then
			descendant.CollisionGroup = Constants.CollisionGroups.Players
		end
	end))
	PlayerManager.RebuildBread(session)

	session.Maid:Give(humanoid.Died:Connect(function()
		task.delay(Config.Movement.RespawnDelay, function()
			if player.Parent == Players and player.Character == character then
				spawnCharacter(player)
			end
		end)
	end))

	-- Restore position for players who reset mid-round.
	local phase = services.RoundManager.GetPhase()
	if session.InRound and ACTIVE_ARENA_PHASES[phase] then
		PlayerManager.TeleportToToaster(session)
	elseif session.InRound and phase == PHASES.Landing then
		services.LaunchManager.FallbackLand(session)
	end
end

local function onPlayerAdded(player: Player)
	local session = newSession(player)
	sessions[player] = session
	player:SetAttribute(ATTR.InRound, false)
	player:SetAttribute(ATTR.IsCharcoal, false)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(session, character)
	end)
	player.CharacterRemoving:Connect(function()
		session.Maid:Clean()
	end)

	services.DataManager.Load(player)
	if player.Parent == Players then
		spawnCharacter(player)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		session.Maid:Clean()
		sessions[player] = nil
	end
end

function PlayerManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerManager
