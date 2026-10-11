-- Keyboard / gamepad bindings and the single place action requests are sent
-- from (on-screen buttons call Request too, so touch works identically).
-- The client pre-checks cooldowns only to avoid spam; the server decides.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityDefinitions = require(Shared.AbilityDefinitions)
local BreadDefinitions = require(Shared.BreadDefinitions)
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Net = require(Shared.Net)

local InputController = {}

local player = Players.LocalPlayer
local registry
local lastRequest: { [string]: number } = {}

local BINDINGS = {
	Ability = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX },
	Butter = { Enum.KeyCode.F, Enum.KeyCode.ButtonY },
	Jam = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
	Nutella = { Enum.KeyCode.R, Enum.KeyCode.ButtonL1 },
	Shop = { Enum.KeyCode.B, Enum.KeyCode.DPadUp },
}

local function now(): number
	return workspace:GetServerTimeNow()
end

function InputController.CooldownDuration(key: string): number
	if key == "Jam" or key == "Nutella" then
		return Config.Spreads[key].Cooldown
	elseif key == "Ability" then
		local bread = BreadDefinitions.ById[player:GetAttribute(Constants.Attr.Bread) or "Bread"]
		local ability = bread and bread.Ability and AbilityDefinitions[bread.Ability]
		return if ability then ability.Cooldown else 0
	end
	return 0
end

local function aimDirection(): Vector3
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	-- Lift the aim slightly so throws don't dive into the floor.
	return (look + Vector3.new(0, 0.12, 0)).Unit
end

function InputController.Request(key: string)
	if key == "Shop" then
		registry.UIController.ToggleShop()
		return
	end
	local t = os.clock()
	if t - (lastRequest[key] or 0) < 0.25 then
		return
	end
	lastRequest[key] = t
	if now() < (player:GetAttribute(Constants.Attr.CooldownPrefix .. key) or 0) then
		return
	end
	if key == "Ability" then
		Net.AbilityEvent:FireServer("Ability")
	elseif key == "Butter" then
		Net.AbilityEvent:FireServer("Butter")
	elseif key == "Jam" or key == "Nutella" then
		Net.AbilityEvent:FireServer("Spread", key, aimDirection())
	end
end

function InputController.Init(reg)
	registry = reg
end

function InputController.Start()
	for key, codes in BINDINGS do
		ContextActionService:BindAction("Toaster" .. key, function(_name, state)
			if state == Enum.UserInputState.Begin then
				InputController.Request(key)
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(codes))
	end
end

return InputController
