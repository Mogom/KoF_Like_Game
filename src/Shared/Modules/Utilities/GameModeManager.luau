local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Server: matchmaking, game modes (Training/Versus/FreeForAll), spawn management
local GameModeManager = {}

-- ============================================
-- 🎮 VARIABLES GLOBALES
-- ============================================

local activeMatches = {} -- { [player1] = player2 } para 1v1
local activeFFA = {} -- { [player] = { opponents = {...}, mode = "FreeForAll" } }
local waitingPlayers = {} -- Cola de jugadores esperando match
local playerModes = {} -- { [player] = "Training" | "Versus" | "FreeForAll" }

-- RemoteEvents
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local SetOpponentEvent = RemoteEvents:WaitForChild("SetOpponent")

-- Crear evento para múltiples oponentes si no existe
local SetOpponentsEvent = RemoteEvents:FindFirstChild("SetOpponents")
if not SetOpponentsEvent then
	SetOpponentsEvent = Instance.new("RemoteEvent")
	SetOpponentsEvent.Name = "SetOpponents"
	SetOpponentsEvent.Parent = RemoteEvents
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CharactersFolder = Modules:WaitForChild("Characters")
local UtilitiesFolder = Modules:WaitForChild("Utilities")
local CharacterRegistry = require(CharactersFolder:WaitForChild("CharacterRegistry"))
local BlastZoneService = require(UtilitiesFolder:WaitForChild("BlastZoneService"))
local StockManager = require(UtilitiesFolder:WaitForChild("StockManager"))

local STOCK_CONFIG = {
	DefaultStocks = 3,
	RespawnInvulnerability = 2.5,
}

local nextMatchId = 1
local matchRuntime = {}
local playerMatchId = {}

-- ============================================
-- 📐 CONFIGURACIÓN DE SPAWN
-- ============================================

local SPAWN_CONFIG = {
	-- Distancia base entre jugadores (studs)
	BaseDistance = 8,

	-- Altura sobre el BasePlate
	SpawnHeight = 3,

	-- Nombre del mapa actual
	CurrentMap = "Map0",

	-- Usar 80% del ancho del mapa máximo
	MapWidthUsage = 0.8,
}

-- ============================================
-- 🗺️ FUNCIONES DE MAPA Y SPAWN
-- ============================================

-- Obtiene el centro y tamaño del BasePlate del mapa actual
local function getMapBounds(mapName)
	mapName = mapName or SPAWN_CONFIG.CurrentMap

	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		warn("⚠️ [GameMode] Maps folder not found! Create workspace/Maps/Map0/BasePlate")
		-- Fallback: usar posición 0,5,0 con tamaño 100x1x100
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	local mapFolder = maps:FindFirstChild(mapName)
	if not mapFolder then
		warn("⚠️ [GameMode] Map not found:", mapName, "| Create workspace/Maps/" .. mapName .. "/BasePlate")
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	local basePlate = mapFolder:FindFirstChild("BasePlate")
	if not basePlate then
		warn("⚠️ [GameMode] BasePlate not found in map:", mapName, "| Create a Part named 'BasePlate' inside")
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	local center = basePlate.Position
	local size = basePlate.Size

	print("✅ [Map] Using", mapName, "| Center:", center, "| Size:", size)
	return center, size
end

-- Calcula posiciones de spawn distribuidas horizontalmente desde el centro
-- Todos en el mismo eje Z (juego 2D)
local function calculateSpawnPositions(playerCount, mapName)
	local center, size = getMapBounds(mapName)
	local positions = {}

	-- El eje Z es fijo (centro del mapa) - CRÍTICO para 2D
	local fixedZ = center.Z

	-- Altura de spawn (encima del BasePlate)
	local spawnY = center.Y + (size.Y / 2) + SPAWN_CONFIG.SpawnHeight

	-- Calcular distancia total necesaria
	local totalWidth = SPAWN_CONFIG.BaseDistance * (playerCount - 1)

	-- Asegurar que no exceda el mapa
	local maxWidth = size.X * SPAWN_CONFIG.MapWidthUsage
	if totalWidth > maxWidth then
		totalWidth = maxWidth
	end

	-- Posición inicial (izquierda del centro)
	local startX = center.X - (totalWidth / 2)
	local spacing = playerCount > 1 and (totalWidth / (playerCount - 1)) or 0

	for i = 1, playerCount do
		local posX = startX + (spacing * (i - 1))
		table.insert(positions, Vector3.new(posX, spawnY, fixedZ))
	end

	print("📍 [Spawn] Calculated", playerCount, "positions from center:", center, "| Z fixed at:", fixedZ)

	return positions
