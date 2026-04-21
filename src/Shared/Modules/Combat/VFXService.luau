-- VFXService: Sistema de VFX pre-construidos (Model/Attachment)
-- Los VFX se crean en Roblox Studio y se almacenan en Characters/<Name>/VFX/<AttackId>/
-- En runtime: los efectos (ParticleEmitter/Trail/Beam/Light) se clonan directo al
-- Attachment del limb declarado en VFX_Limb, sin replicar partes ni rastrear CFrame.
--
-- API:
--   VFXService.Play(characterName, attackId, vfxName, character, limbName, facingDir, duration, forceBurst)
--   VFXService.PlayAtPosition(characterName, attackId, vfxName, position, duration)
--   VFXService.EnableTrail(characterName, attackId, character, limbName, facingDir, enabled)
--   VFXService.HurtFlash(character, hitstopFrames)
--   VFXService.AttackLimbFlash(character, limbName, facingDir, flashConfig, hitstopFrames)
--
-- TIPOS DE VFX EN UN ATAQUE:
--   Startup     → burst al INICIAR el ataque, en el Attachment del limb
--   Active      → burst durante los ACTIVE FRAMES, en el Attachment del limb (sin importar si conecta)
--   OnHit       → se reproduce SOLO al CONECTAR el golpe, en la posición de impacto
--   ActiveTrail → trail activo durante los Active frames (se parentea al limb)
--
-- ESTRUCTURA DE CARPETAS:
--   Characters/
--     Ken/
--       VFX/
--         Punch/           ← carpeta por ataque (coincide con attack.Id)
--           Startup        ← Model/Part con ParticleEmitters (sigue extremidad)
--           OnHit          ← Model/Part con ParticleEmitters (posición de impacto)
--           ActiveTrail    ← Model/Part con Trail (se activa durante Active frames)
--         HeavyPunch/
--           Startup
--           OnHit
--
-- FORMATO EN EL ATAQUE:
--   VFX = {
--     Startup     = "Startup",      -- se reproduce al INICIAR el ataque, sigue VFX_Limb
--     Active      = "Active",       -- se reproduce durante Active frames (sin importar si conecta)
--     OnHit       = "OnHit",        -- se reproduce al CONECTAR el golpe, en posición de impacto
--     ActiveTrail = "ActiveTrail",  -- trail activo durante Active frames
--   },
--   VFX_Limb  = "RightHand",                            -- extremidad donde se posiciona
--   VFX_Limbs = { "RightHand", "LeftHand", "RightFoot" }, -- para combos (por índice)
--
-- VALORES VÁLIDOS PARA VFX_Limb / VFX_Limbs:
--   "RightHand" | "LeftHand" | "RightFoot" | "LeftFoot" | "Head" | "Torso" | "Root"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VFXService = {}

local CharactersFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Characters")
local effectStateCache = setmetatable({}, { __mode = "k" })

-- =============================================
-- CONFIGURACIÓN DE TIMINGS (AJUSTABLES)
-- =============================================
-- Cambia estos valores para ajustar qué tan rápido desaparecen los VFX
local BURST_THRESHOLD = 0.2 -- Duración mínima para usar modo continuo (vs burst)
local FADE_OUT_DURATION = 0.12 -- Tiempo del fade out al terminar Active/Trail
local CLEANUP_DELAY = 0.04 -- Espera antes de destruir clone después del fade
local MAX_LINGER_TIME = 0.1 -- Máximo tiempo para que las partículas vivan después de desactivarlas | AUMENTA si quieres que se vean más, REDUCE para limpiarlas rápido

-- =============================================
-- CACHE Y BÚSQUEDA DE TEMPLATES
-- =============================================

local vfxFolderCache = {}

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

-- Busca el template: Characters/<characterName>/VFX/<attackId>/<vfxName>
local function getVFXTemplate(characterName, attackId, vfxName)
	local vfxFolder = getVFXFolder(characterName)
	if not vfxFolder then
		return nil
	end

	local attackFolder = vfxFolder:FindFirstChild(attackId)
	if not attackFolder then
		return nil
	end

	return attackFolder:FindFirstChild(vfxName)
end

-- =============================================
-- LIMB FINDER
-- =============================================

