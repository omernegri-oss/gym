-- Headless end-to-end simulation of TOASTER's server.
--   python3 tests/harness/build.py   (refresh generated/Sources.luau)
--   luau tests/harness/simulate.luau
--
-- Boots the real server code inside RobloxMock, connects scripted bots and
-- plays several full rounds in virtual time, then checks the gameplay loop
-- against the spec's test list (spawning, timer, crumbs, butter, heat,
-- burning, charcoal, launch, landing, scoring, rewards once, results,
-- next round, leaving, joining, resetting, remote spam, invalid requests,
-- DataStore failures and corrupt saves).

local Mock = require("./RobloxMock")
local Sources = require("./generated/Sources")

local Instance = Mock.Instance
local game = Mock.game
local workspace = Mock.workspace
local data = Mock.data
local task = Mock.task

------------------------------------------------------------------ build the DataModel like Rojo would

local scriptKeys: { [any]: string } = {}
local moduleCache: { [string]: any } = {}

local function newScript(className: string, name: string, key: string, parent: any)
	local s = Instance.new(className)
	s.Name = name
	scriptKeys[s] = key
	s.Parent = parent
	return s
end

local function folder(name: string, parent: any)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local shared = folder("Shared", ReplicatedStorage)
local server = folder("Server", ServerScriptService)
local remotes = folder("Remotes", ReplicatedStorage)
for _, name in { "RoundEvent", "UIEvent", "AbilityEvent", "InteractionEvent", "EffectEvent" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
end
local roundState = folder("RoundState", ReplicatedStorage)
folder("Assets", ReplicatedStorage)

for key in Sources do
	local dir, file = string.match(key, "^(%w+)/([%w_]+)%.luau$")
	if dir == "shared" then
		newScript("ModuleScript", file, key, shared)
	elseif dir == "server" then
		newScript("ModuleScript", file, key, server)
	end
end
local bootstrap = newScript("Script", "Bootstrap", "Bootstrap.server.luau", ServerScriptService)

-- Server and client get separate module instances, like real Roblox.
local clientCache: { [string]: any } = {}
local function makeRequire(cache: { [string]: any })
	local function requireIn(inst: any): any
		local key = scriptKeys[inst]
		assert(key, "require() of something that is not a ModuleScript")
		local cached = cache[key]
		if cached ~= nil then
			return cached
		end
		local fn = assert(loadstring(Sources[key], "=" .. key))
		setfenv(fn, Mock.Environment(inst, requireIn))
		local result = fn()
		cache[key] = result
		return result
	end
	return requireIn
end
local requireModule = makeRequire(moduleCache)
local requireClient = makeRequire(clientCache)

-- Runs the real client scripts for `player` (LocalPlayer = player).
local function startClient(player: any)
	local playerScripts = Mock.AttachClient(player)
	local controllers = folder("Controllers", playerScripts)
	for key in Sources do
		local file = string.match(key, "^client/Controllers/([%w_]+)%.luau$")
		if file then
			newScript("ModuleScript", file, key, controllers)
		end
	end
	local entry = newScript("LocalScript", "ClientController", "client/ClientController.client.luau", playerScripts)
	task.spawn(function()
		local fn = assert(loadstring(Sources["client/ClientController.client.luau"], "=ClientController"))
		setfenv(fn, Mock.Environment(entry, requireClient))
		fn()
	end)
end

local function sharedModule(name: string)
	return requireModule(shared:FindFirstChild(name))
end
local function serverModule(name: string)
	return requireModule(server:FindFirstChild(name))
end

------------------------------------------------------------------ test bookkeeping

local checks: { { name: string, ok: boolean, detail: string? } } = {}
local function check(name: string, ok: boolean, detail: string?)
	table.insert(checks, { name = name, ok = ok, detail = detail })
end

local phaseLog: { { t: number, phase: string } } = {}
roundState:GetAttributeChangedSignal("Phase"):Connect(function()
	table.insert(phaseLog, { t = Mock.Now(), phase = roundState:GetAttribute("Phase") })
end)

local function phase(): string
	return roundState:GetAttribute("Phase") or "LOBBY"
end

local function remoteEvents(player: any?, remoteName: string, kind: string): { any }
	local list = {}
	for _, entry in Mock.RemoteLog do
		if entry.remote == remoteName and entry.args[1] == kind and (player == nil or entry.player == player or entry.player == "all") then
			table.insert(list, entry)
		end
	end
	return list
end

------------------------------------------------------------------ boot

-- Pre-existing saves: Cara is a veteran with crumbs and levels, Hal's save
-- can't be read (outage), Ivy's save is corrupt.
local store = {}
Mock.Stores["ToasterPlayerData_v1"] = store
local Config = sharedModule("Config")
Config.Fork.ForceEveryRound = true -- make sure the boss shows up in the run

task.spawn(function()
	local fn = assert(loadstring(Sources["Bootstrap.server.luau"], "=Bootstrap"))
	setfenv(fn, Mock.Environment(bootstrap, requireModule))
	fn()
end)

Mock.BuildCollisionGrid()
local Net = sharedModule("Net")
local PlayerManager = serverModule("PlayerManager")
local DataManager = serverModule("DataManager")
local MapBuilder = serverModule("MapBuilder")
local info = MapBuilder.Info
check("map built", info ~= nil and #info.ToasterSpawns > 20, info and `spawns: {#info.ToasterSpawns}` or "no map")

local function fire(remote: any, player: any, ...)
	remote.OnServerEvent:Fire(player, ...)
end

local function rootOf(player: any): any
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function posOf(player: any): any
	local root = rootOf(player)
	return root and root.Position
end

local function availablePickups(kinds: { [string]: boolean }): { any }
	local list = {}
	for _, part in workspace:FindFirstChild("Pickups"):GetChildren() do
		if kinds[part.Name] and part.Transparency < 1 then
			table.insert(list, part)
		end
	end
	return list
end

local function nearest(from: any, parts: { any }): any
	local best, bestDist = nil, math.huge
	for _, part in parts do
		local d = (part.Position - from).Magnitude
		if d < bestDist then
			best, bestDist = part, d
		end
	end
	return best
end

------------------------------------------------------------------ bots

local Vector3 = Mock.Environment(nil, requireModule).Vector3

local players: { [string]: any } = {}
local function join(name: string)
	local player = Mock.AddPlayer(name)
	players[name] = player
	return player
end

local function alice(p)
	local pos = posOf(p)
	if not pos then
		return
	end
	local ph = phase()
	if ph == "CALM_PHASE" or ph == "ROUND_START" then
		local wanted = if (p:GetAttribute("ButterCarried") or 0) == 0 then availablePickups({ Butter = true }) else {}
		if #wanted == 0 then
			wanted = availablePickups({ Crumb = true, GoldenCrumb = true })
		end
		local target = nearest(pos, wanted)
		Mock.MoveTo(p, target and target.Position)
	elseif ph == "HEATING_PHASE" then
		Mock.MoveTo(p, Vector3.new(6, 0, 0))
		if (p:GetAttribute("Heat") or 0) > 30 and (p:GetAttribute("ButterCarried") or 0) > 0 then
			fire(Net.AbilityEvent, p, "Butter")
		end
		local bob = players.Bob
		local bobPos = bob and bob.Parent and posOf(bob)
		if bobPos then
			fire(Net.AbilityEvent, p, "Spread", "Jam", (bobPos - pos).Unit)
		end
	elseif ph == "LAUNCH_PHASE" then
		Mock.MoveTo(p, Vector3.new(0, 0, 0))
	end
end

local function bob(p)
	local ph = phase()
	if p:GetAttribute("IsCharcoal") == true and (ph == "CALM_PHASE" or ph == "HEATING_PHASE") then
		local target = players.Alice and posOf(players.Alice)
		Mock.MoveTo(p, target) -- charcoal chases Alice
	elseif ph == "CALM_PHASE" or ph == "HEATING_PHASE" then
		Mock.MoveTo(p, Vector3.new(-20, 0, 30)) -- camps next to the coils
	elseif ph == "LAUNCH_PHASE" then
		Mock.MoveTo(p, Vector3.new(-50, 0, 0))
	end
end

local caraStage = 0
local function cara(p)
	local ph = phase()
	local round = roundState:GetAttribute("RoundNumber") or 0
	if ph == "LOBBY" and caraStage < round then
		caraStage = round
		local order = { "Bagel", "Croissant", "Waffle" }
		local bread = order[math.min(round, 3)]
		fire(Net.InteractionEvent, p, "BuyBread", bread)
	elseif ph == "CALM_PHASE" then
		local alicePos = players.Alice and posOf(players.Alice)
		Mock.MoveTo(p, alicePos)
		fire(Net.AbilityEvent, p, "Ability")
	elseif ph == "HEATING_PHASE" then
		Mock.MoveTo(p, Vector3.new(60, 0, 0)) -- cool spot
		fire(Net.AbilityEvent, p, "Spread", "Nutella", Vector3.new(-1, 0, 0))
	elseif ph == "LAUNCH_PHASE" then
		Mock.MoveTo(p, Vector3.new(3, 0, 2))
	end
end

local eveCrumbsBefore = nil
local function eve(p)
	local ph = phase()
	if ph == "CALM_PHASE" then
		eveCrumbsBefore = eveCrumbsBefore or (p:GetAttribute("Crumbs") or 0)
		-- spam and garbage
		for _ = 1, 50 do
			fire(Net.AbilityEvent, p, "Spread", "Jam", Vector3.new(0 / 0, 1, 0))
			fire(Net.AbilityEvent, p, "Spread", "Ketchup", Vector3.new(1, 0, 0))
			fire(Net.AbilityEvent, p, { "not", "a", "string" })
			fire(Net.AbilityEvent, p, "Ability")
			fire(Net.AbilityEvent, p, "Butter")
		end
		fire(Net.InteractionEvent, p, "BuyBread", "Waffle")
		fire(Net.InteractionEvent, p, "BuyBread", { "Bagel" })
		fire(Net.InteractionEvent, p, "EquipBread", "Waffle")
		fire(Net.InteractionEvent, p, "EquipTitle", "ADMIN")
		fire(Net.InteractionEvent, p, "EquipCosmetic", "Hat", "Crown")
		fire(Net.InteractionEvent, p, "BuyCosmetic", "ChefHat")
		fire(Net.InteractionEvent, p, "DeleteEverything")
		Mock.MoveTo(p, Vector3.new(-40, 0, -10))
	end
end

local franState = "idle"
-- Waypoints around Crumb World's buildings (the bots walk in straight lines).
local FRAN_APPROACH = {
	V1 = { Vector3.new(-38, 0, -15), Vector3.new(-38, 0, -44) },
	V2 = { Vector3.new(-38, 0, -44), Vector3.new(-38, 0, -15), Vector3.new(54, 0, -15), Vector3.new(54, 0, -32) },
	V3 = { Vector3.new(40, 0, 10) },
}
local franApproached: { [string]: number } = {}
local function fran(p)
	local ph = phase()
	local pos = posOf(p)
	if not pos then
		return
	end
	local round = roundState:GetAttribute("RoundNumber") or 0
	if round ~= 2 or ph ~= "CALM_PHASE" then
		if ph == "LAUNCH_PHASE" then
			Mock.MoveTo(p, Vector3.new(-2, 0, -2))
		end
		return
	end
	local world = info.CrumbWorld
	if pos.Y > -100 then
		if franState == "idle" then
			Mock.MoveTo(p, info.SecretSensor.Position)
		end
		return
	end
	franState = "below"
	for _, crumb in world.VintageCrumbs do
		local id = crumb:GetAttribute("VintageId")
		local found = string.find(p:GetAttribute("VintageFound") or "", id, 1, true)
		if not found then
			-- walk around buildings / line up with the sugar-cube steps first
			local route = FRAN_APPROACH[id] or {}
			local index = (franApproached[id] or 0) + 1
			local waypoint = route[index]
			if waypoint then
				Mock.MoveTo(p, waypoint)
				if Vector3.new(waypoint.X - pos.X, 0, waypoint.Z - pos.Z).Magnitude < 1.5 then
					franApproached[id] = index
				end
			else
				Mock.MoveTo(p, crumb.Position)
			end
			return
		end
	end
	if (world.NpcHead.Position - pos).Magnitude > 8 then
		Mock.MoveTo(p, world.NpcHead.Position)
		return
	end
	world.NpcPrompt.Triggered:Fire(p)
	franState = "talked"
	Mock.MoveTo(p, world.ReturnPad.Position)
end

local brains = {}

task.spawn(function()
	while true do
		for name, brain in brains do
			local player = players[name]
			if player and player.Parent then
				local ok, err = pcall(brain, player)
				if not ok then
					print("BOT ERROR", name, err)
				end
			end
		end
		task.wait(0.25)
	end
end)

------------------------------------------------------------------ scenario

store["player_1006"] = { Crumbs = 5000, XP = 3000, Statistics = { RoundsPlayed = 40 } } -- Cara (6th to join)

join("Alice")
brains.Alice = alice
startClient(players.Alice)
join("Bob")
brains.Bob = bob
join("Dan")
join("Eve")
brains.Eve = eve
join("Fran")
brains.Fran = fran
Mock.Advance(5)
check(
	"players spawned in the lobby",
	posOf(players.Alice) ~= nil and math.abs(posOf(players.Alice).X - Config.Map.LobbyCenterX) < 70,
	tostring(posOf(players.Alice))
)

-- Round 1 -------------------------------------------------------------
Mock.Advance(14) -- intermission
check("round 1 started", roundState:GetAttribute("RoundNumber") == 1 and players.Alice:GetAttribute("InRound") == true)
local aPos, bPos = posOf(players.Alice), posOf(players.Bob)
check("spawned inside the toaster", MapBuilder.IsInsideToaster(aPos) and MapBuilder.IsInsideToaster(bPos), tostring(aPos))
check("distinct spawn points", (aPos - bPos).Magnitude > 4)

Mock.Advance(20) -- into calm
local aliceCrumbs = players.Alice:GetAttribute("RoundCrumbs") or 0
check("crumbs collected (server validated)", aliceCrumbs > 0, `Alice round crumbs {aliceCrumbs}`)
check("butter collected", (players.Alice:GetAttribute("ButterCarried") or 0) == 1)

Mock.Kill(players.Eve) -- reset mid-round
Mock.Advance(4)
check(
	"reset player restored into the toaster",
	players.Eve:GetAttribute("InRound") == true and MapBuilder.IsInsideToaster(posOf(players.Eve)),
	tostring(posOf(players.Eve))
)
check("heat does not rise during calm", (players.Alice:GetAttribute("Heat") or 0) == 0)

-- wait for heating
local guard = 0
while phase() ~= "HEATING_PHASE" and guard < 200 do
	Mock.Advance(0.5)
	guard += 1
end
check("calm warning sent", #remoteEvents(nil, "RoundEvent", "CalmWarning") >= 1)
check("hand sequence sent", #remoteEvents(nil, "RoundEvent", "HandSequence") >= 1)
join("Cara") -- joins mid-round
brains.Cara = cara
Mock.Advance(1)
check("late joiner waits in the lobby", players.Cara:GetAttribute("InRound") == false and posOf(players.Cara).X < -150)

Mock.Advance(5)
check("heat rises once the lever is down", (players.Bob:GetAttribute("Heat") or 0) > 0)
local hud = players.Alice.PlayerGui.MainUI
check("client heat meter visible while heating", hud.Heat.Visible == true and hud.Actions.Visible == true)
local shieldHeat = nil
local shieldSeen = false
for _ = 1, 40 do
	Mock.Advance(0.5)
	local endsAt = players.Alice:GetAttribute("ShieldEndsAt") or 0
	if endsAt > 0 then
		shieldSeen = true
		local h = players.Alice:GetAttribute("Heat")
		if shieldHeat == nil then
			shieldHeat = h
		end
	end
	if phase() ~= "HEATING_PHASE" then
		break
	end
	if roundState:GetAttribute("PhaseEndsAt") - (1000 + Mock.Now()) < 12 and players.Dan.Parent then
		Mock.RemovePlayer(players.Dan) -- leaves mid-round
	end
end
check("butter shield activated", shieldSeen)
check("Bob burnt in the coils", players.Bob:GetAttribute("IsCharcoal") == true, `heat {players.Bob:GetAttribute("Heat")}`)
local bobVisual = players.Bob.Character and players.Bob.Character:FindFirstChild("BreadVisual")
check(
	"charcoal face: ember eyes and a frown",
	bobVisual ~= nil and bobVisual:GetAttribute("Expression") == "Charcoal",
	tostring(bobVisual and bobVisual:GetAttribute("Expression"))
)
local emberVisible = false
for _, part in bobVisual and bobVisual:GetChildren() or {} do
	if part.Name == "EmberEye" and part.Transparency < 1 then
		emberVisible = true
	end
end
check("ember eyes visible on charcoal", emberVisible)
check("Dan left without breaking the round", players.Dan.Parent == nil and phase() ~= "LOBBY")

while phase() ~= "LAUNCH_PHASE" do
	Mock.Advance(0.5)
end
check("countdown sent", #remoteEvents(nil, "RoundEvent", "Countdown") >= 1)
while phase() ~= "LANDING_PHASE" do
	Mock.Advance(0.25)
end
Mock.Advance(0.5)
local aliceAir = posOf(players.Alice)
check("launched out of the toaster", aliceAir.Y > Config.Map.FloorY + 20 or aliceAir.X > 100, tostring(aliceAir))
while phase() == "LANDING_PHASE" do
	Mock.Advance(0.25)
end
local aliceSession = PlayerManager.Get(players.Alice)
local bobSession = PlayerManager.Get(players.Bob)
check(
	"Alice landed and scored",
	aliceSession.Landed and aliceSession.LandingPoints >= 100,
	`{aliceSession.LandingZoneName} {aliceSession.LandingPoints}`
)
check("Bob landed too", bobSession.Landed, tostring(bobSession.LandingZoneName))
check("Alice survived golden", aliceSession.Survived and aliceSession.Golden)
check("Bob did not survive", not bobSession.Survived)
check("landed on the field", math.abs(posOf(players.Alice).X - Config.Map.FieldCenterX) < 60, tostring(posOf(players.Alice)))

while phase() ~= "RESULTS" do
	Mock.Advance(0.25)
end
local results = remoteEvents(nil, "RoundEvent", "Results")
check("results sent", #results == 1 and #results[1].args[2].Rows >= 3, `rows {results[1] and #results[1].args[2].Rows}`)
check("round awards handed out", results[1] and #results[1].args[2].Awards >= 2, `awards {results[1] and #results[1].args[2].Awards}`)
local aliceVisual = players.Alice.Character and players.Alice.Character:FindFirstChild("BreadVisual")
check(
	"golden survivors grin",
	aliceVisual ~= nil and aliceVisual:GetAttribute("Expression") == "Golden",
	tostring(aliceVisual and aliceVisual:GetAttribute("Expression"))
)
local mainUI = players.Alice:FindFirstChild("PlayerGui"):FindFirstChild("MainUI")
check("client UI built", mainUI ~= nil and mainUI:FindFirstChild("Timer") ~= nil and mainUI:FindFirstChild("Heat") ~= nil)
Mock.Advance(0.5)
check("client shows the results screen", mainUI and mainUI:FindFirstChild("Results").Visible == true)
local timerText = ""
for _, child in mainUI.Timer:GetChildren() do
	if child:IsA("TextLabel") and string.find(child.Text, "TIME:", 1, true) then
		timerText = child.Text
	end
end
check("client timer shows the phase clock", timerText ~= "", timerText)
local aliceData = DataManager.Get(players.Alice)
check(
	"rewards granted once",
	aliceData.Statistics.RoundsPlayed == 1 and aliceData.Statistics.RoundsSurvived == 1,
	`played {aliceData.Statistics.RoundsPlayed}`
)
check("survival bonus applied", aliceSession.Reward and aliceSession.Reward.Points >= Config.Rewards.SurvivalBonus)
check("butter survivor achievement", aliceData.Achievements.ButterSurvivor == true and aliceData.Achievements.Rookie == true)
check(
	"Eve's exploits changed nothing",
	(players.Eve:GetAttribute("Crumbs") or 0) >= (eveCrumbsBefore or 0)
		and not DataManager.Get(players.Eve).UnlockedBreads.Waffle
		and DataManager.Get(players.Eve).EquippedTitle ~= "ADMIN"
)

while phase() ~= "LOBBY" do
	Mock.Advance(0.25)
end
check("everyone back in the lobby", posOf(players.Alice).X < -150 and players.Alice:GetAttribute("InRound") == false)
check("charcoal carries into the next round", players.Bob:GetAttribute("IsCharcoal") == true)
local ClientEnum = Mock.Environment(nil, requireModule).Enum
Mock.BoundActions.ToasterShop.fn("ToasterShop", ClientEnum.UserInputState.Begin)
Mock.Advance(0.5)
local shopRows = 0
for _, child in hud.Shop:FindFirstChildOfClass("ScrollingFrame"):GetChildren() do
	if child:IsA("Frame") then
		shopRows += 1
	end
end
check("shop opens via keybind and lists breads", hud.Shop.Visible == true and shopRows == 4, `rows {shopRows}`)
check("results screen hides after results", hud.Results.Visible == false)

-- Round 2: Cara (bagel), Fran explores Crumb World, Bob is charcoal --------
Mock.Advance(16)
check("round 2 started with the late joiner", roundState:GetAttribute("RoundNumber") == 2 and players.Cara:GetAttribute("InRound") == true)
check("Cara bought and equipped the bagel", DataManager.Get(players.Cara).EquippedBread == "Bagel")
local noAbilityBefore = 0
for _, entry in Mock.RemoteLog do
	if entry.player == players.Alice and entry.args[1] == "Notify" and string.find(entry.args[2].Text, "no ability", 1, true) then
		noAbilityBefore += 1
	end
end
Mock.Advance(2)
hud.Actions.Ability.Activated:Fire() -- tap the on-screen button
Mock.Advance(1)
local noAbilityAfter = 0
for _, entry in Mock.RemoteLog do
	if entry.player == players.Alice and entry.args[1] == "Notify" and string.find(entry.args[2].Text, "no ability", 1, true) then
		noAbilityAfter += 1
	end
end
check("on-screen ability button reaches the server", noAbilityAfter == noAbilityBefore + 1)
Mock.Advance(27)
check("Cara rolled (cooldown started)", (players.Cara:GetAttribute("CD_Ability") or 0) > 0)
check("Fran found Crumb World", franState ~= "idle", franState)
check("vintage crumbs found", (players.Fran:GetAttribute("VintageFound") or "") ~= "", players.Fran:GetAttribute("VintageFound"))
check(
	"Old Crumb talked",
	#remoteEvents(players.Fran, "UIEvent", "Dialogue") >= 1,
	`fran at {posOf(players.Fran)} state {franState} found {players.Fran:GetAttribute("VintageFound")}`
)
check(
	"charcoal blackened someone",
	DataManager.Get(players.Bob).Statistics.PlayersBlackened > 0,
	tostring(DataManager.Get(players.Bob).Statistics.PlayersBlackened)
)
while phase() ~= "LOBBY" do
	Mock.Advance(0.5)
end
check("charcoal wears off after its extra round", players.Bob:GetAttribute("IsCharcoal") == false)
check("fork boss appeared", #remoteEvents(nil, "EffectEvent", "Fork") >= 1 and #remoteEvents(nil, "EffectEvent", "ForkZap") >= 1)

-- Rounds 3 and 4: croissant, waffle --------------------------------------
Config.Fork.ForceEveryRound = false
for round = 3, 4 do
	while roundState:GetAttribute("RoundNumber") ~= round do
		Mock.Advance(0.5)
	end
	while phase() ~= "LOBBY" do
		Mock.Advance(0.5)
	end
end
local caraData = DataManager.Get(players.Cara)
check(
	"Cara unlocked croissant and waffle",
	caraData.UnlockedBreads.Croissant and caraData.UnlockedBreads.Waffle and caraData.EquippedBread == "Waffle"
)
check("waffle legend achievement", caraData.Achievements.WaffleLegend == true)
local function anyNotify(fragment: string): boolean
	for _, entry in Mock.RemoteLog do
		if entry.remote == "UIEvent" and entry.args[1] == "Notify" and string.find(entry.args[2].Text, fragment, 1, true) then
			return true
		end
	end
	return false
end
check("jam hits stick players", anyNotify("JAMMED you"))
check("nutella puddles appear", #remoteEvents(nil, "EffectEvent", "Puddle") >= 1)
check(
	"bagel roll / croissant flakes / waffle slam all fired",
	#remoteEvents(players.Cara, "EffectEvent", "Roll") >= 1
		and #remoteEvents(nil, "EffectEvent", "Flake") >= 1
		and #remoteEvents(nil, "EffectEvent", "Shockwave") >= 1
)
check(
	"random heating events fired",
	#remoteEvents(nil, "EffectEvent", "FallingItem")
			+ #remoteEvents(nil, "EffectEvent", "HotSpot")
			+ #remoteEvents(nil, "EffectEvent", "SteamWarning")
		>= 3
)
check(
	"Old Crumb's quest rewarded once",
	DataManager.Get(players.Fran).Statistics.VintageQuestDone == 1 and DataManager.Get(players.Fran).Achievements.Archaeologist == true
)
check("four rounds completed", roundState:GetAttribute("RoundNumber") == 4 and #remoteEvents(nil, "RoundEvent", "Results") == 4)
check(
	"survival streak tracked",
	(players.Alice:GetAttribute("Streak") or 0) >= 1 and DataManager.Get(players.Alice).Statistics.BestStreak >= 1,
	tostring(players.Alice:GetAttribute("Streak"))
)
check(
	"rounds played counted once each",
	DataManager.Get(players.Alice).Statistics.RoundsPlayed == 4,
	tostring(DataManager.Get(players.Alice).Statistics.RoundsPlayed)
)

-- DataStore outage + corrupt save ------------------------------------------
store["player_1007"] = { Crumbs = 777 } -- Hal
store["player_1008"] = "definitely not a save" -- Ivy
Mock.DataStoreFailures = 4
local hal = join("Hal")
Mock.Advance(20)
check("failed load keeps the player playing", hal:GetAttribute("DataLoaded") == true)
local ivy = join("Ivy")
Mock.Advance(3)
local backupFound = false
for key in store do
	if string.find(key, "player_1008_corrupt", 1, true) then
		backupFound = true
	end
end
check("corrupt save backed up and reset", backupFound and DataManager.Get(ivy).Crumbs == 0)
Mock.Advance(30)
Mock.RemovePlayer(hal)
Mock.Advance(2)
check("failed load never overwrites the real save", store["player_1007"].Crumbs == 777, tostring(store["player_1007"].Crumbs))

-- Everyone leaves mid-round -> back to lobby; a newcomer starts a round ------
while phase() ~= "CALM_PHASE" do
	Mock.Advance(0.5)
end
for _, name in { "Alice", "Bob", "Cara", "Eve", "Fran", "Ivy" } do
	Mock.RemovePlayer(players[name])
end
Mock.Advance(3)
check("empty server returns to the lobby", phase() == "LOBBY", phase())
check("saved on leave", store["player_1001"] ~= nil and store["player_1001"].Statistics.RoundsPlayed == 4)
local gus = join("Gus")
Mock.Advance(40)
check("a new round starts for the newcomer", gus:GetAttribute("InRound") == true, phase())
while phase() ~= "LOBBY" do
	Mock.Advance(0.5)
end
check("newcomer finished a full round", DataManager.Get(gus).Statistics.RoundsPlayed == 1)

for _, fn in Mock.BindToClose do
	task.spawn(fn)
end
Mock.Advance(5)
check("shutdown saves remaining players", store["player_1009"] ~= nil and store["player_1009"].Statistics.RoundsPlayed == 1)

-- phase order sanity
local expected = { "ROUND_START", "CALM_PHASE", "HEATING_PHASE", "LAUNCH_PHASE", "LANDING_PHASE", "REWARDS", "RESULTS", "LOBBY" }
local sequence = {}
for _, entry in phaseLog do
	if sequence[#sequence] ~= entry.phase then
		table.insert(sequence, entry.phase)
	end
end
local startIndex = table.find(sequence, "ROUND_START")
local orderOk = startIndex ~= nil
if startIndex then
	for i, name in expected do
		if sequence[startIndex + i - 1] ~= name then
			orderOk = false
		end
	end
end
check("phases run in order", orderOk, table.concat(sequence, " > ", 1, math.min(#sequence, 12)))

------------------------------------------------------------------ report

local failed = 0
print("\n================ TOASTER headless simulation ================")
for _, c in checks do
	if not c.ok then
		failed += 1
	end
	print(`{if c.ok then "PASS" else "FAIL"}  {c.name}{if c.detail and not c.ok then "  (" .. c.detail .. ")" else ""}`)
end
print(`\nchecks: {#checks - failed}/{#checks} passed`)
print(`script errors: {#Mock.Errors}, warnings: {#Mock.Warnings}`)
print(`remote messages sent: {#Mock.RemoteLog}, virtual time: {math.floor(Mock.Now())}s`)
if failed > 0 or #Mock.Errors > 0 then
	error("simulation failed")
end