end

-- Spawnea un jugador en una posición específica
local function spawnPlayerAtPosition(player, position)
	player:LoadCharacter()

	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5)

	if root then
		-- Importante: mantener la orientación mirando al centro
		root.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
		print("📍 [Spawn]", player.Name, "spawned at", position)
		return true
	end

	return false
end

local function registerMatchRuntime(mode, players, positions, facings)
	local matchId = nextMatchId
	nextMatchId += 1

	local runtime = {
		id = matchId,
		mode = mode,
		players = players,
		spawnByPlayer = {},
		facingByPlayer = {},
		aliveByPlayer = {},
		aliveCount = 0,
		active = true,
	}

	for i, p in ipairs(players) do
		runtime.spawnByPlayer[p] = positions[i]
		runtime.facingByPlayer[p] = facings[i] == true
		runtime.aliveByPlayer[p] = true
		runtime.aliveCount += 1
		playerMatchId[p] = matchId
	end

	matchRuntime[matchId] = runtime
	return runtime
end

local function clearMatchRuntime(matchId)
	local runtime = matchRuntime[matchId]
	if not runtime then
		return
	end

	runtime.active = false
	BlastZoneService.StopMatch(matchId)

	for _, p in ipairs(runtime.players) do
		if playerMatchId[p] == matchId then
			playerMatchId[p] = nil
		end
	end

	matchRuntime[matchId] = nil
end

local function clearPlayerRuntime(player)
	local matchId = playerMatchId[player]
	if matchId then
		clearMatchRuntime(matchId)
	end
	playerMatchId[player] = nil
end

-- ============================================
-- 🔧 FUNCIONES AUXILIARES
-- ============================================

-- Asigna un SpawnLocation específico al jugador
local function _setPlayerSpawn(player, spawnName)
	local spawn = workspace:FindFirstChild(spawnName)

	if not spawn then
		warn("❌ Spawn not found:", spawnName)
		return false
	end

	player.RespawnLocation = spawn
	return true
end

-- Fuerza respawn del jugador
local function _respawnPlayer(player)
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

local function setReplicatedSpawnState(character, position, facingRight)
	if not character then
		return
	end

	character:SetAttribute("ReplicatedSpawnX", position.X)
	character:SetAttribute("ReplicatedSpawnY", position.Y)
	character:SetAttribute("ReplicatedSpawnZ", position.Z)
	character:SetAttribute("ReplicatedSpawnFacingRight", facingRight == true)
	character:SetAttribute("ReplicatedSpawnVersion", os.clock())
end

-- Mueve un character/dummy a una posición específica
local function moveCharacterToPosition(character, position, facingRight, isDummy)
	if not character then
		warn("⚠️ [Move] No character provided")
		return false
	end

	-- Esperar a que el character esté lista
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		root = character:WaitForChild("HumanoidRootPart", 5)
	end

	if not root then
		warn("⚠️ [Move] HumanoidRootPart not found in", character.Name)
		return false
	end

	-- Para NPCs/dummies, desanclar TODAS las partes para que repliquen
	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
	else
		-- Solo desanclar el root para jugadores
		if root.Anchored then
			root.Anchored = false
		end
	end

	-- Establecer NetworkOwnership al servidor para garantizar el teleport
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- Para dummies, establecer ownership de todas las partes
	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				pcall(function()
					part:SetNetworkOwner(nil)
				end)
			end
		end
	end

	-- Detener cualquier movimiento actual
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	-- facingRight = true mira hacia +X, false mira hacia -X
	local rotation = facingRight and math.rad(-90) or math.rad(90)

	-- Usar PivotTo para mover todo el modelo
	local targetCFrame = CFrame.new(position) * CFrame.Angles(0, rotation, 0)
	setReplicatedSpawnState(character, position, facingRight)
	character:PivotTo(targetCFrame)

	-- También establecer CFrame del root directamente
	root.CFrame = targetCFrame

	-- Asegurar que la velocidad esté en cero
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	-- Para dummies, también asegurar que todos los parts estén quietos
	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end

	-- Devolver ownership al cliente si es un jugador
	if not isDummy then
		task.defer(function()
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				pcall(function()
					root:SetNetworkOwner(player)
				end)
			end
		end)
	end

	print("📍 [Move] Character", character.Name, "moved to", position, isDummy and "(dummy)" or "(player)")
	return true
