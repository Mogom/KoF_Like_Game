local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Cámara 2.5D lateral: zoom dinámico según distancia entre jugadores
local CameraHandler = {}

local CAMERA = {
	baseDistance = 12,
	baseHeight = 1.5,
	lookAtOffset = 3,

	zoomEnabled = true,
	minZoom = 12,
	maxZoom = 18,

	positionSmooth = 0.2,
	zoomSmooth = 0.15,
}

local currentZoom = CAMERA.baseDistance
local opponent = nil
local opponentRoot = nil
local currentCharacter = nil
local humanoidRootPart = nil

-- Control de modo de juego: la cámara 2D solo funciona en Training/Versus
local gameModeActive = false

-- NO forzar cámara scriptable al cargar - solo cuando estemos en modo de juego
-- UserInputService.MouseDeltaSensitivity = 0
-- camera.CameraType = Enum.CameraType.Scriptable

-- Vincula character local y su root para rastreo de cámara
local function bindCharacter(character)
	-- print("🔍 [Camera] Binding character:", character and character.Name or "nil")
	currentCharacter = character
	if currentCharacter then
		-- Wait for character to be fully parented
		local maxWait = 5
		local elapsed = 0
		while not currentCharacter.Parent and elapsed < maxWait do
			task.wait(0.1)
			elapsed = elapsed + 0.1
		end

		if not currentCharacter.Parent then
			print("🔍 [Camera] Character was destroyed before bind completed")
			humanoidRootPart = nil
			return
		end

		-- Retry loop for HumanoidRootPart
		local attempts = 0
		humanoidRootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
		while not humanoidRootPart and attempts < 50 and currentCharacter.Parent do
			task.wait(0.1)
			attempts = attempts + 1
			humanoidRootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
		end

		if not humanoidRootPart then
			warn(
				"⚠️ Camera bind skipped: missing HumanoidRootPart in",
				currentCharacter.Name,
				"after",
				attempts * 0.1,
				"seconds"
			)
			print(
				"🔍 [Camera] Character children:",
				table.concat(
					(function()
						local names = {}
						for _, child in ipairs(currentCharacter:GetChildren()) do
							table.insert(names, child.Name)
						end
						return names
					end)(),
					", "
				)
			)
		else
			print("🔍 [Camera] Successfully bound to", currentCharacter.Name)
		end
	else
		humanoidRootPart = nil
	end
end

bindCharacter(player.Character or player.CharacterAdded:Wait())

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
end)

-- Also detect manual Character assignment (skin swaps)
player:GetPropertyChangedSignal("Character"):Connect(function()
	local character = player.Character
	if character then
		task.defer(function()
			bindCharacter(character)
		end)
	end
end)

-- Busca el oponente (dummy o jugador) para calcular punto medio
local function findOpponent()
	if opponent and opponentRoot and opponentRoot.Parent then
		return opponent, opponentRoot
	end

	local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
	if dummy and dummy:FindFirstChild("HumanoidRootPart") then
		return dummy, dummy.HumanoidRootPart
	end

	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				return otherPlayer.Character, otherRoot
			end
		end
	end

	return nil, nil
end

-- Calcula el punto medio entre ambos jugadores en X
local function getCenterPoint()
	if not humanoidRootPart or not humanoidRootPart.Parent then
		return nil
	end

	local playerPos = humanoidRootPart.Position

	if opponentRoot and opponentRoot.Parent then
		local opponentPos = opponentRoot.Position
		return Vector3.new(
			(playerPos.X + opponentPos.X) / 2,
			(playerPos.Y + opponentPos.Y) / 2,
			(playerPos.Z + opponentPos.Z) / 2
		)
	end

	return playerPos
end

-- Calcula zoom dinámico basado en distancia entre jugadores
local function calculateZoom()
	if not CAMERA.zoomEnabled then
		return CAMERA.baseDistance
	end

	if not humanoidRootPart or not humanoidRootPart.Parent then
		return CAMERA.baseDistance
	end

	if not opponentRoot or not opponentRoot.Parent then
		return CAMERA.minZoom
	end

	local playerPos = humanoidRootPart.Position
	local opponentPos = opponentRoot.Position
	local distance = math.abs(playerPos.X - opponentPos.X)

	local minSeparation = 5
	local maxSeparation = 30

	distance = math.clamp(distance, minSeparation, maxSeparation)
	local normalized = (distance - minSeparation) / (maxSeparation - minSeparation)

	return CAMERA.minZoom + (normalized * (CAMERA.maxZoom - CAMERA.minZoom))
end

-- Actualiza posición y orientación de la cámara cada frame
local function updateCamera(dt)
	-- Solo actualizar cámara 2D si estamos en modo de juego
	if not gameModeActive then
		return
	end

	if not humanoidRootPart or not humanoidRootPart.Parent then
		return
	end

	if not opponent or not opponentRoot or not opponentRoot.Parent then
		opponent, opponentRoot = findOpponent()
	end

	local centerPoint = getCenterPoint()
	if not centerPoint then
		return
	end

	local targetZoom = calculateZoom()
	currentZoom = currentZoom + ((targetZoom - currentZoom) * CAMERA.zoomSmooth)

	local lookTarget = Vector3.new(centerPoint.X, centerPoint.Y + CAMERA.lookAtOffset, centerPoint.Z)

	local cameraOffset = Vector3.new(0, CAMERA.baseHeight, currentZoom)

	local cameraPosition = centerPoint + cameraOffset
	local newCFrame = CFrame.lookAt(cameraPosition, lookTarget)

	camera.CFrame = camera.CFrame:Lerp(newCFrame, CAMERA.positionSmooth)
end

RunService.RenderStepped:Connect(updateCamera)

task.spawn(function()
	while task.wait(1) do
		if not opponent or not opponentRoot or not opponentRoot.Parent then
			opponent, opponentRoot = findOpponent()
		end
	end
end)

-- Setea el oponente para cálculo de cámara
function CameraHandler:SetOpponent(opponentCharacter)
	if opponentCharacter and opponentCharacter:FindFirstChild("HumanoidRootPart") then
		opponent = opponentCharacter
		opponentRoot = opponentCharacter.HumanoidRootPart
		return true
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

-- Restaura la cámara al modo por defecto de Roblox
function CameraHandler:Reset()
	CAMERA.baseDistance = 12
	CAMERA.baseHeight = 1.5
	CAMERA.lookAtOffset = 3
	CAMERA.zoomEnabled = true
	currentZoom = CAMERA.baseDistance
end

-- Activa/desactiva el modo de juego (cámara 2D)
function CameraHandler:SetGameModeActive(active)
	gameModeActive = active
	-- print("📹 [Camera] GameMode active:", active)

	if active then
		-- Activar cámara 2D
		camera.CameraType = Enum.CameraType.Scriptable
		UserInputService.MouseDeltaSensitivity = 0
	else
		-- Restaurar cámara normal de Roblox
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseDeltaSensitivity = 1
	end
end

-- Retorna si el modo de juego está activo
function CameraHandler:IsGameModeActive()
	return gameModeActive
end

return CameraHandler