local LIMB_MAP = {
	RightHand = { "RightHand", "Right Arm" },
	LeftHand = { "LeftHand", "Left Arm" },
	RightFoot = { "RightFoot", "Right Leg" },
	LeftFoot = { "LeftFoot", "Left Leg" },
	Head = { "Head" },
	Torso = { "UpperTorso", "Torso" },
	Root = { "HumanoidRootPart" },
}

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

	local lower = string.lower(limbName)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") and string.find(string.lower(part.Name), lower) then
			return part
		end
	end

	return character:FindFirstChild("HumanoidRootPart")
end

-- =============================================
-- UTILIDADES INTERNAS
-- =============================================

-- Prepara todas las partes de un VFX clonado: no-colisionables, no-físicas
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

-- Posiciona un VFX clonado en un CFrame
local function positionVFX(vfxClone, cframe)
	if vfxClone:IsA("Model") then
		if vfxClone.PrimaryPart then
			vfxClone:PivotTo(cframe)
		end
	elseif vfxClone:IsA("BasePart") then
		vfxClone.CFrame = cframe
	end
end

-- Activa todos los ParticleEmitters y retorna la lista
local function _activateEmitters(vfxClone)
	local emitters = {}
	for _, desc in pairs(vfxClone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
			table.insert(emitters, desc)
		end
	end
	return emitters
end

local function cloneNumberSequence(sequence)
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value, keypoint.Envelope))
	end
	return NumberSequence.new(keypoints)
end

local function fadeNumberSequenceToInvisible(sequence, alpha)
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		local value = keypoint.Value + ((1 - keypoint.Value) * alpha)
		local envelope = keypoint.Envelope * (1 - alpha)
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, value, envelope))
	end
	return NumberSequence.new(keypoints)
end

local function captureEffectState(effect)
	local cached = effectStateCache[effect]
	if cached then
		return cached
	end

	local state = {
		Enabled = effect.Enabled,
	}

	if effect:IsA("ParticleEmitter") then
		state.Transparency = cloneNumberSequence(effect.Transparency)
		state.Rate = effect.Rate
	elseif effect:IsA("Trail") then
		state.Transparency = cloneNumberSequence(effect.Transparency)
		state.Lifetime = effect.Lifetime
	elseif effect:IsA("Beam") then
		state.Transparency = cloneNumberSequence(effect.Transparency)
		state.Brightness = effect.Brightness
	elseif effect:IsA("PointLight") or effect:IsA("SpotLight") or effect:IsA("SurfaceLight") then
		state.Brightness = effect.Brightness
		state.Range = effect.Range
	end

	effectStateCache[effect] = state
	return state
end

local function restoreEffectState(effect)
	local state = effectStateCache[effect]
	if not state or not effect or not effect.Parent then
		return
	end

	if effect:IsA("ParticleEmitter") then
		effect.Transparency = state.Transparency
		effect.Rate = state.Rate
	elseif effect:IsA("Trail") then
		effect.Transparency = state.Transparency
		effect.Lifetime = state.Lifetime
	elseif effect:IsA("Beam") then
		effect.Transparency = state.Transparency
		effect.Brightness = state.Brightness
	elseif effect:IsA("PointLight") or effect:IsA("SpotLight") or effect:IsA("SurfaceLight") then
		effect.Brightness = state.Brightness
		effect.Range = state.Range
	end

	effect.Enabled = state.Enabled
end

