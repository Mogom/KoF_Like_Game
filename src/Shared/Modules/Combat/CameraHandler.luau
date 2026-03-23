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

UserInputService.MouseDeltaSensitivity = 0
camera.CameraType = Enum.CameraType.Scriptable

-- Vincula character local y su root para rastreo de cámara
local function bindCharacter(character)
	currentCharacter = character
	if currentCharacter then
		humanoidRootPart = currentCharacter:WaitForChild("HumanoidRootPart")
	else
		humanoidRootPart = nil
	end
end

bindCharacter(player.Character or player.CharacterAdded:Wait())

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
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

return CameraHandler
