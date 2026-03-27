-- VFXService: efectos visuales para golpes y reacciones
-- Proporciona PlayHitEffect y FlashCharacter
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VFXService = {}

-- =============================================
-- Configuración de efectos por tipo de golpe
-- =============================================
local HitEffectConfig = {
	Light = {
		Color = Color3.fromRGB(255, 255, 255),
		Size = Vector3.new(0.6, 0.6, 0.6),
		Duration = 0.12,
		ParticleCount = 6,
		SpreadRadius = 1.2,
	},
	Heavy = {
		Color = Color3.fromRGB(255, 140, 30),
		Size = Vector3.new(1.1, 1.1, 1.1),
		Duration = 0.2,
		ParticleCount = 12,
		SpreadRadius = 2.0,
	},
	Special = {
		Color = Color3.fromRGB(100, 60, 255),
		Size = Vector3.new(1.5, 1.5, 1.5),
		Duration = 0.3,
		ParticleCount = 18,
		SpreadRadius = 2.8,
	},
}

-- Crea una Part de efecto en la posición indicada y la destruye tras la duración
local function spawnEffectPart(position, color, size, duration)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.2
	part.Shape = Enum.PartType.Ball
	part.Name = "HitVFX"
	part.Parent = workspace

	-- Animar escala y transparencia hacia 0
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(part, tweenInfo, {
		Size = size * 2.5,
		Transparency = 1,
	})
	tween:Play()

	task.delay(duration + 0.05, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end

-- Crea partículas de chispa alrededor de la posición
local function spawnSparks(position, color, count, spreadRadius, duration)
	for _ = 1, count do
		local offset =
			Vector3.new((math.random() - 0.5) * spreadRadius * 2, (math.random() - 0.5) * spreadRadius * 2, 0)

		local sparkPos = position + offset

		local spark = Instance.new("Part")
		spark.Size = Vector3.new(0.15, 0.15, 0.15)
		spark.CFrame = CFrame.new(sparkPos)
		spark.Anchored = true
		spark.CanCollide = false
		spark.CanTouch = false
		spark.CanQuery = false
		spark.CastShadow = false
		spark.Material = Enum.Material.Neon
		spark.Color = color
		spark.Transparency = 0
		spark.Shape = Enum.PartType.Ball
		spark.Name = "HitSpark"
		spark.Parent = workspace

		local tweenInfo = TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(spark, tweenInfo, {
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		})
		tween:Play()

		task.delay(duration + 0.05, function()
			if spark and spark.Parent then
				spark:Destroy()
			end
		end)
	end
end

-- =============================================
-- PlayHitEffect: reproduce efecto visual en la posición del golpe
-- hitType: "Light", "Heavy", "Special"
-- direction: Vector3 opcional (dirección del golpe)
-- =============================================
function VFXService.PlayHitEffect(position, hitType, _direction)
	if not position then
		return
	end

	local config = HitEffectConfig[hitType] or HitEffectConfig.Light

	-- Burst central
	spawnEffectPart(position, config.Color, config.Size, config.Duration)

	-- Chispas
	spawnSparks(position, config.Color, config.ParticleCount, config.SpreadRadius, config.Duration)
end

-- =============================================
-- FlashCharacter: parpadeo blanco/brillante al recibir golpe
-- character: Model del personaje
-- duration: duración del flash en segundos
-- =============================================
function VFXService.FlashCharacter(character, duration)
	if not character then
		return
	end

	duration = duration or 0.08

	local parts = {}
	local originalColors = {}
	local originalMaterials = {}

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Name ~= "HurtboxBody" then
			table.insert(parts, part)
			originalColors[part] = part.Color
			originalMaterials[part] = part.Material
			part.Color = Color3.fromRGB(255, 255, 255)
			part.Material = Enum.Material.Neon
		end
	end

	task.delay(duration, function()
		for _, part in pairs(parts) do
			if part and part.Parent then
				part.Color = originalColors[part] or part.Color
				part.Material = originalMaterials[part] or part.Material
			end
		end
	end)
end

-- =============================================
-- HurtFlash: overlay de color sólido sobre todo el personaje (estilo KOF/SF)
-- Usa Highlight de Roblox para pintar el modelo completo.
-- Pulsa visible/invisible cada TOGGLE_INTERVAL frames durante hitstop.
-- character: Model del personaje
-- hitstopFrames: frames de hitstop (para sincronizar duración)
-- =============================================
local HURTFLASH_COLOR = Color3.fromRGB(187, 187, 187)
local HURTFLASH_OUTLINE_COLOR = Color3.fromRGB(241, 241, 241)
local HURTFLASH_FILL_TRANSPARENCY = 0.15
local HURTFLASH_OUTLINE_TRANSPARENCY = 0.5
local HURTFLASH_ENABLE_BLINK = false
local HURTFLASH_BLINK_INTERVAL_FRAMES = 2

-- Limpia cualquier Highlight de hurtflash previo en el personaje
local function cleanupHurtFlash(character)
	local existing = character:FindFirstChild("HurtFlashHighlight")
	if existing then
		existing:Destroy()
	end
end

-- Crea el Highlight configurado para hurtflash
local function createHurtFlashHighlight(character)
	cleanupHurtFlash(character)

	local highlight = Instance.new("Highlight")
	highlight.Name = "HurtFlashHighlight"
	highlight.FillColor = HURTFLASH_COLOR
	highlight.FillTransparency = HURTFLASH_FILL_TRANSPARENCY
	highlight.OutlineColor = HURTFLASH_OUTLINE_COLOR
	highlight.OutlineTransparency = HURTFLASH_OUTLINE_TRANSPARENCY
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character

	return highlight
end

function VFXService.HurtFlash(character, hitstopFrames)
	if not character then
		return
	end

	hitstopFrames = hitstopFrames or 0

	-- Sin hitstop: flash simple (un solo pulso)
	if hitstopFrames <= 0 then
		local highlight = createHurtFlashHighlight(character)
		task.delay(0.08, function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end)
		return
	end

	-- Flash pulsante durante hitstop
	local highlight = createHurtFlashHighlight(character)

	local frameCounter = 0
	local totalFrames = 0
	local isVisible = true

	local connection
	connection = RunService.RenderStepped:Connect(function()
		totalFrames += 1

		if HURTFLASH_ENABLE_BLINK then
			frameCounter += 1

			if frameCounter >= HURTFLASH_BLINK_INTERVAL_FRAMES then
				frameCounter = 0
				isVisible = not isVisible

				if highlight and highlight.Parent then
					highlight.FillTransparency = isVisible and HURTFLASH_FILL_TRANSPARENCY or 1
					highlight.OutlineTransparency = isVisible and HURTFLASH_OUTLINE_TRANSPARENCY or 1
				end
			end
		end

		-- Terminar al alcanzar la duración del hitstop
		if totalFrames >= hitstopFrames then
			connection:Disconnect()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end
	end)
end

-- =============================================
-- PlayAttackVFX: reproduce un VFX personalizado durante el ataque
-- Se llama al conectar el golpe si el ataque tiene AttackVFX definido.
-- attackVFX: tabla con la configuración del efecto { Type, ... }
-- character: Model del atacante
-- hitPosition: Vector3 del punto de impacto
-- direction: Vector3 dirección del golpe
-- =============================================
function VFXService.PlayAttackVFX(attackVFX, character, hitPosition, direction)
	if not attackVFX or not attackVFX.Type then
		return
	end

	local vfxType = attackVFX.Type

	if vfxType == "FireHand" then
		VFXService._playFireHand(attackVFX, character, hitPosition, direction)
	elseif vfxType == "Custom" then
		-- Punto de extensión para VFX completamente custom
		-- attackVFX.Handler(character, hitPosition, direction) si se necesita
	end
end

-- =============================================
-- FireHand: puño de fuego que estalla en el impacto
-- Crea partículas de fuego alrededor del punto de golpe
-- =============================================
function VFXService._playFireHand(config, _character, hitPosition, _direction)
	local color = config.Color or Color3.fromRGB(255, 100, 0)
	local coreColor = config.CoreColor or Color3.fromRGB(255, 200, 50)
	local size = config.Size or 1.5
	local duration = config.Duration or 0.3
	local flameCount = config.FlameCount or 10

	-- Núcleo de fuego brillante
	local core = Instance.new("Part")
	core.Size = Vector3.new(size, size, size)
	core.CFrame = CFrame.new(hitPosition)
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.CastShadow = false
	core.Material = Enum.Material.Neon
	core.Color = coreColor
	core.Transparency = 0.1
	core.Shape = Enum.PartType.Ball
	core.Name = "FireVFX_Core"
	core.Parent = workspace

	local coreTween =
		TweenService:Create(core, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(size * 2.5, size * 2.5, size * 2.5),
			Transparency = 1,
		})
	coreTween:Play()

	task.delay(duration + 0.05, function()
		if core and core.Parent then
			core:Destroy()
		end
	end)

	-- Anillo exterior de fuego
	local ring = Instance.new("Part")
	ring.Size = Vector3.new(size * 0.8, size * 0.8, size * 0.8)
	ring.CFrame = CFrame.new(hitPosition)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.3
	ring.Shape = Enum.PartType.Ball
	ring.Name = "FireVFX_Ring"
	ring.Parent = workspace

	local ringTween =
		TweenService:Create(ring, TweenInfo.new(duration * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(size * 3.5, size * 3.5, size * 3.5),
			Transparency = 1,
		})
	ringTween:Play()

	task.delay(duration + 0.05, function()
		if ring and ring.Parent then
			ring:Destroy()
		end
	end)

	-- Llamas dispersas (partículas de fuego)
	for i = 1, flameCount do
		local angle = (i / flameCount) * math.pi * 2
		local spreadRadius = size * 1.5
		local offsetX = math.cos(angle) * spreadRadius * (0.5 + math.random() * 0.5)
		local offsetY = math.sin(angle) * spreadRadius * (0.5 + math.random() * 0.5)
		local offset = Vector3.new(offsetX, offsetY, 0)
		local flamePos = hitPosition + offset

		local flameSize = 0.2 + math.random() * 0.3
		local flame = Instance.new("Part")
		flame.Size = Vector3.new(flameSize, flameSize, flameSize)
		flame.CFrame = CFrame.new(flamePos)
		flame.Anchored = true
		flame.CanCollide = false
		flame.CanTouch = false
		flame.CanQuery = false
		flame.CastShadow = false
		flame.Material = Enum.Material.Neon
		-- Alternar entre el color naranja y amarillo
		flame.Color = i % 2 == 0 and color or coreColor
		flame.Transparency = 0.1
		flame.Shape = Enum.PartType.Ball
		flame.Name = "FireVFX_Flame"
		flame.Parent = workspace

		local flameDuration = duration * (0.5 + math.random() * 0.5)
		-- Las llamas suben ligeramente simulando fuego
		local riseY = 0.5 + math.random() * 1.0
		local flameTween =
			TweenService:Create(flame, TweenInfo.new(flameDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
				CFrame = CFrame.new(flamePos + Vector3.new(0, riseY, 0)),
			})
		flameTween:Play()

		task.delay(flameDuration + 0.05, function()
			if flame and flame.Parent then
				flame:Destroy()
			end
		end)
	end
