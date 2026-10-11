-- CRUMB WORLD: the hidden area beneath the toaster. Players slip through the
-- secret crack during the calm phase, chat with Old Crumb (a crumb from 1987)
-- and hunt three vintage crumbs for a one-time reward. Never required for the
-- core loop; everyone is sent back up when the toaster turns on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)

local CrumbWorldManager = {}

local PHASES = Constants.Phases
local services
local debounce: { [Player]: number } = {}
local talkIndex: { [Player]: number } = {}

local LORE = {
	"Back in 1987, we didn't have Wi-Fi.",
	"We had crumbs.",
	"And we liked it.",
	"You kids and your 'bagels'. In my day a hole in your bread meant a MOUSE.",
	"I've been toasted four thousand times. You get used to it. ...You don't, actually.",
	"Never trust the hand. It giveth crumbs. It also pusheth the lever.",
	"The fork? Don't talk to me about the fork.",
	"Psst. Be on the POP pad when the countdown starts. Thank me later.",
	"The ends of the toaster run cool. Your crust will thank you.",
	"Butter's not a snack, kid. It's armour.",
}

local VINTAGE_TOTAL = 3

local function vintageFound(data): number
	local count = 0
	for _ in data.VintageCrumbsFound do
		count += 1
	end
	return count
end

local function publishVintage(player: Player, data)
	local ids = {}
	for id in data.VintageCrumbsFound do
		table.insert(ids, id)
	end
	player:SetAttribute("VintageFound", table.concat(ids, ","))
end

local function bodyOf(player: Player): BasePart?
	local session = services.PlayerManager.Get(player)
	if not session then
		return nil
	end
	return (services.PlayerManager.GetBody(session))
end

local function touchedPlayer(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

local function debounced(player: Player, seconds: number): boolean
	local t = os.clock()
	if t < (debounce[player] or 0) then
		return true
	end
	debounce[player] = t + seconds
	return false
end

local function canEnter(): boolean
	local phase = services.RoundManager.GetPhase()
	return phase == PHASES.Calm or phase == PHASES.RoundStart or not Config.CrumbWorld.OpenDuringCalmOnly
end

local function enter(player: Player)
	local session = services.PlayerManager.Get(player)
	local root = bodyOf(player)
	if not session or not session.InRound or not root or not canEnter() then
		return
	end
	if (root.Position - services.MapBuilder.Info.SecretSensor.Position).Magnitude > 8 then
		return
	end
	local character = player.Character
	if character then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(CFrame.new(services.MapBuilder.Info.CrumbWorld.Entry))
	end
	services.Messaging.Notify(player, "🌎 You slipped through the crack... WELCOME TO CRUMB WORLD!", "Legend", 3.5)
	services.Messaging.Sound(player, "SecretArea")
end

local function leave(player: Player)
	local session = services.PlayerManager.Get(player)
	if not session then
		return
	end
	local phase = services.RoundManager.GetPhase()
	if session.InRound and (phase == PHASES.Calm or phase == PHASES.RoundStart or phase == PHASES.Heating) then
		services.PlayerManager.TeleportToToaster(session)
	else
		services.PlayerManager.TeleportToLobby(session)
	end
	services.Messaging.Notify(player, "⬆️ Back to the toaster!", "Info", 1.5)
end

local function onVintage(player: Player, crumb: BasePart)
	local id = crumb:GetAttribute("VintageId")
	local data = services.DataManager.Get(player)
	local root = bodyOf(player)
	if type(id) ~= "string" or not data or not root or data.VintageCrumbsFound[id] then
		return
	end
	if (root.Position - crumb.Position).Magnitude > 10 then
		return
	end
	services.DataManager.Update(player, function(d)
		d.VintageCrumbsFound[id] = true
	end)
	publishVintage(player, data)
	local found = vintageFound(data)
	services.Messaging.Sound(player, "GoldenCrumb")
	if found >= VINTAGE_TOTAL then
		services.Messaging.Notify(player, "✨ All 3 vintage crumbs found! Go see Old Crumb.", "Legend", 3)
	else
		services.Messaging.Notify(player, `✨ Vintage crumb found ({found}/{VINTAGE_TOTAL})`, "Good", 2)
	end
end

local function talk(player: Player)
	local data = services.DataManager.Get(player)
	if not data then
		return
	end
	local found = vintageFound(data)
	local line
	if found >= VINTAGE_TOTAL and data.Statistics.VintageQuestDone == 0 then
		services.DataManager.Update(player, function(d)
			d.Statistics.VintageQuestDone = 1
		end)
		services.CurrencyManager.Add(player, "Crumbs", Config.CrumbWorld.VintageCrumbReward, "VintageQuest")
		services.AchievementManager.Evaluate(player)
		line = `MY CRUMBS! You found 'em all! Here's {Config.CrumbWorld.VintageCrumbReward} crumbs. Don't spend it all on butter.`
	else
		local index = (talkIndex[player] or 0) + 1
		talkIndex[player] = index
		if data.Statistics.VintageQuestDone == 0 and index % 4 == 1 then
			if found == 0 then
				line = "I lost three vintage crumbs from '87. Golden ones. Find 'em for an old crumb, would ya?"
			else
				line = `You've found {found} of my {VINTAGE_TOTAL} vintage crumbs. Keep looking. One likes rooftops.`
			end
		else
			line = LORE[((index - 1) % #LORE) + 1]
		end
	end
	services.Messaging.Dialogue(player, "OLD CRUMB", line)
	services.Messaging.Sound(player, "NpcTalk")
end

-- Called when the toaster turns on: nobody hides down here from the heat.
function CrumbWorldManager.EvictAll()
	for _, player in Players:GetPlayers() do
		local root = bodyOf(player)
		if root and services.MapBuilder.IsInCrumbWorld(root.Position) then
			services.Messaging.Dialogue(player, "OLD CRUMB", "The toaster's ON! Up you go, kid!")
			leave(player)
		end
	end
end

function CrumbWorldManager.Init(registry)
	services = registry
end

function CrumbWorldManager.Start()
	local world = services.MapBuilder.Info.CrumbWorld

	services.MapBuilder.Info.SecretSensor.Touched:Connect(function(hit)
		local player = touchedPlayer(hit)
		if player and not debounced(player, 1.5) then
			enter(player)
		end
	end)

	world.ReturnPad.Touched:Connect(function(hit)
		local player = touchedPlayer(hit)
		if player and not debounced(player, 1.5) then
			leave(player)
		end
	end)

	world.NpcPrompt.Triggered:Connect(function(player)
		local root = bodyOf(player)
		if root and (root.Position - world.NpcHead.Position).Magnitude <= world.NpcPrompt.MaxActivationDistance + 4 then
			talk(player)
		end
	end)

	for _, crumb in world.VintageCrumbs do
		crumb.Touched:Connect(function(hit)
			local player = touchedPlayer(hit)
			if player then
				onVintage(player, crumb)
			end
		end)
	end

	services.DataManager.OnLoaded(function(player)
		local data = services.DataManager.Get(player)
		if data then
			publishVintage(player, data)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
		talkIndex[player] = nil
	end)
end

return CrumbWorldManager