local function fadeOutEffects(nodes, duration, destroyTarget)
	if not nodes or #nodes == 0 then
		if destroyTarget and destroyTarget.Parent then
			destroyTarget:Destroy()
		end
		return
	end

	for _, node in ipairs(nodes) do
		if node and node.Parent then
			captureEffectState(node)
			if node:IsA("ParticleEmitter") or node:IsA("Trail") or node:IsA("Beam") then
				node.Enabled = false
			end
		end
	end

	task.spawn(function()
		local startTime = os.clock()
		while true do
			local elapsed = os.clock() - startTime
			local alpha = math.clamp(elapsed / duration, 0, 1)

			for _, node in ipairs(nodes) do
				if node and node.Parent then
					local state = captureEffectState(node)
					if node:IsA("ParticleEmitter") then
						node.Transparency = fadeNumberSequenceToInvisible(state.Transparency, alpha)
						node.Rate = state.Rate * (1 - alpha)
					elseif node:IsA("Trail") then
						node.Transparency = fadeNumberSequenceToInvisible(state.Transparency, alpha)
					elseif node:IsA("Beam") then
						node.Transparency = fadeNumberSequenceToInvisible(state.Transparency, alpha)
						node.Brightness = state.Brightness * (1 - alpha)
					elseif node:IsA("PointLight") or node:IsA("SpotLight") or node:IsA("SurfaceLight") then
						node.Brightness = state.Brightness * (1 - alpha)
						node.Range = state.Range * (1 - alpha)
					end
				end
			end

			if alpha >= 1 then
				break
			end

			task.wait()
		end

		if destroyTarget and destroyTarget.Parent then
			task.delay(CLEANUP_DELAY, function()
				if destroyTarget and destroyTarget.Parent then
					destroyTarget:Destroy()
				end
			end)
		else
			for _, node in ipairs(nodes) do
				if node and node.Parent then
					restoreEffectState(node)
					if node:IsA("ParticleEmitter") or node:IsA("Trail") or node:IsA("Beam") then
						node.Enabled = false
					end
				end
			end
		end
	end)
end

