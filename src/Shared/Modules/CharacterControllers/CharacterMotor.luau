local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")
local HitstopService = require(Combat:WaitForChild("HitstopService"))

-- Motor de movimiento y física del personaje (walk, push, jump, dodge, colisión, plane lock)
local CharacterMotor = {}
CharacterMotor.__index = CharacterMotor

-- Inicializa el motor con el contexto compartido y configura todos los estados por defecto
function CharacterMotor.new(context, animationController)
	local self = setmetatable({}, CharacterMotor)

	self.context = context
	self.animationController = animationController

	self.context.moveDirection = self.context.moveDirection or 0
	self.context.currentDirection = self.context.currentDirection or "R"
	self.context.speed = self.context.speed or 16
	self.context.isCrouching = self.context.isCrouching or false
	self.context.crouchSpeedMultiplier = self.context.crouchSpeedMultiplier or 0.2
	self.context.lockedZ = self.context.lockedZ or self.context.root.Position.Z

	self.context.currentX = self.context.root.Position.X
	self.context.attackLockedX = nil

	self.context.pushVelocityX = 0
	self.context.pushDecay = 0

	-- =============================================
	-- 🛡️ BLOCK STATE
	-- =============================================
	self.context.isBlocking = false
	self.context.isCrouchBlocking = false
	self.context.isInBlockstun = false
	self.context.blockstunReactionId = 0

	-- =============================================
	-- 🦅 AIR STATE
	-- =============================================
	self.context.isAirborne = false
	self.context.wasAirborne = false
	self.context.jumpForce = 50
	self.context.airMoveSpeed = 10
	self.context.hasAirAttacked = false
	self.context.isInAirHitstun = false
	self.context.juggleCount = 0
	self.context.maxJuggles = 3

	-- =============================================
	-- 💀 KNOCKDOWN STATE
	-- =============================================
	self.context.isKnockedDown = false
	self.context.knockdownReactionId = 0
	self.context.knockdownDuration = 0.8
	self.context.wakeupDuration = 0.4
	self.context.isInWakeup = false

	self.overlapParams = OverlapParams.new()
	self.overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self.overlapParams.FilterDescendantsInstances = { self.context.character }
	self.overlapParams.MaxParts = 20

	-- =============================================
	-- 💨 DODGE STATE
	-- =============================================
	self.context.isDodging = false
	self.context.dodgeCooldown = 0
	self.context.dodgeCooldownMax = 1.0 -- segundos entre dodges
	self.context.dodgeDuration = 0.4 -- duración de invulnerabilidad
	self.context.dodgeSpeed = 30 -- velocidad del dodge direccional
	self.context.dodgeDirection = 0 -- dirección del dodge (-1, 0, 1)

	return self
end

-- Asigna el oponente y actualiza los filtros de colisión
function CharacterMotor:SetOpponent(opponentRoot)
	self.context.opponentRoot = opponentRoot
	self.context.opponent = opponentRoot and opponentRoot.Parent or nil

	-- Actualizar OverlapParams: excluir solo nuestro personaje
	-- (el oponente se filtra en IsBlockingPart por parte individual)
	self.overlapParams.FilterDescendantsInstances = { self.context.character }
end

-- Cambia la dirección de movimiento (-1, 0, 1). Bloqueado durante hitstun/attack/knockdown
function CharacterMotor:SetMoveDirection(dir)
	if
		self.context.attackLocked
		or self.context.isInHitstun
		or self.context.isKnockedDown
		or self.context.isInWakeup
	then
		return
	end

	self.context.moveDirection = dir
	--self:_updateBlockState()
end

-- Activa/desactiva crouch y transiciona el estado de la máquina
function CharacterMotor:SetCrouch(state)
	state = not not state

	if self.context.isCrouching == state then
		return
	end

	self.context.isCrouching = state
	--self:_updateBlockState()

	if self.context.isAirborne then
		return
	end

	if state then
		if
			self.context.machine:GetState() ~= "Attack"
			and self.context.machine:GetState() ~= "Hitstun"
			and self.context.machine:GetState() ~= "Knockdown"
			and self.context.machine:GetState() ~= "Wakeup"
		then
			if self.context.isBlocking or self.context.isCrouchBlocking then
				self.context.machine:SetState("CrouchBlock")
			else
				self.context.machine:SetState("Crouch")
			end
		end
	else
		local currentState = self.context.machine:GetState()
		if currentState == "Crouch" or currentState == "CrouchBlock" then
			if self.context.isBlocking then
				self.context.machine:SetState("Block")
			elseif math.abs(self.context.moveDirection) > 0.01 then
				self.context.machine:SetState("Walk")
			else
				self.context.machine:SetState("Idle")
			end
		end
	end
