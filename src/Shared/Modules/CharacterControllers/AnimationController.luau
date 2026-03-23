local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Character = Modules:WaitForChild("Character")

local AnimationsFolder = Character:WaitForChild("Animations")
local AnimationsTest = AnimationsFolder:WaitForChild("Test")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local ReplicateAnimationEvent = RemoteEvents:WaitForChild("ReplicateAnimation")

-- Controlador de animaciones: carga, reproduce y replica animaciones con sufijo direccional (_R/_L)
local AnimationController = {}
AnimationController.__index = AnimationController

local DEBUG_ANIMATION = false

-- Carga un KeyframeSequence y retorna el AnimationTrack
local function loadSequence(animator, sequence)
	local anim = Instance.new("Animation")
	anim.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	return animator:LoadAnimation(anim)
end

-- Intentar cargar una animación, devolver nil si no existe
local function tryLoadSequence(animator, folder, name)
	local sequence = folder:FindFirstChild(name)
	if sequence then
		return loadSequence(animator, sequence)
	end
	return nil
end

-- Constructor: carga todas las animaciones del personaje con variantes _R y _L
function AnimationController.new(context)
	local self = setmetatable({}, AnimationController)

	self.context = context
	self.animator = context.animator

	self.currentAnimation = nil
	self.currentAnimationName = nil

	self.opponentAnimations = {}
	self.currentOpponentAnimation = nil
	self.currentOpponentAnimationName = nil

	-- Animaciones base (existentes)
	self.animations = {
		Idle_R = loadSequence(self.animator, AnimationsTest.Idle_R),
		Idle_L = loadSequence(self.animator, AnimationsTest.Idle_L),

		Walk_R = loadSequence(self.animator, AnimationsTest.Walk_R),
		Walk_L = loadSequence(self.animator, AnimationsTest.Walk_L),

		Punch_R = loadSequence(self.animator, AnimationsTest.Punch_R),
		Punch_L = loadSequence(self.animator, AnimationsTest.Punch_L),

		Punch2_R = loadSequence(self.animator, AnimationsTest.Punch2_R),
		Punch2_L = loadSequence(self.animator, AnimationsTest.Punch2_L),

		Punch3_R = loadSequence(self.animator, AnimationsTest.Punch3_R),
		Punch3_L = loadSequence(self.animator, AnimationsTest.Punch3_L),

		HeavyPunch_R = loadSequence(self.animator, AnimationsTest.Heavy_R),
		HeavyPunch_L = loadSequence(self.animator, AnimationsTest.Heavy_R),

		HurtLight_R = loadSequence(self.animator, AnimationsTest.HurtLight_R),
		HurtLight_L = loadSequence(self.animator, AnimationsTest.HurtLight_R),

		Crouch_R = loadSequence(self.animator, AnimationsTest.Crouch_R),
		Crouch_L = loadSequence(self.animator, AnimationsTest.Crouch_R),

		CrouchWalk_R = loadSequence(self.animator, AnimationsTest.CrouchWalk_R),
		CrouchWalk_L = loadSequence(self.animator, AnimationsTest.CrouchWalk_R),

		CrouchPunch_R = loadSequence(self.animator, AnimationsTest.CrouchPunch_R),
		CrouchPunch_L = loadSequence(self.animator, AnimationsTest.CrouchPunch_R),

		CrouchHeavy_R = loadSequence(self.animator, AnimationsTest.Punch3_R),
		CrouchHeavy_L = loadSequence(self.animator, AnimationsTest.Punch3_L),
	}

	-- Nuevas animaciones (con fallback si no existen todavía)
	-- Block
	--self.animations.Block_R = tryLoadSequence(self.animator, AnimationsTest, "Block_R")
	--	or self.animations.Idle_R
	--self.animations.Block_L = tryLoadSequence(self.animator, AnimationsTest, "Block_L")
	--	or self.animations.Idle_L

	---- CrouchBlock
	--self.animations.CrouchBlock_R = tryLoadSequence(self.animator, AnimationsTest, "CrouchBlock_R")
	--	or self.animations.Block_R
	--self.animations.CrouchBlock_L = tryLoadSequence(self.animator, AnimationsTest, "CrouchBlock_L")
	--	or self.animations.Block_L

	---- BlockHit (reacción al bloquear)
	--self.animations.BlockHit_R = tryLoadSequence(self.animator, AnimationsTest, "BlockHit_R")
	--	or self.animations.Block_R
	--self.animations.BlockHit_L = tryLoadSequence(self.animator, AnimationsTest, "BlockHit_L")
	--	or self.animations.Block_L

	-- Dodge
	self.animations.Dodge_R = tryLoadSequence(self.animator, AnimationsTest, "Dodge_R") or self.animations.Idle_R
	self.animations.Dodge_L = tryLoadSequence(self.animator, AnimationsTest, "Dodge_L") or self.animations.Idle_L

	-- Jump
	self.animations.Jump_R = tryLoadSequence(self.animator, AnimationsTest, "Jump_R") or self.animations.Idle_R
	self.animations.Jump_L = tryLoadSequence(self.animator, AnimationsTest, "Jump_L") or self.animations.Idle_L

	-- Air attacks
	self.animations.AirPunch_R = tryLoadSequence(self.animator, AnimationsTest, "AirPunch_R") or self.animations.Punch_R
	self.animations.AirPunch_L = tryLoadSequence(self.animator, AnimationsTest, "AirPunch_L") or self.animations.Punch_L

	self.animations.AirHeavy_R = tryLoadSequence(self.animator, AnimationsTest, "AirHeavy_R")
		or self.animations.HeavyPunch_R
	self.animations.AirHeavy_L = tryLoadSequence(self.animator, AnimationsTest, "AirHeavy_L")
		or self.animations.HeavyPunch_L

	-- Air hurt
	self.animations.AirHurt_R = tryLoadSequence(self.animator, AnimationsTest, "AirHurt_R")
		or self.animations.HurtLight_R
	self.animations.AirHurt_L = tryLoadSequence(self.animator, AnimationsTest, "AirHurt_L")
		or self.animations.HurtLight_L

	-- Knockdown
	self.animations.Knockdown_R = tryLoadSequence(self.animator, AnimationsTest, "Knockdown_R")
		or self.animations.HurtLight_R
	self.animations.Knockdown_L = tryLoadSequence(self.animator, AnimationsTest, "Knockdown_L")
		or self.animations.HurtLight_L

	-- Wakeup (levantarse)
	self.animations.Wakeup_R = tryLoadSequence(self.animator, AnimationsTest, "Wakeup_R") or self.animations.Idle_R
	self.animations.Wakeup_L = tryLoadSequence(self.animator, AnimationsTest, "Wakeup_L") or self.animations.Idle_L

	-- Launch (ser lanzado al aire)
	self.animations.Launch_R = tryLoadSequence(self.animator, AnimationsTest, "Launch_R") or self.animations.AirHurt_R
	self.animations.Launch_L = tryLoadSequence(self.animator, AnimationsTest, "Launch_L") or self.animations.AirHurt_L

	-- Special Move animations
	self.animations.Fireball_R = tryLoadSequence(self.animator, AnimationsTest, "Fireball_R") or self.animations.HeavyPunch_R
	self.animations.Fireball_L = tryLoadSequence(self.animator, AnimationsTest, "Fireball_L") or self.animations.HeavyPunch_L
	self.animations.Uppercut_R = tryLoadSequence(self.animator, AnimationsTest, "Uppercut_R") or self.animations.HeavyPunch_R
	self.animations.Uppercut_L = tryLoadSequence(self.animator, AnimationsTest, "Uppercut_L") or self.animations.HeavyPunch_L

	return self
