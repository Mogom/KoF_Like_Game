-- Cliente: captura teclas (WASD, Space, J/K), mapea a acciones del CharacterController
-- Soporta personaje seleccionado via atributo "SelectedCharacter" en el Player

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
local character = player.Character or player.CharacterAdded:Wait()

-- Leer personaje seleccionado del atributo del jugador (seteado por UIManager)
local selectedCharacter = player:GetAttribute("SelectedCharacter") or nil

local buffer = InputBuffer.new(0.35)
local machine = StateMachine.new("Idle")
local controller = CharacterController.new(character, machine, selectedCharacter)

-- Comandos del personaje (si hay uno seleccionado)
local characterCommands = controller.context and controller.context.commands or nil
local enemy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
if enemy then
	local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
	if enemyRoot then
		controller:SetOpponent(enemyRoot)
	end
end

-- KeyMap: mantiene tus comandos
local KeyMap = {
	[Enum.KeyCode.A] = "Back",
	[Enum.KeyCode.D] = "Forward",
	[Enum.KeyCode.S] = "Down",
	[Enum.KeyCode.W] = "Up",
	[Enum.KeyCode.Space] = "Up",
	[Enum.KeyCode.J] = "Punch",
	[Enum.KeyCode.K] = "HeavyPunch",
	[Enum.UserInputType.MouseButton1] = "Punch",
	[Enum.UserInputType.MouseButton2] = "HeavyPunch",
	[Enum.KeyCode.LeftShift] = "Dodge",

	[Enum.KeyCode.ButtonX] = "Punch", -- Gamepad X
	[Enum.KeyCode.ButtonB] = "HeavyPunch", -- Gamepad B
	[Enum.KeyCode.ButtonA] = "Up", -- Gamepad A
	[Enum.KeyCode.DPadDown] = "Down", -- Gamepad Stick Down
	[Enum.KeyCode.DPadUp] = "Up", -- Gamepad Stick Up
	[Enum.KeyCode.DPadRight] = "Forward", -- Gamepad Stick Right
	[Enum.KeyCode.DPadLeft] = "Back", -- Gamepad Stick Left
}

-- Estado por tecla (evita flicker cuando cambias rápido)
local KeyState = {
	Back = false,
	Forward = false,
	Down = false,
}

-- Calcula dirección de movimiento basado en teclas A/D presionadas
local function resolveMovementFromKeyState()
	if controller:IsAttackLocked() or controller:IsInHitstun() then
		return
	end

	if KeyState.Forward and not KeyState.Back then
		controller:SetMoveDirection(1)
	elseif KeyState.Back and not KeyState.Forward then
		controller:SetMoveDirection(-1)
	else
		controller:SetMoveDirection(0)
	end
end

-- InputBegan
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	-- comando puede venir como KeyCode o UserInputType
	local command = KeyMap[input.KeyCode] or KeyMap[input.UserInputType]
	if not command then
		return
	end

	-- guardamos en buffer (para comandos/combos)
	buffer:AddInput(command)

	-- movimiento/crouch/jump/ataque
	if command == "Back" then
		KeyState.Back = true
		resolveMovementFromKeyState()
		return
	end

	if command == "Forward" then
		KeyState.Forward = true
		resolveMovementFromKeyState()
		return
	end

	if command == "Down" then
		-- Crouch on press
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
		-- Jump (W o Space)
		-- Always call jump (CharacterController decidirá si se puede)
		controller:Jump()
		return
	end

	if command == "Dodge" then
		controller:Dodge()
		return
	end

	-- ataques (otros botones)
	if command == "Punch" then
		return
	end

	if command == "HeavyPunch" then
		return
	end
end)

-- InputEnded
UserInputService.InputEnded:Connect(function(input)
	local command = KeyMap[input.KeyCode] or KeyMap[input.UserInputType]
	if not command then
		return
	end

	if command == "Back" then
		KeyState.Back = false
		resolveMovementFromKeyState()
		return
	end

	if command == "Forward" then
		KeyState.Forward = false
		resolveMovementFromKeyState()
		return
	end

	if command == "Down" then
		KeyState.Down = false
		controller:SetCrouch(false)
		return
	end
end)

-- Loop de parser: usa comandos del personaje si están disponibles
RunService.RenderStepped:Connect(function()
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
end)

-- 🔄 Exponer función para que CharacterController la llame
-- Fuerza recalcular movimiento (usado al soltar tecla)
local function forceResolveMovement()
	resolveMovementFromKeyState()
end

-- 🌐 Hacer accesible desde fuera
_G.ForceResolveMovement = forceResolveMovement
