local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--[[
	CameraHandler - Cámara 2.5D lateral optimizada para multijugador (2-4+ jugadores)
	
	Features:
	- Soporta múltiples targets (jugadores, dummies, NPCs)
	- Calcula centro de masa de todos los jugadores vivos
	- Zoom dinámico según bounding box de todos los targets
	- Smooth transitions con lerp y deadzone anti-jitter
]]

local CameraHandler = {}

-- Configuración de cámara
local CAMERA = {
	-- Distancia base (Z offset)
	baseDistance = 14,
	-- Altura base sobre el centro
	baseHeight = 2,
	-- Offset del punto de mira (hacia arriba)
	lookAtOffset = 3,

	-- Zoom dinámico
	zoomEnabled = true,
	minZoom = 12, -- Zoom mínimo (cuando están cerca)
	maxZoom = 28, -- Zoom máximo (cuando están lejos)

	-- Separación para cálculo de zoom
	minSeparation = 5, -- Distancia mínima entre jugadores más lejanos
	maxSeparation = 40, -- Distancia máxima antes de zoom máximo

	-- Smoothing
	positionSmooth = 0.12, -- Lerp factor para posición (menor = más suave)
	zoomSmooth = 0.08, -- Lerp factor para zoom

	-- Anti-jitter: no mover cámara si el cambio es menor a este threshold
	positionDeadzone = 0.05,
	zoomDeadzone = 0.02,
}

-- Estado interno
local currentZoom = CAMERA.baseDistance
local currentCameraPosition = Vector3.zero
local currentLookTarget = Vector3.zero
local initialized = false

-- Lista de targets a seguir (characters con HumanoidRootPart)
local targets = {}

-- Control de modo de juego: la cámara 2D solo funciona en Training/Versus
local gameModeActive = false

-- Character local del jugador
local currentCharacter = nil
local humanoidRootPart = nil

--------------------------------------------------------------------------------
-- UTILIDADES
--------------------------------------------------------------------------------

-- Verifica si un target es válido (tiene HumanoidRootPart y está en workspace)
local function isValidTarget(target)
	if not target or not target.Parent then
		return false
	end
	local root = target:FindFirstChild("HumanoidRootPart")
	if not root or not root.Parent then
		return false
	end
	-- Verificar si el humanoid está vivo (opcional, para modo versus)
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	return true
end

-- Obtiene la posición del HumanoidRootPart de un target
local function getTargetPosition(target)
	local root = target:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position
	end
	return nil
end

--------------------------------------------------------------------------------
-- BIND CHARACTER LOCAL
--------------------------------------------------------------------------------

local function bindCharacter(character)
	currentCharacter = character
	if not currentCharacter then
		humanoidRootPart = nil
		return
	end

	-- Esperar a que el character esté en workspace
	local maxWait = 5
	local elapsed = 0
	while not currentCharacter.Parent and elapsed < maxWait do
		task.wait(0.1)
		elapsed = elapsed + 0.1
	end

	if not currentCharacter.Parent then
		humanoidRootPart = nil
		return
	end

	-- Buscar HumanoidRootPart con retry
	local attempts = 0
	humanoidRootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
	while not humanoidRootPart and attempts < 50 and currentCharacter.Parent do
		task.wait(0.1)
		attempts = attempts + 1
		humanoidRootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
	end

	if not humanoidRootPart then
		warn("⚠️ Camera bind skipped: missing HumanoidRootPart in", currentCharacter.Name)
	end
end

-- Conectar eventos de character
bindCharacter(player.Character or player.CharacterAdded:Wait())

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
end)

player:GetPropertyChangedSignal("Character"):Connect(function()
	local character = player.Character
	if character then
		task.defer(function()
			bindCharacter(character)
		end)
	end
end)

--------------------------------------------------------------------------------
-- GESTIÓN DE TARGETS (MULTIJUGADOR)
--------------------------------------------------------------------------------

-- Obtiene todos los targets activos (filtrados por validez)
local function getActiveTargets()
	local activeTargets = {}

	-- Siempre incluir el jugador local si es válido
	if currentCharacter and isValidTarget(currentCharacter) then
		table.insert(activeTargets, currentCharacter)
	end

	-- Incluir targets registrados manualmente
	for _, target in ipairs(targets) do
		if isValidTarget(target) and target ~= currentCharacter then
			table.insert(activeTargets, target)
		end
	end

	return activeTargets
end