end

-- Verifica si existe la animación con el nombre base dado
function AnimationController:HasAnimation(baseName)
	local fullName = baseName .. "_" .. self.context.currentDirection
	return self.animations[fullName] ~= nil
end

-- Detiene la animación actual con fadeTime opcional
function AnimationController:StopCurrent(fadeTime)
	fadeTime = fadeTime or 0.1

	if self.currentAnimation then
		self.currentAnimation:Stop(fadeTime)
		self.currentAnimation = nil
		self.currentAnimationName = nil
	end
end

-- Reproduce animación usando sufijo direccional y replica al servidor
function AnimationController:PlayAnimation(baseName, fadeTime)
	fadeTime = fadeTime or 0.15

	local fullName = baseName .. "_" .. self.context.currentDirection

	if DEBUG_ANIMATION then
		print("🎬 Playing animation:", fullName)
	end

	if self.currentAnimationName == fullName and self.currentAnimation and self.currentAnimation.IsPlaying then
		return true
	end

	if self.currentAnimation then
		self.currentAnimation:Stop(fadeTime)
	end

	local anim = self.animations[fullName]

	if anim then
		anim:Play(0, 1, 1)
		self.currentAnimation = anim
		self.currentAnimationName = fullName
		ReplicateAnimationEvent:FireServer(fullName)
		return true
	end

	local fallbackName = baseName .. "_" .. (self.context.currentDirection == "R" and "L" or "R")
	local fallbackAnim = self.animations[fallbackName]

	if fallbackAnim then
		warn("⚠️ Using fallback animation:", fallbackName)
		fallbackAnim:Play(0, 1, 1)
		self.currentAnimation = fallbackAnim
		self.currentAnimationName = fallbackName
		ReplicateAnimationEvent:FireServer(fallbackName)
		return true
	end

	warn("❌ Animation not found:", fullName, "or fallback for", baseName)
	return false
