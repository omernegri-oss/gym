-- Plays sound hooks from Shared.Sounds, either 2D or at a world position.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared").Sounds)

local SoundController = {}

local templates: { [string]: Sound } = {}

local function template(key: string): Sound?
	local existing = templates[key]
	if existing then
		return existing
	end
	local spec = Sounds[key]
	if not spec or spec.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume
	sound.PlaybackSpeed = spec.Speed or 1
	sound.Parent = SoundService
	templates[key] = sound
	return sound
end

function SoundController.Play(key: string, position: Vector3?)
	local base = template(key)
	if not base then
		return
	end
	if not position then
		SoundService:PlayLocalSound(base)
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SoundAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	local sound = base:Clone()
	sound.RollOffMaxDistance = 300
	sound.RollOffMinDistance = 20
	sound.Parent = anchor
	anchor.Parent = workspace
	sound:Play()
	Debris:AddItem(anchor, 6)
end

return SoundController
