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

return VFXService
