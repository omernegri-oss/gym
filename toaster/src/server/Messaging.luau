-- Thin server-side wrappers around the remotes so every manager sends UI and
-- effect messages the same way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Messaging = {}

export type NotifyStyle = "Info" | "Good" | "Warning" | "Danger" | "Legend" | "Electric"

-- target: a Player, a list of Players, or nil for everyone.
local function send(remote: RemoteEvent, target: (Player | { Player })?, ...: any)
	if target == nil then
		remote:FireAllClients(...)
	elseif typeof(target) == "Instance" then
		if (target :: Player).Parent == Players then
			remote:FireClient(target :: Player, ...)
		end
	else
		for _, player in target :: { Player } do
			if player.Parent == Players then
				remote:FireClient(player, ...)
			end
		end
	end
end

function Messaging.Notify(target: (Player | { Player })?, text: string, style: NotifyStyle?, duration: number?)
	send(Net.UIEvent, target, "Notify", { Text = text, Style = style or "Info", Duration = duration or 2.5 })
end

function Messaging.FloatingText(target: (Player | { Player })?, position: Vector3, text: string, color: Color3?)
	send(Net.UIEvent, target, "FloatingText", { Position = position, Text = text, Color = color })
end

function Messaging.Dialogue(target: Player, speaker: string, text: string)
	send(Net.UIEvent, target, "Dialogue", { Speaker = speaker, Text = text })
end

function Messaging.UI(target: (Player | { Player })?, kind: string, payload: any)
	send(Net.UIEvent, target, kind, payload)
end

function Messaging.Effect(target: (Player | { Player })?, kind: string, payload: any)
	send(Net.EffectEvent, target, kind, payload)
end

function Messaging.Round(target: (Player | { Player })?, kind: string, payload: any)
	send(Net.RoundEvent, target, kind, payload)
end

function Messaging.Sound(target: (Player | { Player })?, key: string, position: Vector3?)
	send(Net.EffectEvent, target, "Sound", { Key = key, Position = position })
end

return Messaging