end

-- =============================================
-- 🛡️ BLOCK: Detectar si estamos bloqueando
-- Back = bloqueo (relativo al oponente)
-- =============================================
function CharacterMotor:_updateBlockState()
	-- Sistema de block eliminado.
	-- Reemplazado por Dodge (shift).
	self.context.isBlocking = false
	self.context.isCrouchBlocking = false
end

function CharacterMotor:IsBlocking()
	return self.context.isBlocking or self.context.isCrouchBlocking
end

function CharacterMotor:GetBlockType()
	if self.context.isCrouchBlocking then
		return "Low"
	elseif self.context.isBlocking then
		return "High"
	end
	return nil
end

-- =============================================
-- 🦅 JUMP MEJORADO
-- =============================================
-- Aplica velocity vertical directa si está en el suelo
function CharacterMotor:Jump()
	if
		self.context.isCrouching
		or self.context.isInHitstun
		or self.context.attackLocked
		or self.context.isAirborne
		or self.context.isKnockedDown
		or self.context.isInWakeup
		or self.context.isInBlockstun
	then
		return
	end

	local humanoid = self.context.humanoid
	if not humanoid then
		return
	end

	if humanoid.FloorMaterial ~= Enum.Material.Air then
		-- Resetear bloqueo al saltar
		self.context.isBlocking = false
		self.context.isCrouchBlocking = false
		self.context.hasAirAttacked = false

		-- Aplicar salto con velocity directa para control preciso
		local root = self.context.root
		local currentVel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(currentVel.X, self.context.jumpForce, currentVel.Z)

		self.context.isAirborne = true
		self.context.machine:SetState("Airborne")
	end
end

-- =============================================
-- 🦅 DETECTAR ESTADO AÉREO
-- =============================================
-- Detecta transiciones suelo↔aire y maneja landing recovery
function CharacterMotor:UpdateAirState()
	local humanoid = self.context.humanoid
	if not humanoid then
		return
	end

	local isInAir = humanoid.FloorMaterial == Enum.Material.Air
	local wasInAir = self.context.isAirborne

	if isInAir and not wasInAir then
		-- Acaba de despegar
		self.context.isAirborne = true
		if
			self.context.machine:GetState() ~= "Attack"
			and self.context.machine:GetState() ~= "Hitstun"
			and self.context.machine:GetState() ~= "Knockdown"
		then
			self.context.machine:SetState("Airborne")
		end
	elseif not isInAir and wasInAir then
		-- Acaba de aterrizar
		self.context.isAirborne = false
		self.context.hasAirAttacked = false
		self.context.isInAirHitstun = false
		self.context.juggleCount = 0

		if self.context.isKnockedDown then
			return
		end

		local currentState = self.context.machine:GetState()

		if currentState == "Airborne" then
			-- Aterrizaje normal (sin ataque)
			self.context.attackLocked = false
			self.context.currentAttack = nil
			self.context.currentAnimationName = nil

			-- Resetear combo al aterrizar
			self.context.punchComboCount = 0
			self.context.lastPunchTime = 0

			if self.context.isCrouching then
				self.context.machine:SetState("Crouch")
			elseif math.abs(self.context.moveDirection) > 0.01 then
				self.context.machine:SetState("Walk")
			else
				self.context.machine:SetState("Idle")
			end
		elseif currentState == "Attack" then
			-- Aterrizaje durante ataque aéreo:
			-- Aplicar landing recovery (no puede actuar inmediatamente)
			self.context.punchComboCount = 0
			self.context.lastPunchTime = 0

			local landingRecovery = 0.15 -- 9 frames de recovery al aterrizar

			-- Mantener attackLocked durante landing recovery
			-- (el task.delay del ataque ya liberará si termina después)
			task.delay(landingRecovery, function()
				-- Solo liberar si aún estamos en Attack
				if self.context.machine:GetState() == "Attack" then
					-- Dejar que el timer original del ataque lo maneje
					return
				end

				-- Si ya salimos de Attack pero seguimos locked
				if self.context.attackLocked and not self.context.isInHitstun and not self.context.isKnockedDown then
					self.context.attackLocked = false
					self.context.currentAttack = nil
					self.context.currentAnimationName = nil

					if _G.ForceResolveMovement then
						_G.ForceResolveMovement()
					end

					if self.context.isCrouching then
						self.context.machine:SetState("Crouch")
					elseif math.abs(self.context.moveDirection) > 0.01 then
						self.context.machine:SetState("Walk")
					else
						self.context.machine:SetState("Idle")
					end
				end
			end)
		end
	end

	self.context.wasAirborne = self.context.isAirborne
