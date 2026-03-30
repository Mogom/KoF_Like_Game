local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local CharacterControllers = Modules:WaitForChild("CharacterControllers")
local AnimationController = require(CharacterControllers:WaitForChild("AnimationController"))
local CharacterMotor = require(CharacterControllers:WaitForChild("CharacterMotor"))
local CombatController = require(CharacterControllers:WaitForChild("CombatController"))
local VFXService = require(Combat:WaitForChild("VFXService"))
local Characters = Modules:WaitForChild("Characters")
local CharacterRegistry = require(Characters:WaitForChild("CharacterRegistry"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local SetOpponentEvent = RemoteEvents:WaitForChild("SetOpponent")
local ReplicateAnimationEvent = RemoteEvents:WaitForChild("ReplicateAnimation")
local ReplicateVFXEvent = RemoteEvents:WaitForChild("ReplicateVFX")

-- Orquestador principal: crea Motor, Combat, Animation y corre el loop RenderStepped
local CharacterController = {}
CharacterController.__index = CharacterController

-- Busca al oponente más cercano (dummy o jugador)
local function findOpponent()
	local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
	if dummy and dummy:FindFirstChild("HumanoidRootPart") then
		return dummy.HumanoidRootPart
	end

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

-- Constructor: inicializa context, sub-controladores y conecta RenderStepped + eventos
-- characterName (opcional): nombre del personaje seleccionado (e.g. "Ryu", "Ken")
--   Si no se pasa, usa datos globales (Attacks.luau + CommandList.luau)
function CharacterController.new(character, machine, characterName)
	local self = setmetatable({}, CharacterController)

	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	local animator = humanoid:WaitForChild("Animator")

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.AutoRotate = false

	-- Cargar datos del personaje seleccionado
	local charData = characterName and CharacterRegistry.Get(characterName) or nil
	local charInfo = charData and charData.Info or nil
	local charAttacks = charData and charData.Attacks or nil
	local charCommands = charData and charData:GetSortedCommands() or nil

	-- Aplicar stats del personaje
	local walkSpeed = (charInfo and charInfo.WalkSpeed) or 16
	local weight = (charInfo and charInfo.Weight) or 1.0
	local gravityScale = (charInfo and charInfo.GravityScale) or 1.0

	local context = {
		character = character,
		humanoid = humanoid,
		root = root,
		animator = animator,
		machine = machine,
		hurtbox = nil,

		-- Datos del personaje seleccionado
		characterName = characterName,
		attacks = charAttacks, -- Ataques específicos (o nil → usa globales)
		commands = charCommands, -- Comandos específicos (o nil → usa globales)

		opponent = nil,
		opponentRoot = nil,

		moveDirection = 0,
		currentDirection = "R",
		speed = walkSpeed,
		isCrouching = false,
		crouchSpeedMultiplier = 0.2,
		lockedZ = root.Position.Z,

		attackLocked = false,
		currentAttack = nil,
		currentAnimationName = nil,
		canCancel = false,
		attackFrame = 0,
		lastAttack = nil,

		punchComboCount = 0,
		lastPunchTime = 0,
		punchResetTime = 1,

		isInHitstun = false,
		hitstunReactionId = 0,
		lastReceivedHitCounter = character:GetAttribute("HitCounter") or 0,
		lastReceivedHitResultId = character:GetAttribute("HitResultId") or 0,

		externalVelocityX = 0,
		externalVelocityDecay = 0,

		-- Block state
		isBlocking = false,
		isCrouchBlocking = false,
		isInBlockstun = false,
		blockstunReactionId = 0,

		-- Air state
		isAirborne = false,
		wasAirborne = false,
		jumpForce = 50,
		airMoveSpeed = 10,
		hasAirAttacked = false,
		isInAirHitstun = false,
		juggleCount = 0,
		maxJuggles = 5,

		-- Gravity/Weight system (Brawlhalla-style juggling)
		weight = weight, -- Peso del personaje (menor = vuela más lejos)
		gravityScale = gravityScale, -- Multiplicador de gravedad (mayor = cae más rápido)
		juggleDecay = 0.15, -- Reducción de hitstun/launch por cada juggle (15% por hit)

		-- Knockdown state
		isKnockedDown = false,
		knockdownReactionId = 0,
		knockdownDuration = 0.8,
		wakeupDuration = 0.4,
		isInWakeup = false,
	}

	self.context = context

	context.hurtbox = {
		SetHeightScale = function(_, scale)
			local body = character:FindFirstChild("HurtboxBody")
			if body then
				if not body:GetAttribute("OriginalSizeX") then
					body:SetAttribute("OriginalSizeX", body.Size.X)
					body:SetAttribute("OriginalSizeY", body.Size.Y)
					body:SetAttribute("OriginalSizeZ", body.Size.Z)
				end

				local ox = body:GetAttribute("OriginalSizeX")
				local oy = body:GetAttribute("OriginalSizeY")
				local oz = body:GetAttribute("OriginalSizeZ")

				body.Size = Vector3.new(ox * 1.2, oy * scale, oz)
			end
		end,

		Reset = function(_)
			local body = character:FindFirstChild("HurtboxBody")
			if body then
				local ox = body:GetAttribute("OriginalSizeX")
				local oy = body:GetAttribute("OriginalSizeY")
				local oz = body:GetAttribute("OriginalSizeZ")

				if ox and oy and oz then
					body.Size = Vector3.new(ox, oy, oz)
				end
			end
		end,
	}

	self.character = context.character
	self.humanoid = context.humanoid
	self.root = context.root
	self.machine = context.machine
	self.hurtbox = context.hurtbox

	self.moveDirection = context.moveDirection
	self.currentDirection = context.currentDirection
	self.speed = context.speed
	self.isCrouching = context.isCrouching
	self.attackLocked = context.attackLocked
	self.currentAttack = context.currentAttack
	self.opponent = context.opponent
	self.opponentRoot = context.opponentRoot

	self.animationController = AnimationController.new(context)
	self.motor = CharacterMotor.new(context, self.animationController)
	context.motor = self.motor

	self.combat = CombatController.new(context, self.animationController)

	self:_registerBaseStates()
	self.combat:RegisterStates(machine)

	-- Predicción local de hits
	_G.LocalHitPrediction = function(victimCharacter, attackData)
		if not self.context.opponent then
			return
		end

		if victimCharacter ~= self.context.opponent then
			return
		end

		local Players = game:GetService("Players")
		local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
		if not victimPlayer then
			return
		end

		self.combat:ApplyLocalHitPrediction(victimCharacter, attackData)
	end

	SetOpponentEvent.OnClientEvent:Connect(function(opponentCharacter)
		if opponentCharacter and opponentCharacter:FindFirstChild("HumanoidRootPart") then
			self:SetOpponent(opponentCharacter.HumanoidRootPart)

			-- Resolver nombre de personaje del oponente
			local opponentCharName = nil
			local Players = game:GetService("Players")
			local opponentPlayer = Players:GetPlayerFromCharacter(opponentCharacter)
			if opponentPlayer then
				-- Oponente es un jugador: leer su SelectedCharacter
				opponentCharName = opponentPlayer:GetAttribute("SelectedCharacter")
			else
				-- Oponente es un dummy: leer SelectedDummyCharacter del jugador local
				opponentCharName = Players.LocalPlayer:GetAttribute("SelectedDummyCharacter")
			end

			self.animationController:LoadOpponentAnimations(opponentCharacter, opponentCharName)

			local CameraHandler = require(Combat:WaitForChild("CameraHandler"))
			if CameraHandler.SetOpponent then
				CameraHandler:SetOpponent(opponentCharacter)
			end
		end
	end)

	ReplicateAnimationEvent.OnClientEvent:Connect(function(remoteCharacter, animationName)
		if remoteCharacter ~= self.context.opponent then
			return
		end

		if self.combat.opponentIsInPredictedHitstun then
			return
		end

		self.animationController:PlayOpponentAnimation(animationName)
	end)

	-- =============================================
	-- ✨ RECIBIR VFX DE OTROS JUGADORES
	-- =============================================
	ReplicateVFXEvent.OnClientEvent:Connect(function(remoteCharacter, vfxType, vfxData)
		if not remoteCharacter or not remoteCharacter.Parent then
			return
		end

		if vfxType == "SwingVFX" then
			local vfx = vfxData.VFX
			local limbName = vfxData.VFX_Limb or "RightHand"
			local duration = (vfxData.Startup or 0) + (vfxData.Active or 0)

			if vfx and vfx.Startup then
				VFXService.Play(
					vfxData.CharacterName,
					vfxData.AttackId,
					vfx.Startup,
					remoteCharacter,
					limbName,
					vfxData.FacingDirection,
					vfxData.Startup or 0,
					true -- forceBurst: burst como en Active
				)
			end

			if vfx and vfx.Active then
				local activeCharName = vfxData.CharacterName
				local activeAttackId = vfxData.AttackId
				local activeVfxName = vfx.Active
				local activeLimb = limbName
				local activeFacingDir = vfxData.FacingDirection
				local activeDuration = vfxData.Active or 0.2
				task.delay(vfxData.Startup or 0, function()
					VFXService.Play(
						activeCharName,
						activeAttackId,
						activeVfxName,
						remoteCharacter,
						activeLimb,
						activeFacingDir,
						activeDuration
					)
				end)
			end

			if vfx and vfx.ActiveTrail then
				VFXService.EnableTrail(
					vfxData.CharacterName,
					vfxData.AttackId,
					remoteCharacter,
					limbName,
					vfxData.FacingDirection,
					true
				)
				local charName = vfxData.CharacterName
				local attackId = vfxData.AttackId
				local facingDir = vfxData.FacingDirection
				task.delay(duration, function()
					VFXService.EnableTrail(charName, attackId, remoteCharacter, limbName, facingDir, false)
				end)
			end
		elseif vfxType == "HitEffect" then
			if vfxData.VFX_OnHit and vfxData.CharacterName and vfxData.AttackId then
				VFXService.PlayAtPosition(
					vfxData.CharacterName,
					vfxData.AttackId,
					vfxData.VFX_OnHit,
					vfxData.Position,
					0.5
				)
			end
		end
	end)

	local initialOpponentRoot = findOpponent()
	if initialOpponentRoot then
		self:SetOpponent(initialOpponentRoot)
	end

	task.spawn(function()
		while true do
			task.wait(2)
			if not self.context.opponentRoot or not self.context.opponentRoot.Parent then
				local refreshedOpponentRoot = findOpponent()
				if refreshedOpponentRoot then
					self:SetOpponent(refreshedOpponentRoot)
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		self.context.machine:Update(dt)
		self.combat:Update(dt)
		self.motor:Update(dt)
		self:_syncPublicState()
	end)

	return self
end

-- Sincroniza estado público (isCrouching, isBlocking, etc.) via Attributes
function CharacterController:_syncPublicState()
	self.character = self.context.character
	self.humanoid = self.context.humanoid
	self.root = self.context.root
	self.machine = self.context.machine
	self.hurtbox = self.context.hurtbox

	self.moveDirection = self.context.moveDirection
	self.currentDirection = self.context.currentDirection
	self.speed = self.context.speed
	self.isCrouching = self.context.isCrouching
	self.attackLocked = self.context.attackLocked
	self.currentAttack = self.context.currentAttack
	self.opponent = self.context.opponent
	self.opponentRoot = self.context.opponentRoot
end

-- Registra estados base en la StateMachine (Idle, Walk, CrouchIdle, Jump, Fall, Land)
function CharacterController:_registerBaseStates()
	self.context.machine:AddState("Idle", {
		Enter = function()
			self.animationController:PlayAnimation("Idle")
		end,

		Update = function()
			if
				self.context.attackLocked
				or self.context.isInHitstun
				or self.context.isKnockedDown
				or self.context.isInWakeup
			then
				return
			end

			--if self.context.isBlocking then
			--	self.context.machine:SetState("Block")
			--	return
			--end

			--if self.context.isCrouchBlocking then
			--	self.context.machine:SetState("CrouchBlock")
			--	return
			--end

			if self.context.isCrouching then
				self.context.machine:SetState("Crouch")
				return
			end

			if math.abs(self.context.moveDirection) > 0.01 then
				self.context.machine:SetState("Walk")
			end
		end,
	})

	self.context.machine:AddState("Walk", {
		Enter = function()
			self.animationController:PlayAnimation("Walk")
		end,

		Update = function()
			if
				self.context.attackLocked
				or self.context.isInHitstun
				or self.context.isKnockedDown
				or self.context.isInWakeup
			then
				return
			end

			--if self.context.isBlocking then
			--	self.context.machine:SetState("Block")
			--	return
			--end

			--if self.context.isCrouchBlocking then
			--	self.context.machine:SetState("CrouchBlock")
			--	return
			--end

			if self.context.isCrouching then
				self.context.machine:SetState("Crouch")
				return
			end

			if math.abs(self.context.moveDirection) < 0.01 then
				self.context.machine:SetState("Idle")
			end
		end,
	})

	self.context.machine:AddState("Crouch", {
		Enter = function()
			if self.animationController:HasAnimation("Crouch") then
				self.animationController:PlayAnimation("Crouch", 0.08)
			else
				self.animationController:StopCurrent(0.08)
			end

			self.context.isCrouching = true

			if self.context.hurtbox and self.context.hurtbox.SetHeightScale then
				self.context.hurtbox:SetHeightScale(0.6)
			end
		end,

		Update = function()
			if
				self.context.attackLocked
				or self.context.isInHitstun
				or self.context.isKnockedDown
				or self.context.isInWakeup
			then
				return
			end

			--if self.context.isCrouchBlocking then
			--	self.context.machine:SetState("CrouchBlock")
			--	return
			--end

			if not self.context.isCrouching then
				if self.context.isBlocking then
					self.context.machine:SetState("Block")
				elseif math.abs(self.context.moveDirection) > 0.01 then
					self.context.machine:SetState("Walk")
				else
					self.context.machine:SetState("Idle")
				end
			end
		end,

		Exit = function()
			if self.context.hurtbox and self.context.hurtbox.Reset then
				self.context.hurtbox:Reset()
			end
		end,
	})
end

-- Solicita un dodge si el estado lo permite
function CharacterController:Dodge()
	if self.context.isInHitstun or self.context.isKnockedDown or self.context.isInWakeup or self.context.isDodging then
		return
	end

	self.motor:Dodge()
end

-- Asigna un oponente y lo pasa al motor y combat controller
function CharacterController:SetOpponent(opponentRoot)
	if not opponentRoot or not opponentRoot:IsA("BasePart") then
		self.context.opponentRoot = nil
		self.context.opponent = nil
		self:_syncPublicState()
		return
	end

	self.motor:SetOpponent(opponentRoot)
	self.context.opponentRoot = opponentRoot
	self.context.opponent = opponentRoot.Parent

	self.combat.opponentCurrentX = opponentRoot.Position.X

	self:_syncPublicState()
end

-- Retorna el Character del oponente actual
function CharacterController:GetOpponent()
	return self.context.opponent
end

-- Retorna el HumanoidRootPart del oponente
function CharacterController:GetOpponentRoot()
	return self.context.opponentRoot
end

-- Retorna el HumanoidRootPart propio
function CharacterController:GetRoot()
	return self.context.root
end

-- Retorna el Humanoid propio
function CharacterController:GetHumanoid()
	return self.context.humanoid
end

-- Retorna el estado actual de la StateMachine
function CharacterController:GetState()
	return self.context.machine:GetState()
end

-- Retorna true si está ejecutando un ataque o en recovery
function CharacterController:IsAttackLocked()
	return self.context.attackLocked
end

-- Retorna true si el personaje está agachado
function CharacterController:IsCrouching()
	return self.context.isCrouching
end

-- Retorna true si está en hitstun
function CharacterController:IsInHitstun()
	return self.context.isInHitstun
end

-- Retorna true si está bloqueando
function CharacterController:IsBlocking()
	return self.context.isBlocking or self.context.isCrouchBlocking
end

-- Retorna true si está en el aire
function CharacterController:IsAirborne()
	return self.context.isAirborne
end

-- Retorna true si está en knockdown
function CharacterController:IsKnockedDown()
	return self.context.isKnockedDown
end

-- Retorna la dirección de movimiento actual (-1, 0 o 1)
function CharacterController:GetMoveDirection()
	return self.context.moveDirection
end

-- Retorna la dirección hacia donde mira el personaje (-1 o 1)
function CharacterController:GetFacingDirection()
	return self.context.currentDirection
end

-- Setea dirección de movimiento y actualiza el motor
function CharacterController:SetMoveDirection(dir)
	if self.context.isInHitstun or self.context.isKnockedDown or self.context.isInWakeup then
		return
	end

	self.motor:SetMoveDirection(dir)
	self.animationController:RefreshLocomotionAnimation()
	self:_syncPublicState()
end

-- Setea estado de agachado y actualiza contexto + motor
function CharacterController:SetCrouch(state)
	if self.context.isInHitstun or self.context.isKnockedDown or self.context.isInWakeup then
		return
	end

	self.motor:SetCrouch(state)
	self.animationController:RefreshLocomotionAnimation()
	self:_syncPublicState()
end

-- Solicita un salto al motor si el estado lo permite
function CharacterController:Jump()
	if
		self.context.isInHitstun
		or self.context.isKnockedDown
		or self.context.isInWakeup
		or self.context.isInBlockstun
	then
		return
	end

	self.motor:Jump()
end

-- Delega solicitud de ataque al CombatController
function CharacterController:RequestAttack(type)
	if self.context.isInHitstun or self.context.isKnockedDown or self.context.isInWakeup then
		return
	end

	self.combat:RequestAttack(type)
	self:_syncPublicState()
end

return CharacterController
