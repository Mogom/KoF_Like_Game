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

-- Evento de replicación de animaciones
local ReplicateAnimationEvent = RemoteEvents:WaitForChild("ReplicateAnimation")

-- Evento de sincronización de ataques
local SyncAttackEvent = RemoteEvents:WaitForChild("SyncAttack")

-- ============================================
-- 🎯 MANEJAR REQUESTS DE GAME MODES
-- ============================================

StartTrainingEvent.OnServerEvent:Connect(function(player)
	GameModeManager.StartTrainingMode(player)
end)

StartVersusEvent.OnServerEvent:Connect(function(player)
	GameModeManager.StartVersus1v1Mode(player)
end)

-- ============================================
-- 🎬 REPLICAR ANIMACIONES
-- ============================================

ReplicateAnimationEvent.OnServerEvent:Connect(function(player, animationName)
	-- Obtener oponente
	local opponent = GameModeManager.GetOpponent(player)

	if opponent then
		-- Enviar animación al oponente
		ReplicateAnimationEvent:FireClient(opponent, player.Character, animationName)
	end
end)

-- ============================================
-- ⚔️ SINCRONIZAR ATAQUES
-- ============================================

SyncAttackEvent.OnServerEvent:Connect(function(player, attackData)
	local opponent = GameModeManager.GetOpponent(player)

	if opponent then
		-- Replicar ataque al oponente
		SyncAttackEvent:FireClient(opponent, player.Character, attackData)
	end
end)

-- ============================================
-- 🔌 CLEANUP
-- ============================================

Players.PlayerRemoving:Connect(function(player)
	print("👋 Player leaving:", player.Name)
	GameModeManager.LeaveMatch(player)
end)
