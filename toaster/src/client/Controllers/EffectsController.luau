-- Local visual effects. The server sends small event payloads; every client
-- renders them here (parts are local, short-lived and cleaned with Debris).
-- Also applies physics reactions the server asks of the LOCAL character
-- (knockback, slips, slides, rolls), since each client owns its own physics.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ForkPath = require(Shared.ForkPath)
local Maid = require(Shared.Maid)
local Net = require(Shared.Net)
local Theme = require(Shared.Theme)

local EffectsController = {}

local C = Theme.Colors
local RA = Constants.RoundAttr
local PHASES = Constants.Phases
local player = Players.LocalPlayer
local registry
local rng = Random.new()

local effectsFolder: Folder
local hazardMaid = Maid.new()
local motionMaid = Maid.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function localPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = props.Parent or effectsFolder
	return p
end

local UP_AXIS = CFrame.Angles(0, 0, math.rad(90))

local function disc(position: Vector3, radius: number, color: Color3, material: Enum.Material?, transparency: number?): BasePart
	return localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * UP_AXIS,
		Color = color,
		Material = material or Enum.Material.Neon,
		Transparency = transparency or 0.4,
	})
end

local function tween(
	instance: Instance,
	seconds: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local t =
		TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Reusable particle burst emitter (object pooling: one part, many Emit calls).
local burstPart: BasePart
local burstEmitter: ParticleEmitter
local function burst(position: Vector3, color: Color3, count: number, speed: number?)
	burstPart.Position = position
	burstEmitter.Color = ColorSequence.new(color)
	burstEmitter.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	burstEmitter:Emit(count)
end

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

------------------------------------------------------------------ toaster: coils, lever, hand, pop pad

local coilState = "Cold"
local function setCoils(state: string)
	if coilState == state then
		return
	end
	coilState = state
	for _, coil in CollectionService:GetTagged(Constants.Tags.Coil) do
		local part = coil :: BasePart
		if state == "Hot" then
			part.Material = Enum.Material.Neon
			tween(part, 1.2, { Color = C.CoilHot })
		elseif state == "Warn" then
			part.Material = Enum.Material.Neon
			part.Color = C.CoilWarn
		else
			part.Material = Enum.Material.SmoothPlastic
			tween(part, 1, { Color = C.CoilCold })
		end
	end
end

local function refreshCoils()
	local heatActive = Net.RoundState:GetAttribute(RA.HeatActive) == true
	local phase = Net.RoundState:GetAttribute(RA.Phase)
	setCoils(if heatActive or phase == PHASES.Launch then "Hot" else "Cold")
end

local function leverKnob(): BasePart?
	return CollectionService:GetTagged(Constants.Tags.LeverKnob)[1] :: BasePart?
end

local function setKnob(down: boolean, seconds: number)
	local knob = leverKnob()
	if not knob then
		return
	end
	local y = if down then knob:GetAttribute("DownY") else knob:GetAttribute("UpY")
	local target = Vector3.new(knob.Position.X, y :: number, knob.Position.Z)
	tween(knob, seconds, { CFrame = CFrame.new(target) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local function handModel(): Model?
	local folder = workspace:FindFirstChild("EventObjects")
	return folder and folder:FindFirstChild("GiantHand") :: Model?
end

-- Tween a model's pivot on the client via a CFrameValue.
local function tweenPivot(model: Model, target: CFrame, seconds: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		model:PivotTo(value.Value)
	end)
	local t = tween(value, seconds, { Value = target }, style, direction)
	t.Completed:Once(function()
		conn:Disconnect()
		value:Destroy()
	end)
	return t
end

local function playHandSequence(payload)
	local hand = handModel()
	local knob = leverKnob()
	if not hand or not knob then
		return
	end
	local upY = knob:GetAttribute("UpY") :: number
	local downY = knob:GetAttribute("DownY") :: number
	local knobTop = Vector3.new(knob.Position.X, upY + 2.5, knob.Position.Z)
	local face = CFrame.Angles(0, math.rad(180), 0) -- nails face the toaster window side
	local skyStart = CFrame.new(knobTop + Vector3.new(0, 220, 30)) * face
	local hover = CFrame.new(knobTop + Vector3.new(0, 26, 8)) * face
	local grab = CFrame.new(knobTop + Vector3.new(0, 1, 2)) * face
	local pulled = CFrame.new(Vector3.new(knobTop.X, downY + 2.5, knobTop.Z) + Vector3.new(0, 0, 2)) * face
	local leave = CFrame.new(Vector3.new(knobTop.X, downY + 2.5, knobTop.Z) + Vector3.new(0, 260, 40)) * face

	local elapsed = now() - (payload.StartedAt or now())
	if elapsed > 3 then
		setKnob(true, 0.1)
		return
	end
	hand:PivotTo(skyStart)
	registry.SoundController.Play("HandAppear")
	registry.CameraController.PlayCinematic(knobTop + Vector3.new(-60, 30, 120), knobTop + Vector3.new(0, 10, 0), payload.Duration or 3.4)

	task.spawn(function()
		tweenPivot(hand, hover, 0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out).Completed:Wait()
		task.wait(0.45) -- dramatic pause
		tweenPivot(hand, grab, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		registry.SoundController.Play("Lever")
		setKnob(true, 0.55)
		tweenPivot(hand, pulled, 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		registry.CameraController.Shake(1.4, 0.7)
		registry.CameraController.FovPunch(8, 0.6)
		registry.SoundController.Play("CoilsOn")
		setCoils("Hot")
		task.wait(0.35)
		tweenPivot(hand, leave, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
		hand:PivotTo(CFrame.new(0, 2000, 0))
	end)
end

local function calmWarning(payload)
	-- Flickers, clicks and tiny vibrations before the hand arrives.
	task.spawn(function()
		while now() < (payload.EndsAt or 0) - 0.5 do
			local phase = Net.RoundState:GetAttribute(RA.Phase)
			if phase ~= PHASES.Calm then
				break
			end
			registry.SoundController.Play("ToasterClick")
			setCoils("Warn")
			task.wait(0.15)
			setCoils("Cold")
			registry.CameraController.Shake(0.25, 0.3)
			task.wait(rng:NextNumber(1.2, 2.4))
		end
	end)
end

local function popPadGlow(popAt: number)
	for _, pad in CollectionService:GetTagged(Constants.Tags.PopPad) do
		local part = pad :: BasePart
		local original = part.Color
		part.Material = Enum.Material.Neon
		task.spawn(function()
			while now() < popAt do
				part.Color = if math.floor(os.clock() * 4) % 2 == 0 then C.Orange else C.Gold
				task.wait(0.1)
			end
			part.Material = Enum.Material.SmoothPlastic
			part.Color = original
		end)
	end
end

------------------------------------------------------------------ fork boss

local function forkModel(): Model?
	local folder = workspace:FindFirstChild("EventObjects")
	return folder and folder:FindFirstChild("GiantFork") :: Model?
end

local function runFork(payload)
	local fork = forkModel()
	if not fork then
		return
	end
	local center: Vector3 = payload.Center
	local hoverY = 6
	local function pathPoint(t: number): Vector3
		local ox, oz = ForkPath.Offset(t - payload.StartAt, payload)
		return center + Vector3.new(ox, hoverY + math.sin(t * 3) * 1.5, oz)
	end
	local startPoint = pathPoint(payload.StartAt)
	fork:PivotTo(CFrame.new(startPoint + Vector3.new(0, 200, 0)))
	tweenPivot(fork, CFrame.new(startPoint), math.max(0.3, payload.StartAt - now()), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	registry.SoundController.Play("ForkWarning")

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = now()
		if t < payload.StartAt then
			return
		end
		if t >= payload.EndAt or Net.RoundState:GetAttribute(RA.ForkActive) ~= true then
			connection:Disconnect()
			local here = fork:GetPivot()
			tweenPivot(fork, here + Vector3.new(0, 220, 0), 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
				fork:PivotTo(CFrame.new(0, 2200, 0))
			end)
			return
		end
		fork:PivotTo(CFrame.new(pathPoint(t)) * CFrame.Angles(0, t * 0.6, 0))
	end)
	hazardMaid:Give(connection)
end

local function bolt(from: Vector3, to: Vector3)
	local segments = 6
	local previous = from
	for i = 1, segments do
		local alpha = i / segments
		local point = from:Lerp(to, alpha)
		if i < segments then
			point += Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1, 1), rng:NextNumber(-3, 3))
		end
		local length = (point - previous).Magnitude
		local seg = localPart({
			Size = Vector3.new(0.5, 0.5, length),
			CFrame = CFrame.lookAt((previous + point) / 2, point),
			Color = C.Electric,
			Material = Enum.Material.Neon,
		})
		Debris:AddItem(seg, 0.25)
		previous = point
	end
end

------------------------------------------------------------------ hazards and items

local JUNK_BUILDERS = {
	function(cf: CFrame): { BasePart }
		return {
			localPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = cf, Color = C.Butter }),
			localPart({ Size = Vector3.new(1.6, 0.6, 1.2), CFrame = cf * CFrame.new(0, 0, -1.8), Color = C.Orange }),
		}
	end,
	function(cf: CFrame): { BasePart }
		return {
			localPart({ Size = Vector3.new(0.6, 0.4, 7), CFrame = cf, Color = C.Chrome, Material = Enum.Material.Metal }),
			localPart({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(2.2, 2.2, 2.2),
				CFrame = cf * CFrame.new(0, 0, -3.6),
				Color = C.Chrome,
				Material = Enum.Material.Metal,
			}),
		}
	end,
	function(cf: CFrame): { BasePart }
		return {
			localPart({ Size = Vector3.new(2, 4, 1.2), CFrame = cf, Color = Color3.fromRGB(230, 90, 120), Material = Enum.Material.Fabric }),
			localPart({
				Size = Vector3.new(2, 1.4, 2.8),
				CFrame = cf * CFrame.new(0, -2, -0.8),
				Color = Color3.fromRGB(230, 90, 120),
				Material = Enum.Material.Fabric,
			}),
		}
	end,
}

local function itemVisual(kind: string, cf: CFrame): { BasePart }
	if kind == "Junk" then
		return JUNK_BUILDERS[rng:NextInteger(1, #JUNK_BUILDERS)](cf)
	elseif kind == "Butter" then
		return { localPart({ Size = Vector3.new(2.6, 1.1, 1.8), CFrame = cf, Color = C.Butter }) }
	elseif kind == "GoldenCrumb" then
		return { localPart({ Size = Vector3.new(1.6, 1.2, 1.4), CFrame = cf, Color = C.Legend, Material = Enum.Material.Neon }) }
	end
	return { localPart({ Size = Vector3.new(1.3, 0.9, 1.1), CFrame = cf, Color = C.Crumb }) }
end

local function fallingItem(payload)
	local position: Vector3 = payload.Position
	local impactAt: number = payload.ImpactAt
	local fallTime: number = payload.FallTime
	local shadow = disc(
		position,
		if payload.Kind == "Junk" then 4.5 else 2.5,
		if payload.Kind == "Junk" then C.Danger else C.Charcoal,
		Enum.Material.SmoothPlastic,
		0.5
	)
	shadow.Size = Vector3.new(0.2, 1, 1)
	local finalSize = if payload.Kind == "Junk" then 9 else 5
	tween(shadow, math.max(0.2, impactAt - now()), { Size = Vector3.new(0.2, finalSize, finalSize) })
	Debris:AddItem(shadow, math.max(0.3, impactAt - now() + 0.1))
	hazardMaid:Give(shadow)

	task.delay(math.max(0, impactAt - fallTime - now()), function()
		local startCf = CFrame.new(position + Vector3.new(0, 90, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		local parts = itemVisual(payload.Kind, startCf)
		local model = Instance.new("Model")
		for _, part in parts do
			part.Parent = model
		end
		model.Parent = effectsFolder
		local landing = CFrame.new(position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0)
		tweenPivot(model, landing, math.max(0.1, impactAt - now()), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(model, math.max(0.2, impactAt - now()) + (if payload.Kind == "Junk" then 1.2 else 0.05))
	end)
end

local function hotSpot(payload)
	local position: Vector3 = payload.Position
	local warning = disc(position, payload.Radius, C.Danger, Enum.Material.Neon, 0.75)
	hazardMaid:Give(warning)
	task.spawn(function()
		while now() < payload.StartsAt and warning.Parent do
			warning.Transparency = if math.floor(os.clock() * 6) % 2 == 0 then 0.55 else 0.85
			task.wait(0.08)
		end
		if not warning.Parent then
			return
		end
		warning.Transparency = 0.35
		warning.Color = C.CoilHot
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(255, 160, 120)
		smoke.Opacity = 0.15
		smoke.Size = 6
		smoke.Parent = warning
		task.wait(math.max(0, payload.EndsAt - now()))
		if warning.Parent then
			tween(warning, 0.4, { Transparency = 1 })
			Debris:AddItem(warning, 0.45)
		end
	end)
end

local function pulseWarning(position: Vector3, radius: number, color: Color3, untilTime: number)
	local warning = disc(position, radius, color, Enum.Material.Neon, 0.7)
	hazardMaid:Give(warning)
	task.spawn(function()
		while now() < untilTime and warning.Parent do
			warning.Transparency = if math.floor(os.clock() * 8) % 2 == 0 then 0.45 else 0.85
			task.wait(0.06)
		end
		if warning.Parent then
			warning:Destroy()
		end
	end)
end

local function steam(payload)
	local column = localPart({
		Size = Vector3.new(payload.Radius * 2, 30, payload.Radius * 2),
		CFrame = CFrame.new(payload.Position + Vector3.new(0, 15, 0)),
		Transparency = 1,
	})
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.new(1, 1, 1)
	smoke.Opacity = 0.5
	smoke.Size = 10
	smoke.RiseVelocity = 25
	smoke.Parent = column
	task.delay(1.2, function()
		smoke.Enabled = false
	end)
	Debris:AddItem(column, 4)
	burst(payload.Position + Vector3.new(0, 2, 0), Color3.new(1, 1, 1), 25, 30)
end

local function projectile(payload)
	local color = if payload.Kind == "Jam" then C.Jam else C.Nutella
	local ball = localPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = payload.From,
		Color = color,
		Material = Enum.Material.Glass,
	})
	local from: Vector3, to: Vector3 = payload.From, payload.To
	local duration = math.max(0.05, payload.Duration)
	local arcHeight = if payload.Kind == "Jam" then 3 else 10
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min(1, (os.clock() - start) / duration)
		ball.Position = from:Lerp(to, alpha) + Vector3.new(0, math.sin(alpha * math.pi) * arcHeight, 0)
		if alpha >= 1 then
			connection:Disconnect()
			ball:Destroy()
		end
	end)
end

local function splat(position: Vector3, color: Color3)
	local s = disc(position - Vector3.new(0, 2.4, 0), 2.2, color, Enum.Material.Glass, 0.1)
	tween(s, 0.15, { Size = Vector3.new(0.2, 5, 5) }, Enum.EasingStyle.Back)
	Debris:AddItem(s, 3)
	burst(position, color, 18, 18)
end

local function puddle(payload)
	local p = disc(payload.Position, payload.Radius, C.Nutella, Enum.Material.Glass, 0.05)
	p.Size = Vector3.new(0.2, 2, 2)
	tween(p, 0.3, { Size = Vector3.new(0.2, payload.Radius * 2, payload.Radius * 2) }, Enum.EasingStyle.Back)
	hazardMaid:Give(p)
	task.delay(payload.Duration - 0.5, function()
		if p.Parent then
			tween(p, 0.5, { Transparency = 1 })
			Debris:AddItem(p, 0.55)
		end
	end)
end

local function flake(payload)
	for _ = 1, 3 do
		local f = localPart({
			Size = Vector3.new(rng:NextNumber(0.8, 1.6), 0.1, rng:NextNumber(0.5, 1.1)),
			CFrame = CFrame.new(payload.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), 0.15, rng:NextNumber(-1.5, 1.5)))
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			Color = Color3.fromRGB(233, 169, 78),
		})
		hazardMaid:Give(f)
		Debris:AddItem(f, payload.Lifetime)
	end
end

local function shockwave(payload)
	local ring = disc(payload.Position, 1, C.Legend, Enum.Material.Neon, 0.2)
	tween(ring, 0.45, { Size = Vector3.new(0.2, payload.Radius * 2, payload.Radius * 2), Transparency = 1 })
	Debris:AddItem(ring, 0.5)
	burst(payload.Position, C.Legend, 30, 35)
	local r = root()
	if r and (r.Position - payload.Position).Magnitude < payload.Radius * 2 then
		registry.CameraController.Shake(1, 0.4)
	end
end

local function landing(payload)
	local color = Theme.ZoneColors[payload.Zone] or C.Cream
	local ring = disc(payload.Position - Vector3.new(0, 2.5, 0), 1, color, Enum.Material.Neon, 0.2)
	tween(ring, 0.5, { Size = Vector3.new(0.2, 14, 14), Transparency = 1 })
	Debris:AddItem(ring, 0.55)
	burst(payload.Position, Color3.fromRGB(196, 160, 118), 20, 20)
	if payload.Zone == "Jackpot" or payload.Zone == "Perfect" then
		for _, confettiColor in { C.Legend, C.Orange, C.Electric, C.Jam } do
			burst(payload.Position + Vector3.new(0, 3, 0), confettiColor, 12, 40)
		end
	end
	registry.SoundController.Play("Landing", payload.Position)
end

local function clearHazards()
	hazardMaid:Clean()
end

------------------------------------------------------------------ local physics reactions

local function knockback(payload)
	local r, h = root(), humanoid()
	if not r or not h then
		return
	end
	local velocity: Vector3 = payload.Velocity
	if velocity.Y < 20 then
		velocity = Vector3.new(velocity.X, 20, velocity.Z)
	end
	h:ChangeState(Enum.HumanoidStateType.Freefall)
	r.AssemblyLinearVelocity = velocity
	registry.CameraController.Shake(0.6, 0.25)
end

local function slip(payload)
	local r, h = root(), humanoid()
	if not r or not h then
		return
	end
	h.PlatformStand = true
	r.AssemblyLinearVelocity = r.AssemblyLinearVelocity + Vector3.new(rng:NextNumber(-12, 12), 18, rng:NextNumber(-12, 12))
	r.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8))
	task.delay(payload.Duration, function()
		if h.Parent then
			h.PlatformStand = false
			h:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- Horizontal-only LinearVelocity on the local root: unlike writing velocity
-- every frame, it doesn't fight the Humanoid controller. Gravity is untouched.
local function horizontalDrive(r: BasePart, name: string): LinearVelocity
	local attachment = Instance.new("Attachment")
	attachment.Name = name .. "Attachment"
	attachment.Parent = r
	local drive = Instance.new("LinearVelocity")
	drive.Name = name
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	drive.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	drive.VectorVelocity = Vector3.zero
	drive.Parent = r
	motionMaid:Set(name .. "Attachment", attachment)
	motionMaid:Set(name .. "Drive", drive)
	return drive
end

local function stopDrive(name: string)
	motionMaid:Set(name, nil)
	motionMaid:Set(name .. "Drive", nil)
	motionMaid:Set(name .. "Attachment", nil)
end

local function slide(payload)
	local r, h = root(), humanoid()
	if not r or not h then
		return
	end
	local flat = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z)
	local direction = if flat.Magnitude > 2 then flat.Unit else r.CFrame.LookVector
	local slideVelocity = direction * math.max(flat.Magnitude * 1.6, 34)
	local deadline = os.clock() + payload.Duration
	local drive = horizontalDrive(r, "Slide")
	motionMaid:Set(
		"Slide",
		RunService.Heartbeat:Connect(function(dt)
			if os.clock() >= deadline or not r.Parent then
				stopDrive("Slide")
				return
			end
			-- Barely any traction: input only nudges the slide.
			slideVelocity = slideVelocity * (1 - 0.6 * dt) + h.MoveDirection * 20 * dt
			drive.VectorVelocity = Vector3.new(slideVelocity.X, 0, slideVelocity.Z)
		end)
	)
	registry.SoundController.Play("NutellaSlip")
