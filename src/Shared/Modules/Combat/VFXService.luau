-- VFXService: efectos visuales para golpes y reacciones
-- Proporciona PlayHitEffect, FlashCharacter, HurtFlash, PlayAttackVFX, PlaySwingVFX
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- SWING VFX SYSTEM (basado en carpeta)
-- VFX que se reproduce durante el ataque, NO requiere conectar el golpe.
-- Se usa para que ataques pesados/especiales se sientan poderosos.
--
-- CÓMO AGREGAR UN VFX A UN ATAQUE:
-- 1. Dentro de la carpeta del personaje (ej: Characters/Ken/), crea una carpeta "VFX"
-- 2. Dentro de VFX/, coloca un Model o Part con el nombre que quieras (ej: "FirePunch")
--    → Puede contener ParticleEmitters, Lights, Parts con Neon, lo que quieras
-- 3. En el ataque, agrega:
--      VFX_Name = "FirePunch"       → nombre del efecto en la carpeta VFX
--      VFX_Limb = "RightHand"       → parte del cuerpo donde se posiciona
--
-- PROPIEDADES DE VFX EN EL ATAQUE:
--   VFX_Name   (string)  → Nombre del objeto en Characters/<Name>/VFX/
--   VFX_Limb   (string)  → Parte del cuerpo donde se posiciona el VFX (default: "RightHand")
--   VFX_Limbs  (tabla)   → Para combos: {"RightHand", "LeftHand", "RightFoot"}
--                           El índice se toma del comboIndex (hit 1 = [1], hit 2 = [2], etc.)
--                           Si VFX_Limbs existe, tiene prioridad sobre VFX_Limb.
--
-- VALORES VÁLIDOS PARA VFX_Limb / VFX_Limbs:
--   "RightHand"  → Mano/brazo derecho
--   "LeftHand"   → Mano/brazo izquierdo
--   "RightFoot"  → Pie/pierna derecha
--   "LeftFoot"   → Pie/pierna izquierda
--   "Head"       → Cabeza
--   "Torso"      → Torso/pecho
--   "Root"       → HumanoidRootPart (centro del personaje)
--
-- EJEMPLO COMBO (Punch que alterna puños y termina en patada):
--   Attacks.Punch = {
--     VFX_Name  = "FirePunch",
--     VFX_Limbs = { "RightHand", "LeftHand", "RightFoot" },
--     ...
--   }
--   → Punch1 usa RightHand, Punch2 usa LeftHand, Punch3 usa RightFoot
--
-- ESTRUCTURA DE CARPETAS:
--   Characters/
--     Ken/
--       Ken.luau
--       Animations/
--       VFX/
--         FirePunch
--     Ryu/
--       Ryu.luau
--       VFX/
--         ...
-- =============================================

local CharactersFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Characters")

-- Cache para no buscar la carpeta VFX repetidamente
local vfxFolderCache = {}

-- Busca la carpeta VFX del personaje dado
local function getVFXFolder(characterName)
	if vfxFolderCache[characterName] ~= nil then
		return vfxFolderCache[characterName]
	end

	local charFolder = CharactersFolder:FindFirstChild(characterName)
	if charFolder then
		local vfxFolder = charFolder:FindFirstChild("VFX")
		vfxFolderCache[characterName] = vfxFolder or false
		return vfxFolder
	end

	vfxFolderCache[characterName] = false
	return nil
end

-- =============================================
-- LIMB FINDER: busca la parte del cuerpo correcta en el personaje
-- Soporta R6, R15 y rigs custom.
-- limbName: string (uno de los valores válidos listados arriba)
-- =============================================

-- Mapeo de nombre lógico → nombres de parte en R15 y R6
local LIMB_MAP = {
	RightHand = { "RightHand", "Right Arm" },
	LeftHand = { "LeftHand", "Left Arm" },
	RightFoot = { "RightFoot", "Right Leg" },
	LeftFoot = { "LeftFoot", "Left Leg" },
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso" },
	Root = { "HumanoidRootPart" },
}

-- Espejo de extremidades cuando el personaje mira a la izquierda (animación invertida)
local MIRROR_MAP = {
	RightHand = "LeftHand",
	LeftHand = "RightHand",
	RightFoot = "LeftFoot",
	LeftFoot = "RightFoot",
}

local function findLimb(character, limbName)
	if not limbName then
		limbName = "RightHand"
	end

	local candidates = LIMB_MAP[limbName]
	if candidates then
		for _, name in ipairs(candidates) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				return part
			end
		end
	end

	-- Fallback: buscar por nombre parcial en descendientes
	local lower = string.lower(limbName)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and string.find(string.lower(part.Name), lower) then
			return part
		end
	end

	-- Fallback final: HumanoidRootPart
	return character:FindFirstChild("HumanoidRootPart")