end

-- =============================================
-- SWING VFX SYSTEM
-- VFX que se reproduce durante el ataque, NO requiere conectar el golpe.
-- Se usa para que ataques pesados/especiales se sientan poderosos.
--
-- CÓMO AGREGAR UN VFX PERSONALIZADO:
-- 1. Crea una función que reciba (character, attackData) y genere el efecto
-- 2. Regístrala: VFXService.RegisterSwingVFX("MiNombre", miFuncion)
-- 3. En el ataque, pon VFX_Name = "MiNombre"
-- El efecto se disparará automáticamente al iniciar el ataque.
-- =============================================

-- Registro interno de VFX por nombre
local SwingVFXRegistry = {}

-- Registra un VFX personalizado por nombre.
-- name: string identificador único (el que usarás en VFX_Name del ataque)
-- handler: función(character, attackData) que crea el efecto visual
function VFXService.RegisterSwingVFX(name, handler)
	if type(name) ~= "string" or type(handler) ~= "function" then
		warn("❌ RegisterSwingVFX: name must be string, handler must be function")
		return
	end
	SwingVFXRegistry[name] = handler
end

-- Reproduce el VFX de swing registrado bajo el nombre dado.
-- Se llama desde CombatController al INICIAR el ataque (no depende de hit).
-- vfxName: string (el VFX_Name del ataque)
-- character: Model del atacante
-- attackData: tabla del ataque completo
function VFXService.PlaySwingVFX(vfxName, character, attackData)
	if not vfxName or not character then
		return
	end

	local handler = SwingVFXRegistry[vfxName]
	if handler then
		task.spawn(handler, character, attackData)
	else
		warn("⚠️ SwingVFX not found:", vfxName, "- Registra con VFXService.RegisterSwingVFX()")
	end
