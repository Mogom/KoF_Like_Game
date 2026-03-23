local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")
local Character = Modules:WaitForChild("Character")

local Attacks = require(Combat:WaitForChild("Attacks"))

local Hitbox = require(Combat:WaitForChild("Hitbox"))
local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

local AnimationsFolder = Character:WaitForChild("Animations")
local AnimationsTest = AnimationsFolder:WaitForChild("Test")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local SetOpponentEvent = RemoteEvents:WaitForChild("SetOpponent")
local ReplicateAnimationEvent = RemoteEvents:WaitForChild("ReplicateAnimation")

-- [LEGACY] Versi\u00f3n anterior del CharacterController monol\u00edtico (deprecado)\nlocal CharacterController = {}\nCharacterController.__index = CharacterController

local RunService = game:GetService("RunService")

local DEBUG_HITBOX = false

function CharacterController:PlayAnimation(baseName, fadeTime)
	fadeTime = fadeTime or 0.15

	-- ✅ Construir nombre completo con dirección
	local fullName = baseName .. "_" .. self.currentDirection

	if DEBUG_HITBOX then
		print("🎬 Playing animation:", fullName, "(base:", baseName, "dir:", self.currentDirection .. ")")
	end

	if self.currentAnimation then
		self.currentAnimation:Stop(fadeTime)
	end

	local anim = self.animations[fullName]

	if anim then
		anim:Play(0, 1, 1)
		self.currentAnimation = anim
		ReplicateAnimationEvent:FireServer(fullName)
	else
		warn("❌ Animation not found:", fullName)

		-- ✅ Fallback: intentar con dirección opuesta
		local fallbackName = baseName .. "_" .. (self.currentDirection == "R" and "L" or "R")
		local fallbackAnim = self.animations[fallbackName]

		if fallbackAnim then
			print("⚠️ Using fallback animation:", fallbackName)
			fallbackAnim:Play(0, 1, 1)
			self.currentAnimation = fallbackAnim
		else
			warn("❌ No animation available for:", baseName)
		end
	end
end

function CharacterController:SetOpponent(opponentRoot)
	self.opponentRoot = opponentRoot
end

function CharacterController:GetFacingDirection()
	if not self.opponentRoot then
		return 1
	end

	if self.opponentRoot.Position.X > self.root.Position.X then
		return 1
	else
		return -1
	end
end

