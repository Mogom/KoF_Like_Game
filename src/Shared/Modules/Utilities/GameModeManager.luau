local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Server: matchmaking, game modes (Training/Versus), spawn management
local GameModeManager = {}

-- ============================================
-- 🎮 VARIABLES GLOBALES
-- ============================================

local activeMatches = {} -- { [player1] = player2 }
local waitingPlayers = {} -- Cola de jugadores esperando match
local playerModes = {} -- { [player] = "Training" or "Versus" }

-- RemoteEvents
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local SetOpponentEvent = RemoteEvents:WaitForChild("SetOpponent")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CharactersFolder = Modules:WaitForChild("Characters")
local CharacterRegistry = require(CharactersFolder:WaitForChild("CharacterRegistry"))

-- ============================================
-- 🔧 FUNCIONES AUXILIARES
-- ============================================

-- Asigna un SpawnLocation específico al jugador
local function setPlayerSpawn(player, spawnName)
	local spawn = workspace:FindFirstChild(spawnName)

	if not spawn then
		warn("❌ Spawn not found:", spawnName)
		return false
	end

	player.RespawnLocation = spawn
	return true
end

-- Fuerza respawn del jugador
local function respawnPlayer(player)
	-- Forzar respawn usando LoadCharacter
	player:LoadCharacter()
end

local function findSkinModel(characterName, skinName)
	if not characterName or not skinName then
		return nil
	end

	local characterFolder = CharactersFolder:FindFirstChild(characterName)
	if not characterFolder then
		return nil
	end

	local skinsFolder = characterFolder:FindFirstChild("Skins")
	if not skinsFolder then
		return nil
	end

	local model = skinsFolder:FindFirstChild(skinName)
	if model and model:IsA("Model") then
		return model
	end

	return nil
end

local function applySelectedCharacterModel(player)
	local selectedCharacter = player:GetAttribute("SelectedCharacter")
	print("🔍 [SkinSwap] Checking skin for", player.Name, "| Character:", selectedCharacter or "nil")

	if not selectedCharacter or selectedCharacter == "" then
		print("🔍 [SkinSwap] No character selected, keeping default avatar")
		return
	end

	local charData = CharacterRegistry.Get(selectedCharacter)
	if not charData then
		warn("⚠️ Character not registered:", selectedCharacter)
		return
	end

	local selectedSkin = player:GetAttribute("SelectedSkin")
	local skinId = charData:GetSkin(selectedSkin)
	print("🔍 [SkinSwap] SkinId resolved to:", skinId)

	-- Compatibilidad con fallback actual: "Dummy" significa mantener avatar estándar
	if skinId == "Dummy" then
		print("🔍 [SkinSwap] SkinId is 'Dummy', keeping default avatar")
		return
	end

	local skinModelTemplate = findSkinModel(selectedCharacter, skinId)
	if not skinModelTemplate then
		print(
			"🔍 [SkinSwap] No skin model found at Characters/"
				.. selectedCharacter
				.. "/Skins/"
				.. skinId
				.. ", keeping default avatar"
		)
		return
	end

	print("🔍 [SkinSwap] Found skin template:", skinModelTemplate:GetFullName())

	local currentCharacter = player.Character
	if not currentCharacter or not currentCharacter.Parent then
		return
	end

	if currentCharacter:GetAttribute("CustomSkinApplied") == true then
		local appliedCharacter = currentCharacter:GetAttribute("AppliedCharacterName")
		local appliedSkin = currentCharacter:GetAttribute("AppliedSkinName")
		if appliedCharacter == selectedCharacter and appliedSkin == skinId then
			return
		end
	end

	local currentRoot = currentCharacter:FindFirstChild("HumanoidRootPart")
	if not currentRoot then
		currentRoot = currentCharacter:WaitForChild("HumanoidRootPart", 2)
	end
	local spawnCFrame = currentRoot and currentRoot.CFrame or currentCharacter:GetPivot()

	local newCharacter = skinModelTemplate:Clone()
	newCharacter.Name = player.Name

	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	local newRoot = newCharacter:FindFirstChild("HumanoidRootPart")
	if not newHumanoid or not newRoot then
		warn("⚠️ Skin model requires Humanoid and HumanoidRootPart:", selectedCharacter, skinId)
		newCharacter:Destroy()
		return
	end

	if not newCharacter.PrimaryPart then
		newCharacter.PrimaryPart = newRoot
	end

	newCharacter:SetAttribute("CustomSkinApplied", true)
	newCharacter:SetAttribute("AppliedCharacterName", selectedCharacter)
	newCharacter:SetAttribute("AppliedSkinName", skinId)

	newCharacter.Parent = workspace
	newCharacter:PivotTo(spawnCFrame)

	player.Character = newCharacter

	currentCharacter:Destroy()
end

local function setupPlayerSkinAutoApply(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			applySelectedCharacterModel(player)
		end)
	end)

	player:GetAttributeChangedSignal("SelectedCharacter"):Connect(function()
		if player.Character and player.Character.Parent then
			applySelectedCharacterModel(player)
		end
	end)

	player:GetAttributeChangedSignal("SelectedSkin"):Connect(function()
		if player.Character and player.Character.Parent then
			applySelectedCharacterModel(player)
		end
	end)

	if player.Character and player.Character.Parent then
		task.defer(function()
			applySelectedCharacterModel(player)
		end)
	end
end

-- Busca el dummy de entrenamiento en workspace
local function findDummy()
	return workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
end

-- ============================================
-- 🎯 TRAINING MODE (Solo vs Dummy)
-- ============================================

-- Inicia modo Training: spawn + dummy + SetOpponent
function GameModeManager.StartTrainingMode(player)
	player:SetAttribute("GameMode", "Training")

	playerModes[player] = "Training"

	-- Cambiar spawn y respawnear
	setPlayerSpawn(player, "TrainingSpawn")
	respawnPlayer(player)

	-- Esperar a que spawne
	local character = player.Character or player.CharacterAdded:Wait()
	applySelectedCharacterModel(player)
	character = player.Character or character
	task.wait(0.5) -- Tiempo para que todo cargue

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

-- Inicia modo Versus 1v1: empareja jugadores, spawn, SetOpponent mutuo
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
	applySelectedCharacterModel(player)
	applySelectedCharacterModel(opponent)
	char1 = player.Character or char1
	char2 = opponent.Character or char2
	task.wait(0.5)

	-- Notificar a ambos clientes sobre su oponente
	SetOpponentEvent:FireClient(player, char2)
	SetOpponentEvent:FireClient(opponent, char1)

	print("✅ Match started:", player.Name, "vs", opponent.Name)
end

-- ============================================
-- 🔄 FUNCIÓN: Obtener oponente actual
-- ============================================

-- Retorna el oponente asignado al jugador
function GameModeManager.GetOpponent(player)
	return activeMatches[player]
end

-- ============================================
-- 🚪 FUNCIÓN: Salir del match
-- ============================================

-- Limpia match y datos del jugador al salir
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

	-- Limpiar atributo GameMode para desactivar inputs/cámara 2D
	player:SetAttribute("GameMode", nil)
end

-- ============================================
-- 🔌 EVENTOS: Cleanup al desconectar
-- ============================================

Players.PlayerRemoving:Connect(function(player)
	GameModeManager.LeaveMatch(player)
end)

Players.PlayerAdded:Connect(function(player)
	setupPlayerSkinAutoApply(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerSkinAutoApply(player)
end

return GameModeManager