-- Auto-descubre targets (otros jugadores y dummies)
local function discoverTargets()
	local discovered = {}

	-- Buscar dummies en workspace
	for _, name in ipairs({ "Enemy", "TrainingDummy", "Dummy" }) do
		local dummy = workspace:FindFirstChild(name)
		if dummy and isValidTarget(dummy) then
			table.insert(discovered, dummy)
		end
	end

	-- Buscar otros jugadores
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			if isValidTarget(otherPlayer.Character) then
				table.insert(discovered, otherPlayer.Character)
			end
		end
	end

	return discovered
end

--------------------------------------------------------------------------------
-- CÁLCULOS DE CÁMARA MULTIJUGADOR
--------------------------------------------------------------------------------

-- Calcula el centro de masa de todos los targets activos
local function getCenterOfMass(activeTargets)
	if #activeTargets == 0 then
		return nil
	end

	local sumX, sumY, sumZ = 0, 0, 0
	local count = 0

	for _, target in ipairs(activeTargets) do
		local pos = getTargetPosition(target)
		if pos then
			sumX = sumX + pos.X
			sumY = sumY + pos.Y
			sumZ = sumZ + pos.Z
			count = count + 1
		end
	end

	if count == 0 then
		return nil
	end

	return Vector3.new(sumX / count, sumY / count, sumZ / count)
end

-- Calcula el bounding box de todos los targets (para zoom dinámico)
local function getBoundingBox(activeTargets)
	if #activeTargets == 0 then
		return nil, nil
	end

	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge

	for _, target in ipairs(activeTargets) do
		local pos = getTargetPosition(target)
		if pos then
			minX = math.min(minX, pos.X)
			maxX = math.max(maxX, pos.X)
			minY = math.min(minY, pos.Y)
			maxY = math.max(maxY, pos.Y)
		end
	end

	if minX == math.huge then
		return nil, nil
	end

	return Vector3.new(minX, minY, 0), Vector3.new(maxX, maxY, 0)
end

-- Calcula zoom dinámico basado en el bounding box
local function calculateZoom(activeTargets)
	if not CAMERA.zoomEnabled then
		return CAMERA.baseDistance
	end

	if #activeTargets <= 1 then
		return CAMERA.minZoom
	end

	local minBound, maxBound = getBoundingBox(activeTargets)
	if not minBound or not maxBound then
		return CAMERA.minZoom
	end

	-- La distancia relevante es el span horizontal (X) principalmente
	-- pero también consideramos altura (Y) para saltos
	local spanX = maxBound.X - minBound.X
	local spanY = maxBound.Y - minBound.Y

	-- Usar el span mayor como referencia
	local maxSpan = math.max(spanX, spanY * 0.5) -- Y pesa menos

	-- Normalizar al rango de separación
	maxSpan = math.clamp(maxSpan, CAMERA.minSeparation, CAMERA.maxSeparation)
	local normalized = (maxSpan - CAMERA.minSeparation) / (CAMERA.maxSeparation - CAMERA.minSeparation)

	-- Interpolar entre minZoom y maxZoom
	return CAMERA.minZoom + (normalized * (CAMERA.maxZoom - CAMERA.minZoom))
end

--------------------------------------------------------------------------------
-- UPDATE LOOP
--------------------------------------------------------------------------------

local function updateCamera(dt)
	-- Solo actualizar si estamos en modo de juego
	if not gameModeActive then
		return
	end

	-- Obtener targets activos (incluye auto-discovery)
	local activeTargets = getActiveTargets()

	-- Si no hay targets registrados, intentar descubrir
	if #activeTargets <= 1 then
		local discovered = discoverTargets()
		for _, target in ipairs(discovered) do
			if isValidTarget(target) then
				table.insert(activeTargets, target)
			end
		end
	end

	-- Si aún no hay suficientes targets, seguir al jugador local
	if #activeTargets == 0 then
		if humanoidRootPart and humanoidRootPart.Parent then
			-- Fallback: seguir solo al jugador
			local pos = humanoidRootPart.Position
			local cameraPos = pos + Vector3.new(0, CAMERA.baseHeight, CAMERA.minZoom)
			local lookAt = pos + Vector3.new(0, CAMERA.lookAtOffset, 0)
			camera.CFrame = CFrame.lookAt(cameraPos, lookAt)
		end
		return
	end

	-- Calcular centro de masa
	local centerOfMass = getCenterOfMass(activeTargets)
	if not centerOfMass then
		return
	end

	-- Calcular zoom basado en bounding box
	local targetZoom = calculateZoom(activeTargets)

	-- Smooth zoom con deadzone
	local zoomDelta = targetZoom - currentZoom
	if math.abs(zoomDelta) > CAMERA.zoomDeadzone then
		currentZoom = currentZoom + (zoomDelta * CAMERA.zoomSmooth)
	end

	-- Calcular posición y lookAt target
	local targetLookAt = Vector3.new(centerOfMass.X, centerOfMass.Y + CAMERA.lookAtOffset, centerOfMass.Z)
	local cameraOffset = Vector3.new(0, CAMERA.baseHeight, currentZoom)
	local targetCameraPosition = centerOfMass + cameraOffset

	-- Inicializar posición si es primera vez
	if not initialized then
		currentCameraPosition = targetCameraPosition
		currentLookTarget = targetLookAt
		initialized = true
	end

	-- Smooth position con deadzone
	local posDelta = (targetCameraPosition - currentCameraPosition).Magnitude
	if posDelta > CAMERA.positionDeadzone then
		currentCameraPosition = currentCameraPosition:Lerp(targetCameraPosition, CAMERA.positionSmooth)
		currentLookTarget = currentLookTarget:Lerp(targetLookAt, CAMERA.positionSmooth)
	end

	-- Aplicar CFrame
	camera.CFrame = CFrame.lookAt(currentCameraPosition, currentLookTarget)