-- Desactiva emitters, fade out y destruir
-- lingerTime: tiempo extra para que las partículas ya emitidas terminen su Lifetime (respeta MAX_LINGER_TIME)
local function _cleanupVFX(vfxClone, emitters, lingerTime)
	-- Calcular el mayor Lifetime de las partículas para dejarlas terminar (con máximo cap)
	if not lingerTime then
		lingerTime = 0
		if emitters then
			for _, emitter in ipairs(emitters) do
				if emitter and emitter.Parent then
					-- Permitir override por atributo si existe
					local maxLife = emitter:GetAttribute("MaxLingerTime")
						or math.min(emitter.Lifetime.Max or 0, MAX_LINGER_TIME)
					if maxLife > lingerTime then
						lingerTime = maxLife
					end
				end
			end
		end
	end
	-- Respetar el máximo global
	lingerTime = math.min(lingerTime, MAX_LINGER_TIME)

	-- Desactivar emisión (no emitir nuevas partículas)
	if emitters then
		for _, emitter in ipairs(emitters) do
			if emitter and emitter.Parent then
				emitter.Enabled = false
			end
		end
	end

	-- Esperar a que las partículas existentes terminen, luego fade out y destruir
	task.delay(lingerTime, function()
		if not vfxClone or not vfxClone.Parent then
			return
		end

		local nodes = {}
		for _, desc in pairs(vfxClone:GetDescendants()) do
			if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
				table.insert(nodes, desc)
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				table.insert(nodes, desc)
			elseif desc:IsA("BasePart") then
				TweenService:Create(
					desc,
					TweenInfo.new(FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Transparency = 1 }
				):Play()
			end
		end
		if vfxClone:IsA("BasePart") then
			TweenService:Create(
				vfxClone,
				TweenInfo.new(FADE_OUT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		end

		fadeOutEffects(nodes, FADE_OUT_DURATION, vfxClone)
	end)
end

-- =============================================
-- Play: Clona los efectos del VFX directamente en el Attachment del limb.
-- En lugar de clonar una parte entera y seguirla por CFrame cada frame,
-- usamos el Attachment que ya existe dentro de la parte declarada en VFX_Limb.
-- Esto es más preciso y visualmente claro.
-- Si forceBurst es true o la duración < BURST_THRESHOLD, emite un burst instantáneo.
-- =============================================
function VFXService.Play(characterName, attackId, vfxName, character, limbName, facingDirection, duration, forceBurst)
	if not characterName or not attackId or not vfxName or not character then
		return
	end

	local template = getVFXTemplate(characterName, attackId, vfxName)
	if not template then
		return
	end

	limbName = limbName or "RightHand"
	if facingDirection == "L" and MIRROR_MAP[limbName] then
		limbName = MIRROR_MAP[limbName]
	end

	local limb = findLimb(character, limbName)
	if not limb then
		return
	end

	duration = duration or 0.4

	-- Usar el Attachment que ya existe dentro del limb para posicionamiento preciso
	local attachment = limb:FindFirstChildWhichIsA("Attachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "VFXAttachment"
		attachment.Parent = limb
	end

	-- Clonar los efectos visuales del template directo al Attachment del limb
	local clonedEffects = {}
	for _, desc in pairs(template:GetDescendants()) do
		if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") or desc:IsA("Light") then
			local clone = desc:Clone()
			clone.Parent = attachment
			table.insert(clonedEffects, clone)
		end
	end

	if #clonedEffects == 0 then
		return
	end

	local useBurst = forceBurst or (duration < BURST_THRESHOLD)

	if useBurst then
		-- BURST MODE: Emit partículas de golpe, se destruyen tras linger time
		local maxLifetime = 0
		for _, effect in ipairs(clonedEffects) do
			if effect:IsA("ParticleEmitter") then
				local burstCount = effect:GetAttribute("BurstCount") or math.max(math.ceil(effect.Rate * 0.3), 8)
				effect:Emit(burstCount)
				local life = effect:GetAttribute("MaxLingerTime")
					or math.min(effect.Lifetime.Max or 0.5, MAX_LINGER_TIME)
				if life > maxLifetime then
					maxLifetime = life
				end
			end
		end

		local lingerDuration = math.min(maxLifetime, MAX_LINGER_TIME)
		task.delay(lingerDuration + CLEANUP_DELAY, function()
			for _, effect in ipairs(clonedEffects) do
				if effect and effect.Parent then
					effect:Destroy()
				end
			end
		end)
	else
		-- CONTINUOUS MODE: Emitir partículas durante toda la duración
		for _, effect in ipairs(clonedEffects) do
			if effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam") then
				effect.Enabled = true
			elseif effect:IsA("PointLight") or effect:IsA("SpotLight") or effect:IsA("SurfaceLight") then
				captureEffectState(effect)
			end
		end

		task.delay(duration, function()
			local lingerTime = 0
			for _, effect in ipairs(clonedEffects) do
				if effect and effect.Parent then
					if effect:IsA("ParticleEmitter") then
						effect.Enabled = false
						local maxLife = effect:GetAttribute("MaxLingerTime")
							or math.min(effect.Lifetime.Max or 0, MAX_LINGER_TIME)
						if maxLife > lingerTime then
							lingerTime = maxLife
						end
					end
				end
			end
			lingerTime = math.min(lingerTime, MAX_LINGER_TIME)

			task.delay(lingerTime, function()
				fadeOutEffects(clonedEffects, FADE_OUT_DURATION, nil)
				task.delay(FADE_OUT_DURATION + CLEANUP_DELAY, function()
					for _, effect in ipairs(clonedEffects) do
						if effect and effect.Parent then
							effect:Destroy()
						end
					end
				end)
			end)
		end)
	end
end

-- =============================================
-- PlayAtPosition: Clona VFX y lo coloca en una posición fija (para OnHit).
-- Hace burst de partículas y se destruye tras la duración.
-- characterName: string → nombre del personaje
-- attackId:      string → Id del ataque
-- vfxName:       string → nombre del VFX (ej: "OnHit")
-- position:      Vector3 → posición de impacto
-- duration:      number → duración en segundos
-- =============================================
function VFXService.PlayAtPosition(characterName, attackId, vfxName, position, duration)
	if not characterName or not attackId or not vfxName or not position then
		return
	end

	local template = getVFXTemplate(characterName, attackId, vfxName)
	if not template then
		return
	end

	duration = duration or 0.5

	local vfxClone = template:Clone()
	vfxClone.Name = "VFX_" .. attackId .. "_" .. vfxName
	prepareVFXInstance(vfxClone)
	vfxClone.Parent = workspace

	positionVFX(vfxClone, CFrame.new(position))

	-- Burst: emitir partículas una vez (no continuo)
	for _, desc in pairs(vfxClone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			local burstCount = desc:GetAttribute("BurstCount") or math.max(desc.Rate, 5)
			desc:Emit(burstCount)
		end
	end

	task.delay(duration, function()
		if vfxClone and vfxClone.Parent then
			vfxClone:Destroy()
		end
	end)
end

-- =============================================
-- EnableTrail: Activa/desactiva un VFX de trail en una extremidad.
-- Modo híbrido:
-- 1) Si el limb ya tiene trails preinstalados (atributo CombatActiveTrail=true),
--    solo se activan/desactivan (no se clonan ni destruyen).
-- 2) Si no existen, usa fallback clonado desde template ActiveTrail.
-- =============================================

local activeTrails = {}

local function setTrailNodesEnabled(nodes, enabled)
	for _, node in ipairs(nodes) do
		if node and node.Parent then
			if enabled then
				restoreEffectState(node)
			end
			if node:IsA("Trail") then
				node.Enabled = enabled
			elseif node:IsA("ParticleEmitter") then
				node.Enabled = enabled
			elseif node:IsA("Beam") then
				node.Enabled = enabled
			end
		end
	end
end

local function cleanupTrailHandle(handle)
	if not handle then
		return
	end

	if handle.Mode == "PreAttached" then
		fadeOutEffects(handle.Nodes or {}, FADE_OUT_DURATION, nil)
		return
	end

	local instance = handle.Instance
	if instance and instance.Parent then
		local nodes = {}
		for _, desc in pairs(instance:GetDescendants()) do
			if desc:IsA("Trail") or desc:IsA("ParticleEmitter") or desc:IsA("Beam") then
				table.insert(nodes, desc)
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				table.insert(nodes, desc)
			end
		end
		fadeOutEffects(nodes, FADE_OUT_DURATION, instance)
	end
end

local function collectPreAttachedTrailNodes(limb, attackId)
	local nodes = {}
	for _, desc in pairs(limb:GetDescendants()) do
		if desc:IsA("Trail") or desc:IsA("ParticleEmitter") then
			local tagged = desc:GetAttribute("CombatActiveTrail") == true
			if tagged then
				local onlyAttackId = desc:GetAttribute("AttackId")
				if onlyAttackId == nil or onlyAttackId == attackId then
					table.insert(nodes, desc)
				end
			end
		end
	end
	return nodes
end

function VFXService.EnableTrail(characterName, attackId, character, limbName, facingDirection, enabled)
	if not character or not attackId then
		return
	end

	local key = tostring(character) .. "_" .. attackId

	limbName = limbName or "RightHand"
	if facingDirection == "L" and MIRROR_MAP[limbName] then
		limbName = MIRROR_MAP[limbName]
	end

	local limb = findLimb(character, limbName)
	if not limb then
		return
	end

	if enabled then
		-- Limpiar trail anterior si existe
		cleanupTrailHandle(activeTrails[key])

		local preAttachedNodes = collectPreAttachedTrailNodes(limb, attackId)
		if #preAttachedNodes > 0 then
			setTrailNodesEnabled(preAttachedNodes, true)
			activeTrails[key] = {
				Mode = "PreAttached",
				Nodes = preAttachedNodes,
			}
			return
		end

		local template = getVFXTemplate(characterName, attackId, "ActiveTrail")
		if not template then
			return
		end

		local vfxClone = template:Clone()
		vfxClone.Name = "VFX_Trail_" .. attackId
		prepareVFXInstance(vfxClone)

		-- Parentar al limb para que siga automáticamente
		vfxClone.Parent = limb

		local clonedNodes = {}
		for _, desc in pairs(vfxClone:GetDescendants()) do
			if desc:IsA("Trail") or desc:IsA("ParticleEmitter") or desc:IsA("Beam") then
				table.insert(clonedNodes, desc)
			elseif desc:IsA("PointLight") or desc:IsA("SpotLight") or desc:IsA("SurfaceLight") then
				table.insert(clonedNodes, desc)
			end
		end
		setTrailNodesEnabled(clonedNodes, true)

		activeTrails[key] = {
			Mode = "Cloned",
			Instance = vfxClone,
		}
	else
		cleanupTrailHandle(activeTrails[key])
		activeTrails[key] = nil
	end
end

-- =============================================
-- HurtFlash: overlay de color sólido sobre todo el personaje (estilo KOF/SF)
-- Usa Highlight de Roblox para pintar el modelo completo.
-- CharacterFlash / HurtFlash: overlay de color sólido sobre todo el personaje.
-- Usa Highlight de Roblox para pintar el modelo completo.
-- CharacterFlash es reutilizable para dodge, hit, parry, etc.
-- HurtFlash mantiene la API anterior y usa CharacterFlash internamente.
-- Pulsa visible/invisible cada TOGGLE_INTERVAL frames durante hitstop.
-- =============================================
local HURTFLASH_COLOR = Color3.fromRGB(187, 187, 187)
local HURTFLASH_OUTLINE_COLOR = Color3.fromRGB(241, 241, 241)
local HURTFLASH_FILL_TRANSPARENCY = 0.15
local HURTFLASH_OUTLINE_TRANSPARENCY = 0.5
local HURTFLASH_ENABLE_BLINK = false
local HURTFLASH_BLINK_INTERVAL_FRAMES = 2

local ATTACKFLASH_DEFAULT_COLOR = Color3.fromRGB(255, 60, 60)
local ATTACKFLASH_DEFAULT_FILL_TRANSPARENCY = 0.2
local ATTACKFLASH_DEFAULT_OUTLINE_TRANSPARENCY = 0.65
local ATTACKFLASH_DEFAULT_DURATION = 0.08
local CHARACTERFLASH_DEFAULT_DURATION = 0.08
local CHARACTERFLASH_DEFAULT_DEPTH_MODE = Enum.HighlightDepthMode.Occluded

local NAMED_COLORS = {
	red = Color3.fromRGB(255, 60, 60),
	white = Color3.fromRGB(255, 255, 255),
	blue = Color3.fromRGB(70, 140, 255),
	green = Color3.fromRGB(80, 255, 120),
	yellow = Color3.fromRGB(255, 230, 80),
	orange = Color3.fromRGB(255, 150, 60),
	purple = Color3.fromRGB(180, 90, 255),
	cyan = Color3.fromRGB(90, 255, 255),
	pink = Color3.fromRGB(255, 110, 200),
}

local function parseFlashColor(value)
	if typeof(value) == "Color3" then
		return value
	end

	if typeof(value) == "string" then
		local named = NAMED_COLORS[string.lower(value)]
		if named then
			return named
		end

		if string.sub(value, 1, 1) == "#" and #value == 7 then
			local hex = string.sub(value, 2)
			local r = tonumber(string.sub(hex, 1, 2), 16)
			local g = tonumber(string.sub(hex, 3, 4), 16)
			local b = tonumber(string.sub(hex, 5, 6), 16)
			if r and g and b then
				return Color3.fromRGB(r, g, b)
			end
		end
	end

	if typeof(value) == "table" then
		local r = value.R or value.r
		local g = value.G or value.g
		local b = value.B or value.b
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			return Color3.fromRGB(r, g, b)
		end
	end

	return ATTACKFLASH_DEFAULT_COLOR
end
local function cleanupCharacterFlash(character, highlightName)
	highlightName = highlightName or "CharacterFlashHighlight"
	local existing = character:FindFirstChild(highlightName)
	if existing then
		existing:Destroy()
	end
end

local function createCharacterFlashHighlight(character, flashConfig)
	flashConfig = flashConfig or {}
	local highlightName = flashConfig.Name or "CharacterFlashHighlight"
	cleanupCharacterFlash(character, highlightName)

	local fillColor = parseFlashColor(flashConfig.FillColor or flashConfig.Color or HURTFLASH_COLOR)
	local outlineColor = parseFlashColor(flashConfig.OutlineColor or flashConfig.Color or HURTFLASH_OUTLINE_COLOR)
	local fillTransparency = flashConfig.FillTransparency
	if typeof(fillTransparency) ~= "number" then
		fillTransparency = HURTFLASH_FILL_TRANSPARENCY
	end
	local outlineTransparency = flashConfig.OutlineTransparency
	if typeof(outlineTransparency) ~= "number" then
		outlineTransparency = HURTFLASH_OUTLINE_TRANSPARENCY
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = highlightName
	highlight.FillColor = fillColor
	highlight.FillTransparency = math.clamp(fillTransparency, 0, 1)
	highlight.OutlineColor = outlineColor
	highlight.OutlineTransparency = math.clamp(outlineTransparency, 0, 1)
	highlight.DepthMode = flashConfig.DepthMode or CHARACTERFLASH_DEFAULT_DEPTH_MODE
	highlight.Adornee = character
	highlight.Parent = character

	return highlight
end

function VFXService.CharacterFlash(character, flashConfig)
	if not character then
		return
	end

	flashConfig = flashConfig or {}
	local hitstopFrames = flashConfig.HitstopFrames or 0
	local duration = flashConfig.Duration
	if typeof(duration) ~= "number" or duration <= 0 then
		duration = CHARACTERFLASH_DEFAULT_DURATION
	end
	local blink = flashConfig.Blink
	if typeof(blink) ~= "boolean" then
		blink = HURTFLASH_ENABLE_BLINK
	end
	local blinkIntervalFrames = flashConfig.BlinkIntervalFrames
	if typeof(blinkIntervalFrames) ~= "number" or blinkIntervalFrames <= 0 then
		blinkIntervalFrames = HURTFLASH_BLINK_INTERVAL_FRAMES
	end

	local highlight = createCharacterFlashHighlight(character, flashConfig)

	if hitstopFrames <= 0 then
		task.delay(duration, function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end)
		return highlight
	end

	local frameCounter = 0
	local totalFrames = 0
	local isVisible = true
	local fillTransparency = highlight.FillTransparency
	local outlineTransparency = highlight.OutlineTransparency

	local connection
	connection = RunService.RenderStepped:Connect(function()
		totalFrames += 1

		if blink then
			frameCounter += 1
			if frameCounter >= blinkIntervalFrames then
				frameCounter = 0
				isVisible = not isVisible
				if highlight and highlight.Parent then
					highlight.FillTransparency = isVisible and fillTransparency or 1
					highlight.OutlineTransparency = isVisible and outlineTransparency or 1
				end
			end
		end

		if totalFrames >= hitstopFrames then
			connection:Disconnect()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end
	end)

	return highlight
end

function VFXService.HurtFlash(character, hitstopFrames)
	if not character then
		return
	end

	VFXService.CharacterFlash(character, {
		Name = "HurtFlashHighlight",
		FillColor = HURTFLASH_COLOR,
		OutlineColor = HURTFLASH_OUTLINE_COLOR,
		FillTransparency = HURTFLASH_FILL_TRANSPARENCY,
		OutlineTransparency = HURTFLASH_OUTLINE_TRANSPARENCY,
		Duration = 0.08,
		HitstopFrames = hitstopFrames or 0,
		Blink = HURTFLASH_ENABLE_BLINK,
		BlinkIntervalFrames = HURTFLASH_BLINK_INTERVAL_FRAMES,
	})
end

function VFXService.AttackLimbFlash(character, limbName, facingDirection, flashConfig, hitstopFrames)
	if not character or not flashConfig or not flashConfig.Enabled then
		return
	end

	-- Este flash usa una ventana de tiempo explícita (Duration),
	-- para poder limitarlo exactamente a Startup + Active frames.
	hitstopFrames = hitstopFrames -- compatibilidad de firma

	limbName = limbName or "RightHand"
	if facingDirection == "L" and MIRROR_MAP[limbName] then
		limbName = MIRROR_MAP[limbName]
	end

	local limb = findLimb(character, limbName)
	if not limb then
		return
	end

	local color = parseFlashColor(flashConfig.Color)
	local fillTransparency = flashConfig.FillTransparency
	if typeof(fillTransparency) ~= "number" then
		fillTransparency = ATTACKFLASH_DEFAULT_FILL_TRANSPARENCY
	end

	local outlineTransparency = flashConfig.OutlineTransparency
	if typeof(outlineTransparency) ~= "number" then
		outlineTransparency = ATTACKFLASH_DEFAULT_OUTLINE_TRANSPARENCY
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "AttackLimbFlashHighlight"
	highlight.FillColor = color
	highlight.FillTransparency = math.clamp(fillTransparency, 0, 1)
	highlight.OutlineColor = color
	highlight.OutlineTransparency = math.clamp(outlineTransparency, 0, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = limb
	highlight.Parent = character

	local duration = flashConfig.Duration
	if typeof(duration) ~= "number" or duration <= 0 then
		duration = ATTACKFLASH_DEFAULT_DURATION
	end

	task.delay(duration, function()
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
	end)
end

return VFXService
