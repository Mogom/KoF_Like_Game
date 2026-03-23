local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Character = Modules:WaitForChild("Character")
local Combat = Modules:WaitForChild("Combat")

local AnimationsFolder = Character:WaitForChild("Animations")
local AnimationsTest = AnimationsFolder:WaitForChild("Test")

local HitstopService = require(Combat:WaitForChild("HitstopService"))

-- Controlador del dummy de entrenamiento: recibe hits, pushback, facing y regen
local DummyController = {}
DummyController.__index = DummyController

-- Constructor: inicializa dummy con posición, animaciones y listeners
function DummyController.new(character)
	local self = setmetatable({}, DummyController)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")

	self.initialPosition = self.root.Position
	self.currentX = self.root.Position.X
	self.lockedZ = self.root.Position.Z

	self.humanoid.AutoRotate = false
	self.humanoid.WalkSpeed = 0
	self.humanoid.JumpPower = 0

	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

	local animator = self.humanoid:WaitForChild("Animator")
	self.animator = animator

	local function loadSequence(sequence)
		local anim = Instance.new("Animation")
		anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
		return animator:LoadAnimation(anim)
	end

	self.animations = {
		Idle = loadSequence(AnimationsTest.Idle_L),
		HurtLight = loadSequence(AnimationsTest.HurtLight_R),
	}

	self.currentAnimation = nil
	self.isInHitstun = false
	self.hitReactionId = 0
	self.lastReceivedHitResultId = character:GetAttribute("HitResultId") or 0

	self.pushVelocityX = 0
	self.pushDecay = 0

	self:PlayAnimation("Idle", 0.1)
	self:_bindHitResult()
	self:_startFacingLoop()
	self:_startRegenLoop()

	return self
end

-- Reproduce animación en el dummy por nombre
function DummyController:PlayAnimation(name, fadeTime)
	fadeTime = fadeTime or 0.1

	local anim = self.animations[name]
	if not anim then
		warn("❌ Dummy animation not found:", name)
		return
	end

	if self.currentAnimation == anim and anim.IsPlaying then
		return
	end

	if self.currentAnimation then
		self.currentAnimation:Stop(fadeTime)
	end

	anim:Play(fadeTime, 1, 1)
	self.currentAnimation = anim
end

-- Escucha cambios en HitResultId del dummy para reaccionar a golpes
function DummyController:_bindHitResult()
	self.character:SetAttribute("HitResultId", self.character:GetAttribute("HitResultId") or 0)

	self.character:GetAttributeChangedSignal("HitResultId"):Connect(function()
		local current = self.character:GetAttribute("HitResultId") or 0

		if current <= self.lastReceivedHitResultId then
			return
		end

		self.lastReceivedHitResultId = current

		local hitData = {
			HitAnimation = self.character:GetAttribute("LastHitAnimation") or "HurtLight",
			HitstunDuration = self.character:GetAttribute("LastHitstunDuration") or 0.25,
			Pushback = self.character:GetAttribute("LastHitPushback") or 0,
			AttackerPositionX = self.character:GetAttribute("LastAttackerPositionX") or 0,
			HitstopFrames = self.character:GetAttribute("LastHitstopFrames") or 0,
		}

		self:OnHit(hitData)
	end)
end

-- Obtiene el root del jugador local más cercano
function DummyController:_getPlayerRoot()
	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

-- Verifica si el dummy puede moverse a la posición X (colisión)
function DummyController:CanMoveToX(targetX)
	local currentPos = self.root.Position

	local testCFrame = CFrame.new(targetX, currentPos.Y, self.lockedZ)
	local testSize = Vector3.new(3, 5, 3)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { self.character }
	overlapParams.MaxParts = 20

	local parts = workspace:GetPartBoundsInBox(testCFrame, testSize, overlapParams)

	for _, part in ipairs(parts) do
		if self:IsBlockingPart(part) then
			return false
		end
	end

	return true
end

-- Verifica si una part es obstáculo de colisión (pared, piso, jugador)
function DummyController:IsBlockingPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if part:IsDescendantOf(self.character) then
		return false
	end

	if part.Name == "HurtboxBody" then
		return false
	end

	if part.Name == "DebugHitbox" then
		return false
	end

	if part.CanCollide == false then
		return false
	end

	return true
end

-- Mueve currentX del dummy con verificación de colisión
function DummyController:MoveCurrentX(deltaX)
	if math.abs(deltaX) <= 0.0001 then
		return
	end

	local targetX = self.currentX + deltaX

	if self:CanMoveToX(targetX) then
		self.currentX = targetX
		return
	end

	-- Intentar mover en pasos más pequeños
	local steps = 6
	local stepDelta = deltaX / steps

	for _ = 1, steps do
		local stepTarget = self.currentX + stepDelta
		if self:CanMoveToX(stepTarget) then
			self.currentX = stepTarget
		else
			break
		end
	end