end

-- ============================================
-- 🎯 TRAINING MODE (Solo vs Dummy)
-- ============================================

-- Inicia modo Training: spawn en BasePlate + dummy + SetOpponent
function GameModeManager.StartTrainingMode(player)
	player:SetAttribute("GameMode", "Training")
	playerModes[player] = "Training"

	-- Buscar dummy primero
	local dummy = findDummy()
	if not dummy then
		warn("⚠️ No training dummy found in workspace!")
		return
	end

	print("🎯 [Training] Starting for", player.Name, "| Map:", SPAWN_CONFIG.CurrentMap)

	-- Calcular posiciones para 2 combatientes en el mapa actual
	local positions = calculateSpawnPositions(2, SPAWN_CONFIG.CurrentMap)

	if #positions < 2 then
		warn("⚠️ Could not calculate spawn positions")
		return
	end

	-- Posición izquierda para jugador, derecha para dummy
	local playerPos = positions[1]
	local dummyPos = positions[2]

	print("📍 [Training] Positions - Player:", playerPos, "| Dummy:", dummyPos)
	setReplicatedSpawnState(dummy, dummyPos, false)

	-- Respawnear jugador
	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()

	-- Esperar a que el character tenga HumanoidRootPart
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		warn("⚠️ [Training] HumanoidRootPart not found for player")
		return
	end

	-- Aplicar skin si está seleccionado
	applySelectedCharacterModel(player)

	-- Re-obtener character y root después de aplicar skin
	character = player.Character
	if not character then
		warn("⚠️ [Training] Character lost after skin application")
		return
	end

	root = character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		warn("⚠️ [Training] HumanoidRootPart lost after skin application")
		return
	end

	-- Esperar un momento para que todo se estabilice
	task.wait(0.3)

	-- Mover jugador a su posición (mirando hacia la derecha)
	print("📍 [Training] About to move player, Character:", character.Name, "Root:", root)
	local playerMoved = moveCharacterToPosition(character, playerPos, true, false)
	print("📍 [Training] Player moved:", playerMoved)

	-- Pequeña pausa entre movimientos
	task.wait(0.1)

	-- Mover dummy a su posición (mirando hacia la izquierda)
	local dummyMoved = moveCharacterToPosition(dummy, dummyPos, false, true)
	print("📍 [Training] Dummy moved:", dummyMoved)

	task.wait(0.2)

	-- Notificar al cliente sobre su oponente (el dummy)
	SetOpponentEvent:FireClient(player, dummy)

	print("✅ [Training] Started at", SPAWN_CONFIG.CurrentMap, "| Player:", playerPos, "| Dummy:", dummyPos)
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

	-- Calcular posiciones para 2 jugadores en el mapa
	local positions = calculateSpawnPositions(2, SPAWN_CONFIG.CurrentMap)

	-- Respawnear ambos jugadores
	player:LoadCharacter()
	opponent:LoadCharacter()

	-- Esperar a que ambos spawnen
	local char1 = player.Character or player.CharacterAdded:Wait()
	local char2 = opponent.Character or opponent.CharacterAdded:Wait()

	applySelectedCharacterModel(player)
	applySelectedCharacterModel(opponent)
	char1 = player.Character or char1
	char2 = opponent.Character or char2

	task.wait(0.3)

	-- Mover a posiciones calculadas
	if #positions >= 2 then
		moveCharacterToPosition(char1, positions[1], true, false) -- Player 1 mira derecha
		moveCharacterToPosition(char2, positions[2], false, false) -- Player 2 mira izquierda
	end

	StockManager.InitPlayer(player, STOCK_CONFIG.DefaultStocks)
	StockManager.InitPlayer(opponent, STOCK_CONFIG.DefaultStocks)

	local runtime = registerMatchRuntime(
		"Versus",
		{ player, opponent },
		{ positions[1], positions[2] },
		{ true, false }
	)

	BlastZoneService.StartMatch(runtime.id, runtime.players, SPAWN_CONFIG.CurrentMap, function(outPlayer)
		if not runtime.active then
			return
		end

		local alive = StockManager.LoseStock(outPlayer)
		if alive then
			local respawnPos = runtime.spawnByPlayer[outPlayer]
			local facing = runtime.facingByPlayer[outPlayer]
			local respawned =
				StockManager.RespawnPlayerAt(outPlayer, respawnPos, facing, STOCK_CONFIG.RespawnInvulnerability)

			applySelectedCharacterModel(outPlayer)
			local finalCharacter = outPlayer.Character or respawned
			local other = outPlayer == player and opponent or player
			if finalCharacter and other and other.Character then
				SetOpponentEvent:FireClient(outPlayer, other.Character)
				SetOpponentEvent:FireClient(other, finalCharacter)
			end
			return
		end

		local winner = outPlayer == player and opponent or player
		if winner and winner.Parent then
			winner:SetAttribute("MatchResult", "Win")
		end
		if outPlayer and outPlayer.Parent then
			outPlayer:SetAttribute("MatchResult", "Lose")
		end

		clearMatchRuntime(runtime.id)
		GameModeManager.LeaveMatch(outPlayer)
		if winner then
			GameModeManager.LeaveMatch(winner)
		end
	end)

	task.wait(0.2)

	-- Notificar a ambos clientes sobre su oponente
	SetOpponentEvent:FireClient(player, char2)
	SetOpponentEvent:FireClient(opponent, char1)

	print("✅ [Versus] Match started:", player.Name, "vs", opponent.Name, "at", SPAWN_CONFIG.CurrentMap)
