-- Server principal: maneja game modes, replica animaciones y ataques entre jugadores
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ============================================
-- 📦 CARGAR MÓDULOS
-- ============================================

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")
local GameModeManager = require(Utilities:WaitForChild("GameModeManager"))

-- ============================================
-- 📡 REMOTE EVENTS
-- ============================================

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")

-- Eventos de game mode
local StartTrainingEvent = Instance.new("RemoteEvent")
StartTrainingEvent.Name = "StartTraining"
StartTrainingEvent.Parent = RemoteEvents

local StartVersusEvent = Instance.new("RemoteEvent")
StartVersusEvent.Name = "StartVersus"
StartVersusEvent.Parent = RemoteEvents

local StartFFAEvent = Instance.new("RemoteEvent")
StartFFAEvent.Name = "StartFreeForAll"
StartFFAEvent.Parent = RemoteEvents

-- Evento de replicación de animaciones
local ReplicateAnimationEvent = RemoteEvents:WaitForChild("ReplicateAnimation")

-- Evento de sincronización de ataques
local SyncAttackEvent = RemoteEvents:WaitForChild("SyncAttack")

-- Evento de replicación de VFX
local ReplicateVFXEvent = Instance.new("RemoteEvent")
ReplicateVFXEvent.Name = "ReplicateVFX"
ReplicateVFXEvent.Parent = RemoteEvents

-- ============================================
-- 🎯 MANEJAR REQUESTS DE GAME MODES
-- ============================================

StartTrainingEvent.OnServerEvent:Connect(function(player, selectedCharacter, selectedDummyCharacter)
	if typeof(selectedCharacter) == "string" and selectedCharacter ~= "" then
		player:SetAttribute("SelectedCharacter", selectedCharacter)
	end
	if typeof(selectedDummyCharacter) == "string" and selectedDummyCharacter ~= "" then
		player:SetAttribute("SelectedDummyCharacter", selectedDummyCharacter)
	end
	GameModeManager.StartTrainingMode(player)
end)

StartVersusEvent.OnServerEvent:Connect(function(player, selectedCharacter)
	if typeof(selectedCharacter) == "string" and selectedCharacter ~= "" then
		player:SetAttribute("SelectedCharacter", selectedCharacter)
	end
	GameModeManager.StartVersus1v1Mode(player)
end)

StartFFAEvent.OnServerEvent:Connect(function(player, selectedCharacter, targetPlayers)
	if typeof(selectedCharacter) == "string" and selectedCharacter ~= "" then
		player:SetAttribute("SelectedCharacter", selectedCharacter)
	end
	-- targetPlayers es opcional, default será el máximo
	local target = tonumber(targetPlayers) or nil
	GameModeManager.StartFreeForAllMode(player, target)
end)

-- ============================================
-- 🎬 REPLICAR ANIMACIONES
-- ============================================

ReplicateAnimationEvent.OnServerEvent:Connect(function(player, animationName)
	-- Obtener oponente(s) según el modo
	local opponents = GameModeManager.GetOpponents(player)

	for _, opponent in ipairs(opponents) do
		if opponent and opponent.Parent then
			-- Obtener Player del oponente
			local opponentPlayer = Players:GetPlayerFromCharacter(opponent)
			if opponentPlayer then
				ReplicateAnimationEvent:FireClient(opponentPlayer, player.Character, animationName)
			end
		end
	end

	-- Fallback para 1v1 legacy
	if #opponents == 0 then
		local opponent = GameModeManager.GetOpponent(player)
		if opponent then
			ReplicateAnimationEvent:FireClient(opponent, player.Character, animationName)
		end
	end
end)

-- ============================================
-- ⚔️ SINCRONIZAR ATAQUES
-- ============================================

SyncAttackEvent.OnServerEvent:Connect(function(player, attackData)
	-- Obtener oponente(s) según el modo
	local opponents = GameModeManager.GetOpponents(player)

	for _, opponent in ipairs(opponents) do
		if opponent and opponent.Parent then
			local opponentPlayer = Players:GetPlayerFromCharacter(opponent)
			if opponentPlayer then
				SyncAttackEvent:FireClient(opponentPlayer, player.Character, attackData)
			end
		end
	end

	-- Fallback para 1v1 legacy
	if #opponents == 0 then
		local opponent = GameModeManager.GetOpponent(player)
		if opponent then
			SyncAttackEvent:FireClient(opponent, player.Character, attackData)
		end
	end
end)

-- ============================================
-- ✨ REPLICAR VFX A OTROS JUGADORES
-- ============================================

ReplicateVFXEvent.OnServerEvent:Connect(function(player, vfxType, vfxData)
	-- Broadcast VFX a todos los jugadores excepto el que lo envió
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			ReplicateVFXEvent:FireClient(otherPlayer, player.Character, vfxType, vfxData)
		end
	end
end)

-- ============================================
-- 🔌 CLEANUP
-- ============================================

Players.PlayerRemoving:Connect(function(player)
	print("👋 Player leaving:", player.Name)
	GameModeManager.LeaveMatch(player)
end)
