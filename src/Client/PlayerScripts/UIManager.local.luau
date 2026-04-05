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
local CharacterSelectComponent = require(Components:WaitForChild("CharacterSelectComponent"))
local LobbyComponent = require(Components:WaitForChild("LobbyComponent"))
local LobbyListComponent = require(Components:WaitForChild("LobbyListComponent"))

-- Remote Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local StartTrainingEvent = RemoteEvents:WaitForChild("StartTraining")
local StartVersusEvent = RemoteEvents:WaitForChild("StartVersus")

-- Crear evento FreeForAll si no existe
local StartFFAEvent = RemoteEvents:FindFirstChild("StartFreeForAll")
if not StartFFAEvent then
	StartFFAEvent = Instance.new("RemoteEvent")
	StartFFAEvent.Name = "StartFreeForAll"
	StartFFAEvent.Parent = RemoteEvents
end

-- Eventos de Lobby
local CreateLobbyEvent = RemoteEvents:FindFirstChild("CreateLobby")
if not CreateLobbyEvent then
	CreateLobbyEvent = Instance.new("RemoteEvent")
	CreateLobbyEvent.Name = "CreateLobby"
	CreateLobbyEvent.Parent = RemoteEvents
end

local JoinLobbyEvent = RemoteEvents:FindFirstChild("JoinLobby")
if not JoinLobbyEvent then
	JoinLobbyEvent = Instance.new("RemoteEvent")
	JoinLobbyEvent.Name = "JoinLobby"
	JoinLobbyEvent.Parent = RemoteEvents
end

local GetLobbiesFunction = Remotes:FindFirstChild("Functions") and Remotes.Functions:FindFirstChild("GetLobbies")
if not GetLobbiesFunction then
	local Functions = Remotes:FindFirstChild("Functions") or Instance.new("Folder", Remotes)
	Functions.Name = "Functions"
	GetLobbiesFunction = Instance.new("RemoteFunction")
	GetLobbiesFunction.Name = "GetLobbies"
	GetLobbiesFunction.Parent = Functions
end

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
-- HELPER: Selección de personaje antes de un modo
-- Muestra CharacterSelectComponent, al confirmar llama onReady(characterName)
-- dualSelect: si true, selecciona jugador + dummy → onReady(charName, dummyCharName)
-- ============================================

local function showCharacterSelect(onReady, onCancel, dualSelect)
	currentScreen = CharacterSelectComponent.new(playerGui, {
		dualSelect = dualSelect or false,
		onConfirm = function(characterName, dummyCharName)
			-- Guardar selección en atributo del jugador (InputClient lo lee)
			player:SetAttribute("SelectedCharacter", characterName)
			if dummyCharName then
				player:SetAttribute("SelectedDummyCharacter", dummyCharName)
			end
			destroyCurrentScreen()
			if onReady then
				onReady(characterName, dummyCharName)
			end
		end,
		onBackClick = function()
			destroyCurrentScreen()
			if onCancel then
				onCancel()
			end
		end,
	})
end

-- ============================================
-- CALLBACK: Play → abre pantalla de selección de modo
-- ============================================

-- Forward declaration
local onJoinLobbyClick

local function onPlayClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	currentScreen = PlayMenuComponent.new(playerGui, {
		-- Al pulsar 1V1 → selección de personaje → iniciar versus
		onVersus1v1Click = function()
			destroyCurrentScreen()
			showCharacterSelect(function(characterName)
				StartVersusEvent:FireServer(characterName)
				task.wait(0.5)
				currentHUD = GameHUDComponent.new(playerGui, player)
			end, returnToMainMenu)
		end,

		-- Al pulsar Free For All → selección de personaje → buscar partida FFA
		onFreeForAllClick = function()
			destroyCurrentScreen()
			showCharacterSelect(function(characterName)
				StartFFAEvent:FireServer(characterName)
				task.wait(0.5)
				currentHUD = GameHUDComponent.new(playerGui, player)
			end, returnToMainMenu)
		end,

		-- Al pulsar Join Lobby → mostrar lista de lobbies
		onJoinLobbyClick = function()
			destroyCurrentScreen()
			if onJoinLobbyClick then
				onJoinLobbyClick()
			end
		end,

		-- Al pulsar Volver → regresar al menú principal
		onBackClick = returnToMainMenu,
	})
end

-- ============================================
-- CALLBACK: Training → selección de personaje + dummy → inicia entrenamiento
-- ============================================

local function onTrainingClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	showCharacterSelect(function(characterName, dummyCharName)
		StartTrainingEvent:FireServer(characterName, dummyCharName)
		task.wait(0.5)
		currentHUD = GameHUDComponent.new(playerGui, player)
	end, returnToMainMenu, true) -- dualSelect = true
end

-- ============================================
-- CALLBACK: Create Sala → muestra LobbyComponent para crear lobby
-- ============================================

local function onCreateSalaClick()
	if not mainMenu then
		return
	end
	mainMenu:hide()

	-- Crear lobby en el servidor
	CreateLobbyEvent:FireServer("1v1") -- Modo por defecto

	-- Mostrar componente de lobby
	currentScreen = LobbyComponent.new(playerGui, {
		isHost = true,
		onBackClick = function()
			destroyCurrentScreen()
			returnToMainMenu()
		end,
		onStartGame = function()
			-- El servidor manejará el inicio del juego
			destroyCurrentScreen()
			task.wait(0.5)
			currentHUD = GameHUDComponent.new(playerGui, player)
		end,
	})
end

-- ============================================
-- CALLBACK: Join Lobby → muestra lista de lobbies disponibles
-- ============================================

onJoinLobbyClick = function()
	if not mainMenu then
		return
	end
	mainMenu:hide()
	destroyCurrentScreen()

	-- Obtener lobbies del servidor
	local lobbies = {}
	local success = pcall(function()
		lobbies = GetLobbiesFunction:InvokeServer() or {}
	end)

	if not success then
		lobbies = {}
	end

	currentScreen = LobbyListComponent.new(playerGui, {
		lobbies = lobbies,
		onBackClick = returnToMainMenu,
		onJoinLobby = function(lobbyId)
			-- Unirse al lobby
			JoinLobbyEvent:FireServer(lobbyId)
			destroyCurrentScreen()

			-- Mostrar pantalla de lobby (como miembro, no host)
			currentScreen = LobbyComponent.new(playerGui, {
				isHost = false,
				onBackClick = function()
					destroyCurrentScreen()
					returnToMainMenu()
				end,
				onStartGame = function()
					destroyCurrentScreen()
					task.wait(0.5)
					currentHUD = GameHUDComponent.new(playerGui, player)
				end,
			})
		end,
		onRefresh = function()
			-- Refrescar lista de lobbies
			local updatedLobbies = {}
			pcall(function()
				updatedLobbies = GetLobbiesFunction:InvokeServer() or {}
			end)
			if currentScreen and currentScreen.updateLobbies then
				currentScreen:updateLobbies(updatedLobbies)
			end
		end,
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