end

-- ============================================
-- 🔄 FUNCIÓN: Obtener oponente actual
-- ============================================

-- Retorna el oponente asignado al jugador (para 1v1)
function GameModeManager.GetOpponent(player)
	return activeMatches[player]
end

-- Retorna todos los oponentes del jugador (para FFA)
function GameModeManager.GetOpponents(player)
	local ffaData = activeFFA[player]
	if ffaData then
		return ffaData.opponents
	end

	-- Fallback para 1v1
	local opponent = activeMatches[player]
	if opponent then
		return { opponent }
	end

	return {}
end

-- ============================================
-- 🎮 FREE FOR ALL MODE (2-8 jugadores)
-- ============================================

-- Cola de jugadores esperando FFA
local ffaWaitingPlayers = {}
local FFA_MIN_PLAYERS = 2
local FFA_MAX_PLAYERS = 8
local FFA_WAIT_TIME = 30 -- Segundos de espera antes de iniciar con mínimo

-- Inicia modo Free For All
function GameModeManager.StartFreeForAllMode(player, targetPlayers)
	targetPlayers = targetPlayers or FFA_MAX_PLAYERS
	targetPlayers = math.clamp(targetPlayers, FFA_MIN_PLAYERS, FFA_MAX_PLAYERS)

	print("🎮 [FFA] Player requesting Free For All:", player.Name, "| Target:", targetPlayers)

	playerModes[player] = "FreeForAll"
	player:SetAttribute("GameMode", "FreeForAll")

	-- Agregar a cola FFA
	table.insert(ffaWaitingPlayers, {
		player = player,
		targetPlayers = targetPlayers,
		joinedAt = tick(),
	})

	-- Verificar si podemos iniciar
	GameModeManager._checkFFAStart()
end

