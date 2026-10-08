-- Client entry point: initialises and starts every controller in order.

local Controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"SoundController",
	"CameraController",
	"InputController",
	"UIController",
	"EffectsController",
}

local registry = {}
for _, name in ORDER do
	registry[name] = require(Controllers:WaitForChild(name))
end

for _, name in ORDER do
	local controller = registry[name]
	if type(controller.Init) == "function" then
		controller.Init(registry)
	end
end

for _, name in ORDER do
	local controller = registry[name]
	if type(controller.Start) == "function" then
		controller.Start()
	end
end