end

-- =============================================
-- BUILT-IN SWING VFX: FirePunch
-- Puño de fuego que envuelve la mano del personaje durante el ataque.
-- El efecto se adhiere a la mano derecha y dura startup + active frames.
-- =============================================

local FIRE_PUNCH_COLOR = Color3.fromRGB(255, 100, 0)
local FIRE_PUNCH_CORE_COLOR = Color3.fromRGB(255, 220, 60)
local FIRE_PUNCH_GLOW_SIZE = 1.2
local FIRE_PUNCH_FLAME_COUNT = 6
local FIRE_PUNCH_ORBIT_SPEED = 12

-- Encuentra la mano derecha del personaje (R15 o R6)
local function findRightHand(character)
	-- R15
	local hand = character:FindFirstChild("RightHand")
	if hand then
		return hand
	end
	-- R6
	local arm = character:FindFirstChild("Right Arm")
	if arm then
		return arm
	end
	-- Fallback: cualquier parte con "right" y "hand/arm"
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local lowerName = string.lower(part.Name)
			if
				string.find(lowerName, "right") and (string.find(lowerName, "hand") or string.find(lowerName, "arm"))
			then
				return part
			end
		end
	end
	return nil
end

VFXService.RegisterSwingVFX("FirePunch", function(character, attackData)
	local hand = findRightHand(character)
	if not hand then
		return
	end

	local duration = (attackData.Startup or 0) + (attackData.Active or 0)
	if duration <= 0 then
		duration = 0.4
	end

	local elapsed = 0
	local parts = {}

	-- Glow central adherido a la mano
	local glow = Instance.new("Part")
	glow.Size = Vector3.new(FIRE_PUNCH_GLOW_SIZE, FIRE_PUNCH_GLOW_SIZE, FIRE_PUNCH_GLOW_SIZE)
	glow.CFrame = hand.CFrame
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanTouch = false
	glow.CanQuery = false
	glow.CastShadow = false
	glow.Material = Enum.Material.Neon
	glow.Color = FIRE_PUNCH_CORE_COLOR
	glow.Transparency = 0.3
	glow.Shape = Enum.PartType.Ball
	glow.Name = "FirePunch_Glow"
	glow.Parent = workspace
	table.insert(parts, glow)

	-- Llamitas orbitantes alrededor de la mano
	local flames = {}
	for i = 1, FIRE_PUNCH_FLAME_COUNT do
		local flame = Instance.new("Part")
		local fSize = 0.2 + math.random() * 0.25
		flame.Size = Vector3.new(fSize, fSize, fSize)
		flame.Anchored = true
		flame.CanCollide = false
		flame.CanTouch = false
		flame.CanQuery = false
		flame.CastShadow = false
		flame.Material = Enum.Material.Neon
		flame.Color = i % 2 == 0 and FIRE_PUNCH_COLOR or FIRE_PUNCH_CORE_COLOR
		flame.Transparency = 0.15
		flame.Shape = Enum.PartType.Ball
		flame.Name = "FirePunch_Flame"
		flame.Parent = workspace
		table.insert(parts, flame)
		table.insert(
			flames,
			{ part = flame, angle = (i / FIRE_PUNCH_FLAME_COUNT) * math.pi * 2, radius = 0.5 + math.random() * 0.3 }
		)
	end

	-- Loop de seguimiento: las llamas orbitan la mano durante el ataque
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt

		if elapsed >= duration or not hand or not hand.Parent then
			connection:Disconnect()
			-- Fade out
			for _, p in ipairs(parts) do
				if p and p.Parent then
					local fadeInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					TweenService:Create(p, fadeInfo, { Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
				end
			end
			task.delay(0.2, function()
				for _, p in ipairs(parts) do
					if p and p.Parent then
						p:Destroy()
					end
				end
			end)
			return
		end

		-- Seguir la mano
		local handPos = hand.Position
		glow.CFrame = CFrame.new(handPos)

		-- Pulsar tamaño del glow
		local pulse = 1 + math.sin(elapsed * 20) * 0.15
		glow.Size =
			Vector3.new(FIRE_PUNCH_GLOW_SIZE * pulse, FIRE_PUNCH_GLOW_SIZE * pulse, FIRE_PUNCH_GLOW_SIZE * pulse)

		-- Orbitar llamas
		for _, f in ipairs(flames) do
			f.angle += FIRE_PUNCH_ORBIT_SPEED * dt
			local ox = math.cos(f.angle) * f.radius
			local oy = math.sin(f.angle) * f.radius
			f.part.CFrame = CFrame.new(handPos + Vector3.new(ox, oy, 0))
		end
	end)
end)

return VFXService