end

local function roll(payload)
	local r, h = root(), humanoid()
	if not r or not h then
		return
	end
	local direction = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z).Unit
	local deadline = os.clock() + payload.Duration
	local drive = horizontalDrive(r, "Roll")
	motionMaid:Set(
		"Roll",
		RunService.Heartbeat:Connect(function(dt)
			if os.clock() >= deadline or not r.Parent or h.Health <= 0 then
				stopDrive("Roll")
				return
			end
			local desired = h.MoveDirection
			if desired.Magnitude > 0.1 then
				-- Reduced turning: rotate toward input by at most TurnRate rad/s.
				local angle = math.atan2(direction:Cross(desired).Y, direction:Dot(desired))
				local step = math.clamp(angle, -payload.TurnRate * dt, payload.TurnRate * dt)
				direction = (CFrame.Angles(0, step, 0) * direction).Unit
			end
			drive.VectorVelocity = direction * payload.Speed
		end)
	)
end

local function slamJump(payload)
	local r, h = root(), humanoid()
	if not r or not h then
		return
	end
	h:ChangeState(Enum.HumanoidStateType.Jumping)
	r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, payload.Velocity, r.AssemblyLinearVelocity.Z)
	task.delay(0.3, function()
		if r.Parent then
			r.AssemblyLinearVelocity = Vector3.new(0, -payload.Velocity * 1.6, 0)
		end
	end)
