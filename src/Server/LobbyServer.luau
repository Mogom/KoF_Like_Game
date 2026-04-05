--[[
	LobbyServer.luau
	----------------
	Script de servidor que conecta los RemoteEvents de lobby con LobbyManager.
	
	EVENTOS MANEJADOS:
	- CreateLobby: Crear un nuevo lobby
	- JoinLobby: Unirse a un lobby existente  
	- LeaveLobby: Salir del lobby actual
	- SetReady: Cambiar estado de ready
	- StartMatch: Iniciar la partida (solo host)
	
	FUNCIONES MANEJADAS:
	- GetLobbies: Obtener lista de lobbies disponibles
	- GetLobbyInfo: Obtener información de un lobby específico
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Esperar a que se carguen los módulos
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")
local LobbyManager = require(Utilities:WaitForChild("LobbyManager"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")

-- Crear eventos si no existen
local function getOrCreateEvent(name)
	local event = RemoteEvents:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = RemoteEvents
	end
	return event
end

local function getOrCreateFunction(name)
	local functions = Remotes:FindFirstChild("Functions")
	if not functions then
		functions = Instance.new("Folder")
		functions.Name = "Functions"
		functions.Parent = Remotes
	end

	local func = functions:FindFirstChild(name)
	if not func then
		func = Instance.new("RemoteFunction")
		func.Name = name
		func.Parent = functions
	end
	return func
end

-- Eventos
local CreateLobbyEvent = getOrCreateEvent("CreateLobby")
local JoinLobbyEvent = getOrCreateEvent("JoinLobby")
local LeaveLobbyEvent = getOrCreateEvent("LeaveLobby")
local SetReadyEvent = getOrCreateEvent("SetReady")
local StartMatchEvent = getOrCreateEvent("StartMatch")

-- Funciones
local GetLobbiesFunction = getOrCreateFunction("GetLobbies")
local GetLobbyInfoFunction = getOrCreateFunction("GetLobbyInfo")

-- ============================================
-- HANDLERS DE EVENTOS
-- ============================================

-- Crear lobby
CreateLobbyEvent.OnServerEvent:Connect(function(player, mode, maxPlayers)
	mode = mode or "Versus1v1"
	maxPlayers = maxPlayers or 2

	local lobby = LobbyManager.CreateLobby(player, mode, maxPlayers)

	if lobby then
		print("✅ [LobbyServer] Lobby created by", player.Name, "| ID:", lobby.id)
	else
		warn("❌ [LobbyServer] Failed to create lobby for", player.Name)
	end
end)

-- Unirse a lobby
JoinLobbyEvent.OnServerEvent:Connect(function(player, lobbyId)
	if not lobbyId then
		warn("⚠️ [LobbyServer] JoinLobby called without lobbyId")
		return
	end

	local success, result = LobbyManager.JoinLobby(player, lobbyId)

	if success then
		print("✅ [LobbyServer]", player.Name, "joined lobby", lobbyId)
	else
		warn("❌ [LobbyServer] Failed to join lobby:", result)
	end
end)

-- Salir de lobby
LeaveLobbyEvent.OnServerEvent:Connect(function(player)
	local success, result = LobbyManager.LeaveLobby(player)

	if success then
		print("✅ [LobbyServer]", player.Name, "left lobby")
	else
		warn("⚠️ [LobbyServer]", player.Name, "leave failed:", result)
	end
end)

-- Cambiar estado ready
SetReadyEvent.OnServerEvent:Connect(function(player, isReady)
	isReady = isReady == true

	local success, result = LobbyManager.SetPlayerReady(player, isReady)

	if not success then
		warn("⚠️ [LobbyServer] SetReady failed for", player.Name, ":", result)
	end
end)

-- Iniciar partida (solo host)
StartMatchEvent.OnServerEvent:Connect(function(player)
	local success, result = LobbyManager.StartMatch(player)

	if success then
		print("🎮 [LobbyServer] Match started by", player.Name)
	else
		warn("❌ [LobbyServer] StartMatch failed:", result)
	end
end)

-- ============================================
-- HANDLERS DE FUNCIONES
-- ============================================

-- Obtener lista de lobbies disponibles
GetLobbiesFunction.OnServerInvoke = function(_player)
	return LobbyManager.GetAvailableLobbies()
end

-- Obtener info de un lobby específico
GetLobbyInfoFunction.OnServerInvoke = function(_player, lobbyId)
	local lobby = LobbyManager.GetLobby(lobbyId)

	if not lobby then
		return nil
	end

	-- Serializar datos del lobby (sin referencias a Player directamente)
	local playerNames = {}
	for _, p in ipairs(lobby.players) do
		table.insert(playerNames, p.Name)
	end

	local readyStates = {}
	for p, ready in pairs(lobby.readyState) do
		readyStates[p.Name] = ready
	end

	return {
		id = lobby.id,
		host = lobby.host.Name,
		mode = lobby.mode,
		maxPlayers = lobby.maxPlayers,
		players = playerNames,
		readyState = readyStates,
		state = lobby.state,
		mapName = lobby.mapName,
	}
end

-- ============================================
-- CLEANUP
-- ============================================

Players.PlayerRemoving:Connect(function(player)
	-- LobbyManager ya maneja esto, pero logueamos
	local lobby = LobbyManager.GetPlayerLobby(player)
	if lobby then
		print("🚪 [LobbyServer] Player", player.Name, "disconnected from lobby", lobby.id)
	end
end)

print("✅ [LobbyServer] Initialized")