function CharacterController.new(character, machine)
	local self = setmetatable({}, CharacterController)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	self.root = character:WaitForChild("HumanoidRootPart")
	self.lockedZ = self.root.Position.Z
	self.hurtbox = Hurtbox.new(character)

	self.machine = machine
	self.moveDirection = 0
	self.currentDirection = "R"
	self.speed = 16
	self.attackLocked = false
	self.lastAttack = nil

	self.punchComboCount = 0
	self.lastPunchTime = 0
	self.punchResetTime = 1 -- Tiempo antes de resetear contador

	self.isCrouching = false
	self.crouchSpeedMultiplier = 0.2 -- reduce speed cuando agachado
	self.facingRight = true

	self.humanoid.AutoRotate = false
	--self.humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	self.animator = self.humanoid:WaitForChild("Animator")

	--COMENTAR SOLO EN DESARROLLO, DEBE EXISTIR LA LINEA EN PRODUCCION
	--self.animations = {

	--	Idle = self.animator:LoadAnimation(AnimationsFolder.Idle),
	--	Walk = self.animator:LoadAnimation(AnimationsFolder.Walk),
	--	Punch = self.animator:LoadAnimation(AnimationsFolder.Punch)

	--}

	--ANIMACIONES EN DESARROLLO, LA LINEA DEBE ESTAR COMENTADA EN PRODUCCION
	-- ✅ Cargar animaciones con dirección (Left/Right)
	local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

	local function loadSequence(animator, sequence)
		local anim = Instance.new("Animation")
		anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
		return animator:LoadAnimation(anim)
	end

	self.animations = {
		-- Idle
		Idle_R = loadSequence(self.animator, AnimationsTest.Idle_R),
		Idle_L = loadSequence(self.animator, AnimationsTest.Idle_L),

		-- Walk
		Walk_R = loadSequence(self.animator, AnimationsTest.Walk_R),
		Walk_L = loadSequence(self.animator, AnimationsTest.Walk_L),

		-- Punch
		Punch_R = loadSequence(self.animator, AnimationsTest.Punch_R),
		Punch_L = loadSequence(self.animator, AnimationsTest.Punch_L),

		Punch2_R = loadSequence(self.animator, AnimationsTest.Punch2_R),
		Punch2_L = loadSequence(self.animator, AnimationsTest.Punch2_L),

		Punch3_R = loadSequence(self.animator, AnimationsTest.Punch3_R),
		Punch3_L = loadSequence(self.animator, AnimationsTest.Punch3_L),

		-- Heavy Punch
		HeavyPunch_R = loadSequence(self.animator, AnimationsTest.Heavy_R),
		HeavyPunch_L = loadSequence(self.animator, AnimationsTest.Heavy_R),

		-- Hurt
		HurtLight_R = loadSequence(self.animator, AnimationsTest.HurtLight_R),
		HurtLight_L = loadSequence(self.animator, AnimationsTest.HurtLight_R),
	}

	-- ✅ Escuchar cuando el servidor asigna un oponente
	SetOpponentEvent.OnClientEvent:Connect(function(opponentCharacter)
		if opponentCharacter and opponentCharacter:FindFirstChild("HumanoidRootPart") then
			self.opponentRoot = opponentCharacter.HumanoidRootPart
			self.opponent = opponentCharacter

			-- ✅ CARGAR ANIMACIONES DEL OPONENTE
			self:LoadOpponentAnimations(opponentCharacter)

			-- Actualizar cámara
			local CameraHandler = require(ReplicatedStorage.Modules.Combat.CameraHandler)
			if CameraHandler.SetOpponent then
				CameraHandler:SetOpponent(opponentCharacter)
			end
		end
	end)

	-- ✅ Escuchar animaciones del oponente
	ReplicateAnimationEvent.OnClientEvent:Connect(function(character, animationName)
		if character ~= self.opponent then
			return
		end

		-- Reproducir en el oponente
		if self.opponentAnimations and self.opponentAnimations[animationName] then
			self.opponentAnimations[animationName]:Play()
		else
			warn("❌ Opponent animation not found:", animationName)
		end
	end)

	local function findOpponent()
		-- Primero buscar dummy (training mode)
		local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
		if dummy and dummy:FindFirstChild("HumanoidRootPart") then
			return dummy.HumanoidRootPart
		end

		-- Buscar otro jugador (versus mode)
		local Players = game:GetService("Players")
		local player = Players.LocalPlayer

		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer.Character then
				local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if otherRoot then
					return otherRoot
				end
			end
		end

		return nil
	end

	-- Buscar oponente al inicio
	self.opponentRoot = findOpponent()
	if self.opponentRoot then
		self.opponent = self.opponentRoot.Parent
	end

	-- Re-buscar cada 2 segundos por si aparece/desaparece
	task.spawn(function()
		while true do
			task.wait(2)
			if not self.opponentRoot or not self.opponentRoot.Parent then
				self.opponentRoot = findOpponent()
				if self.opponentRoot then
					self.opponent = self.opponentRoot.Parent
				end
			end
		end
	end)

	--------------------------------------------------
	-- STATES
	--------------------------------------------------

	self.machine:AddState("Attack", {

		Enter = function()
			self.attackLocked = true
			self.attackFrame = 0
			self.canCancel = false

			-- ✅ FORZAR movimiento a 0 INMEDIATAMENTE
			self.moveDirection = 0

			-- ✅ DETENER velocidad INMEDIATAMENTE
			local vel = self.root.AssemblyLinearVelocity
			self.root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)

			self.lastAttack = self.currentAttack

			-- Usa el nombre de animación determinado en RequestAttack
			local animName = self.currentAnimationName or self.currentAttack.Animation
			self:PlayAnimation(animName, 0.1)

			local attack = self.currentAttack

			--Reproducir sonido cuando ataca
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local Combat = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Combat")
			local SoundManager = require(Combat:WaitForChild("SoundManager"))

			-- Pequeño "whoosh" cuando inicia el ataque
			SoundManager.PlaySound(attack.SoundEffect, self.root.Position, 0.5)

			if not attack then
				return
			end

			local hitbox

			-- STARTUP
			task.delay(attack.Startup, function()
				if DEBUG_HITBOX then
					print("📍 Active Frames Start")
				end

				hitbox = Hitbox.new(self.root, attack.Hitbox)
				hitbox.attackData = attack

				local connection

				connection = RunService.RenderStepped:Connect(function()
					if hitbox then
						hitbox:Update()
					end
				end)

				-- DESTRUIR HITBOX AL TERMINAR ACTIVE
				task.delay(attack.Active, function()
					if hitbox then
						hitbox:Destroy()
						hitbox = nil
					end

					connection:Disconnect()
				end)
			end)

			-- FIN DEL ATAQUE
			task.delay(attack.Startup + attack.Active + attack.Recovery, function()
				self.attackLocked = false

				-- ✅ Resetear a 0 (el input manejará el resto)
				self.moveDirection = 0

				-- ✅ Re-evaluar input actual
				if _G.ForceResolveMovement then
					_G.ForceResolveMovement()
				end

				self.machine:SetState("Idle")
			end)
		end,
	})

	self.machine:AddState("Idle", {
		Enter = function()
			self:PlayAnimation("Idle")
		end,

		Update = function()
			-- ✅ BLOQUEAR transiciones durante ataque
			if self.attackLocked then
				return
			end

			if self.isCrouching then
				self.machine:SetState("Crouch")
				return
			end

			if math.abs(self.moveDirection) > 0.01 then
				self.machine:SetState("Walk")
			end
		end,
	})

	self.machine:AddState("Walk", {
		Enter = function()
			self:PlayAnimation("Walk")
		end,

		Update = function()
			-- ✅ BLOQUEAR transiciones durante ataque
			if self.attackLocked then
				return
			end

			if self.isCrouching then
				self.machine:SetState("Crouch")
				return
			end

			if math.abs(self.moveDirection) < 0.01 then
				self.machine:SetState("Idle")
			end
		end,
	})

	self.machine:AddState("Crouch", {
		Enter = function()
			self:PlayAnimation("Crouch", 0.08)
			self.isCrouching = true
			-- Ajustar hurtbox
			if self.hurtbox and self.hurtbox.SetHeightScale then
				self.hurtbox:SetHeightScale(0.6)
			end
		end,

		Update = function()
			-- No se puede atacar agachado (opcional, puedes cambiarlo)
			if self.attackLocked then
				return
			end

			-- Si suelta S, volver a Idle o Walk
			if not self.isCrouching then
				if math.abs(self.moveDirection) > 0.01 then
					self.machine:SetState("Walk")
				else
					self.machine:SetState("Idle")
				end
			end
		end,

		Exit = function()
			-- Restaurar hurtbox
			if self.hurtbox and self.hurtbox.Reset then
				self.hurtbox:Reset()
			end
		end,
	})

	--AL CORRER EL JUEGO

	RunService.RenderStepped:Connect(function(dt)
		self.machine:Update(dt)

		local speedBase = self.speed
		local effectiveSpeed = speedBase * (self.isCrouching and (self.crouchSpeedMultiplier or 0.5) or 1)

		local velocity = self.root.AssemblyLinearVelocity

		if self.attackLocked then
			-- ✅ FORZAR ABSOLUTAMENTE TODO A 0
			self.moveDirection = 0
			self.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)

			-- ✅ EXTRA: Anclar el CFrame en X durante ataque
			local pos = self.root.Position
			if not self.attackStartPosition then
				self.attackStartPosition = pos.X
			end
			self.root.CFrame = CFrame.new(self.attackStartPosition, pos.Y, self.lockedZ)
		else
			self.attackStartPosition = nil -- Resetear cuando no está atacando
			-- movimiento normal
			self.root.AssemblyLinearVelocity = Vector3.new(self.moveDirection * effectiveSpeed, velocity.Y, 0)
		end

		local pos = self.root.Position
		local targetX = pos.X

		if self.attackLocked then
			self.moveDirection = 0
			self.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)

			if not self.attackStartPosition then
				self.attackStartPosition = pos.X
			end

			targetX = self.attackStartPosition
		else
			self.attackStartPosition = nil
			self.root.AssemblyLinearVelocity = Vector3.new(self.moveDirection * effectiveSpeed, velocity.Y, 0)
		end

		local angleY = 0
		if self.opponentRoot then
			local myPos = self.root.Position
			local enemyPos = self.opponentRoot.Position
			local faceRight = enemyPos.X >= myPos.X

			local newDirection = faceRight and "R" or "L"
			if newDirection ~= self.currentDirection then
				self.currentDirection = newDirection

				if self.currentAnimation and self.currentAnimation.IsPlaying then
					local currentState = self.machine:GetState()
					if currentState == "Idle" then
						self:PlayAnimation("Idle", 0.1)
					elseif currentState == "Walk" then
						self:PlayAnimation("Walk", 0.1)
					end
				end
			end

			angleY = faceRight and math.rad(-90) or math.rad(90)
		end

		local finalY = self.root.Position.Y
		self.root.CFrame = CFrame.new(targetX, finalY, self.lockedZ) * CFrame.Angles(0, angleY, 0)

		if self.machine:GetState() == "Attack" then
			self.attackFrame += 1
		end

		local attack = self.currentAttack

		if attack and attack.CancelWindow then
			if self.attackFrame >= attack.CancelWindow.Start and self.attackFrame <= attack.CancelWindow.End then
				self.canCancel = true
			else
				self.canCancel = false
			end
		end
	end)

	return self