end

------------------------------------------------------------------ per-character visuals (all clients)

-- Spins every rolling bagel and shows jam on stuck players.
local rollAngles: { [Model]: number } = {}
local function stepCharacterVisuals(dt: number)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local visual = character and character:FindFirstChild("BreadVisual")
		local core = visual and visual:FindFirstChild("BreadCore")
		local joint = core and core:FindFirstChild("BreadJoint") :: Weld?
		if character and joint then
			if character:GetAttribute(Constants.CharAttr.Rolling) == true then
				local angle = (rollAngles[character] or 0) - dt * 14
				rollAngles[character] = angle
				joint.C0 = CFrame.new(0, 1.4, 0) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -1.4, 0)
			elseif rollAngles[character] then
				rollAngles[character] = nil
				joint.C0 = CFrame.identity
			end
		end
	end
	for character in rollAngles do
		if not character.Parent then
			rollAngles[character] = nil
		end
	end
end

local function attachJam(character: Model)
	local r = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local existing = character:FindFirstChild("JamSplat")
	if character:GetAttribute(Constants.CharAttr.Stuck) == true then
		if existing or not r then
			return
		end
		local jam = Instance.new("Part")
		jam.Name = "JamSplat"
		jam.Shape = Enum.PartType.Ball
		jam.Size = Vector3.new(6, 6, 6)
		jam.Color = C.Jam
		jam.Material = Enum.Material.Glass
		jam.Transparency = 0.35
		jam.CanCollide = false
		jam.CanQuery = false
		jam.CanTouch = false
		jam.Massless = true
		jam.CFrame = r.CFrame * CFrame.new(0, 1, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = r
		weld.Part1 = jam
		weld.Parent = jam
		jam.Parent = character
		burst(r.Position, C.Jam, 20, 16)
	elseif existing then
		existing:Destroy()
	end
end

local function decorateCharacter(other: Player, character: Model)
	character:GetAttributeChangedSignal(Constants.CharAttr.Stuck):Connect(function()
		attachJam(character)
	end)
	local head = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not head then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(200, 44)
	billboard.StudsOffset = Vector3.new(0, 6.2, 0)
	billboard.MaxDistance = 120
	billboard.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 0.55)
	name.Font = Theme.Fonts.Display
	name.TextScaled = true
	name.TextColor3 = C.Cream
	name.TextStrokeTransparency = 0.3
	name.Text = other.DisplayName
	name.Parent = billboard
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.55)
	title.Size = UDim2.fromScale(1, 0.45)
	title.Font = Theme.Fonts.Body
	title.TextScaled = true
	title.TextColor3 = C.Gold
	title.TextStrokeTransparency = 0.4
	title.Parent = billboard
	local function refresh()
		local t = other:GetAttribute(Constants.Attr.Title) or ""
		if other:GetAttribute(Constants.Attr.IsCharcoal) == true then
			title.Text = "🪨 CHARCOAL"
			title.TextColor3 = C.CreamMuted
		else
			title.Text = t
			title.TextColor3 = C.Gold
		end
	end
	refresh()
	local c1 = other:GetAttributeChangedSignal(Constants.Attr.Title):Connect(refresh)
	local c2 = other:GetAttributeChangedSignal(Constants.Attr.IsCharcoal):Connect(refresh)
	character.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)
	billboard.Adornee = head
	billboard.Parent = head
	local h = character:FindFirstChildOfClass("Humanoid")
	if h then
		h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function watchPlayer(other: Player)
	if other.Character then
		task.spawn(decorateCharacter, other, other.Character)
	end
	other.CharacterAdded:Connect(function(character)
		decorateCharacter(other, character)
	end)
