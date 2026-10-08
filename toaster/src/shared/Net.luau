-- Typed access to the RemoteEvents declared in default.project.json, plus the
-- RoundState folder whose attributes replicate the round to every client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

return {
	RoundEvent = remotes:WaitForChild("RoundEvent") :: RemoteEvent,
	UIEvent = remotes:WaitForChild("UIEvent") :: RemoteEvent,
	AbilityEvent = remotes:WaitForChild("AbilityEvent") :: RemoteEvent,
	InteractionEvent = remotes:WaitForChild("InteractionEvent") :: RemoteEvent,
	EffectEvent = remotes:WaitForChild("EffectEvent") :: RemoteEvent,
	RoundState = ReplicatedStorage:WaitForChild("RoundState") :: Folder,
}
