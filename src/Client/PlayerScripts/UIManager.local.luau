-- Cliente: gestiona UI (menú principal + HUD), conecta game modes
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ✅ Ocultar TopBar
task.wait(0.5)
pcall(function()
	StarterGui:SetCore("TopbarEnabled", false)
end)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")
local Components = UI:WaitForChild("Components")

local MainMenuComponent = require(Components:WaitForChild("MainMenuComponent"))
local GameHUDComponent = require(Components:WaitForChild("GameHUDComponent"))

-- ✅ REMOTE EVENTS
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local StartTrainingEvent = RemoteEvents:WaitForChild("StartTraining")
local StartVersusEvent = RemoteEvents:WaitForChild("StartVersus")

print("✅ Modules loaded")

local mainMenu = nil
local currentHUD = nil

-- ============================================
-- 🎯 CALLBACK: Training Mode
-- ============================================

-- Callback al seleccionar Training: oculta menú, muestra HUD, fire server
local function onTrainingClick()
	if not mainMenu then
		warn("❌ mainMenu is nil!")
		return
	end

	-- Ocultar menú
	mainMenu:hide()

	-- Pedir al servidor iniciar training mode
	StartTrainingEvent:FireServer()

	-- Mostrar HUD
	task.wait(0.5)
	currentHUD = GameHUDComponent.new(playerGui, player)
end

-- ============================================
-- ⚔️ CALLBACK: Versus Mode
-- ============================================

-- Callback al seleccionar Versus: oculta menú, muestra HUD, fire server
local function onVersusClick()
	if not mainMenu then
		warn("❌ mainMenu is nil!")
		return
	end

	mainMenu:hide()

	-- Pedir al servidor iniciar versus mode
	StartVersusEvent:FireServer()

	task.wait(0.5)
	currentHUD = GameHUDComponent.new(playerGui, player)

	-- TODO: Mostrar "Buscando oponente..." mientras espera
end

-- ============================================
-- 🎨 CREAR MENÚ
-- ============================================

mainMenu = MainMenuComponent.new(playerGui, {
	onTrainingClick = onTrainingClick,
	onVersusClick = onVersusClick,
})

if mainMenu then
	print("✅ UI System initialized")
else
	warn("❌ Failed to create MainMenu!")
end