-- Verifica si hay suficientes jugadores para iniciar FFA
function GameModeManager._checkFFAStart()
	-- Limpiar jugadores desconectados
	for i = #ffaWaitingPlayers, 1, -1 do
		if not ffaWaitingPlayers[i].player.Parent then
			table.remove(ffaWaitingPlayers, i)
		end
	end

	if #ffaWaitingPlayers < FFA_MIN_PLAYERS then
		return false
	end

	-- Verificar si hay suficientes para el target más común
	local targetCounts = {}
	for _, data in ipairs(ffaWaitingPlayers) do
		local target = data.targetPlayers
		targetCounts[target] = (targetCounts[target] or 0) + 1
	end

	-- Buscar un target alcanzable
	for target, count in pairs(targetCounts) do
		if count >= target then
			-- Tenemos suficientes para este target
			local participants = {}
			for i = #ffaWaitingPlayers, 1, -1 do
				local data = ffaWaitingPlayers[i]
				if data.targetPlayers == target and #participants < target then
					table.insert(participants, data.player)
					table.remove(ffaWaitingPlayers, i)
				end
			end

			if #participants >= FFA_MIN_PLAYERS then
				GameModeManager._startFFAMatch(participants)
				return true
			end
		end
	end

	-- Verificar timeout: si alguien esperó mucho, iniciar con el mínimo
	local now = tick()
	for _, data in ipairs(ffaWaitingPlayers) do
		if now - data.joinedAt > FFA_WAIT_TIME and #ffaWaitingPlayers >= FFA_MIN_PLAYERS then
			-- Iniciar con todos los que están esperando
			local participants = {}
			for i = #ffaWaitingPlayers, 1, -1 do
				table.insert(participants, ffaWaitingPlayers[i].player)
				table.remove(ffaWaitingPlayers, i)
				if #participants >= FFA_MAX_PLAYERS then
					break
				end
			end

			GameModeManager._startFFAMatch(participants)
			return true
		end
	end

	return false
end