end

------------------------------------------------------------------ pickups spin

local function stepPickups(dt: number)
	local spin = CFrame.Angles(0, dt * 2, 0)
	for _, pickup in CollectionService:GetTagged(Constants.Tags.Pickup) do
		local part = pickup :: BasePart
		if part.Transparency < 1 then
			part.CFrame = part.CFrame * spin
		end
	end
end

------------------------------------------------------------------ wiring

local EFFECT_HANDLERS = {
	Sound = function(p)
		registry.SoundController.Play(p.Key, p.Position)
	end,
	Shake = function(p)
		registry.CameraController.Shake(p.Intensity, p.Duration)
	end,
	Knockback = knockback,
	Slip = slip,
	Slide = slide,
	Roll = roll,
	SlamJump = slamJump,
	Pickup = function(p)
		burst(p.Position, if p.Kind == "Butter" then C.Butter elseif p.Kind == "GoldenCrumb" then C.Legend else C.Crumb, 10, 12)
	end,
	Flake = flake,
	Puddle = puddle,
	Projectile = projectile,
	Splat = function(p)
		splat(p.Position, if p.Kind == "Jam" then C.Jam else C.Nutella)
	end,
	Shockwave = shockwave,
	FallingItem = fallingItem,
	Impact = function(p)
		burst(p.Position + Vector3.new(0, 1, 0), if p.Kind == "Junk" then C.Chrome else C.Crumb, 14, 20)
		local r = root()
		if p.Kind == "Junk" and r and (r.Position - p.Position).Magnitude < 25 then
			registry.CameraController.Shake(0.5, 0.25)
		end
	end,
	HotSpot = hotSpot,
	SteamWarning = function(p)
		pulseWarning(p.Position, p.Radius, Color3.new(1, 1, 1), p.At)
	end,
	Steam = steam,
	Fork = runFork,
	ForkZapWarning = function(p)
		pulseWarning(p.Position, p.Radius, C.Electric, p.At)
	end,
	ForkZap = function(p)
		local fork = forkModel()
		local tip = if fork then fork:GetPivot().Position else p.Position + Vector3.new(0, 8, 0)
		for _ = 1, 3 do
			bolt(tip, p.Position + Vector3.new(rng:NextNumber(-p.Radius, p.Radius) * 0.6, 0, rng:NextNumber(-p.Radius, p.Radius) * 0.6))
		end
		local flash = disc(p.Position, p.Radius, C.Electric, Enum.Material.Neon, 0.1)
		tween(flash, 0.4, { Transparency = 1 })
		Debris:AddItem(flash, 0.45)
		local r = root()
		if r and (r.Position - p.Position).Magnitude < p.Radius * 2.5 then
			registry.CameraController.Shake(1.2, 0.35)
		end
	end,
	Landing = landing,
	Pop = function(p)
		for _, color in { C.Orange, C.Gold, C.Crumb } do
			burst(p.Position, color, 25, 60)
		end
		registry.CameraController.Shake(1.5, 0.6)
		setKnob(false, 0.15)
	end,
	ClearHazards = clearHazards,
}

