-- GameInputController: Sistema de input que se re-inicializa con cada Character
-- Vive en PlayerScripts para sobrevivir cambios de personaje/skin
-- Solo permite inputs cuando el jugador está en un modo de juego activo (Training/Versus)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local InputBuffer = require(Combat:WaitForChild("InputBuffer"))
local StateMachine = require(Combat:WaitForChild("StateMachine"))
local CharacterControllers = Modules:WaitForChild("CharacterControllers")
local CharacterController = require(CharacterControllers:WaitForChild("CharacterController"))
local CommandParser = require(Combat:WaitForChild("CommandParser"))
local CameraHandler = require(Combat:WaitForChild("CameraHandler"))

local player = Players.LocalPlayer

-- ============================================
-- 📦 ESTADO GLOBAL DEL INPUT SYSTEM
-- ============================================

local controller = nil
local buffer = nil
local machine = nil
local characterCommands = nil

-- Conexiones activas (para limpiar al cambiar de personaje)
local activeConnections = {}

-- Estado de teclas
local KeyState = {
	Left = false,
	Right = false,
	Down = false,
}

-- ============================================
-- 🎮 GAME MODE CHECK
-- ============================================

-- Retorna true si el jugador está en un modo de juego activo
local function isInGameMode()
	local gameMode = player:GetAttribute("GameMode")
	return gameMode == "Training" or gameMode == "Versus"
end

-- ============================================
-- ⌨️ KEY MAPPING
-- ============================================

local KeyMap = {
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.D] = "Right",
	[Enum.KeyCode.S] = "Down",
	[Enum.KeyCode.W] = "Up",
	[Enum.KeyCode.Space] = "Up",
	[Enum.KeyCode.J] = "Punch",
	[Enum.KeyCode.K] = "HeavyPunch",
	[Enum.UserInputType.MouseButton1] = "Punch",
	[Enum.UserInputType.MouseButton2] = "HeavyPunch",
	[Enum.KeyCode.LeftShift] = "Dodge",

	[Enum.KeyCode.ButtonX] = "Punch",
	[Enum.KeyCode.ButtonB] = "HeavyPunch",
	[Enum.KeyCode.ButtonA] = "Up",
	[Enum.KeyCode.DPadDown] = "Down",
	[Enum.KeyCode.DPadUp] = "Up",
	[Enum.KeyCode.DPadRight] = "Right",
	[Enum.KeyCode.DPadLeft] = "Left",
}

-- ============================================
-- 🔄 HELPER FUNCTIONS
-- ============================================

local function toRelativeDirection(absoluteDir)
	if not controller or not controller.context then
		return absoluteDir
	end
	local facing = controller.context.currentDirection or "R"
	if absoluteDir == "Right" then
		return facing == "R" and "Forward" or "Back"
	elseif absoluteDir == "Left" then
		return facing == "L" and "Forward" or "Back"
	end
	return absoluteDir
end

local function resolveMovementFromKeyState()
	if not controller then
		return
	end
	if not isInGameMode() then
		return
	end
	if controller:IsAttackLocked() then
		return
	end
	if controller:IsInHitstun() then
		return
	end

	local dir = 0
	if KeyState.Right and not KeyState.Left then
		dir = 1
	elseif KeyState.Left and not KeyState.Right then
		dir = -1
	end

	controller:SetMoveDirection(dir)
end

-- Limpia todas las conexiones activas
local function cleanupConnections()
	for _, connection in ipairs(activeConnections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	activeConnections = {}
end

-- Resetea el estado de teclas
local function resetKeyState()
	KeyState.Left = false
	KeyState.Right = false
	KeyState.Down = false
end

-- ============================================
-- 🎯 INICIALIZACIÓN POR PERSONAJE
-- ============================================

local function initializeForCharacter(character)
	-- print("🎮 [Input] Initializing for character:", character.Name)

	-- Limpiar estado anterior
	cleanupConnections()
	resetKeyState()

	-- Destruir controlador anterior si existe
	if controller then
		controller:Destroy()
		controller = nil
	end

	-- Esperar a que el personaje esté listo
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)

	if not humanoid or not root then
		warn("⚠️ [Input] Character missing Humanoid or HumanoidRootPart")
		return
	end

	-- Leer personaje seleccionado
	local selectedCharacter = player:GetAttribute("SelectedCharacter") or nil

	-- Crear nuevos controladores
	buffer = InputBuffer.new(0.35)
	machine = StateMachine.new("Idle")
	controller = CharacterController.new(character, machine, selectedCharacter)

	-- Comandos del personaje
	characterCommands = controller.context and controller.context.commands or nil

	-- Buscar oponente inicial
	local enemy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
	if enemy then
		local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
		if enemyRoot then
			controller:SetOpponent(enemyRoot)
		end
	end

	-- Actualizar cámara
	CameraHandler:SetGameModeActive(isInGameMode())

	-- print("🎮 [Input] Controller ready for", character.Name, "| GameMode:", player:GetAttribute("GameMode") or "none")