-- Inicia un match FFA con los participantes dados
function GameModeManager._startFFAMatch(participants)
	print("🎮 [FFA] Starting match with", #participants, "players")

	-- Calcular posiciones de spawn desde el centro del mapa
	local positions = calculateSpawnPositions(#participants, SPAWN_CONFIG.CurrentMap)

	-- Spawear a todos los jugadores
	local spawnedPlayers = {}

	for i, player in ipairs(participants) do
		player:SetAttribute("GameMode", "FreeForAll")
		playerModes[player] = "FreeForAll"
		StockManager.InitPlayer(player, STOCK_CONFIG.DefaultStocks)

		-- Spawnear en posición calculada
		local success = spawnPlayerAtPosition(player, positions[i])

		if success then
			-- Aplicar skin del personaje seleccionado
			task.defer(function()
				applySelectedCharacterModel(player)
			end)
			table.insert(spawnedPlayers, player)
		end
	end

	-- Esperar a que todos spawnen
	task.wait(0.5)

	local spawnPositions = {}
	local spawnFacings = {}
	for i, p in ipairs(spawnedPlayers) do
		spawnPositions[i] = positions[i]
		spawnFacings[i] = (i % 2 == 1)
	end

	local runtime = registerMatchRuntime("FreeForAll", spawnedPlayers, spawnPositions, spawnFacings)

	-- Registrar oponentes para cada jugador
	for _, player in ipairs(spawnedPlayers) do
		local opponents = {}
		for _, other in ipairs(spawnedPlayers) do
			if other ~= player and other.Character then
				table.insert(opponents, other.Character)
			end
		end

		activeFFA[player] = {
			opponents = opponents,
			mode = "FreeForAll",
			participants = spawnedPlayers,
		}

		-- Notificar al cliente sobre sus oponentes (múltiples)
		SetOpponentsEvent:FireClient(player, opponents)
	end

	BlastZoneService.StartMatch(runtime.id, runtime.players, SPAWN_CONFIG.CurrentMap, function(outPlayer)
		if not runtime.active then
			return
		end

		local alive = StockManager.LoseStock(outPlayer)
		if alive then
			local respawnPos = runtime.spawnByPlayer[outPlayer]
			local facing = runtime.facingByPlayer[outPlayer]
			local respawned =
				StockManager.RespawnPlayerAt(outPlayer, respawnPos, facing, STOCK_CONFIG.RespawnInvulnerability)

			applySelectedCharacterModel(outPlayer)
			local finalCharacter = outPlayer.Character or respawned
			if finalCharacter then
				local updatedOpponents = {}
				for _, other in ipairs(spawnedPlayers) do
					if other ~= outPlayer and other.Parent and runtime.aliveByPlayer[other] then
						table.insert(updatedOpponents, other.Character)
					end
				end
				SetOpponentsEvent:FireClient(outPlayer, updatedOpponents)
			end
			return
		end

		if runtime.aliveByPlayer[outPlayer] then
			runtime.aliveByPlayer[outPlayer] = false
			runtime.aliveCount = math.max(0, runtime.aliveCount - 1)
		end

		if runtime.aliveCount <= 1 then
			local winner = nil
			for _, p in ipairs(runtime.players) do
				if runtime.aliveByPlayer[p] and p.Parent then
					winner = p
					break
				end
			end

			for _, p in ipairs(runtime.players) do
				if p and p.Parent then
					if winner and p == winner then
						p:SetAttribute("MatchResult", "Win")
					else
						p:SetAttribute("MatchResult", "Lose")
					end
				end
			end

			clearMatchRuntime(runtime.id)
			for _, p in ipairs(runtime.players) do
				GameModeManager.LeaveMatch(p)
			end
		end
	end)

	print(
		"✅ [FFA] Match started with players:",
		table.concat(
			(function()
				local names = {}
				for _, p in ipairs(spawnedPlayers) do
					table.insert(names, p.Name)
				end
				return names
			end)(),
			", "
		)
	)
end

-- Cancela la búsqueda de FFA para un jugador
function GameModeManager.CancelFFASearch(player)
	for i, data in ipairs(ffaWaitingPlayers) do
		if data.player == player then
			table.remove(ffaWaitingPlayers, i)
			print("❌ [FFA]", player.Name, "cancelled FFA search")
			return true
		end
	end
	return false
end

-- Obtener cantidad de jugadores esperando FFA
function GameModeManager.GetFFAQueueCount()
	-- Limpiar desconectados
	for i = #ffaWaitingPlayers, 1, -1 do
		if not ffaWaitingPlayers[i].player.Parent then
			table.remove(ffaWaitingPlayers, i)
		end
	end
	return #ffaWaitingPlayers
end

-- ============================================
-- 🚪 FUNCIÓN: Salir del match
-- ============================================

-- Limpia match y datos del jugador al salir
function GameModeManager.LeaveMatch(player)
	clearPlayerRuntime(player)
	BlastZoneService.StopAllForPlayer(player)
	StockManager.ClearPlayer(player)
	player:SetAttribute("MatchResult", nil)

	-- Limpiar 1v1
	local opponent = activeMatches[player]
	if opponent then
		activeMatches[player] = nil
		activeMatches[opponent] = nil
		print("🚪", player.Name, "left match with", opponent.Name)
	end

	-- Limpiar FFA
	local ffaData = activeFFA[player]
	if ffaData then
		-- Notificar a los demás que este jugador salió
		for _, other in ipairs(ffaData.participants or {}) do
			if other ~= player and other.Parent then
				local otherFFA = activeFFA[other]
				if otherFFA then
					-- Remover de la lista de oponentes
					for i, opp in ipairs(otherFFA.opponents) do
						if opp == player.Character then
							table.remove(otherFFA.opponents, i)
							break
						end
					end
				end
			end
		end
		activeFFA[player] = nil
		print("🚪 [FFA]", player.Name, "left FFA match")
	end

	-- Remover de colas
	for i, waitingPlayer in ipairs(waitingPlayers) do
		if waitingPlayer == player then
			table.remove(waitingPlayers, i)
			break
		end
	end

	GameModeManager.CancelFFASearch(player)

	playerModes[player] = nil
	player:SetAttribute("GameMode", nil)
end

-- ============================================
-- 📐 UTILIDADES PÚBLICAS
-- ============================================

-- Establece el mapa actual para spawns
function GameModeManager.SetCurrentMap(mapName)
	SPAWN_CONFIG.CurrentMap = mapName
	print("🗺️ [GameMode] Current map set to:", mapName)
end

-- Obtiene posiciones de spawn para N jugadores
function GameModeManager.GetSpawnPositions(playerCount, mapName)
	return calculateSpawnPositions(playerCount, mapName or SPAWN_CONFIG.CurrentMap)
end

-- Obtiene el modo actual del jugador
function GameModeManager.GetPlayerMode(player)
	return playerModes[player]
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