end

-- Recalcula y reproduce la animación de locomoción según estado actual
function AnimationController:RefreshLocomotionAnimation()
	local state = self.context.machine:GetState()

	if self.context.isInHitstun then
		return
	end

	if state == "Attack" or state == "Hitstun" then
		return
	end

	if self.context.isCrouching then
		if math.abs(self.context.moveDirection) > 0.01 then
			if self:HasAnimation("CrouchWalk") then
				self:PlayAnimation("CrouchWalk", 0.08)
			elseif self:HasAnimation("Crouch") then
				self:PlayAnimation("Crouch", 0.08)
			else
				self:StopCurrent(0.08)
			end
		else
			if self:HasAnimation("Crouch") then
				self:PlayAnimation("Crouch", 0.08)
			else
				self:StopCurrent(0.08)
			end
		end
		return
	end

	if state == "Walk" then
		self:PlayAnimation("Walk", 0.08)
	else
		self:PlayAnimation("Idle", 0.08)
	end
end

-- Carga animaciones del oponente para reproducir localmente (predicción visual)
function AnimationController:LoadOpponentAnimations(opponentCharacter)
	if not opponentCharacter then
		return
	end

	local opponentHumanoid = opponentCharacter:FindFirstChildOfClass("Humanoid")
	if not opponentHumanoid then
		warn("❌ Opponent has no Humanoid")
		return
	end

	local opponentAnimator = opponentHumanoid:FindFirstChild("Animator")
	if not opponentAnimator then
		warn("❌ Opponent has no Animator")
		return
	end

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

		Crouch_R = loadSequence(opponentAnimator, AnimationsTest.Crouch_R),
		Crouch_L = loadSequence(opponentAnimator, AnimationsTest.Crouch_R),

		CrouchWalk_R = loadSequence(opponentAnimator, AnimationsTest.CrouchWalk_R),
		CrouchWalk_L = loadSequence(opponentAnimator, AnimationsTest.CrouchWalk_R),
	}

	-- Nuevas animaciones del oponente con fallback
	--self.opponentAnimations.Block_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Block_R")
	--	or self.opponentAnimations.Idle_R
	--self.opponentAnimations.Block_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Block_L")
	--	or self.opponentAnimations.Idle_L

	--self.opponentAnimations.CrouchBlock_R = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchBlock_R")
	--	or self.opponentAnimations.Block_R
	--self.opponentAnimations.CrouchBlock_L = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchBlock_L")
	--	or self.opponentAnimations.Block_L

	--self.opponentAnimations.BlockHit_R = tryLoadSequence(opponentAnimator, AnimationsTest, "BlockHit_R")
	--	or self.opponentAnimations.Block_R
	--self.opponentAnimations.BlockHit_L = tryLoadSequence(opponentAnimator, AnimationsTest, "BlockHit_L")
	--	or self.opponentAnimations.Block_L

	self.opponentAnimations.CrouchPunch_R = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchPunch_R")
		or self.opponentAnimations.Punch_R
	self.opponentAnimations.CrouchPunch_L = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchPunch_L")
		or self.opponentAnimations.Punch_L

	self.opponentAnimations.CrouchHeavy_R = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchHeavy_R")
		or self.opponentAnimations.HeavyPunch_R
	self.opponentAnimations.CrouchHeavy_L = tryLoadSequence(opponentAnimator, AnimationsTest, "CrouchHeavy_L")
		or self.opponentAnimations.HeavyPunch_L

	self.opponentAnimations.Dodge_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Dodge_R")
		or self.opponentAnimations.Idle_R
	self.opponentAnimations.Dodge_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Dodge_L")
		or self.opponentAnimations.Idle_L

	self.opponentAnimations.Jump_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Jump_R")
		or self.opponentAnimations.Idle_R
	self.opponentAnimations.Jump_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Jump_L")
		or self.opponentAnimations.Idle_L

	self.opponentAnimations.AirPunch_R = tryLoadSequence(opponentAnimator, AnimationsTest, "AirPunch_R")
		or self.opponentAnimations.Punch_R
	self.opponentAnimations.AirPunch_L = tryLoadSequence(opponentAnimator, AnimationsTest, "AirPunch_L")
		or self.opponentAnimations.Punch_L

	self.opponentAnimations.AirHeavy_R = tryLoadSequence(opponentAnimator, AnimationsTest, "AirHeavy_R")
		or self.opponentAnimations.HeavyPunch_R
	self.opponentAnimations.AirHeavy_L = tryLoadSequence(opponentAnimator, AnimationsTest, "AirHeavy_L")
		or self.opponentAnimations.HeavyPunch_L

	self.opponentAnimations.AirHurt_R = tryLoadSequence(opponentAnimator, AnimationsTest, "AirHurt_R")
		or self.opponentAnimations.HurtLight_R
	self.opponentAnimations.AirHurt_L = tryLoadSequence(opponentAnimator, AnimationsTest, "AirHurt_L")
		or self.opponentAnimations.HurtLight_L

	self.opponentAnimations.Knockdown_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Knockdown_R")
		or self.opponentAnimations.HurtLight_R
	self.opponentAnimations.Knockdown_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Knockdown_L")
		or self.opponentAnimations.HurtLight_L

	self.opponentAnimations.Wakeup_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Wakeup_R")
		or self.opponentAnimations.Idle_R
	self.opponentAnimations.Wakeup_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Wakeup_L")
		or self.opponentAnimations.Idle_L

	self.opponentAnimations.Launch_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Launch_R")
		or self.opponentAnimations.AirHurt_R
	self.opponentAnimations.Launch_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Launch_L")
		or self.opponentAnimations.AirHurt_L

	self.opponentAnimations.Fireball_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Fireball_R")
		or self.opponentAnimations.HeavyPunch_R
	self.opponentAnimations.Fireball_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Fireball_L")
		or self.opponentAnimations.HeavyPunch_L
	self.opponentAnimations.Uppercut_R = tryLoadSequence(opponentAnimator, AnimationsTest, "Uppercut_R")
		or self.opponentAnimations.HeavyPunch_R
	self.opponentAnimations.Uppercut_L = tryLoadSequence(opponentAnimator, AnimationsTest, "Uppercut_L")
		or self.opponentAnimations.HeavyPunch_L

	self.currentOpponentAnimation = nil
	self.currentOpponentAnimationName = nil
end

-- Detiene la animación del oponente en curso
function AnimationController:StopOpponentAnimation(fadeTime)
	fadeTime = fadeTime or 0.1

	if self.currentOpponentAnimation then
		self.currentOpponentAnimation:Stop(fadeTime)
		self.currentOpponentAnimation = nil
		self.currentOpponentAnimationName = nil
	end
end

-- Reproduce animación del oponente localmente (predicción visual)
function AnimationController:PlayOpponentAnimation(animationName, fadeTime)
	fadeTime = fadeTime or 0.1

	if not self.opponentAnimations or not self.opponentAnimations[animationName] then
		warn("❌ Opponent animation not found:", animationName)
		return false
	end

	if
		self.currentOpponentAnimationName == animationName
		and self.currentOpponentAnimation
		and self.currentOpponentAnimation.IsPlaying
	then
		return true
	end

	if self.currentOpponentAnimation then
		self.currentOpponentAnimation:Stop(fadeTime)
	end

	local track = self.opponentAnimations[animationName]
	track:Play(0, 1, 1)

	self.currentOpponentAnimation = track
	self.currentOpponentAnimationName = animationName

	return true
end

return AnimationController