end

-- ============================================
-- ⌨️ INPUT HANDLERS
-- ============================================

local function onInputBegan(input, processed)
	if processed then
		return
	end
	if not controller then
		return
	end
	if not isInGameMode() then
		return
	end

	local command = KeyMap[input.KeyCode] or KeyMap[input.UserInputType]
	if not command then
		return
	end

	-- Buffer para comandos especiales
	local bufferInput = command
	if command == "Left" or command == "Right" then
		bufferInput = toRelativeDirection(command)
	end
	buffer:AddInput(bufferInput)

	-- Movimiento
	if command == "Left" then
		KeyState.Left = true
		resolveMovementFromKeyState()
		return
	end

	if command == "Right" then
		KeyState.Right = true
		resolveMovementFromKeyState()
		return
	end

	if command == "Down" then
		KeyState.Down = true
		controller:SetCrouch(true)
		return
	end

	if command == "Up" then
		if KeyState.Down then
			return
		end
		if controller:IsAttackLocked() or controller:IsInHitstun() then
			return
		end
		controller:Jump()
		return
	end

	if command == "Dodge" then
		controller:Dodge()
		return
	end
end

local function onInputEnded(input)
	if not controller then
		return
	end
	if not isInGameMode() then
		return
	end

	local command = KeyMap[input.KeyCode] or KeyMap[input.UserInputType]
	if not command then
		return
	end

	if command == "Left" then
		KeyState.Left = false
		resolveMovementFromKeyState()
		return
	end

	if command == "Right" then
		KeyState.Right = false
		resolveMovementFromKeyState()
		return
	end

	if command == "Down" then
		KeyState.Down = false
		controller:SetCrouch(false)
		return
	end
end

local function onRenderStepped()
	if not controller or not buffer then
		return
	end
	if not isInGameMode() then
		return
	end

	local command = CommandParser.Parse(buffer, characterCommands)
	if not command then
		return
	end

	if command == "Fireball" then
		controller:RequestAttack("Fireball")
	elseif command == "Uppercut" then
		controller:RequestAttack("Uppercut")
	elseif command == "Punch" then
		buffer:Consume("Punch")
		controller:RequestAttack("Punch")
	elseif command == "HeavyPunch" then
		buffer:Consume("HeavyPunch")
		controller:RequestAttack("HeavyPunch")
	end
end

-- ============================================
-- 🔗 CONEXIONES GLOBALES (sobreviven cambios de personaje)
-- ============================================

UserInputService.InputBegan:Connect(onInputBegan)
UserInputService.InputEnded:Connect(onInputEnded)
RunService.RenderStepped:Connect(onRenderStepped)

-- ============================================
-- 👤 CHARACTER BINDING
-- ============================================

-- Cuando cambia el Character (por LoadCharacter o skin swap)
local function onCharacterChanged()
	local character = player.Character
	if character then
		-- Pequeño delay para asegurar que el personaje esté completamente cargado
		task.defer(function()
			if character == player.Character then -- Verificar que siga siendo el mismo
				initializeForCharacter(character)
			end
		end)
	end
end

-- CharacterAdded (respawn normal via LoadCharacter)
player.CharacterAdded:Connect(onCharacterChanged)

-- PropertyChanged (skin swap via player.Character = newModel)
player:GetPropertyChangedSignal("Character"):Connect(function()
	task.defer(onCharacterChanged)
end)

-- GameMode changed - actualizar cámara y resetear estado
player:GetAttributeChangedSignal("GameMode"):Connect(function()
	local inGame = isInGameMode()
	-- print("🎮 [Input] GameMode changed:", player:GetAttribute("GameMode"), "| Active:", inGame)

	CameraHandler:SetGameModeActive(inGame)

	if not inGame then
		-- Salimos del modo de juego - resetear estado
		resetKeyState()
		if controller then
			controller:SetMoveDirection(0)
			controller:SetCrouch(false)
		end
	end
end)

-- Inicializar si ya hay personaje
if player.Character then
	task.defer(function()
		onCharacterChanged()
	end)
end

-- ============================================
-- 🌐 GLOBAL EXPORT
-- ============================================

_G.ForceResolveMovement = function()
	resolveMovementFromKeyState()
end

_G.GetCurrentController = function()
	return controller
end

-- print("🎮 [Input] GameInputController loaded")