end

function CharacterController:Jump()
	if self.isCrouching then
		return
	end

	if not self.humanoid then
		warn("Jump: humanoid missing")
		return
	end

	-- set Jump true y fuerza el estado Jumping
	if self.humanoid.FloorMaterial ~= Enum.Material.Air then
		self.humanoid.Jump = true
		pcall(function()
			self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end
end

function CharacterController:SetMoveDirection(dir)
	-- ✅ Pero NO aplicar si está atacando
	if self.attackLocked then
		return
	end

	self.moveDirection = dir
end

function CharacterController:RequestAttack(type)
	if DEBUG_HITBOX then
		print("\n=== REQUEST ATTACK ===")
		print("Type:", type)
		print("State:", self.machine:GetState())
		print("AttackLocked:", self.attackLocked)
		print("PunchCombo:", self.punchComboCount)
	end

	if self.attackLocked then
		if DEBUG_HITBOX then
			print("❌ REJECTED: AttackLocked")
		end
		return
	end

	local state = self.machine:GetState()

	if state ~= "Idle" and state ~= "Walk" then
		if not self.canCancel then
			if DEBUG_HITBOX then
				print("❌ REJECTED: Cannot Cancel")
			end
			return
		end
	end

	local attack = Attacks[type]

	if not attack then
		if DEBUG_HITBOX then
			print("❌ Attack not found:", type)
		end
		return
	end

	-- ✅ NUEVO: Sistema de combo para Punch
	if type == "Punch" then
		local now = tick()
		local MAX_PUNCH_COMBO = 3 -- ✅ MÁXIMO 3 PUNCHES (Punch, Punch2, Punch3)

		-- ✅ Si pasó mucho tiempo, resetea el contador
		if now - self.lastPunchTime > self.punchResetTime then
			self.punchComboCount = 0
			if DEBUG_HITBOX then
				print("🔄 Punch combo reset")
			end
		end

		-- ✅ Si llegaste al máximo, rechaza
		if self.punchComboCount >= MAX_PUNCH_COMBO then
			if DEBUG_HITBOX then
				print("❌ Max punch combo reached (" .. MAX_PUNCH_COMBO .. ")")
			end
			return
		end

		-- ✅ Incrementa el contador
		self.punchComboCount += 1
		self.lastPunchTime = now

		-- ✅ Determina qué animación usar
		local animName = attack.AnimationBase
		if self.punchComboCount > 1 then
			animName = attack.AnimationBase .. self.punchComboCount
		end

		if DEBUG_HITBOX then
			print("Punch #" .. self.punchComboCount)
			print("Animation:", animName)
		end

		-- ✅ Guarda qué ataque estamos usando
		self.currentAttack = attack
		self.currentAnimationName = animName -- Para usar en el estado
	else
		-- Para otros ataques (HeavyPunch, etc.)
		self.currentAttack = attack
		self.currentAnimationName = attack.Animation
		self.punchComboCount = 0 -- Resetea el combo de punch
	end

	-- ✅ ATTACK ACCEPTED
	if DEBUG_HITBOX then
		print("✅ ATTACK ACCEPTED")
		print("========================\n")
	end

	self.moveDirection = 0 -- dejar quieto

	if self.root and self.root:IsA("BasePart") then
		local vel = self.root.AssemblyLinearVelocity
		self.root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
	end

	-- guardar attack y anim y luego cambiar de estado (la Enter del state repetirá algunas cosas)
	self.currentAttack = attack

	-- finalmente cambia de estado (esto activará Attack.Enter que también puede hacer cosas adicionales)
	self.machine:SetState("Attack")
end

function CharacterController:SetCrouch(state)
	state = not not state
	if self.isCrouching == state then
		return
	end

	self.isCrouching = state

	-- Dejar que la máquina de estados maneje la transición
	if state then
		if self.machine:GetState() ~= "Attack" then
			self.machine:SetState("Crouch")
		end
	else
		if self.machine:GetState() == "Crouch" then
			self.machine:SetState("Idle")
		end
	end
end

-- ============================================
-- 🎬 FUNCIÓN: Cargar animaciones para oponente
-- ============================================

function CharacterController:LoadOpponentAnimations(opponentCharacter)
	if not opponentCharacter then
		return
	end

	local opponentAnimator = opponentCharacter:FindFirstChildOfClass("Humanoid")
	if opponentAnimator then
		opponentAnimator = opponentAnimator:FindFirstChild("Animator")
	end

	if not opponentAnimator then
		warn("❌ Opponent has no Animator")
		return
	end

	-- Crear tabla de animaciones del oponente
	self.opponentAnimations = {}

	local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

	local function loadSequence(animator, sequence)
		local anim = Instance.new("Animation")
		anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
		return animator:LoadAnimation(anim)
	end

	-- Cargar las mismas animaciones para el oponente
	self.opponentAnimations = {
		Idle_R = loadSequence(opponentAnimator, AnimationsTest.Idle_R),
		Idle_L = loadSequence(opponentAnimator, AnimationsTest.Idle_L),
		Walk_R = loadSequence(opponentAnimator, AnimationsTest.Walk_R),
		Walk_L = loadSequence(opponentAnimator, AnimationsTest.Walk_L),
		Punch_R = loadSequence(opponentAnimator, AnimationsTest.Punch_R),
		Punch_L = loadSequence(opponentAnimator, AnimationsTest.Punch_L),
		Punch2_R = loadSequence(opponentAnimator, AnimationsTest.Punch2_R),
		Punch2_L = loadSequence(opponentAnimator, AnimationsTest.Punch2_L),
		Punch3_R = loadSequence(opponentAnimator, AnimationsTest.Punch3_R),
		Punch3_L = loadSequence(opponentAnimator, AnimationsTest.Punch3_L),
		HeavyPunch_R = loadSequence(opponentAnimator, AnimationsTest.Heavy_R),
		HeavyPunch_L = loadSequence(opponentAnimator, AnimationsTest.Heavy_R),
		HurtLight_R = loadSequence(opponentAnimator, AnimationsTest.HurtLight_R),
		HurtLight_L = loadSequence(opponentAnimator, AnimationsTest.HurtLight_R),
	}
end

return CharacterController
