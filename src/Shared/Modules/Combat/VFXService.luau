-- VFXService: Sistema de VFX pre-construidos (Model/Attachment)
-- Los VFX se crean en Roblox Studio y se almacenan en Characters/<Name>/VFX/<AttackId>/
-- En runtime: clone → posicionar → emitir partículas/trails → destruir
--
-- API:
--   VFXService.Play(characterName, attackId, vfxName, character, limbName, facingDir, duration)
--   VFXService.PlayAtPosition(characterName, attackId, vfxName, position, duration)
--   VFXService.EnableTrail(characterName, attackId, character, limbName, facingDir, enabled)
--   VFXService.HurtFlash(character, hitstopFrames)
--
-- TIPOS DE VFX EN UN ATAQUE:
--   Startup     → se reproduce al INICIAR el ataque, sigue la extremidad (Startup + Active frames)
--   Active      → se reproduce durante los ACTIVE FRAMES, sigue la extremidad (sin importar si conecta)
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
local function activateEmitters(vfxClone)
	local emitters = {}
	for _, desc in pairs(vfxClone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
			table.insert(emitters, desc)
		end
	end
	return emitters
end

-- Desactiva emitters, fade out y destruir
-- lingerTime: tiempo extra para que las partículas ya emitidas terminen su Lifetime
local function cleanupVFX(vfxClone, emitters, lingerTime)
	-- Calcular el mayor Lifetime de las partículas para dejarlas terminar
	if not lingerTime then
		lingerTime = 0
		if emitters then
			for _, emitter in ipairs(emitters) do
				if emitter and emitter.Parent then
					local maxLife = emitter.Lifetime.Max or 0
					if maxLife > lingerTime then
						lingerTime = maxLife
					end
				end
			end
		end
	end

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

		local fadeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, desc in pairs(vfxClone:GetDescendants()) do
			if desc:IsA("BasePart") then
				TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
			end
		end
		if vfxClone:IsA("BasePart") then
			TweenService:Create(vfxClone, fadeInfo, { Transparency = 1 }):Play()
		end

		task.delay(0.3, function()
			if vfxClone and vfxClone.Parent then
				vfxClone:Destroy()
			end
		end)
	end)
end

-- =============================================
-- Play: Clona VFX y lo adjunta a una extremidad del personaje.
-- Sigue la extremidad durante toda la duración.
-- characterName:   string → nombre del personaje (ej: "Ken")
-- attackId:        string → Id del ataque (ej: "HeavyPunch")
-- vfxName:         string → nombre del VFX dentro de la carpeta del ataque (ej: "Startup")
-- character:       Model  → modelo del personaje
-- limbName:        string → extremidad donde posicionar (default: "RightHand")
-- facingDirection: string → "R" o "L" (para espejear extremidad)
-- duration:        number → duración en segundos
-- =============================================
function VFXService.Play(characterName, attackId, vfxName, character, limbName, facingDirection, duration)
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

	local vfxClone = template:Clone()
	vfxClone.Name = "VFX_" .. attackId .. "_" .. vfxName
	prepareVFXInstance(vfxClone)
	vfxClone.Parent = workspace

	positionVFX(vfxClone, limb.CFrame)

	local emitters = activateEmitters(vfxClone)

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt

		if elapsed >= duration or not limb or not limb.Parent then
			connection:Disconnect()
			cleanupVFX(vfxClone, emitters)
			return
		end

		positionVFX(vfxClone, limb.CFrame)
	end)
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
-- El trail se parenta directamente al limb para seguirlo automáticamente.
-- =============================================

local activeTrails = {}

function VFXService.EnableTrail(characterName, attackId, character, limbName, facingDirection, enabled)
	if not character or not attackId then
		return
	end

	local key = tostring(character) .. "_" .. attackId

	if enabled then
		-- Limpiar trail anterior si existe
		local old = activeTrails[key]
		if old and old.Parent then
			old:Destroy()
		end

		local template = getVFXTemplate(characterName, attackId, "ActiveTrail")
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

		local vfxClone = template:Clone()
		vfxClone.Name = "VFX_Trail_" .. attackId
		prepareVFXInstance(vfxClone)

		-- Parentar al limb para que siga automáticamente
		vfxClone.Parent = limb

		-- Activar todos los Trail y ParticleEmitter
		for _, desc in pairs(vfxClone:GetDescendants()) do
			if desc:IsA("Trail") then
				desc.Enabled = true
			elseif desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			end
		end

		activeTrails[key] = vfxClone
	else
		local existing = activeTrails[key]
		if existing and existing.Parent then
			-- Desactivar trails/emitters antes de destruir para fade natural
			for _, desc in pairs(existing:GetDescendants()) do
				if desc:IsA("Trail") then
					desc.Enabled = false
				elseif desc:IsA("ParticleEmitter") then
					desc.Enabled = false
				end
			end

			task.delay(0.3, function()
				if existing and existing.Parent then
					existing:Destroy()
				end
			end)
		end
		activeTrails[key] = nil
	end
end

-- =============================================
-- HurtFlash: overlay de color sólido sobre todo el personaje (estilo KOF/SF)
-- Usa Highlight de Roblox para pintar el modelo completo.
-- Pulsa visible/invisible cada TOGGLE_INTERVAL frames durante hitstop.
-- =============================================
local HURTFLASH_COLOR = Color3.fromRGB(187, 187, 187)
local HURTFLASH_OUTLINE_COLOR = Color3.fromRGB(241, 241, 241)
local HURTFLASH_FILL_TRANSPARENCY = 0.15
local HURTFLASH_OUTLINE_TRANSPARENCY = 0.5
local HURTFLASH_ENABLE_BLINK = false
local HURTFLASH_BLINK_INTERVAL_FRAMES = 2

local function cleanupHurtFlash(character)
	local existing = character:FindFirstChild("HurtFlashHighlight")
	if existing then
		existing:Destroy()
	end
end

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

	if hitstopFrames <= 0 then
		local highlight = createHurtFlashHighlight(character)
		task.delay(0.08, function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end)
		return
	end

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

		if totalFrames >= hitstopFrames then
			connection:Disconnect()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end
	end)
end

return VFXService
