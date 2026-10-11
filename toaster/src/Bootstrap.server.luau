-- Entry point: builds the world, then initialises and starts every server
-- manager in dependency order. Managers receive the registry in Init so they
-- can reference each other without circular requires.

local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")

local ORDER = {
	"Messaging",
	"MapBuilder",
	"DataManager",
	"CurrencyManager",
	"PlayerManager",
	"HeatManager",
	"PickupManager",
	"LaunchManager",
	"RewardManager",
	"AchievementManager",
	"AbilityManager",
	"EventManager",
	"CrumbWorldManager",
	"ShopManager",
	"RoundManager",
}

local registry = {}
for _, name in ORDER do
	registry[name] = require(Server:WaitForChild(name))
end

registry.MapBuilder.Build()

for _, name in ORDER do
	local service = registry[name]
	if type(service.Init) == "function" then
		service.Init(registry)
	end
end

-- PlayerManager starts last so every other manager is already listening
-- (e.g. DataManager.OnLoaded) before the first player is processed.
local START_LAST = "PlayerManager"
for _, name in ORDER do
	local service = registry[name]
	if name ~= START_LAST and type(service.Start) == "function" then
		service.Start()
	end
end
registry[START_LAST].Start()

print("[TOASTER] 🍞 Server ready.")
