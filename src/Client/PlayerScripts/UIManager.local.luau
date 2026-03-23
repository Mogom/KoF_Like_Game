--[[
	UIManager.local.luau
	-----------------------
	Cliente: gestiona TODA la navegación de UI.

	FLUJO DE PANTALLAS:
	  MainMenu
	   ├── Play → PlayMenuComponent
	   │           └── 1V1 → Versus mode (HUD)
	   ├── Training → Training mode (HUD)
	   ├── Create Sala → PlaceholderScreen → Volver → MainMenu
	   └── Shop → PlaceholderScreen → Volver → MainMenu

	CÓMO EDITAR:
	- Para agregar un nuevo botón al menú principal:
	  1. Agregar entrada en BUTTON_CONFIG de MainMenuComponent.luau
	  2. Agregar callback aquí (función + pasarla en props del mainMenu)
	- Para agregar un nuevo modo de juego (ej: 2V2):
	  1. Agregar entrada en MODE_BUTTONS de PlayMenuComponent.luau
	  2. Agregar callback aquí y conectar el RemoteEvent correspondiente
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Ocultar TopBar de Roblox
task.wait(0.5)
pcall(function()
	StarterGui:SetCore("TopbarEnabled", false)
end)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")
local Components = UI:WaitForChild("Components")

local MainMenuComponent = require(Components:WaitForChild("MainMenuComponent"))
local GameHUDComponent = require(Components:WaitForChild("GameHUDComponent"))
local PlayMenuComponent = require(Components:WaitForChild("PlayMenuComponent"))
local PlaceholderScreen = require(Components:WaitForChild("PlaceholderScreen"))

-- Remote Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local StartTrainingEvent = RemoteEvents:WaitForChild("StartTraining")
local StartVersusEvent = RemoteEvents:WaitForChild("StartVersus")

print("✅ Modules loaded")

-- ============================================
-- ESTADO
-- ============================================

local mainMenu = nil -- MainMenuComponent (persiste)
local currentScreen = nil -- PlayMenuComponent | PlaceholderScreen (se destruye al volver)
local currentHUD = nil -- GameHUDComponent (durante la partida)

-- ============================================
-- HELPERS
-- ============================================

-- Destruye la sub-pantalla actual (Play, Sala, Shop) si existe
local function destroyCurrentScreen()
	if currentScreen then
		currentScreen:destroy()
		currentScreen = nil
	end
end

-- Muestra el menú principal de nuevo (al volver de una sub-pantalla)
local function returnToMainMenu()
	destroyCurrentScreen()
	if mainMenu then
		mainMenu:show()
	end
end

-- ============================================
-- CALLBACK: Play → abre pantalla de selección de modo
-- ============================================

local function onPlayClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	currentScreen = PlayMenuComponent.new(playerGui, {
		-- Al pulsar 1V1 → iniciar versus
		onVersus1v1Click = function()
			destroyCurrentScreen()
			StartVersusEvent:FireServer()
			task.wait(0.5)
			currentHUD = GameHUDComponent.new(playerGui, player)
		end,

		-- Al pulsar Volver → regresar al menú principal
		onBackClick = returnToMainMenu,
	})
end

-- ============================================
-- CALLBACK: Training → inicia entrenamiento directo
-- ============================================

local function onTrainingClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	StartTrainingEvent:FireServer()

	task.wait(0.5)
	currentHUD = GameHUDComponent.new(playerGui, player)
end

-- ============================================
-- CALLBACK: Create Sala → placeholder screen
-- ============================================

local function onCreateSalaClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	currentScreen = PlaceholderScreen.new(playerGui, {
		title = "CREATE SALA",
		onBackClick = returnToMainMenu,
	})
end

-- ============================================
-- CALLBACK: Shop → placeholder screen
-- ============================================

local function onShopClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	currentScreen = PlaceholderScreen.new(playerGui, {
		title = "SHOP",
		onBackClick = returnToMainMenu,
	})
end

-- ============================================
-- CREAR MENÚ PRINCIPAL
-- ============================================

mainMenu = MainMenuComponent.new(playerGui, {
	onPlayClick = onPlayClick,
	onTrainingClick = onTrainingClick,
	onCreateSalaClick = onCreateSalaClick,
	onShopClick = onShopClick,
})

if mainMenu then
	print("✅ UI System initialized")
else
	warn("❌ Failed to create MainMenu!")
end
