--[[
	LobbyManager.luau
	-----------------
	Sistema de lobbies/salas para multijugador (2-8 jugadores).
	
	CARACTERÍSTICAS:
	- Crear/unirse/salir de lobbies
	- Host puede iniciar partida y kickear jugadores
	- Sistema de ready
	- Spawn dinámico basado en número de jugadores
	- Cálculo de posiciones desde el centro del mapa
	
	MODOS DE JUEGO SOPORTADOS:
	- Versus1v1: 2 jugadores
	- FreeForAll: 2-8 jugadores
	- Team2v2: 4 jugadores (2 equipos)
	- Team3v3: 6 jugadores (2 equipos)
	- Team4v4: 8 jugadores (2 equipos)
	
	USO:
	local LobbyManager = require(LobbyManager)
	local lobby = LobbyManager.CreateLobby(hostPlayer, "FreeForAll", 4)
	LobbyManager.JoinLobby(player, lobbyId)
	LobbyManager.SetPlayerReady(player, true)
	LobbyManager.StartMatch(hostPlayer)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _RunService = game:GetService("RunService") -- Reserved for future use

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")
local SpawnService = require(Utilities:WaitForChild("SpawnService"))

local LobbyManager = {}

-- ============================================
-- CONFIGURACIÓN
-- ============================================

local CONFIG = {
	-- Límites de jugadores por modo
	ModeLimits = {
		Versus1v1 = { min = 2, max = 2 },
		FreeForAll = { min = 2, max = 8 },
		Team2v2 = { min = 4, max = 4 },
		Team3v3 = { min = 6, max = 6 },
		Team4v4 = { min = 8, max = 8 },
	},

	-- Distancia base entre jugadores (studs)
	BaseSpawnDistance = 8,

	-- Altura de spawn sobre el BasePlate
	SpawnHeight = 3,

	-- Tiempo máximo de espera en lobby (segundos)
	LobbyTimeout = 300,

	-- Permitir bots para completar equipos
	AllowBots = false,
}

-- ============================================
-- ESTADO INTERNO
-- ============================================

-- { [lobbyId] = LobbyData }
local lobbies = {}

-- { [player] = lobbyId }
local playerLobbies = {}

-- ID counter
local nextLobbyId = 1

-- Remote Events (se crean si no existen)
local Remotes = nil
local LobbyEvents = nil

--[[
	LobbyData structure:
	{
		id = number,
		host = Player,
		mode = string ("Versus1v1", "FreeForAll", etc),
		maxPlayers = number,
		players = { Player, ... },
		readyState = { [Player] = bool },
		teams = { [Player] = teamNumber } (opcional),
		state = "Waiting" | "Starting" | "InGame",
		createdAt = number (tick),
		mapName = string,
	}
]]

-- ============================================
-- UTILIDADES DE MAPA
-- ============================================

-- Obtiene el centro y tamaño del BasePlate del mapa actual
-- Calcula posiciones de spawn para N jugadores distribuidos horizontalmente
-- Todos en el mismo eje Z (juego 2D)
local function calculateSpawnPositions(playerCount, mapName)
	return SpawnService.CalculateSpawnPositions(playerCount, mapName)
end

-- Calcula posiciones para equipos (lado izquierdo vs lado derecho)
local function calculateTeamSpawnPositions(team1Count, team2Count, mapName)
	return SpawnService.CalculateTeamSpawnPositions(team1Count, team2Count, mapName)
end

-- ============================================
-- GESTIÓN DE LOBBIES
-- ============================================

-- Genera un ID único para el lobby
local function generateLobbyId()
	local id = nextLobbyId
	nextLobbyId = nextLobbyId + 1
	return id
end

-- Crea un nuevo lobby
function LobbyManager.CreateLobby(host, mode, maxPlayers)
	if not host or not host.Parent then
		warn("⚠️ [LobbyManager] Invalid host player")
		return nil
	end

	-- Verificar que el modo existe
	local limits = CONFIG.ModeLimits[mode]
	if not limits then
		warn("⚠️ [LobbyManager] Unknown game mode:", mode)
		return nil
	end

	-- Validar maxPlayers
	maxPlayers = maxPlayers or limits.max
	maxPlayers = math.clamp(maxPlayers, limits.min, limits.max)

	-- Si ya está en un lobby, salir primero
	if playerLobbies[host] then
		LobbyManager.LeaveLobby(host)
	end

	local lobbyId = generateLobbyId()

	local lobby = {
		id = lobbyId,
		host = host,
		mode = mode,
		maxPlayers = maxPlayers,
		players = { host },
		readyState = { [host] = false },
		teams = {},
		state = "Waiting",
		createdAt = tick(),
		mapName = "Map0",
	}

	lobbies[lobbyId] = lobby
	playerLobbies[host] = lobbyId

	print("🏠 [Lobby] Created lobby", lobbyId, "by", host.Name, "| Mode:", mode, "| Max:", maxPlayers)

	-- Notificar al host
	LobbyManager._fireEvent("LobbyCreated", host, lobby)

	return lobby
end

-- Unirse a un lobby existente
function LobbyManager.JoinLobby(player, lobbyId)
	if not player or not player.Parent then
		return false, "Invalid player"
	end

	local lobby = lobbies[lobbyId]
	if not lobby then
		return false, "Lobby not found"
	end

	if lobby.state ~= "Waiting" then
		return false, "Lobby is not accepting players"
	end

	if #lobby.players >= lobby.maxPlayers then
		return false, "Lobby is full"
	end

	-- Si ya está en otro lobby, salir primero
	if playerLobbies[player] then
		LobbyManager.LeaveLobby(player)
	end

	-- Agregar al lobby
	table.insert(lobby.players, player)
	lobby.readyState[player] = false
	playerLobbies[player] = lobbyId

	print("➕ [Lobby]", player.Name, "joined lobby", lobbyId)

	-- Notificar a todos en el lobby
	for _, p in ipairs(lobby.players) do
		LobbyManager._fireEvent("PlayerJoined", p, lobby, player)
	end

	return true, lobby
end

-- Salir del lobby actual
function LobbyManager.LeaveLobby(player)
	local lobbyId = playerLobbies[player]
	if not lobbyId then
		return false, "Not in a lobby"
	end

	local lobby = lobbies[lobbyId]
	if not lobby then
		playerLobbies[player] = nil
		return false, "Lobby not found"
	end

	-- Remover del lobby
	for i, p in ipairs(lobby.players) do
		if p == player then
			table.remove(lobby.players, i)
			break
		end
	end

	lobby.readyState[player] = nil
	lobby.teams[player] = nil
	playerLobbies[player] = nil

	print("➖ [Lobby]", player.Name, "left lobby", lobbyId)

	-- Si era el host, transferir o cerrar
	if lobby.host == player then
		if #lobby.players > 0 then
			-- Transferir host al siguiente jugador
			lobby.host = lobby.players[1]
			print("👑 [Lobby] New host:", lobby.host.Name)

			for _, p in ipairs(lobby.players) do
				LobbyManager._fireEvent("HostChanged", p, lobby)
			end
		else
			-- Cerrar lobby vacío
			LobbyManager.CloseLobby(lobbyId)
			return true
		end
	end

	-- Notificar a los demás
	for _, p in ipairs(lobby.players) do
		LobbyManager._fireEvent("PlayerLeft", p, lobby, player)
	end

	return true
end

-- Cerrar un lobby
function LobbyManager.CloseLobby(lobbyId)
	local lobby = lobbies[lobbyId]
	if not lobby then
		return false
	end

	-- Remover todos los jugadores
	for _, player in ipairs(lobby.players) do
		playerLobbies[player] = nil
		LobbyManager._fireEvent("LobbyClosed", player, lobbyId)
	end

	lobbies[lobbyId] = nil
	print("🚪 [Lobby] Closed lobby", lobbyId)

	return true
end

-- ============================================
-- SISTEMA DE READY
-- ============================================

-- Cambiar estado de ready del jugador
function LobbyManager.SetPlayerReady(player, isReady)
	local lobbyId = playerLobbies[player]
	if not lobbyId then
		return false, "Not in a lobby"
	end

	local lobby = lobbies[lobbyId]
	if not lobby then
		return false, "Lobby not found"
	end

	lobby.readyState[player] = isReady

	print(isReady and "✅" or "⬜", "[Lobby]", player.Name, "ready:", isReady)

	-- Notificar a todos
	for _, p in ipairs(lobby.players) do
		LobbyManager._fireEvent("PlayerReadyChanged", p, lobby, player, isReady)
	end

	return true
end

-- Verificar si todos están listos
function LobbyManager.AllPlayersReady(lobbyId)
	local lobby = lobbies[lobbyId]
	if not lobby then
		return false
	end

	for _, player in ipairs(lobby.players) do
		if not lobby.readyState[player] then
			return false
		end
	end

	return true
end

-- ============================================
-- CONTROL DE HOST
-- ============================================

-- Kickear un jugador (solo host)
function LobbyManager.KickPlayer(host, targetPlayer)
	local lobbyId = playerLobbies[host]
	if not lobbyId then
		return false, "Not in a lobby"
	end

	local lobby = lobbies[lobbyId]
	if not lobby then
		return false, "Lobby not found"
	end

	if lobby.host ~= host then
		return false, "Only host can kick players"
	end

	if targetPlayer == host then
		return false, "Cannot kick yourself"
	end

	-- Verificar que el target está en el lobby
	local found = false
	for _, p in ipairs(lobby.players) do
		if p == targetPlayer then
			found = true
			break
		end
	end

	if not found then
		return false, "Player not in lobby"
	end

	print("🚫 [Lobby]", host.Name, "kicked", targetPlayer.Name)

	-- Notificar al kickeado
	LobbyManager._fireEvent("Kicked", targetPlayer, lobbyId)

	-- Remover del lobby
	LobbyManager.LeaveLobby(targetPlayer)

	return true
end

-- Transferir host a otro jugador
function LobbyManager.TransferHost(currentHost, newHost)
	local lobbyId = playerLobbies[currentHost]
	if not lobbyId then
		return false, "Not in a lobby"
	end

	local lobby = lobbies[lobbyId]
	if not lobby or lobby.host ~= currentHost then
		return false, "Not the host"
	end

	-- Verificar que el nuevo host está en el lobby
	local found = false
	for _, p in ipairs(lobby.players) do
		if p == newHost then
			found = true
			break
		end
	end

	if not found then
		return false, "Player not in lobby"
	end

	lobby.host = newHost
	print("👑 [Lobby] Host transferred to", newHost.Name)

	for _, p in ipairs(lobby.players) do
		LobbyManager._fireEvent("HostChanged", p, lobby)
	end

	return true
end

-- ============================================
-- INICIAR PARTIDA
-- ============================================

-- Inicia la partida (solo host)
function LobbyManager.StartMatch(host)
	local lobbyId = playerLobbies[host]
	if not lobbyId then
		return false, "Not in a lobby"
	end

	local lobby = lobbies[lobbyId]
	if not lobby then
		return false, "Lobby not found"
	end

	if lobby.host ~= host then
		return false, "Only host can start"
	end

	if lobby.state ~= "Waiting" then
		return false, "Match already started"
	end

	-- Verificar mínimo de jugadores
	local limits = CONFIG.ModeLimits[lobby.mode]
	if #lobby.players < limits.min then
		return false, "Not enough players (need " .. limits.min .. ")"
	end

	-- Verificar que todos estén listos (opcional, el host puede forzar)
	-- if not LobbyManager.AllPlayersReady(lobbyId) then
	-- 	return false, "Not all players are ready"
	-- end

	lobby.state = "Starting"
	print("🚀 [Lobby] Starting match in lobby", lobbyId)

	-- Notificar a todos
	for _, p in ipairs(lobby.players) do
		LobbyManager._fireEvent("MatchStarting", p, lobby)
	end

	-- Calcular posiciones de spawn
	local positions
	if lobby.mode == "FreeForAll" or lobby.mode == "Versus1v1" then
		positions = calculateSpawnPositions(#lobby.players, lobby.mapName)
	else
		-- Modo por equipos
		local team1 = {}
		local team2 = {}
		for _, p in ipairs(lobby.players) do
			local team = lobby.teams[p] or 1
			if team == 1 then
				table.insert(team1, p)
			else
				table.insert(team2, p)
			end
		end
		local teamPositions = calculateTeamSpawnPositions(#team1, #team2, lobby.mapName)
		positions = {}
		for i, p in ipairs(team1) do
			positions[p] = teamPositions.team1[i]
		end
		for i, p in ipairs(team2) do
			positions[p] = teamPositions.team2[i]
		end
	end

	-- Spawnar jugadores
	task.spawn(function()
		LobbyManager._spawnPlayers(lobby, positions)
	end)

	return true
end

-- Spawna a todos los jugadores en sus posiciones
function LobbyManager._spawnPlayers(lobby, positions)
	local spawnedPlayers = {}

	for i, player in ipairs(lobby.players) do
		local spawnPos = positions[player] or positions[i]

		if spawnPos then
			-- Establecer GameMode
			player:SetAttribute("GameMode", lobby.mode)

			-- Respawnear jugador
			player:LoadCharacter()

			local character = player.Character or player.CharacterAdded:Wait()
			local root = character:WaitForChild("HumanoidRootPart", 5)

			if root then
				-- Mover a la posición calculada
				root.CFrame = CFrame.new(spawnPos)
				table.insert(spawnedPlayers, player)
				print("📍 [Lobby] Spawned", player.Name, "at", spawnPos)
			end
		end
	end

	task.wait(0.5)

	-- Cambiar estado a InGame
	lobby.state = "InGame"

	-- Notificar inicio con lista de oponentes
	for _, player in ipairs(spawnedPlayers) do
		local opponents = {}
		for _, other in ipairs(spawnedPlayers) do
			if other ~= player then
				table.insert(opponents, other.Character)
			end
		end
		LobbyManager._fireEvent("MatchStarted", player, lobby, opponents)
	end

	print("🎮 [Lobby] Match started in lobby", lobby.id, "with", #spawnedPlayers, "players")
end

-- ============================================
-- CONSULTAS
-- ============================================

-- Obtener lobby de un jugador
function LobbyManager.GetPlayerLobby(player)
	local lobbyId = playerLobbies[player]
	if lobbyId then
		return lobbies[lobbyId]
	end
	return nil
end

-- Obtener lobby por ID
function LobbyManager.GetLobby(lobbyId)
	return lobbies[lobbyId]
end

-- Obtener todos los lobbies públicos en estado "Waiting"
function LobbyManager.GetAvailableLobbies()
	local available = {}
	for id, lobby in pairs(lobbies) do
		if lobby.state == "Waiting" and #lobby.players < lobby.maxPlayers then
			table.insert(available, {
				id = id,
				host = lobby.host.Name,
				mode = lobby.mode,
				players = #lobby.players,
				maxPlayers = lobby.maxPlayers,
			})
		end
	end
	return available
end

-- Verificar si el jugador es host de su lobby
function LobbyManager.IsHost(player)
	local lobby = LobbyManager.GetPlayerLobby(player)
	return lobby and lobby.host == player
end

-- Obtener configuración de límites
function LobbyManager.GetModeLimits(mode)
	return CONFIG.ModeLimits[mode]
end

-- Obtener todos los modos disponibles
function LobbyManager.GetAvailableModes()
	local modes = {}
	for mode, limits in pairs(CONFIG.ModeLimits) do
		table.insert(modes, {
			name = mode,
			minPlayers = limits.min,
			maxPlayers = limits.max,
		})
	end
	return modes
end

-- ============================================
-- SISTEMA DE EVENTOS (REMOTES)
-- ============================================

-- Inicializa RemoteEvents para comunicación cliente-servidor
function LobbyManager._initRemotes()
	if Remotes then
		return
	end

	Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not Remotes then
		Remotes = Instance.new("Folder")
		Remotes.Name = "Remotes"
		Remotes.Parent = ReplicatedStorage
	end

	local eventsFolder = Remotes:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = Remotes
	end

	-- Crear eventos de lobby
	local eventNames = {
		"LobbyCreated",
		"PlayerJoined",
		"PlayerLeft",
		"LobbyClosed",
		"PlayerReadyChanged",
		"HostChanged",
		"Kicked",
		"MatchStarting",
		"MatchStarted",
		"LobbyUpdated",
	}

	LobbyEvents = {}
	for _, name in ipairs(eventNames) do
		local eventName = "Lobby" .. name
		local event = eventsFolder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = eventsFolder
		end
		LobbyEvents[name] = event
	end
end

-- Dispara un evento a un jugador
function LobbyManager._fireEvent(eventName, player, ...)
	if not LobbyEvents then
		LobbyManager._initRemotes()
	end

	local event = LobbyEvents[eventName]
	if event and player and player.Parent then
		event:FireClient(player, ...)
	end
end

-- ============================================
-- CLEANUP
-- ============================================

-- Limpieza cuando un jugador se desconecta
Players.PlayerRemoving:Connect(function(player)
	if playerLobbies[player] then
		LobbyManager.LeaveLobby(player)
	end
end)

-- Inicializar remotes al cargar
LobbyManager._initRemotes()

return LobbyManager
