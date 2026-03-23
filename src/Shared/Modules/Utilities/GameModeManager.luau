local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeManager = {}

-- ============================================
-- 🎮 VARIABLES GLOBALES
-- ============================================

local activeMatches = {}  -- { [player1] = player2 }
local waitingPlayers = {}  -- Cola de jugadores esperando match
local playerModes = {}  -- { [player] = "Training" or "Versus" }

-- RemoteEvents
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local SetOpponentEvent = RemoteEvents:WaitForChild("SetOpponent")

-- ============================================
-- 🔧 FUNCIONES AUXILIARES
-- ============================================

local function setPlayerSpawn(player, spawnName)
	local spawn = workspace:FindFirstChild(spawnName)

	if not spawn then
		warn("❌ Spawn not found:", spawnName)
		return false
	end

	player.RespawnLocation = spawn
	return true
end

local function respawnPlayer(player)
	-- Forzar respawn usando LoadCharacter
	player:LoadCharacter()
end

local function findDummy()
	return workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
end

-- ============================================
-- 🎯 TRAINING MODE (Solo vs Dummy)
-- ============================================

function GameModeManager.StartTrainingMode(player)
	
	player:SetAttribute("GameMode", "Training")

	playerModes[player] = "Training"

	-- Cambiar spawn y respawnear
	setPlayerSpawn(player, "TrainingSpawn")
	respawnPlayer(player)

	-- Esperar a que spawne
	local character = player.Character or player.CharacterAdded:Wait()
	task.wait(0.5)  -- Tiempo para que todo cargue

	-- Buscar dummy
	local dummy = findDummy()

	if not dummy then
		warn("⚠️ No training dummy found in workspace!")
		return
	end

	-- Notificar al cliente sobre su oponente (el dummy)
	SetOpponentEvent:FireClient(player, dummy)
end

-- ============================================
-- ⚔️ VERSUS MODE (1v1 Multiplayer)
-- ============================================

function GameModeManager.StartVersus1v1Mode(player)
	
	player:SetAttribute("GameMode", "Versus")
	
	print("⚔️ Player requesting 1v1:", player.Name)

	playerModes[player] = "Versus"

	-- Buscar oponente en la cola
	local opponent = nil

	for i, waitingPlayer in ipairs(waitingPlayers) do
		if waitingPlayer ~= player and waitingPlayer.Parent then
			opponent = waitingPlayer
			table.remove(waitingPlayers, i)
			break
		end
	end

	-- Si no hay oponente, agregar a cola
	if not opponent then
		table.insert(waitingPlayers, player)
		print("⏳", player.Name, "added to matchmaking queue")
		-- TODO: Mostrar UI de "Buscando oponente..."
		return
	end

	-- ============================================
	-- MATCH ENCONTRADO
	-- ============================================

	print("🎮 Match found:", player.Name, "vs", opponent.Name)
	opponent:SetAttribute("GameMode", "Versus")

	-- Registrar match activo
	activeMatches[player] = opponent
	activeMatches[opponent] = player

	-- Cambiar spawns y respawnear ambos
	setPlayerSpawn(player, "ArenaSpawn1")
	setPlayerSpawn(opponent, "ArenaSpawn2")

	respawnPlayer(player)
	respawnPlayer(opponent)

	-- Esperar a que ambos spawnen
	local char1 = player.Character or player.CharacterAdded:Wait()
	local char2 = opponent.Character or opponent.CharacterAdded:Wait()
	task.wait(0.5)

	-- Notificar a ambos clientes sobre su oponente
	SetOpponentEvent:FireClient(player, char2)
	SetOpponentEvent:FireClient(opponent, char1)

	print("✅ Match started:", player.Name, "vs", opponent.Name)
end

-- ============================================
-- 🔄 FUNCIÓN: Obtener oponente actual
-- ============================================

function GameModeManager.GetOpponent(player)
	return activeMatches[player]
end

-- ============================================
-- 🚪 FUNCIÓN: Salir del match
-- ============================================

function GameModeManager.LeaveMatch(player)
	local opponent = activeMatches[player]

	if opponent then
		activeMatches[player] = nil
		activeMatches[opponent] = nil

		print("🚪", player.Name, "left match with", opponent.Name)
	end

	-- Remover de cola
	for i, waitingPlayer in ipairs(waitingPlayers) do
		if waitingPlayer == player then
			table.remove(waitingPlayers, i)
			break
		end
	end

	playerModes[player] = nil
end

-- ============================================
-- 🔌 EVENTOS: Cleanup al desconectar
-- ============================================

Players.PlayerRemoving:Connect(function(player)
	GameModeManager.LeaveMatch(player)
end)

return GameModeManager