end

-- Gira el personaje hacia el oponente comparando posiciones X
function CharacterMotor:UpdateFacing()
	if not self.context.opponentRoot or not self.context.opponentRoot.Parent then
		return
	end

	local myX = self.context.currentX
	local enemyX = self.context.opponentRoot.Position.X
	local faceRight = enemyX >= myX
	local newDirection = faceRight and "R" or "L"

	if newDirection ~= self.context.currentDirection then
		self.context.currentDirection = newDirection

		if not self.context.attackLocked and not self.context.isInHitstun then
			--self:_updateBlockState()
			self.animationController:RefreshLocomotionAnimation()
		end
	end
end

-- Determina si una Part debe bloquear el movimiento (colisión)
function CharacterMotor:IsBlockingPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	-- Ignorar nuestras propias partes
	if part:IsDescendantOf(self.context.character) then
		return false
	end

	-- Siempre ignorar hurtboxes (no son colisión física)
	if part.Name == "HurtboxBody" then
		return false
	end

	-- Ignorar hitboxes de debug
	if part.Name == "DebugHitbox" then
		return false
	end

	-- Para el oponente: solo ignorar sus partes NO colisionables
	-- Pero BLOQUEAR su HumanoidRootPart (para push collision)
	if self.context.opponent and part:IsDescendantOf(self.context.opponent) then
		-- El HumanoidRootPart del oponente actúa como "cuerpo sólido"
		if part.Name == "HumanoidRootPart" then
			return true
		end
		-- Ignorar otras partes del oponente (brazos, piernas, etc.)
		return false
	end

	-- Para partes del mundo: respetar CanCollide
	if part.CanCollide == false then
		return false
	end

	return true
end

-- Verifica si la posición targetX está libre de colisiones con GetPartBoundsInBox
function CharacterMotor:CanMoveToX(targetX)
	local root = self.context.root
	local currentPos = root.Position

	local testCFrame = CFrame.new(targetX, currentPos.Y, self.context.lockedZ)
	local testSize = Vector3.new(3, 5, 3)

	local parts = Workspace:GetPartBoundsInBox(testCFrame, testSize, self.overlapParams)

	for _, part in ipairs(parts) do
		if self:IsBlockingPart(part) then
			return false
		end
	end

	return true
end

-- Mueve currentX por deltaX. Si hay colisión, intenta en pasos más pequeños
function CharacterMotor:MoveCurrentX(deltaX)
	if math.abs(deltaX) <= 0.0001 then
		return
	end

	local targetX = self.context.currentX + deltaX

	if self:CanMoveToX(targetX) then
		self.context.currentX = targetX
		return
	end

	local steps = 6
	local stepDelta = deltaX / steps

	for _ = 1, steps do
		local stepTarget = self.context.currentX + stepDelta
		if self:CanMoveToX(stepTarget) then
			self.context.currentX = stepTarget
		else
			break
		end
	end
end

-- Aplica movimiento horizontal según input del jugador y estado actual
function CharacterMotor:UpdateWalkMovement(dt)
	-- No mover durante knockdown o wakeup
	if self.context.isKnockedDown or self.context.isInWakeup then
		self.context.moveDirection = 0
		return
	end

	local effectiveSpeed = self.context.speed * (self.context.isCrouching and self.context.crouchSpeedMultiplier or 1)

	-- En el aire: movimiento horizontal limitado
	if self.context.isAirborne then
		if not self.context.attackLocked and not self.context.isInHitstun then
			local airDelta = self.context.moveDirection * self.context.airMoveSpeed * dt
			self:MoveCurrentX(airDelta)
		end
		return
	end

	if self.context.attackLocked and not self.context.isInHitstun then
		self.context.moveDirection = 0

		if self.context.attackLockedX == nil then
			self.context.attackLockedX = self.context.currentX
		end

		self.context.currentX = self.context.attackLockedX
		return
	end

	self.context.attackLockedX = nil

	if self.context.isInHitstun then
		self.context.moveDirection = 0
		return
	end

	-- En blockstun no caminar
	if self.context.isInBlockstun then
		return
	end

	local walkDelta = self.context.moveDirection * effectiveSpeed * dt
	self:MoveCurrentX(walkDelta)
end