end

RunService.RenderStepped:Connect(updateCamera)

--------------------------------------------------------------------------------
-- API PÚBLICA
--------------------------------------------------------------------------------

-- Agrega un target a la lista (character con HumanoidRootPart)
function CameraHandler:AddTarget(character)
	if not character then
		return false
	end

	-- Evitar duplicados
	for _, existing in ipairs(targets) do
		if existing == character then
			return true
		end
	end

	table.insert(targets, character)
	return true
end

-- Remueve un target de la lista
function CameraHandler:RemoveTarget(character)
	for i, target in ipairs(targets) do
		if target == character then
			table.remove(targets, i)
			return true
		end
	end
	return false
end

-- Limpia todos los targets
function CameraHandler:ClearTargets()
	targets = {}
end

-- Retorna la lista de targets activos
function CameraHandler:GetTargets()
	return getActiveTargets()
end

-- Setea el oponente (legacy, ahora usa AddTarget internamente)
function CameraHandler:SetOpponent(opponentCharacter)
	if opponentCharacter and opponentCharacter:FindFirstChild("HumanoidRootPart") then
		-- Limpiar targets anteriores y agregar este
		self:ClearTargets()
		return self:AddTarget(opponentCharacter)
	end
	warn("📹 Invalid opponent character for camera")
	return false
end

-- Modifica distancia base de la cámara al eje Z
function CameraHandler:SetDistance(distance)
	CAMERA.baseDistance = distance
	currentZoom = distance
end

-- Modifica altura base de la cámara
function CameraHandler:SetHeight(height)
	CAMERA.baseHeight = height
end

-- Activa o desactiva el zoom dinámico
function CameraHandler:SetDynamicZoom(enabled)
	CAMERA.zoomEnabled = enabled
end

-- Configura límites de zoom
function CameraHandler:SetZoomLimits(minZoom, maxZoom)
	CAMERA.minZoom = minZoom or CAMERA.minZoom
	CAMERA.maxZoom = maxZoom or CAMERA.maxZoom
end

-- Configura smoothing
function CameraHandler:SetSmoothing(positionSmooth, zoomSmooth)
	CAMERA.positionSmooth = positionSmooth or CAMERA.positionSmooth
	CAMERA.zoomSmooth = zoomSmooth or CAMERA.zoomSmooth
end

-- Restaura la cámara al modo por defecto
function CameraHandler:Reset()
	CAMERA.baseDistance = 14
	CAMERA.baseHeight = 2
	CAMERA.lookAtOffset = 3
	CAMERA.zoomEnabled = true
	CAMERA.minZoom = 12
	CAMERA.maxZoom = 28
	CAMERA.positionSmooth = 0.12
	CAMERA.zoomSmooth = 0.08
	currentZoom = CAMERA.baseDistance
	targets = {}
	initialized = false
end

-- Activa/desactiva el modo de juego (cámara 2D)
function CameraHandler:SetGameModeActive(active)
	gameModeActive = active

	if active then
		camera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseDeltaSensitivity = 0
		initialized = false -- Resetear para smooth transition inicial
	else
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseDeltaSensitivity = 1
	end
end

-- Retorna si el modo de juego está activo
function CameraHandler:IsGameModeActive()
	return gameModeActive
end

-- Retorna la configuración actual de cámara (para debug)
function CameraHandler:GetConfig()
	return {
		currentZoom = currentZoom,
		targetCount = #getActiveTargets(),
		gameModeActive = gameModeActive,
		config = CAMERA,
	}
end

return CameraHandler
