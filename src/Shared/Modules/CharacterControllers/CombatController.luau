local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DefaultAttacks = require(Combat:WaitForChild("Attacks"))
local Hitbox = require(Combat:WaitForChild("Hitbox"))
local SoundManager = require(Combat:WaitForChild("SoundManager"))
local HitstopService = require(Combat:WaitForChild("HitstopService"))
local VFXService = require(Combat:WaitForChild("VFXService"))
local ControllerRegistry = require(Combat:WaitForChild("ControllerRegistry"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local ReplicateVFXEvent = RemoteEvents:WaitForChild("ReplicateVFX")

-- Controlador de combate: ataques, hit reactions, hitstun, knockdown, predicción del oponente
local CombatController = {}
CombatController.__index = CombatController

local function usesClassicHealth(context)
	local ownerPlayer = Players:GetPlayerFromCharacter(context.character)
	local mode = nil

	if ownerPlayer then
		mode = ownerPlayer:GetAttribute("GameMode")
	end

	if not mode then
		mode = context.character:GetAttribute("GameMode")
	end

	return mode == "Classic"
end

-- Inicializa estados de combate y predicción del oponente
function CombatController.new(context, animationController)
	local self = setmetatable({}, CombatController)

	self.context = context
	self.animationController = animationController

	-- Usa ataques del personaje seleccionado, o los globales como fallback
	self.attacks = context.attacks or DefaultAttacks

	self.context.attackLocked = false
	self.context.lastAttack = nil
	self.context.currentAttack = nil
	self.context.currentAnimationName = nil
	self.context.attackFrame = 0
	self.context.canCancel = false

	self.context.punchComboCount = 0
	self.context.lastPunchTime = 0
	self.context.punchResetTime = 1

	self.context.isInHitstun = false
	self.context.hitstunReactionId = 0
	self.context.lastReceivedHitCounter = self.context.character:GetAttribute("HitCounter") or 0
	self.context.lastReceivedHitResultId = self.context.character:GetAttribute("HitResultId") or 0
	self.context.lastLocalPredictionTime = 0

	-- Predicción local del oponente
	self.opponentPushVelocityX = 0
	self.opponentPushDecay = 0
	self.opponentCurrentX = nil
	self.opponentIsInPredictedHitstun = false
	self.opponentPredictedHitstunId = 0

	self:_bindHitListener()

	return self
end

-- Escucha cambios en HitResultId (set por el servidor) para detectar hits entrantes
function CombatController:_bindHitListener()
	self.context.character:SetAttribute("HitCounter", self.context.character:GetAttribute("HitCounter") or 0)
	self.context.character:SetAttribute("HitResultId", self.context.character:GetAttribute("HitResultId") or 0)

	self.context.character:GetAttributeChangedSignal("HitResultId"):Connect(function()
		local newId = self.context.character:GetAttribute("HitResultId") or 0

		if newId <= self.context.lastReceivedHitResultId then
			return
		end

		self.context.lastReceivedHitResultId = newId

		-- Saltar si local prediction ya manejó este hit recientemente (dentro de 0.5s)
		local now = tick()
		if now - (self.context.lastLocalPredictionTime or 0) < 0.5 then
			return
		end

		-- No procesar si ya estamos en algún estado de reacción a golpe
		if
			self.context.isInHitstun
			or self.context.isKnockedDown
			or self.context.isInBlockstun
			or self.context.isInWakeup
		then
			return
		end

		-- CRÍTICO: Usar nuestra posición ACTUAL, no la que el servidor registró.
		-- El servidor ve una posición desfasada porque el pushback se ejecuta
		-- en el cliente del atacante (predicción local) antes de que el servidor
		-- pueda leer la posición actualizada.
		local myCurrentX = self.context.root.Position.X
		local attackerX = self.context.character:GetAttribute("LastAttackerPositionX") or 0

		local hitData = {
			Damage = self.context.character:GetAttribute("LastHitDamage") or 0,
			DamagePercent = self.context.character:GetAttribute("LastDamagePercent")
				or self.context.character:GetAttribute("DamagePercent")
				or 0,
			HitType = self.context.character:GetAttribute("LastHitType") or "Light",
			HitAnimation = self.context.character:GetAttribute("LastHitAnimation") or "HurtLight",
			HitstunDuration = self.context.character:GetAttribute("LastHitstunDuration") or 0.25,
			Pushback = self.context.character:GetAttribute("LastHitPushback") or 0,
			AttackerPositionX = attackerX,
			VictimPositionX = myCurrentX,
			HitstopFrames = self.context.character:GetAttribute("LastHitstopFrames") or 0,
			AttackHeight = self.context.character:GetAttribute("LastAttackHeight") or "Mid",
			BlockPushback = self.context.character:GetAttribute("LastBlockPushback") or 0,
			BlockstunDuration = self.context.character:GetAttribute("LastBlockstunDuration") or 0,
			ChipDamage = self.context.character:GetAttribute("LastChipDamage") or 0,
			Knockdown = self.context.character:GetAttribute("LastKnockdown") or false,
			LaunchForce = self.context.character:GetAttribute("LastLaunchForce") or 0,
			LaunchAngle = self.context.character:GetAttribute("LastLaunchAngle") or 0,
			BaseKnockback = self.context.character:GetAttribute("LastBaseKnockback") or 0,
			KnockbackGrowth = self.context.character:GetAttribute("LastKnockbackGrowth") or 0,
		}

		self:ProcessIncomingHit(hitData)
	end)
end

-- =============================================
-- 🛡️ PROCESAR HIT ENTRANTE: ¿Bloqueo o daño?
-- =============================================
-- Evalúa si el hit fue bloqueado o no, y aplica la reacción correspondiente
function CombatController:ProcessIncomingHit(hitData)
	local blocked = self:_checkBlock(hitData)

	if blocked then
		self:ApplyBlockReaction(hitData)
	else
		self:ApplyHitReaction(hitData)
	end
end

-- Verifica si estamos en posición de bloqueo y si el tipo de guardia cubre el ataque
function CombatController:_checkBlock(hitData)
	-- No se puede bloquear en el aire, durante hitstun, ataque, knockdown
	if
		self.context.isAirborne
		or self.context.isInHitstun
		or self.context.attackLocked
		or self.context.isKnockedDown
		or self.context.isInWakeup
	then
		return false
	end

	local attackHeight = hitData.AttackHeight or "Mid"

	if attackHeight == "Unblockable" then
		return false
	end

	local motor = self.context.motor
	if not motor or not motor.IsBlocking then
		return false
	end

	local isBlocking = motor:IsBlocking()
	if not isBlocking then
		return false
	end

	local blockType = motor:GetBlockType()

	-- Mid: se bloquea con cualquier tipo de guardia
	if attackHeight == "Mid" then
		return true
	end

	-- High: solo se bloquea parado
	if attackHeight == "High" then
		return blockType == "High"
	end

	-- Low: solo se bloquea agachado
	if attackHeight == "Low" then
		return blockType == "Low"
	end

	return false
end

-- =============================================
-- 🛡️ BLOCK REACTION
-- =============================================
-- Reacción al bloquear: chip damage, hitstop reducido, blockstun + pushback
function CombatController:ApplyBlockReaction(hitData)
	self.context.blockstunReactionId = (self.context.blockstunReactionId or 0) + 1
	local reactionId = self.context.blockstunReactionId

	self.context.isInBlockstun = true
	self.context.moveDirection = 0
	self.context.canCancel = false
	self.context.currentAttack = nil
	self.context.currentAnimationName = nil

	local blockstunDuration = hitData.BlockstunDuration or 0.15
	local blockPushback = hitData.BlockPushback or 5
	local chipDamage = hitData.ChipDamage or 0
	local hitstopFrames = hitData.HitstopFrames or 0

	-- Chip damage
	if chipDamage > 0 and usesClassicHealth(self.context) then
		local humanoid = self.context.humanoid
		if humanoid then
			humanoid:TakeDamage(chipDamage)
		end
	end

	-- Animación de bloqueo
	if self.context.isCrouchBlocking then
		self.context.machine:SetState("CrouchBlock")
		self.animationController:PlayAnimation("CrouchBlock", 0.03)
	else
		self.context.machine:SetState("Block")
		self.animationController:PlayAnimation("BlockHit", 0.03)
	end

	-- Hitstop durante bloqueo (más corto que al recibir daño)
	local blockHitstopFrames = math.max(1, math.floor(hitstopFrames * 0.6))

	local function applyBlockPushback()
		if blockPushback > 0 and self.context.motor and self.context.motor.ApplyPushReaction then
			local attackerX = hitData.AttackerPositionX or 0
			local victimX = self.context.root.Position.X
			local direction = victimX >= attackerX and 1 or -1

			self.context.motor:ApplyPushReaction(blockPushback, direction, blockstunDuration)
		end

		task.delay(blockstunDuration, function()
			if reactionId ~= self.context.blockstunReactionId then
				return
			end

			self.context.attackLockedX = nil

			-- Re-sincronizar posición y limpiar pushback residual
			self.context.currentX = self.context.root.Position.X
			self.context.pushVelocityX = 0
			self.context.pushDecay = 0

			self.context.isInBlockstun = false

			ControllerRegistry.ForceResolveMovement()

			if self.context.motor and self.context.motor._updateBlockState then
				self.context.motor:_updateBlockState()
			end

			self:ResolvePostActionState(true)
		end)
	end

	if blockHitstopFrames > 0 then
		local animsToFreeze = {}
		if self.animationController.currentAnimation then
			table.insert(animsToFreeze, self.animationController.currentAnimation)
		end

		-- Congelar también al atacante (oponente) en la pantalla de la víctima
		local opponentAnimsToFreeze = {}
		if self.animationController.currentOpponentAnimation then
			table.insert(opponentAnimsToFreeze, self.animationController.currentOpponentAnimation)
		end
		if self.context.opponent then
			HitstopService:Apply(self.context.opponent, blockHitstopFrames, opponentAnimsToFreeze)
		end

		HitstopService:Apply(self.context.character, blockHitstopFrames, animsToFreeze, applyBlockPushback)
	else
		applyBlockPushback()
	end
end

-- =============================================
-- 💥 HIT REACTION (con knockdown y launch)
-- =============================================
-- Reacción al recibir daño: hitstop → pushback → hitstun → (knockdown opcional)
function CombatController:ApplyHitReaction(hitData)
	if not hitData then
		return
	end

	self.context.hitstunReactionId += 1
	local reactionId = self.context.hitstunReactionId

	self.context.isInHitstun = true
	self.context.attackLocked = true
	self.context.moveDirection = 0
	self.context.canCancel = false
	self.context.currentAttack = nil
	self.context.currentAnimationName = nil
	self.context.isBlocking = false
	self.context.isCrouchBlocking = false
	self.context.isInBlockstun = false
	self.context.suspendAirGravity = false

	-- Sincronizar currentX con posición real antes de entrar en hitstun
	-- Esto es el ÚNICO momento donde sincronizamos, no cada frame
	self.context.currentX = self.context.root.Position.X
	self.context.attackLockedX = nil
	self.context.pushVelocityX = 0
	self.context.pushDecay = 0
	self.context.pushVelocityY = 0
	self.context.pushDecayY = 0

	local hitAnimation = hitData.HitAnimation or "HurtLight"
	local hitstunDuration = hitData.HitstunDuration or 0.35
	local hitstopFrames = hitData.HitstopFrames or 0
	local knockdown = hitData.Knockdown or false
	local launchForce = hitData.LaunchForce or 0
	local horizontalLaunch = hitData.HorizontalLaunch or 0

	-- =============================================
	-- DAÑO ACUMULADO (percent): escala el knockback al estilo Smash
	-- =============================================
	local damage = hitData.Damage or 0
	self.context.damagePercent = hitData.DamagePercent
		or self.context.character:GetAttribute("DamagePercent")
		or ((self.context.damagePercent or 0) + damage)
	self.context.character:SetAttribute("DamagePercent", self.context.damagePercent)

	-- =============================================
	-- KNOCKBACK DIRECCIONAL: calcular knockback basado en ángulo + percent
	-- Fórmula: totalKnockback = BaseKnockback + (damagePercent * KnockbackGrowth * 0.1)
	-- Luego se descompone en X/Y usando LaunchAngle
	-- =============================================
	local launchAngle = hitData.LaunchAngle -- nil = usar pushback clásico
	local baseKnockback = hitData.BaseKnockback or 0
	local knockbackGrowth = hitData.KnockbackGrowth or 0

	local knockbackX = 0
	local knockbackY = 0

	if launchAngle and baseKnockback > 0 then
		local totalKnockback = baseKnockback + (self.context.damagePercent * knockbackGrowth * 0.1)

		-- Weight system
		local victimWeight = self.context.weight or 1.0
		local weightMul = 1 / math.max(0.3, victimWeight)
		totalKnockback = totalKnockback * weightMul

		-- Descomponer en componentes usando el ángulo
		local angleRad = math.rad(launchAngle)
		knockbackX = totalKnockback * math.cos(angleRad)
		knockbackY = totalKnockback * math.sin(angleRad)
	end

	-- =============================================
	-- JUGGLE DECAY: cada hit aéreo reduce la fuerza de lanzamiento y hitstun
	-- Esto evita combos infinitos al estilo Brawlhalla
	-- =============================================
	local juggleCount = self.context.juggleCount or 0
	local juggleDecay = self.context.juggleDecay or 0.15
	local decayMultiplier = math.max(0.2, 1 - (juggleCount * juggleDecay))

	-- WEIGHT SYSTEM: personajes ligeros vuelan más, pesados menos
	local victimWeight = self.context.weight or 1.0
	local weightMultiplier = 1 / math.max(0.3, victimWeight) -- Lighter = higher multiplier

	-- Si estamos en el aire, usar animación de air hurt
	if self.context.isAirborne then
		hitAnimation = "AirHurt"
		self.context.isInAirHitstun = true
		self.context.juggleCount = juggleCount + 1

		-- Aplicar decay a hitstun y launch para cada golpe aéreo sucesivo
		hitstunDuration = hitstunDuration * decayMultiplier
		launchForce = launchForce * decayMultiplier
		horizontalLaunch = horizontalLaunch * decayMultiplier
		knockbackX = knockbackX * decayMultiplier
		knockbackY = knockbackY * decayMultiplier
	end

	-- Si tiene launch force, lanzar al aire
	if launchForce > 0 and not self.context.isAirborne then
		hitAnimation = "Launch"
		self.context.isAirborne = true
		self.context.isInAirHitstun = true
		self.context.juggleCount = 1

		local root = self.context.root
		local scaledLaunch = launchForce * weightMultiplier

		-- Horizontal launch: empuja en la dirección del atacante
		local hLaunch = horizontalLaunch * weightMultiplier
		local pushDir = 0
		if hLaunch > 0 then
			local attackerX = hitData.AttackerPositionX or 0
			local victimX = self.context.currentX
			pushDir = victimX >= attackerX and 1 or -1
		end

		root.AssemblyLinearVelocity = Vector3.new(pushDir * hLaunch, scaledLaunch, 0)
	elseif self.context.isAirborne and launchForce > 0 then
		-- Re-launch en el aire (juggle): aplicar fuerza vertical reducida + horizontal
		local root = self.context.root
		local scaledLaunch = launchForce * weightMultiplier * decayMultiplier

		local hLaunch = horizontalLaunch * weightMultiplier * decayMultiplier
		local pushDir = 0
		if hLaunch > 0 then
			local attackerX = hitData.AttackerPositionX or 0
			local victimX = self.context.currentX
			pushDir = victimX >= attackerX and 1 or -1
		end

		root.AssemblyLinearVelocity = Vector3.new(pushDir * hLaunch, scaledLaunch, 0)
	elseif knockbackY > 0 and not self.context.isAirborne then
		-- Knockback direccional con componente vertical: lanzar al aire
		hitAnimation = "Launch"
		self.context.isAirborne = true
		self.context.isInAirHitstun = true
		self.context.juggleCount = 1
	end

	self.context.machine:SetState("Hitstun")
	self.animationController:PlayAnimation(hitAnimation, 0.03)

	-- Hurtflash pulsante durante hitstop (o flash simple si no hay hitstop)
	VFXService.HurtFlash(self.context.character, hitstopFrames)

	if hitstopFrames > 0 then
		local animsToFreeze = {}
		if self.animationController.currentAnimation then
			table.insert(animsToFreeze, self.animationController.currentAnimation)
		end

		-- Congelar también al atacante (oponente) en la pantalla de la víctima
		local opponentAnimsToFreeze = {}
		if self.animationController.currentOpponentAnimation then
			table.insert(opponentAnimsToFreeze, self.animationController.currentOpponentAnimation)
		end
		if self.context.opponent then
			HitstopService:Apply(self.context.opponent, hitstopFrames, opponentAnimsToFreeze)
		end

		HitstopService:Apply(self.context.character, hitstopFrames, animsToFreeze, function()
			self:_applyPostHitstopPushback(hitData, reactionId, hitstunDuration, knockdown, knockbackX, knockbackY)
		end)
	else
		self:_applyPostHitstopPushback(hitData, reactionId, hitstunDuration, knockdown, knockbackX, knockbackY)
	end
end

-- Post-hitstop: sincroniza currentX, aplica pushback direccional, programa salida de hitstun
function CombatController:_applyPostHitstopPushback(
	hitData,
	reactionId,
	hitstunDuration,
	knockdown,
	knockbackX,
	knockbackY
)
	-- Re-sincronizar currentX con la posición física real antes de aplicar pushback.
	-- Esto garantiza que el pushback arranque desde la posición exacta del personaje,
	-- evitando drift acumulado durante el hitstop.
	self.context.currentX = self.context.root.Position.X

	knockbackX = knockbackX or 0
	knockbackY = knockbackY or 0

	local attackerX = hitData.AttackerPositionX or 0
	local victimX = self.context.currentX
	local direction = victimX >= attackerX and 1 or -1

	-- Si hay knockback direccional (LaunchAngle), usar componentes calculados
	if knockbackX ~= 0 or knockbackY ~= 0 then
		if self.context.motor and self.context.motor.ApplyPushReaction then
			self.context.motor:ApplyPushReaction(knockbackX, direction, hitstunDuration, knockbackY)
		end
	else
		-- Fallback: pushback clásico lineal (solo X)
		local pushback = hitData.Pushback or 0
		if pushback > 0 and self.context.motor and self.context.motor.ApplyPushReaction then
			self.context.motor:ApplyPushReaction(pushback, direction, hitstunDuration)
		end
	end

	-- =============================================
	-- 🪂 AIR TECH WINDOW: activar tech después de 40% del hitstun aéreo
	-- =============================================
	if self.context.isInAirHitstun and (self.context.airTechCooldown or 0) <= 0 then
		local techDelay = hitstunDuration * 0.4
		task.delay(techDelay, function()
			if reactionId ~= self.context.hitstunReactionId then
				return
			end
			if not self.context.isInAirHitstun then
				return
			end

			self.context.canAirTech = true
			self:_startTechFlash()
		end)
	end

	task.delay(hitstunDuration, function()
		if reactionId ~= self.context.hitstunReactionId then
			return
		end

		-- Limpiar canAirTech si el hitstun terminó naturalmente
		self.context.canAirTech = false

		-- Limpiar attack lock
		self.context.attackLockedX = nil

		-- Re-sincronizar currentX y limpiar pushback residual antes de
		-- devolver control al motor. Esto garantiza que no haya salto
		-- de posición al retomar autoridad sobre CFrame.
		self.context.currentX = self.context.root.Position.X
		self.context.pushVelocityX = 0
		self.context.pushDecay = 0
		self.context.pushVelocityY = 0
		self.context.pushDecayY = 0

		self.context.isInHitstun = false
		self.context.isInAirHitstun = false

		if knockdown then
			self:_startKnockdown(reactionId)
			return
		end

		self.context.attackLocked = false

		ControllerRegistry.ForceResolveMovement()

		self:ResolvePostActionState(true)
	end)
end

-- =============================================
-- 💀 KNOCKDOWN SYSTEM
-- =============================================
-- Inicia estado de knockdown (caído) con timer para despertar
function CombatController:_startKnockdown(reactionId)
	self.context.knockdownReactionId = (self.context.knockdownReactionId or 0) + 1
	local knockdownId = self.context.knockdownReactionId

	self.context.isKnockedDown = true
	self.context.attackLocked = true
	self.context.moveDirection = 0
	self.context.isBlocking = false
	self.context.isCrouchBlocking = false

	self.context.machine:SetState("Knockdown")
	self.animationController:PlayAnimation("Knockdown", 0.05)

	local knockdownDuration = self.context.knockdownDuration or 0.8

	task.delay(knockdownDuration, function()
		if knockdownId ~= self.context.knockdownReactionId then
			return
		end

		if not self.context.isKnockedDown then
			return
		end

		self:_startWakeup(knockdownId)
	end)
end

-- Animación de levantarse. Al terminar, libera control y sincroniza posición
function CombatController:_startWakeup(knockdownId)
	self.context.isKnockedDown = false
	self.context.isInWakeup = true
	self.context.moveDirection = 0

	self.context.machine:SetState("Wakeup")
	self.animationController:PlayAnimation("Wakeup", 0.08)

	local wakeupDuration = self.context.wakeupDuration or 0.4

	task.delay(wakeupDuration, function()
		if knockdownId ~= self.context.knockdownReactionId then
			return
		end

		self.context.attackLockedX = nil

		-- Re-sincronizar posición y limpiar pushback residual
		self.context.currentX = self.context.root.Position.X
		self.context.pushVelocityX = 0
		self.context.pushDecay = 0

		self.context.isInWakeup = false
		self.context.attackLocked = false
		self.context.juggleCount = 0

		ControllerRegistry.ForceResolveMovement()

		if self.context.motor and self.context.motor._updateBlockState then
			self.context.motor:_updateBlockState()
		end

		self:ResolvePostActionState(true)
	end)
end

-- =============================================
-- 🪂 AIR TECH / RECOVERY
-- =============================================
-- Cancela hitstun aéreo con un tech: breves i-frames, luego FreeFall con control limitado
function CombatController:AirTech()
	-- Solo se puede hacer tech durante air hitstun
	if not self.context.isInAirHitstun then
		return false
	end

	-- No durante hitstop
	if HitstopService:IsInHitstop(self.context.character) then
		return false
	end

	-- Cooldown check
	if (self.context.airTechCooldown or 0) > 0 then
		return false
	end

	-- No se puede tech si no es techeable aún
	if not self.context.canAirTech then
		return false
	end

	-- Incrementar hitstunReactionId para invalidar la limpieza delayed del hitstun actual
	self.context.hitstunReactionId += 1

	-- Cancelar hitstun
	self.context.isInHitstun = false
	self.context.isInAirHitstun = false
	self.context.canAirTech = false

	-- Limpiar pushback
	self.context.pushVelocityX = 0
	self.context.pushDecay = 0
	self.context.pushVelocityY = 0
	self.context.pushDecayY = 0

	-- Reducir velocidad actual (frenar el knockback)
	local root = self.context.root
	local vel = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(vel.X * 0.3, math.max(vel.Y * 0.2, 0), 0)

	-- Entrar en FreeFall: control limitado, sin poder atacar
	self.context.isInFreeFall = true
	self.context.attackLocked = true
	self.context.freeFallSpeed = self.context.airMoveSpeed * 0.5

	-- Iniciar cooldown
	self.context.airTechCooldown = self.context.airTechCooldownMax or 2.5

	-- I-frames breves (0.3s)
	local hurtboxBody = self.context.character:FindFirstChild("HurtboxBody")
	if hurtboxBody then
		hurtboxBody.CanQuery = false
	end
	self:_setCharacterTransparency(0.5)

	self.context.machine:SetState("FreeFall")
	self.animationController:PlayAnimation("Dodge", 0.05)

	-- Restaurar i-frames después de 0.3s
	task.delay(0.3, function()
		if not self.context.isInFreeFall then
			return
		end

		local hb = self.context.character:FindFirstChild("HurtboxBody")
		if hb then
			hb.CanQuery = true
		end
		self:_setCharacterTransparency(0)
	end)

	return true
end

-- Flash pulsante que indica que el personaje puede hacer air tech
function CombatController:_startTechFlash()
	task.spawn(function()
		while self.context.canAirTech and self.context.isInAirHitstun do
			-- Flash rápido: alternar transparencia
			self:_setCharacterTransparency(0.4)
			task.wait(0.08)
			if not self.context.canAirTech or not self.context.isInAirHitstun then
				break
			end
			self:_setCharacterTransparency(0)
			task.wait(0.08)
		end
		-- Asegurar que quede opaco al terminar
		if not self.context.isInFreeFall then
			self:_setCharacterTransparency(0)
		end
	end)
end

-- =============================================
-- STATE REGISTRATION
-- =============================================

-- Ajusta transparencia del personaje (usado para efecto visual del dodge)
function CombatController:_setCharacterTransparency(alpha)
	for _, part in pairs(self.context.character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "HurtboxBody" then
			part.Transparency = alpha
		end
	end
end

-- Registra estados de combate en la StateMachine (Attack, Hitstun, Dodge, etc.)
function CombatController:RegisterStates(machine)
	machine:AddState("Attack", {
		Enter = function()
			local attack = self.context.currentAttack
			if not attack then
				return
			end

			self.context.attackLocked = true
			self.context.attackFrame = 0
			self.context.canCancel = false
			self.context.lastAttack = attack

			-- En el aire con allowAirAttackMovement: mantener moveDirection actual
			if not (self.context.isAirborne and self.context.allowAirAttackMovement) then
				self.context.moveDirection = 0
			end

			-- En el aire, no frenar Y
			if not self.context.isAirborne then
				local vel = self.context.root.AssemblyLinearVelocity
				self.context.root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
			end

			-- Suspender gravedad durante ataques aéreos (inmediato)
			-- Para AttackJump, NO suspender aquí — el sistema de AttackJump
			-- maneja su propio delay de gravedad después de aplicar el impulso
			if self.context.isAirborne and not attack.AttackJump then
				self.context.suspendAirGravity = true
				-- Congelar velocidad Y actual al iniciar el ataque aéreo
				local vel = self.context.root.AssemblyLinearVelocity
				self.context.root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
			end

			local animName = self.context.currentAnimationName or attack.Animation or attack.AnimationBase
			self.animationController:PlayAnimation(animName, 0.1)

			if attack.SoundEffect then
				SoundManager.PlaySound(attack.SoundEffect, self.context.root.Position, attack.SoundVolume or 0.5)
			end

			local comboIndex = self.context.punchComboCount or 1
			if comboIndex < 1 then
				comboIndex = 1
			end

			local attackLimbName = "RightHand"
			if attack.VFX_Limbs and comboIndex and #attack.VFX_Limbs > 0 then
				local idx = ((comboIndex - 1) % #attack.VFX_Limbs) + 1
				attackLimbName = attack.VFX_Limbs[idx]
			elseif attack.VFX_Limb then
				attackLimbName = attack.VFX_Limb
			end

			-- Flash del limb atacante: se reproduce SIEMPRE al ejecutar el ataque (no al conectar)
			if attack.HitLimbFlash and attack.HitLimbFlash.Enabled then
				local flashDuration = (attack.Startup or 0) + (attack.Active or 0)
				local flashConfig = table.clone(attack.HitLimbFlash)
				flashConfig.Duration = flashDuration
				VFXService.AttackLimbFlash(
					self.context.character,
					attackLimbName,
					self.context.currentDirection,
					flashConfig,
					0
				)
			end

			-- VFX: se reproduce al INICIAR el ataque (Startup y ActiveTrail)
			if attack.VFX and self.context.characterName then
				-- Startup VFX: burst instantáneo al iniciar el ataque
				if attack.VFX.Startup then
					local vfxDuration = attack.Startup or 0
					VFXService.Play(
						self.context.characterName,
						attack.Id,
						attack.VFX.Startup,
						self.context.character,
						attackLimbName,
						self.context.currentDirection,
						vfxDuration,
						true -- forceBurst: burst como en Active
					)
				end

				-- Active VFX: sigue la extremidad durante los Active frames (sin importar si conecta)
				if attack.VFX.Active then
					local activeCharName = self.context.characterName
					local activeAttackId = attack.Id
					local activeVfxName = attack.VFX.Active
					local activeCharacter = self.context.character
					local activeLimb = attackLimbName
					local activeDir = self.context.currentDirection
					local activeDuration = attack.Active or 0.2
					task.delay(attack.Startup or 0, function()
						VFXService.Play(
							activeCharName,
							activeAttackId,
							activeVfxName,
							activeCharacter,
							activeLimb,
							activeDir,
							activeDuration
						)
					end)
				end

				-- ActiveTrail: se activa durante los Active frames
				if attack.VFX.ActiveTrail then
					VFXService.EnableTrail(
						self.context.characterName,
						attack.Id,
						self.context.character,
						attackLimbName,
						self.context.currentDirection,
						true
					)
					local trailCharName = self.context.characterName
					local trailAttackId = attack.Id
					local trailCharacter = self.context.character
					local trailLimb = attackLimbName
					local trailDir = self.context.currentDirection
					task.delay((attack.Startup or 0) + (attack.Active or 0), function()
						VFXService.EnableTrail(trailCharName, trailAttackId, trailCharacter, trailLimb, trailDir, false)
					end)
				end

				-- Replicar a otros jugadores
				ReplicateVFXEvent:FireServer("SwingVFX", {
					CharacterName = self.context.characterName,
					AttackId = attack.Id,
					VFX = attack.VFX,
					VFX_Limb = attackLimbName,
					HitLimbFlash = attack.HitLimbFlash,
					Startup = attack.Startup,
					Active = attack.Active,
					FacingDirection = self.context.currentDirection,
				})
			end

			if
				not attack.VFX
				and self.context.characterName
				and attack.HitLimbFlash
				and attack.HitLimbFlash.Enabled
			then
				ReplicateVFXEvent:FireServer("SwingVFX", {
					CharacterName = self.context.characterName,
					AttackId = attack.Id,
					VFX = nil,
					VFX_Limb = attackLimbName,
					HitLimbFlash = attack.HitLimbFlash,
					Startup = attack.Startup,
					Active = attack.Active,
					FacingDirection = self.context.currentDirection,
				})
			end

			-- =============================================
			-- 🏃 ATTACK DASH: Desplazamiento durante ataque
			-- DashDistance > 0 → avanza hacia el oponente
			-- DashDistance < 0 → retrocede (se aleja del oponente)
			-- =============================================
			if attack.AttackDash and attack.DashDistance and attack.DashDistance ~= 0 then
				local dashFrameStart = attack.DashFrameStart or 1
				local dashDuration = attack.DashDuration or 4
				local dashDistance = math.abs(attack.DashDistance)
				local dashReverse = attack.DashDistance < 0

				-- Calcular dirección base: hacia donde mira el personaje
				local dashDir = self.context.currentDirection == "R" and 1 or -1

				-- DESACTIVADO: Dash hacia el oponente (útil para modos 1v1 clásicos)
				-- if self.context.opponentRoot and self.context.opponentRoot.Parent then
				-- 	local enemyX = self.context.opponentRoot.Position.X
				-- 	local myX = self.context.currentX or self.context.root.Position.X
				-- 	dashDir = enemyX >= myX and 1 or -1
				-- elseif self.context.currentDirection == "L" then
				-- 	dashDir = -1
				-- end

				-- Si DashDistance es negativo, invertir dirección (retroceder)
				if dashReverse then
					dashDir = -dashDir
				end

				-- Distancia por frame
				local distPerFrame = dashDistance / dashDuration
				local dashFrameCount = 0
				local dashStarted = false
				local dashFinished = false

				local dashConnection
				dashConnection = RunService.RenderStepped:Connect(function()
					if dashFinished then
						if dashConnection then
							dashConnection:Disconnect()
							dashConnection = nil
						end
						return
					end

					-- Si estamos en hitstop, no avanzar
					if HitstopService:IsInHitstop(self.context.character) then
						return
					end

					-- Si ya no estamos en Attack, cancelar
					if self.context.machine:GetState() ~= "Attack" then
						dashFinished = true
						return
					end

					local currentFrame = self.context.attackFrame

					-- Esperar al frame de inicio
					if currentFrame < dashFrameStart then
						return
					end

					if not dashStarted then
						dashStarted = true
						-- Desbloquear posición para el dash
						self.context.attackLockedX = nil

						-- Aplicar impulso vertical si tiene DashLiftY (dash aéreo con subida)
						if attack.DashLiftY and attack.DashLiftY ~= 0 and self.context.root then
							-- Desactivar suspensión temporalmente para que el impulso se aplique
							self.context.suspendAirGravity = false
							local vel = self.context.root.AssemblyLinearVelocity
							self.context.root.AssemblyLinearVelocity = Vector3.new(vel.X, attack.DashLiftY, vel.Z)

							-- Re-suspender gravedad después de unos frames para que el lift se ejecute
							local liftFrameCount = 0
							local liftConn
							liftConn = RunService.RenderStepped:Connect(function()
								liftFrameCount += 1
								if liftFrameCount >= 3 then
									if self.context.machine:GetState() == "Attack" then
										self.context.suspendAirGravity = true
									end
									if liftConn then
										liftConn:Disconnect()
										liftConn = nil
									end
								end
							end)
						end
					end

					dashFrameCount += 1

					if dashFrameCount <= dashDuration then
						-- Mover usando el motor (respeta colisiones)
						if self.context.motor then
							self.context.motor:MoveCurrentX(dashDir * distPerFrame)
							-- Actualizar la posición "locked" del ataque
							self.context.attackLockedX = self.context.currentX
						end
					else
						dashFinished = true
					end
				end)

				-- Cleanup por si el ataque termina antes
				task.delay(attack.Startup + attack.Active + attack.Recovery + 0.1, function()
					dashFinished = true
					if dashConnection then
						dashConnection:Disconnect()
						dashConnection = nil
					end
				end)
			end

			-- =============================================
			-- 🦘 ATTACK JUMP: Salto durante el ataque
			-- =============================================
			if attack.AttackJump and attack.JumpHeight and attack.JumpHeight > 0 then
				local jumpFrameStart = attack.JumpFrameStart or 1
				local jumpHeight = attack.JumpHeight
				local gravityDelayFrames = attack.JumpGravityDelayFrames or 3
				local jumpApplied = false
				local jumpFinished = false

				local jumpConnection
				jumpConnection = RunService.RenderStepped:Connect(function()
					if jumpFinished then
						if jumpConnection then
							jumpConnection:Disconnect()
							jumpConnection = nil
						end
						return
					end

					-- Si ya no estamos en Attack, cancelar
					if self.context.machine:GetState() ~= "Attack" then
						jumpFinished = true
						return
					end

					-- No saltar durante hitstop
					if HitstopService:IsInHitstop(self.context.character) then
						return
					end

					local currentFrame = self.context.attackFrame

					-- Esperar al frame de inicio
					if currentFrame < jumpFrameStart then
						return
					end

					-- Solo disparar una vez
					if not jumpApplied then
						jumpApplied = true
						jumpFinished = true

						local root = self.context.root
						root.AssemblyLinearVelocity = Vector3.new(0, jumpHeight, 0)
						self.context.isAirborne = true

						-- Suspender gravedad después de aplicar el impulso del salto
						-- Esperar unos frames para que el personaje suba antes de congelar
						local gravityFrameCount = 0
						local gravityConn
						gravityConn = RunService.RenderStepped:Connect(function()
							gravityFrameCount += 1
							if gravityFrameCount >= gravityDelayFrames then
								if self.context.machine:GetState() == "Attack" then
									self.context.suspendAirGravity = true
								end
								if gravityConn then
									gravityConn:Disconnect()
									gravityConn = nil
								end
							end
						end)
					end
				end)

				-- Cleanup ligado a la duración total del ataque
				task.delay(attack.Startup + attack.Active + attack.Recovery + 0.1, function()
					jumpFinished = true
					if jumpConnection then
						jumpConnection:Disconnect()
						jumpConnection = nil
					end
				end)
			end

			-- Proyectil (e.g. Fireball): spawn en lugar de hitbox local
			if attack.IsProjectile then
				local ProjectileService = require(Combat:WaitForChild("ProjectileService"))
				local dir = self.context.currentDirection == "L" and -1 or 1
				task.delay(attack.Startup, function()
					if self.context.machine:GetState() ~= "Attack" then
						return
					end
					ProjectileService.Spawn(self.context.root, attack, dir, self.context.characterName)
				end)
			else
				task.delay(attack.Startup, function()
					if self.context.machine:GetState() ~= "Attack" then
						return
					end

					local hitbox = Hitbox.new(self.context.root, attack.Hitbox)
					hitbox.attackData = attack

					-- Efecto visual al conectar el golpe (OnHit VFX)
					hitbox.onHit = function(hitPosition, direction, _victimCharacter)
						if attack.VFX and attack.VFX.OnHit and self.context.characterName then
							VFXService.PlayAtPosition(
								self.context.characterName,
								attack.Id,
								attack.VFX.OnHit,
								hitPosition,
								0.5
							)
						end

						-- Replicar HitEffect a otros jugadores
						ReplicateVFXEvent:FireServer("HitEffect", {
							CharacterName = self.context.characterName,
							AttackId = attack.Id,
							VFX_OnHit = attack.VFX and attack.VFX.OnHit,
							Position = hitPosition,
						})
					end

					local connection
					connection = RunService.RenderStepped:Connect(function()
						if hitbox then
							hitbox:Update()
						end
					end)

					task.delay(attack.Active, function()
						if hitbox then
							hitbox:Destroy()
							hitbox = nil
						end

						if connection then
							connection:Disconnect()
							connection = nil
						end
					end)
				end)
			end

			task.delay(attack.Startup + attack.Active + attack.Recovery, function()
				if self.context.machine:GetState() ~= "Attack" then
					return
				end

				self.context.attackLocked = false
				self.context.currentAttack = nil
				self.context.currentAnimationName = nil
				self.context.canCancel = false
				self.context.suspendAirGravity = false

				ControllerRegistry.ForceResolveMovement()

				-- Si estamos en el aire, volver a Airborne
				if self.context.isAirborne then
					self.context.machine:SetState("Airborne")
					return
				end

				self:ResolvePostActionState(true)
			end)
		end,
	})

	machine:AddState("Hitstun", {
		Enter = function()
			self.context.attackLocked = true
			self.context.moveDirection = 0

			if not self.context.isAirborne then
				local vel = self.context.root.AssemblyLinearVelocity
				self.context.root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
			end
		end,

		Update = function()
			self.context.moveDirection = 0
		end,
	})

	-- =============================================
	-- 💨 DODGE STATE (estilo Brawlhalla)
	-- =============================================
	machine:AddState("Dodge", {
		Enter = function()
			self.context.isDodging = true
			self.context.attackLocked = true
			self.context.moveDirection = 0
			self.context.isBlocking = false
			self.context.isCrouchBlocking = false

			-- Animación: usa Idle como placeholder hasta que tengas Dodge_R/L
			self.animationController:PlayAnimation("Dodge", 0.03)

			-- Hacer la hurtbox invisible/inactiva (i-frames)
			local hurtboxBody = self.context.character:FindFirstChild("HurtboxBody")
			if hurtboxBody then
				hurtboxBody.CanQuery = false
			end

			-- Efecto visual: brillo global reutilizable durante dodge
			VFXService.CharacterFlash(self.context.character, {
				Name = "DodgeFlashHighlight",
				Color = Color3.fromRGB(215, 235, 255),
				FillTransparency = 0.72,
				OutlineTransparency = 0.18,
				Duration = self.context.dodgeDuration or 0.4,
			})
			self:_setCharacterTransparency(0.2)

			local dodgeDuration = self.context.dodgeDuration or 0.4

			task.delay(dodgeDuration, function()
				if not self.context.isDodging then
					return
				end

				self.context.isDodging = false
				self.context.attackLocked = false

				-- Restaurar hurtbox
				local hb = self.context.character:FindFirstChild("HurtboxBody")
				if hb then
					hb.CanQuery = true
				end

				-- Restaurar transparencia
				self:_setCharacterTransparency(0)
				local dodgeFlash = self.context.character:FindFirstChild("DodgeFlashHighlight")
				if dodgeFlash then
					dodgeFlash:Destroy()
				end

				ControllerRegistry.ForceResolveMovement()

				if self.context.isAirborne then
					self.context.machine:SetState("Airborne")
					return
				end

				self:ResolvePostActionState(true)
			end)
		end,

		Update = function()
			self.context.moveDirection = 0
		end,
	})

	-- =============================================
	-- 🦅 AIRBORNE STATE
	-- =============================================
	machine:AddState("Airborne", {
		Enter = function()
			self.animationController:PlayAnimation("Jump", 0.1)
		end,

		Update = function()
			-- Transiciones las maneja CharacterMotor:UpdateAirState()
		end,
	})

	-- =============================================
	-- 🪂 FREEFALL STATE (post air-tech, control limitado)
	-- =============================================
	machine:AddState("FreeFall", {
		Enter = function()
			self.context.isInFreeFall = true
			self.context.attackLocked = true
		end,

		Update = function()
			-- Movimiento limitado: usa freeFallSpeed en vez de airMoveSpeed completo
			local dir = 0
			if self.context.inputLeft then
				dir = dir - 1
			end
			if self.context.inputRight then
				dir = dir + 1
			end
			self.context.moveDirection = dir
		end,

		Exit = function()
			self.context.isInFreeFall = false
			self.context.attackLocked = false
		end,
	})

	-- =============================================
	-- 💀 KNOCKDOWN STATES
	-- =============================================
	machine:AddState("Knockdown", {
		Enter = function()
			self.context.isKnockedDown = true
			self.context.attackLocked = true
			self.context.moveDirection = 0
			self.context.isBlocking = false
			self.context.isCrouchBlocking = false

			self.animationController:PlayAnimation("Knockdown", 0.05)
		end,

		Update = function()
			self.context.moveDirection = 0
		end,
	})

	machine:AddState("Wakeup", {
		Enter = function()
			self.context.isInWakeup = true
			self.context.isKnockedDown = false
			self.context.moveDirection = 0

			self.animationController:PlayAnimation("Wakeup", 0.08)
		end,

		Update = function()
			self.context.moveDirection = 0
		end,
	})
end

-- Determina el estado correcto post-acción según flags actuales
function CombatController:ResolvePostActionState(forceAnimationRefresh)
	if self.context.isInHitstun then
		self.context.machine:SetState("Hitstun")
		return
	end

	if self.context.isKnockedDown then
		self.context.machine:SetState("Knockdown")
		return
	end

	if self.context.isInWakeup then
		self.context.machine:SetState("Wakeup")
		return
	end

	if self.context.isAirborne then
		if self.context.isInFreeFall then
			self.context.machine:SetState("FreeFall")
		else
			self.context.machine:SetState("Airborne")
		end
		return
	end

	if self.context.isDodging then
		return -- Dodge maneja su propia salida
	end

	if self.context.isCrouching then
		self.context.machine:SetState("Crouch")
	else
		if math.abs(self.context.moveDirection) > 0.01 then
			self.context.machine:SetState("Walk")
		else
			self.context.machine:SetState("Idle")
		end
	end

	if forceAnimationRefresh then
		self.animationController:RefreshLocomotionAnimation()
	end
end

-- =============================================
-- 🦅 REQUEST ATTACK (con soporte aéreo)
-- =============================================
-- Procesa solicitud de ataque: verifica estado, mapea crouch/air, inicia combo
function CombatController:RequestAttack(type)
	if
		self.context.attackLocked
		or self.context.isInHitstun
		or self.context.isKnockedDown
		or self.context.isInWakeup
		or self.context.isInBlockstun
	then
		return
	end

	local state = self.context.machine:GetState()
	local inputLeft = self.context.inputLeft == true
	local inputRight = self.context.inputRight == true
	local inputDown = self.context.inputDown == true
	local hasHorizontalInput = inputLeft ~= inputRight

	-- =============================================
	-- 🦅 ATAQUE AÉREO
	-- =============================================
	if self.context.isAirborne then
		-- Solo un ataque aéreo por salto
		if self.context.hasAirAttacked then
			return
		end

		local airType = nil

		if type == "Punch" then
			if inputDown then
				airType = "AerialRush"
			else
				airType = "AirPunch"
			end
		elseif type == "HeavyPunch" then
			if inputDown and self.attacks.AirHeavyDown then
				airType = "AirHeavyDown"
			elseif self.attacks.AirHeavy then
				airType = "AirHeavy"
			end
		end

		if not airType then
			return
		end

		local attack = self.attacks[airType]
		if not attack then
			return
		end

		self.context.hasAirAttacked = true
		self.context.currentAttack = attack
		self.context.currentAnimationName = attack.Animation
		self.context.punchComboCount = 0

		-- Mantener moveDirection si allowAirAttackMovement está activo
		if not self.context.allowAirAttackMovement then
			self.context.moveDirection = 0
		end

		self.context.machine:SetState("Attack")
		return
	end

	-- =============================================
	-- ATAQUE DE SUELO
	-- =============================================
	if state ~= "Idle" and state ~= "Walk" and state ~= "Crouch" then
		if not self.context.canCancel then
			return
		end
	end

	-- =============================================
	-- 🦵 CROUCH ATTACKS: Mapear a versión agachada
	-- Los movimientos especiales omiten este mapeo
	-- =============================================
	local actualType = type
	if not (self.attacks[type] and self.attacks[type].IsSpecial) then
		if self.context.isCrouching then
			local crouchAttackMap = {
				Punch = "CrouchPunch",
				HeavyPunch = "CrouchHeavy",
			}
			if crouchAttackMap[type] and self.attacks[crouchAttackMap[type]] then
				actualType = crouchAttackMap[type]
			end
		elseif type == "HeavyPunch" then
			-- Heavy direccional solo si se mantiene A o D
			if hasHorizontalInput and self.attacks.HeavyPunchDirectional then
				actualType = "HeavyPunchDirectional"
			end
		end
	end

	local attack = self.attacks[actualType]
	if not attack then
		warn("❌ Attack not found:", actualType)
		return
	end

	-- Si el ataque es solo aéreo, no permitir en suelo
	if attack.AirOk and not self.context.isAirborne then
		return
	end

	if actualType == "Punch" then
		local now = os.clock()
		local MAX_PUNCH_COMBO = 3

		if now - self.context.lastPunchTime > self.context.punchResetTime then
			self.context.punchComboCount = 0
		end

		if self.context.punchComboCount >= MAX_PUNCH_COMBO then
			return
		end

		self.context.punchComboCount += 1
		self.context.lastPunchTime = now

		local animName = attack.AnimationBase
		if self.context.punchComboCount > 1 then
			animName = attack.AnimationBase .. self.context.punchComboCount
		end

		self.context.currentAttack = attack
		self.context.currentAnimationName = animName
	else
		self.context.currentAttack = attack
		self.context.currentAnimationName = attack.Animation or attack.AnimationBase
		self.context.punchComboCount = 0
	end

	self.context.moveDirection = 0

	if self.context.root and self.context.root:IsA("BasePart") then
		local vel = self.context.root.AssemblyLinearVelocity
		self.context.root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
	end

	self.context.machine:SetState("Attack")
end

-- =============================================
-- PREDICCIÓN LOCAL DEL OPONENTE
-- =============================================
-- Predicción local: aplica hitstop + pushback en el oponente ANTES de la confirmación del server
function CombatController:ApplyLocalHitPrediction(victimCharacter, attackData)
	if not victimCharacter or not victimCharacter:IsA("Model") then
		return
	end

	local victimRoot = victimCharacter:FindFirstChild("HumanoidRootPart")
	if not victimRoot then
		return
	end

	if self.opponentCurrentX == nil then
		self.opponentCurrentX = victimRoot.Position.X
	end

	local pushback = attackData.Pushback or 0
	local hitstunDuration = attackData.HitstunDuration or 0.35
	local hitAnimation = attackData.HitAnimation or "HurtLight"
	local hitstopFrames = attackData.HitstopFrames or 0
	local knockdown = attackData.Knockdown or false

	local opponentDir = "R"
	if self.context.opponentRoot and self.context.opponentRoot.Parent then
		local enemyX = self.context.opponentRoot.Position.X
		local myX = self.context.root.Position.X
		opponentDir = myX >= enemyX and "R" or "L"
	end

	self.animationController:PlayOpponentAnimation(hitAnimation .. "_" .. opponentDir, 0.03)

	-- Hurtflash en la víctima (predicción local)
	VFXService.HurtFlash(victimCharacter, hitstopFrames)

	self.opponentPredictedHitstunId += 1
	local predictionId = self.opponentPredictedHitstunId
	self.opponentIsInPredictedHitstun = true

	if hitstopFrames > 0 then
		-- Hitstop en el atacante (yo) y la víctima (oponente)
		local attackerAnims = {}
		if self.animationController.currentAnimation then
			table.insert(attackerAnims, self.animationController.currentAnimation)
		end
		local victimAnims = {}
		if self.animationController.currentOpponentAnimation then
			table.insert(victimAnims, self.animationController.currentOpponentAnimation)
		end

		HitstopService:Apply(self.context.character, hitstopFrames, attackerAnims, function()
			self:_startOpponentPredictedPushback(pushback, hitstunDuration, predictionId, knockdown, opponentDir)
		end)
		if victimCharacter then
			HitstopService:Apply(victimCharacter, hitstopFrames, victimAnims)
		end
	else
		self:_startOpponentPredictedPushback(pushback, hitstunDuration, predictionId, knockdown, opponentDir)
	end
end

-- Inicia pushback predicho del oponente post-hitstop con decay
function CombatController:_startOpponentPredictedPushback(
	pushback,
	hitstunDuration,
	predictionId,
	knockdown,
	opponentDir
)
	if pushback > 0 then
		local attackerX = self.context.root.Position.X
		local victimX = self.opponentCurrentX or 0
		local direction = victimX >= attackerX and 1 or -1

		self.opponentPushVelocityX = direction * (pushback * 0.12)
		self.opponentPushDecay = math.max(0.01, math.abs(self.opponentPushVelocityX) * 0.12)
	end

	task.delay(hitstunDuration, function()
		if predictionId ~= self.opponentPredictedHitstunId then
			return
		end

		-- Si tiene knockdown, mantener predicción un poco más
		if knockdown then
			local knockdownDuration = self.context.knockdownDuration or 0.8
			self.animationController:PlayOpponentAnimation("Knockdown_" .. opponentDir, 0.05)

			task.delay(knockdownDuration, function()
				if predictionId ~= self.opponentPredictedHitstunId then
					return
				end

				local wakeupDuration = self.context.wakeupDuration or 0.4
				self.animationController:PlayOpponentAnimation("Wakeup_" .. opponentDir, 0.08)

				task.delay(wakeupDuration, function()
					if predictionId ~= self.opponentPredictedHitstunId then
						return
					end

					self.opponentIsInPredictedHitstun = false
					self.animationController:PlayOpponentAnimation("Idle_" .. opponentDir, 0.1)
				end)
			end)

			return
		end

		self.opponentIsInPredictedHitstun = false
		self.animationController:PlayOpponentAnimation("Idle_" .. opponentDir, 0.1)
	end)
end

-- Mueve visualmente al oponente durante predicción: pushback + lock CFrame
function CombatController:UpdateOpponentPrediction()
	if HitstopService:IsInHitstop(self.context.character) then
		if self.opponentIsInPredictedHitstun and self.opponentCurrentX then
			local opponentRoot = self.context.opponentRoot
			if opponentRoot and opponentRoot.Parent then
				local pos = opponentRoot.Position
				local myX = self.context.root.Position.X
				local faceRight = myX >= self.opponentCurrentX
				local angleY = faceRight and math.rad(-90) or math.rad(90)

				opponentRoot.CFrame = CFrame.new(self.opponentCurrentX, pos.Y, self.context.lockedZ)
					* CFrame.Angles(0, angleY, 0)
			end
		end
		return
	end

	if math.abs(self.opponentPushVelocityX or 0) > 0.01 then
		if self.opponentCurrentX then
			-- Verificar colisión antes de mover al oponente predicho
			local newX = self.opponentCurrentX + self.opponentPushVelocityX
			local canMove = true

			if self.context.motor and self.context.motor.CanMoveToX then
				-- Usar un test simple en la posición del oponente
				local opponentRoot = self.context.opponentRoot
				if opponentRoot and opponentRoot.Parent then
					local testCFrame = CFrame.new(newX, opponentRoot.Position.Y, self.context.lockedZ)
					local testSize = Vector3.new(3, 5, 3)

					local overlapParams = OverlapParams.new()
					overlapParams.FilterType = Enum.RaycastFilterType.Exclude
					overlapParams.FilterDescendantsInstances = {
						self.context.character,
						self.context.opponent or {},
					}
					overlapParams.MaxParts = 20

					local parts = workspace:GetPartBoundsInBox(testCFrame, testSize, overlapParams)
					for _, part in ipairs(parts) do
						if
							part:IsA("BasePart")
							and part.CanCollide
							and part.Name ~= "HurtboxBody"
							and part.Name ~= "DebugHitbox"
						then
							canMove = false
							break
						end
					end
				end
			end

			if canMove then
				self.opponentCurrentX = newX
			else
				-- Parar el pushback si hay pared
				self.opponentPushVelocityX = 0
			end

			local sign = self.opponentPushVelocityX >= 0 and 1 or -1
			local absVel = math.abs(self.opponentPushVelocityX or 0)
			absVel = math.max(0, absVel - self.opponentPushDecay)
			self.opponentPushVelocityX = absVel * sign
		end
	else
		self.opponentPushVelocityX = 0
	end

	if self.opponentIsInPredictedHitstun and self.opponentCurrentX then
		local opponentRoot = self.context.opponentRoot
		if opponentRoot and opponentRoot.Parent then
			local pos = opponentRoot.Position
			local myX = self.context.root.Position.X
			local faceRight = myX >= self.opponentCurrentX
			local angleY = faceRight and math.rad(-90) or math.rad(90)

			opponentRoot.CFrame = CFrame.new(self.opponentCurrentX, pos.Y, self.context.lockedZ)
				* CFrame.Angles(0, angleY, 0)
		end
	else
		if self.context.opponentRoot and self.context.opponentRoot.Parent then
			self.opponentCurrentX = self.context.opponentRoot.Position.X
		end
	end
end

-- Update por frame: cuenta attackFrames, cancel window, predicción oponente
function CombatController:Update(dt)
	if HitstopService:IsInHitstop(self.context.character) then
		self:UpdateOpponentPrediction()
		return
	end

	if self.context.machine:GetState() == "Attack" then
		self.context.attackFrame += 1
	end

	local attack = self.context.currentAttack
	if attack and attack.CancelWindow then
		if
			self.context.attackFrame >= attack.CancelWindow.Start
			and self.context.attackFrame <= attack.CancelWindow.End
		then
			self.context.canCancel = true
		else
			self.context.canCancel = false
		end
	else
		self.context.canCancel = false
	end

	self:UpdateOpponentPrediction()
end

return CombatController