-- Aplica pushVelocityX cada frame con decay lineal hasta detenerse
function CharacterMotor:UpdatePushback()
	if math.abs(self.context.pushVelocityX or 0) > 0.01 then
		local delta = self.context.pushVelocityX
		self:MoveCurrentX(delta)

		local sign = self.context.pushVelocityX >= 0 and 1 or -1
		local absVel = math.abs(self.context.pushVelocityX)
		absVel = math.max(0, absVel - (self.context.pushDecay or 0))
		self.context.pushVelocityX = absVel * sign
	else
		self.context.pushVelocityX = 0
	end
end

-- Escribe el CFrame final: currentX en X, physics Y, lockedZ, rotación hacia oponente
function CharacterMotor:ApplyPlaneLockAndRotation()
	local root = self.context.root
	local pos = root.Position

	local finalX = self.context.currentX
	local finalY = pos.Y
	local finalZ = self.context.lockedZ

	local angleY = 0

	if self.context.opponentRoot and self.context.opponentRoot.Parent then
		local enemyX = self.context.opponentRoot.Position.X
		local faceRight = enemyX >= finalX
		angleY = faceRight and math.rad(-90) or math.rad(90)
	end

	root.CFrame = CFrame.new(finalX, finalY, finalZ) * CFrame.Angles(0, angleY, 0)
end

-- Inicia empuje por golpe: velocity = direction * pushback * 0.12, decay = 12%
function CharacterMotor:ApplyPushReaction(pushback, direction, duration)
	if pushback <= 0 then
		return
	end

	self.context.pushVelocityX = direction * (pushback * 0.12)
	self.context.pushDecay = math.max(0.01, math.abs(self.context.pushVelocityX) * 0.12)
end

function CharacterMotor:StopPushReaction()
	self.context.pushVelocityX = 0
	self.context.pushDecay = 0
end

-- Inicia dodge direccional con i-frames. Retorna true si se activó
function CharacterMotor:Dodge()
	if
		self.context.isDodging
		or self.context.isInHitstun
		or self.context.attackLocked
		or self.context.isKnockedDown
		or self.context.isInWakeup
		or self.context.isInBlockstun
	then
		return false
	end

	if self.context.dodgeCooldown > 0 then
		return false
	end

	-- Capturar dirección ANTES de resetear moveDirection
	local dir = self.context.moveDirection or 0

	self.context.isDodging = true
	self.context.dodgeCooldown = self.context.dodgeCooldownMax
	self.context.attackLocked = true
	self.context.dodgeDirection = dir
	self.context.moveDirection = 0

	self.context.machine:SetState("Dodge")

	return true
end

-- Decrementa cooldown del dodge y aplica movimiento si está activo
function CharacterMotor:UpdateDodge(dt)
	-- Cooldown
	if self.context.dodgeCooldown > 0 then
		self.context.dodgeCooldown = math.max(0, self.context.dodgeCooldown - dt)
	end

	-- Movimiento durante dodge
	if self.context.isDodging and math.abs(self.context.dodgeDirection or 0) > 0.01 then
		local dodgeDelta = self.context.dodgeDirection * self.context.dodgeSpeed * dt
		self:MoveCurrentX(dodgeDelta)
	end
end

-- Loop principal del motor. Durante hit reaction cede CFrame al atacante (NetworkOwner)
function CharacterMotor:Update(dt)
	local root = self.context.root

	-- Mientras estamos en una reacción de golpe (hitstun/knockdown/wakeup/blockstun),
	-- el atacante tiene NetworkOwnership y controla nuestra posición vía predicción.
	-- Solo leemos root.Position.X para mantener currentX sincronizado.
	-- NO escribimos CFrame para no pelear con la autoridad del atacante.
	local isInHitReaction = self.context.isInHitstun
		or self.context.isKnockedDown
		or self.context.isInWakeup
		or self.context.isInBlockstun

	-- HITSTOP: Congelar todo
	if HitstopService:IsInHitstop() then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		if isInHitReaction then
			-- Seguir la posición autoritativa del atacante
			self.context.currentX = root.Position.X
		else
			self:ApplyPlaneLockAndRotation()
		end
		return
	end

	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)

	self:UpdateAirState()
	self:UpdateFacing()

	if isInHitReaction then
		-- Seguir la posición autoritativa del atacante sin escribir CFrame
		self.context.currentX = root.Position.X
		self:UpdateDodge(dt)
		return
	end

	self:UpdateWalkMovement(dt)
	self:UpdatePushback()
	self:UpdateDodge(dt)

	self:ApplyPlaneLockAndRotation()
end

return CharacterMotor