end

-- Aplica pushback con decay por frame
function DummyController:_updatePushback()
	if math.abs(self.pushVelocityX) > 0.01 then
		self:MoveCurrentX(self.pushVelocityX)

		local sign = self.pushVelocityX >= 0 and 1 or -1
		local absVel = math.abs(self.pushVelocityX)
		absVel = math.max(0, absVel - self.pushDecay)
		self.pushVelocityX = absVel * sign
	else
		self.pushVelocityX = 0
	end
end

-- Loop que hace al dummy mirar siempre hacia el jugador
function DummyController:_startFacingLoop()
	RunService.RenderStepped:Connect(function()
		if not self.character or not self.character.Parent then
			return
		end

		if not self.root or not self.root.Parent then
			return
		end

		local playerRoot = self:_getPlayerRoot()
		if not playerRoot then
			return
		end

		-- =============================================
		-- 🧊 HITSTOP: Congelar movimiento del dummy
		-- =============================================
		if HitstopService:IsInHitstop() then
			-- Solo mantener posición, no aplicar pushback
			local myPos = self.root.Position
			local playerPos = playerRoot.Position
			local faceRight = playerPos.X >= self.currentX
			local angleY = faceRight and math.rad(-90) or math.rad(90)

			self.root.CFrame = CFrame.new(self.currentX, myPos.Y, self.lockedZ) * CFrame.Angles(0, angleY, 0)
			return
		end

		self:_updatePushback()

		local myPos = self.root.Position
		local playerPos = playerRoot.Position

		local faceRight = playerPos.X >= self.currentX
		local angleY = faceRight and math.rad(-90) or math.rad(90)

		local targetY = self.isInHitstun and myPos.Y or self.initialPosition.Y

		self.root.CFrame = CFrame.new(self.currentX, targetY, self.lockedZ) * CFrame.Angles(0, angleY, 0)
	end)
end

-- Loop de regeneración de HP del dummy tras no recibir daño
function DummyController:_startRegenLoop()
	task.spawn(function()
		while self.character and self.character.Parent do
			task.wait(2)

			if self.humanoid.Health < self.humanoid.MaxHealth then
				self.humanoid.Health = math.min(self.humanoid.MaxHealth, self.humanoid.Health + 10)
			end
		end
	end)
end

-- Procesa el hit recibido: hitstop, animación, pushback
function DummyController:OnHit(hitData)
	self.hitReactionId += 1
	local reactionId = self.hitReactionId

	self.isInHitstun = true
	self:PlayAnimation(hitData.HitAnimation or "HurtLight", 0.05)

	local pushback = hitData.Pushback or 0
	local hitstopFrames = hitData.HitstopFrames or 0
	local hitstunDuration = hitData.HitstunDuration or 0.35

	-- =============================================
	-- 🧊 HITSTOP: Congelar animación del dummy
	-- y retrasar el pushback
	-- =============================================
	if hitstopFrames > 0 then
		local animsToFreeze = {}
		if self.currentAnimation then
			table.insert(animsToFreeze, self.currentAnimation)
		end

		HitstopService:Apply(hitstopFrames, animsToFreeze, function()
			-- Después del hitstop: aplicar pushback
			self:_applyPushbackAfterHitstop(hitData, reactionId, pushback, hitstunDuration)
		end)
	else
		self:_applyPushbackAfterHitstop(hitData, reactionId, pushback, hitstunDuration)
	end
end

-- Post-hitstop: sincroniza posición, aplica velocidad de pushback, programa fin hitstun
function DummyController:_applyPushbackAfterHitstop(hitData, reactionId, pushback, hitstunDuration)
	if pushback > 0 then
		local attackerX = hitData.AttackerPositionX or 0
		local direction = self.currentX >= attackerX and 1 or -1

		self.pushVelocityX = direction * (pushback * 0.12)
		self.pushDecay = math.max(0.01, math.abs(self.pushVelocityX) * 0.12)
	end

	task.delay(hitstunDuration, function()
		if not self.character or not self.character.Parent then
			return
		end

		if reactionId ~= self.hitReactionId then
			return
		end

		self.isInHitstun = false
		self:PlayAnimation("Idle", 0.1)
	end)
end

-- Resetea posición del dummy a su spawn original
function DummyController:ResetPosition()
	if not self.root or not self.root.Parent then
		return
	end

	self.currentX = self.initialPosition.X
	self.pushVelocityX = 0
	self.pushDecay = 0
	self.root.CFrame = CFrame.new(self.initialPosition)
	self.humanoid.Health = self.humanoid.MaxHealth
end

return DummyController
