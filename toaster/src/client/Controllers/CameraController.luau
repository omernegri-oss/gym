-- Camera comedy: shakes (via Humanoid.CameraOffset so the default camera keeps
-- working), FOV punches and a short, skippable cinematic for the lever pull.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local BASE_FOV = 70

local shakeUntil = 0
local shakeIntensity = 0
local shakeBound = false
local cinematicToken = 0

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function stepShake()
	local h = humanoid()
	local t = os.clock()
	if t >= shakeUntil then
		if h then
			h.CameraOffset = Vector3.zero
		end
		RunService:UnbindFromRenderStep("ToasterShake")
		shakeBound = false
		return
	end
	if h then
		local fade = math.clamp((shakeUntil - t) / 0.3, 0, 1)
		local amount = shakeIntensity * fade
		h.CameraOffset = Vector3.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, (math.random() - 0.5) * amount * 0.5)
	end
end

function CameraController.Shake(intensity: number, duration: number)
	local t = os.clock()
	local alreadyShaking = t < shakeUntil
	shakeIntensity = if alreadyShaking then math.max(shakeIntensity, intensity) else intensity
	shakeUntil = math.max(shakeUntil, t + duration)
	if not shakeBound then
		shakeBound = true
		RunService:BindToRenderStep("ToasterShake", Enum.RenderPriority.Camera.Value + 1, stepShake)
	end
end

function CameraController.FovPunch(amount: number, duration: number)
	camera = workspace.CurrentCamera
	local out = TweenService:Create(camera, TweenInfo.new(duration * 0.3, Enum.EasingStyle.Quad), { FieldOfView = BASE_FOV + amount })
	out:Play()
	out.Completed:Once(function()
		TweenService:Create(camera, TweenInfo.new(duration * 0.7, Enum.EasingStyle.Quad), { FieldOfView = BASE_FOV }):Play()
	end)
end

-- Look at `focus` from `from` for `duration` seconds; any input skips it.
function CameraController.PlayCinematic(from: Vector3, focus: Vector3, duration: number)
	camera = workspace.CurrentCamera
	cinematicToken += 1
	local token = cinematicToken
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(from, focus)
	TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Sine), {
		CFrame = CFrame.lookAt(from + (focus - from).Unit * 18, focus),
	}):Play()

	local skip
	local function finish()
		if token ~= cinematicToken then
			return
		end
		cinematicToken += 1
		if skip then
			skip:Disconnect()
		end
		camera.CameraType = Enum.CameraType.Custom
		local h = humanoid()
		if h then
			camera.CameraSubject = h
		end
	end
	skip = UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			finish()
		end
	end)
	task.delay(duration, finish)
end

function CameraController.Init(_registry) end

function CameraController.Start()
	player.CharacterAdded:Connect(function()
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
	end)
end

return CameraController
