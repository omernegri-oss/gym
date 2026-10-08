-- Server-authoritative round state machine:
-- LOBBY -> ROUND_START -> CALM_PHASE -> HEATING_PHASE -> LAUNCH_PHASE
--       -> LANDING_PHASE -> REWARDS -> RESULTS -> LOBBY
-- Clients only read the RoundState folder attributes and one-shot events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local RoundManager = {}

local PHASES = Constants.Phases
local RA = Constants.RoundAttr
local ROUND = Config.Round
local services

local phase = PHASES.Lobby
local roundNumber = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

function RoundManager.Init(registry)
	services = registry
end

function RoundManager.GetPhase(): string
	return phase
end

function RoundManager.GetRoundNumber(): number
	return roundNumber
end

function RoundManager.SetRoundAttribute(name: string, value: any)
	Net.RoundState:SetAttribute(name, value)
end

local function setPhase(newPhase: string, duration: number?)
	phase = newPhase
	local t = now()
	Net.RoundState:SetAttribute(RA.Phase, newPhase)
	Net.RoundState:SetAttribute(RA.PhaseStartedAt, t)
	Net.RoundState:SetAttribute(RA.PhaseEndsAt, if duration then t + duration else 0)
	Net.RoundState:SetAttribute(RA.PlayersInRound, services.PlayerManager.CountInRound())
end

local function roundAborted(): boolean
	return services.PlayerManager.CountInRound() == 0
end

-- Waits for `duration`, returning false early if everyone left.
local function waitPhase(duration: number, untilFn: (() -> boolean)?): boolean
	local deadline = os.clock() + duration
	while os.clock() < deadline do
		if roundAborted() then
			return false
		end
		if untilFn and untilFn() then
			return true
		end
		task.wait(0.2)
	end
	return not roundAborted()
end

local function runLobby()
	setPhase(PHASES.Lobby, nil) -- "waiting for players" until enough are ready
	local readySince = nil
	while true do
		local ready = #services.PlayerManager.ReadyPlayers() >= ROUND.MinimumPlayers
		if ready then
			if not readySince then
				readySince = os.clock()
				setPhase(PHASES.Lobby, ROUND.IntermissionDuration)
			end
			if os.clock() - readySince >= ROUND.IntermissionDuration then
				return
			end
		elseif readySince then
			readySince = nil
			setPhase(PHASES.Lobby, nil) -- "waiting for players"
		end
		task.wait(0.25)
	end
end

local function runCalm(): boolean
	setPhase(PHASES.Calm, ROUND.CalmDuration)
	local warnAt = ROUND.CalmDuration - ROUND.CalmWarningLead
	if not waitPhase(warnAt) then
		return false
	end
	services.Messaging.Round(nil, "CalmWarning", { EndsAt = now() + ROUND.CalmWarningLead })
	services.Messaging.Notify(nil, "🔧 *click*... did the toaster just move?", "Warning", 3)
	return waitPhase(ROUND.CalmWarningLead)
end

local function runHeating(): boolean
	setPhase(PHASES.Heating, ROUND.HeatingDuration)
	services.CrumbWorldManager.EvictAll()
	services.Messaging.Round(nil, "HandSequence", { StartedAt = now(), Duration = ROUND.HandSequenceDuration })
	services.Messaging.Notify(nil, "🖐️ THE HAND IS COMING!", "Danger", 2.5)
	if not waitPhase(ROUND.HandSequenceDuration) then
		return false
	end
	services.HeatManager.SetActive(true)
	services.Messaging.Notify(nil, "🔥 OH NO... THE TOASTER IS ON!", "Danger", 3)
	services.EventManager.StartHeating()
	local ok = waitPhase(ROUND.HeatingDuration - ROUND.HandSequenceDuration)
	services.EventManager.StopHeating()
	services.HeatManager.SetActive(false)
	return ok
end

local function runLaunch(): boolean
	setPhase(PHASES.Launch, ROUND.LaunchDuration)
	services.Messaging.Round(nil, "Countdown", { PopAt = now() + ROUND.LaunchDuration })
	services.Messaging.Notify(nil, "🚀 GET READY TO LAUNCH! Run to the POP PAD!", "Warning", 2.5)
	if not waitPhase(ROUND.LaunchDuration) then
		return false
	end
	services.LaunchManager.LaunchAll()
	return true
end

local function runLanding(): boolean
	setPhase(PHASES.Landing, ROUND.LandingDuration)
	-- Give everyone time to land, then a short beat to look around.
	local landedEarly = waitPhase(ROUND.LandingDuration, function()
		return services.LaunchManager.AllLanded()
	end)
	services.LaunchManager.FinalizeAll()
	if landedEarly then
		task.wait(1.5)
	end
	return not roundAborted()
end

local function runRewardsAndResults()
	setPhase(PHASES.Rewards, ROUND.RewardsDuration)
	services.RewardManager.GrantRound()
	task.wait(ROUND.RewardsDuration)

	setPhase(PHASES.Results, ROUND.ResultsDuration)
	services.Messaging.Round(nil, "Results", { Round = roundNumber, Rows = services.RewardManager.BuildResults() })
	task.wait(ROUND.ResultsDuration)
end

local function cleanupRound()
	services.LaunchManager.Reset()
	services.EventManager.Cleanup()
	services.AbilityManager.ResetRound()
	services.HeatManager.ResetRound()
	services.PickupManager.ClearRoundPickups()
	services.PlayerManager.EndRound()
	services.Messaging.Round(nil, "RoundEnded", {})
end

local function runRound()
	local participants = services.PlayerManager.ReadyPlayers()
	if #participants < ROUND.MinimumPlayers then
		return
	end
	roundNumber += 1
	Net.RoundState:SetAttribute(RA.RoundNumber, roundNumber)

	services.PlayerManager.BeginRound(participants)
	services.PickupManager.SpawnRoundPickups()
	services.EventManager.PrepareRound(roundNumber)
	setPhase(PHASES.RoundStart, ROUND.RoundStartDuration)
	services.Messaging.Notify(nil, "🍞 ROUND STARTED! Grab crumbs and butter!", "Good", 3)
	services.Messaging.Sound(nil, "RoundStart")

	local ok = waitPhase(ROUND.RoundStartDuration) and runCalm() and runHeating() and runLaunch() and runLanding()
	if ok then
		runRewardsAndResults()
	else
		services.Messaging.Notify(nil, "Everyone left the toaster. Back to the lobby!", "Info", 3)
	end
	cleanupRound()
end

function RoundManager.Start()
	setPhase(PHASES.Lobby, nil)
	task.spawn(function()
		while true do
			runLobby()
			local ok, err = pcall(runRound)
			if not ok then
				warn("[RoundManager] round crashed, recovering:", err)
				pcall(cleanupRound)
			end
		end
	end)

	-- Keep the in-round count fresh when players leave mid-round.
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			Net.RoundState:SetAttribute(RA.PlayersInRound, services.PlayerManager.CountInRound())
		end)
	end)
end

return RoundManager