end

-- Prepara todas las partes de un VFX clonado: las hace no-colisionables y no-físicas
local function prepareVFXInstance(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
	end
	for _, child in pairs(instance:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
		end
	end
end

-- Reproduce el VFX de swing desde la carpeta VFX del personaje.
-- Se llama desde CombatController al INICIAR el ataque (no depende de hit).
-- vfxName:         string → nombre del efecto en Characters/<name>/VFX/
-- characterName:   string → nombre del personaje (ej: "Ken")
-- character:       Model  → modelo del atacante
-- attackData:      tabla  → datos del ataque (para duración)
-- comboIndex:      number → índice del combo actual (1, 2, 3...) para elegir limb de VFX_Limbs
-- facingDirection: string → "R" o "L", dirección a la que mira el personaje
function VFXService.PlaySwingVFX(vfxName, characterName, character, attackData, comboIndex, facingDirection)
	if not vfxName or not characterName or not character then
		return
	end

	local vfxFolder = getVFXFolder(characterName)
	if not vfxFolder then
		warn(
			"⚠️ VFX folder not found for character:",
			characterName,
			"— Crea Characters/" .. characterName .. "/VFX/ y coloca tus efectos ahí"
		)
		return
	end

	local vfxTemplate = vfxFolder:FindFirstChild(vfxName)
	if not vfxTemplate then
		warn("⚠️ VFX '" .. vfxName .. "' not found in Characters/" .. characterName .. "/VFX/")
		return
	end

	-- Determinar qué extremidad usar:
	-- 1. Si hay VFX_Limbs (tabla) y comboIndex, usar el índice
	-- 2. Si hay VFX_Limb (string), usarlo directamente
	-- 3. Default: "RightHand"
	local limbName = "RightHand"
	if attackData.VFX_Limbs and comboIndex then
		-- Ciclar si el comboIndex excede la tabla
		local idx = ((comboIndex - 1) % #attackData.VFX_Limbs) + 1
		limbName = attackData.VFX_Limbs[idx]
	elseif attackData.VFX_Limb then
		limbName = attackData.VFX_Limb
	end

	-- Espejear extremidad si el personaje mira a la izquierda
	if facingDirection == "L" and MIRROR_MAP[limbName] then
		limbName = MIRROR_MAP[limbName]
	end

	local limb = findLimb(character, limbName)
	if not limb then
		warn("⚠️ PlaySwingVFX: Limb not found:", limbName)
		return
	end

	-- Calcular duración del efecto
	local duration = (attackData.Startup or 0) + (attackData.Active or 0)
	if duration <= 0 then
		duration = 0.4
	end

	-- Clonar el VFX y prepararlo
	local vfxClone = vfxTemplate:Clone()
	vfxClone.Name = "SwingVFX_" .. vfxName
	prepareVFXInstance(vfxClone)
	vfxClone.Parent = workspace

	-- Posición inicial
	if vfxClone:IsA("Model") then
		if vfxClone.PrimaryPart then
			vfxClone:PivotTo(limb.CFrame)
		end
	elseif vfxClone:IsA("BasePart") then
		vfxClone.CFrame = limb.CFrame
	end

	-- Activar ParticleEmitters si existen
	local emitters = {}
	for _, desc in pairs(vfxClone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
			table.insert(emitters, desc)
		end
	end

	-- Loop: seguir la extremidad durante toda la duración del ataque
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt

		if elapsed >= duration or not limb or not limb.Parent then
			connection:Disconnect()

			-- Desactivar emitters
			for _, emitter in ipairs(emitters) do
				if emitter and emitter.Parent then
					emitter.Enabled = false
				end
			end

			-- Fade out
			local fadeInfoVFX = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for _, desc in pairs(vfxClone:GetDescendants()) do
				if desc:IsA("BasePart") then
					TweenService:Create(desc, fadeInfoVFX, { Transparency = 1 }):Play()
				end
			end
			if vfxClone:IsA("BasePart") then
				TweenService:Create(vfxClone, fadeInfoVFX, { Transparency = 1 }):Play()
			end

			task.delay(0.3, function()
				if vfxClone and vfxClone.Parent then
					vfxClone:Destroy()
				end
			end)
			return
		end

		-- Seguir la extremidad
		if vfxClone:IsA("Model") then
			if vfxClone.PrimaryPart and vfxClone.PrimaryPart.Parent then
				vfxClone:PivotTo(limb.CFrame)
			end
		elseif vfxClone:IsA("BasePart") and vfxClone.Parent then
			vfxClone.CFrame = limb.CFrame
		end
	end)
end

return VFXService