local ROUND_HANDLERS = {
	CalmWarning = calmWarning,
	HandSequence = playHandSequence,
	Countdown = function(p)
		popPadGlow(p.PopAt)
		registry.CameraController.Shake(0.3, 3)
	end,
	Launched = function(_p)
		registry.CameraController.FovPunch(18, 1.2)
		registry.CameraController.Shake(1.2, 0.5)
		motionMaid:Clean()
	end,
	RoundEnded = function(_p)
		clearHazards()
		motionMaid:Clean()
		setKnob(false, 0.3)
		setCoils("Cold")
	end,
}

function EffectsController.Init(reg)
	registry = reg
end

function EffectsController.Start()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "LocalEffects"
	effectsFolder.Parent = workspace

	burstPart = localPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	burstEmitter = Instance.new("ParticleEmitter")
	burstEmitter.Enabled = false
	burstEmitter.Lifetime = NumberRange.new(0.4, 0.8)
	burstEmitter.Size = NumberSequence.new(0.6, 0)
	burstEmitter.SpreadAngle = Vector2.new(180, 180)
	burstEmitter.Acceleration = Vector3.new(0, -30, 0)
	burstEmitter.LightEmission = 0.3
	burstEmitter.Parent = burstPart

	Net.EffectEvent.OnClientEvent:Connect(function(kind: string, payload: any)
		local handler = EFFECT_HANDLERS[kind]
		if handler then
			local ok, err = pcall(handler, payload)
			if not ok then
				warn("[EffectsController]", kind, err)
			end
		end
	end)
	Net.RoundEvent.OnClientEvent:Connect(function(kind: string, payload: any)
		local handler = ROUND_HANDLERS[kind]
		if handler then
			local ok, err = pcall(handler, payload)
			if not ok then
				warn("[EffectsController]", kind, err)
			end
		end
	end)

	Net.RoundState:GetAttributeChangedSignal(RA.HeatActive):Connect(refreshCoils)
	Net.RoundState:GetAttributeChangedSignal(RA.Phase):Connect(refreshCoils)
	refreshCoils()

	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	RunService.RenderStepped:Connect(function(dt)
		stepCharacterVisuals(dt)
		stepPickups(dt)
	end)

	player.CharacterAdded:Connect(function()
		motionMaid:Clean()
	end)
end

return EffectsController
