--[[
	PartyService.luau
	-----------------
	Sistema de Party/Grupo para mantener jugadores juntos entre partidas.
	
	CARACTERÍSTICAS:
	- Crear party e invitar amigos por username
	- Party leader con control del grupo
	- Persistencia entre partidas
	- Matchmaking como grupo
	- Transferir liderazgo
	
	FLUJO:
	1. Jugador crea party (se convierte en leader)
	2. Leader invita amigos por username
	3. Amigos aceptan/rechazan invitación
	4. Party se une a lobbies juntos
	5. Al terminar partida, vuelven al party
	
	USO:
	local PartyService = require(PartyService)
	PartyService.CreateParty(player)
	PartyService.InviteByUsername(leader, "FriendName")
	PartyService.AcceptInvite(player, partyId)
	PartyService.JoinLobbyAsParty(leader, lobbyId)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyService = {}

-- ============================================
-- CONFIGURACIÓN
-- ============================================

local CONFIG = {
	-- Máximo de miembros en un party
	MaxPartySize = 4,

	-- Tiempo de expiración de invitación (segundos)
	InviteExpiration = 60,

	-- Permitir invitar jugadores en otra party
	AllowStealInvites = false,
}

-- ============================================
-- ESTADO INTERNO
-- ============================================

-- { [partyId] = PartyData }
local parties = {}

-- { [player] = partyId }
local playerParties = {}

-- { [player] = { partyId, sentAt, fromPlayer } }
local pendingInvites = {}

-- ID counter
local nextPartyId = 1

-- Remote Events
local Remotes = nil
local PartyEvents = nil

--[[
	PartyData structure:
	{
		id = number,
		leader = Player,
		members = { Player, ... },
		createdAt = number (tick),
		currentLobbyId = number? (si están en un lobby)
	}
]]

-- ============================================
-- UTILIDADES
-- ============================================

-- Genera un ID único para el party
local function generatePartyId()
	local id = nextPartyId
	nextPartyId = nextPartyId + 1
	return id
end

-- Busca un jugador por username
local function findPlayerByUsername(username)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower() == username:lower() then
			return player
		end
	end
	return nil
end

-- ============================================
-- GESTIÓN DE PARTIES
-- ============================================

-- Crea un nuevo party con el jugador como leader
function PartyService.CreateParty(player)
	if not player or not player.Parent then
		return nil, "Invalid player"
	end

	-- Si ya está en un party, salir primero
	if playerParties[player] then
		PartyService.LeaveParty(player)
	end

	local partyId = generatePartyId()

	local party = {
		id = partyId,
		leader = player,
		members = { player },
		createdAt = tick(),
		currentLobbyId = nil,
	}

	parties[partyId] = party
	playerParties[player] = partyId

	print("🎉 [Party] Created party", partyId, "by", player.Name)

	-- Notificar al creador
	PartyService._fireEvent("PartyCreated", player, party)

	return party
end

-- Unirse a un party (usado internamente al aceptar invitación)
local function joinParty(player, partyId)
	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if #party.members >= CONFIG.MaxPartySize then
		return false, "Party is full"
	end

	-- Si está en otro party, salir
	if playerParties[player] then
		PartyService.LeaveParty(player)
	end

	table.insert(party.members, player)
	playerParties[player] = partyId

	print("➕ [Party]", player.Name, "joined party", partyId)

	-- Notificar a todos los miembros
	for _, member in ipairs(party.members) do
		PartyService._fireEvent("MemberJoined", member, party, player)
	end

	return true, party
end

-- Salir del party actual
function PartyService.LeaveParty(player)
	local partyId = playerParties[player]
	if not partyId then
		return false, "Not in a party"
	end

	local party = parties[partyId]
	if not party then
		playerParties[player] = nil
		return false, "Party not found"
	end

	-- Remover del party
	for i, member in ipairs(party.members) do
		if member == player then
			table.remove(party.members, i)
			break
		end
	end

	playerParties[player] = nil

	print("➖ [Party]", player.Name, "left party", partyId)

	-- Si era el leader, transferir o disolver
	if party.leader == player then
		if #party.members > 0 then
			-- Transferir liderazgo
			party.leader = party.members[1]
			print("👑 [Party] New leader:", party.leader.Name)

			for _, member in ipairs(party.members) do
				PartyService._fireEvent("LeaderChanged", member, party)
			end
		else
			-- Disolver party vacío
			PartyService.DisbandParty(partyId)
			return true
		end
	end

	-- Notificar al que se va
	PartyService._fireEvent("LeftParty", player, partyId)

	-- Notificar a los demás
	for _, member in ipairs(party.members) do
		PartyService._fireEvent("MemberLeft", member, party, player)
	end

	return true
end

-- Disolver un party completamente
function PartyService.DisbandParty(partyId)
	local party = parties[partyId]
	if not party then
		return false
	end

	-- Notificar y remover a todos
	for _, member in ipairs(party.members) do
		playerParties[member] = nil
		PartyService._fireEvent("PartyDisbanded", member, partyId)
	end

	parties[partyId] = nil
	print("💔 [Party] Disbanded party", partyId)

	return true
end

-- ============================================
-- SISTEMA DE INVITACIONES
-- ============================================

-- Invitar a un jugador por username
function PartyService.InviteByUsername(leader, username)
	local partyId = playerParties[leader]
	if not partyId then
		return false, "Create a party first"
	end

	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if party.leader ~= leader then
		return false, "Only leader can invite"
	end

	if #party.members >= CONFIG.MaxPartySize then
		return false, "Party is full"
	end

	-- Buscar jugador
	local targetPlayer = findPlayerByUsername(username)
	if not targetPlayer then
		return false, "Player not found: " .. username
	end

	if targetPlayer == leader then
		return false, "Cannot invite yourself"
	end

	-- Verificar si ya está en el party
	for _, member in ipairs(party.members) do
		if member == targetPlayer then
			return false, "Player is already in party"
		end
	end

	-- Verificar si ya está en otro party (opcional)
	if playerParties[targetPlayer] and not CONFIG.AllowStealInvites then
		return false, "Player is already in another party"
	end

	-- Crear invitación
	pendingInvites[targetPlayer] = {
		partyId = partyId,
		sentAt = tick(),
		fromPlayer = leader,
	}

	print("📨 [Party]", leader.Name, "invited", targetPlayer.Name, "to party", partyId)

	-- Notificar al invitado
	PartyService._fireEvent("InviteReceived", targetPlayer, {
		partyId = partyId,
		fromUsername = leader.Name,
		partySize = #party.members,
		maxSize = CONFIG.MaxPartySize,
	})

	-- Notificar al leader
	PartyService._fireEvent("InviteSent", leader, targetPlayer.Name)

	return true
end

-- Invitar a un jugador directamente (por Player)
function PartyService.InvitePlayer(leader, targetPlayer)
	if not targetPlayer or not targetPlayer.Parent then
		return false, "Invalid player"
	end
	return PartyService.InviteByUsername(leader, targetPlayer.Name)
end

-- Aceptar una invitación pendiente
function PartyService.AcceptInvite(player)
	local invite = pendingInvites[player]
	if not invite then
		return false, "No pending invite"
	end

	-- Verificar expiración
	if tick() - invite.sentAt > CONFIG.InviteExpiration then
		pendingInvites[player] = nil
		return false, "Invite expired"
	end

	local partyId = invite.partyId
	pendingInvites[player] = nil

	print("✅ [Party]", player.Name, "accepted invite to party", partyId)

	return joinParty(player, partyId)
end

-- Rechazar una invitación pendiente
function PartyService.DeclineInvite(player)
	local invite = pendingInvites[player]
	if not invite then
		return false, "No pending invite"
	end

	local fromPlayer = invite.fromPlayer
	pendingInvites[player] = nil

	print("❌ [Party]", player.Name, "declined invite")

	-- Notificar al que invitó
	if fromPlayer and fromPlayer.Parent then
		PartyService._fireEvent("InviteDeclined", fromPlayer, player.Name)
	end

	return true
end

-- Verificar si el jugador tiene invitación pendiente
function PartyService.HasPendingInvite(player)
	local invite = pendingInvites[player]
	if not invite then
		return false
	end

	-- Verificar expiración
	if tick() - invite.sentAt > CONFIG.InviteExpiration then
		pendingInvites[player] = nil
		return false
	end

	return true, invite
end

-- ============================================
-- CONTROL DE LEADER
-- ============================================

-- Transferir liderazgo a otro miembro
function PartyService.TransferLeadership(currentLeader, newLeader)
	local partyId = playerParties[currentLeader]
	if not partyId then
		return false, "Not in a party"
	end

	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if party.leader ~= currentLeader then
		return false, "Not the leader"
	end

	-- Verificar que el nuevo leader está en el party
	local found = false
	for _, member in ipairs(party.members) do
		if member == newLeader then
			found = true
			break
		end
	end

	if not found then
		return false, "Player not in party"
	end

	party.leader = newLeader
	print("👑 [Party] Leadership transferred to", newLeader.Name)

	for _, member in ipairs(party.members) do
		PartyService._fireEvent("LeaderChanged", member, party)
	end

	return true
end

-- Kickear un miembro del party (solo leader)
function PartyService.KickMember(leader, targetPlayer)
	local partyId = playerParties[leader]
	if not partyId then
		return false, "Not in a party"
	end

	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if party.leader ~= leader then
		return false, "Only leader can kick"
	end

	if targetPlayer == leader then
		return false, "Cannot kick yourself"
	end

	-- Verificar que el target está en el party
	local found = false
	for _, member in ipairs(party.members) do
		if member == targetPlayer then
			found = true
			break
		end
	end

	if not found then
		return false, "Player not in party"
	end

	print("🚫 [Party]", leader.Name, "kicked", targetPlayer.Name)

	-- Notificar al kickeado
	PartyService._fireEvent("Kicked", targetPlayer, partyId)

	-- Remover del party
	PartyService.LeaveParty(targetPlayer)

	return true
end

-- ============================================
-- INTEGRACIÓN CON LOBBIES
-- ============================================

-- Unir a todo el party a un lobby
function PartyService.JoinLobbyAsParty(leader, lobbyId)
	local partyId = playerParties[leader]
	if not partyId then
		return false, "Not in a party"
	end

	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if party.leader ~= leader then
		return false, "Only leader can join lobbies"
	end

	-- Intentar cargar LobbyManager
	local Modules = ReplicatedStorage:FindFirstChild("Modules")
	local Utilities = Modules and Modules:FindFirstChild("Utilities")
	local LobbyManager = Utilities and require(Utilities:FindFirstChild("LobbyManager"))

	if not LobbyManager then
		return false, "LobbyManager not available"
	end

	-- Unir a cada miembro al lobby
	local failures = {}
	for _, member in ipairs(party.members) do
		local success, result = LobbyManager.JoinLobby(member, lobbyId)
		if not success then
			table.insert(failures, { player = member.Name, reason = result })
		end
	end

	if #failures > 0 then
		return false, "Some members failed to join", failures
	end

	party.currentLobbyId = lobbyId

	return true
end

-- Crear un lobby para el party
function PartyService.CreateLobbyForParty(leader, mode, maxPlayers)
	local partyId = playerParties[leader]
	if not partyId then
		return false, "Not in a party"
	end

	local party = parties[partyId]
	if not party then
		return false, "Party not found"
	end

	if party.leader ~= leader then
		return false, "Only leader can create lobbies"
	end

	local Modules = ReplicatedStorage:FindFirstChild("Modules")
	local Utilities = Modules and Modules:FindFirstChild("Utilities")
	local LobbyManager = Utilities and require(Utilities:FindFirstChild("LobbyManager"))

	if not LobbyManager then
		return false, "LobbyManager not available"
	end

	-- Crear lobby
	local lobby = LobbyManager.CreateLobby(leader, mode, maxPlayers)
	if not lobby then
		return false, "Failed to create lobby"
	end

	-- Unir a los demás miembros
	for _, member in ipairs(party.members) do
		if member ~= leader then
			LobbyManager.JoinLobby(member, lobby.id)
		end
	end

	party.currentLobbyId = lobby.id

	return true, lobby
end

-- ============================================
-- CONSULTAS
-- ============================================

-- Obtener party de un jugador
function PartyService.GetPlayerParty(player)
	local partyId = playerParties[player]
	if partyId then
		return parties[partyId]
	end
	return nil
end

-- Obtener party por ID
function PartyService.GetParty(partyId)
	return parties[partyId]
end

-- Verificar si el jugador es leader de su party
function PartyService.IsLeader(player)
	local party = PartyService.GetPlayerParty(player)
	return party and party.leader == player
end

-- Obtener miembros del party como lista de nombres
function PartyService.GetMemberNames(player)
	local party = PartyService.GetPlayerParty(player)
	if not party then
		return {}
	end

	local names = {}
	for _, member in ipairs(party.members) do
		table.insert(names, member.Name)
	end
	return names
end

-- Obtener configuración
function PartyService.GetConfig()
	return {
		maxSize = CONFIG.MaxPartySize,
		inviteExpiration = CONFIG.InviteExpiration,
	}
end

-- ============================================
-- SISTEMA DE EVENTOS (REMOTES)
-- ============================================

-- Inicializa RemoteEvents
function PartyService._initRemotes()
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

	local eventNames = {
		"PartyCreated",
		"MemberJoined",
		"MemberLeft",
		"PartyDisbanded",
		"LeaderChanged",
		"LeftParty",
		"Kicked",
		"InviteReceived",
		"InviteSent",
		"InviteDeclined",
		"PartyUpdated",
	}

	PartyEvents = {}
	for _, name in ipairs(eventNames) do
		local eventName = "Party" .. name
		local event = eventsFolder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = eventsFolder
		end
		PartyEvents[name] = event
	end
end

-- Dispara un evento a un jugador
function PartyService._fireEvent(eventName, player, ...)
	if not PartyEvents then
		PartyService._initRemotes()
	end

	local event = PartyEvents[eventName]
	if event and player and player.Parent then
		event:FireClient(player, ...)
	end
end

-- ============================================
-- CLEANUP
-- ============================================

-- Limpieza cuando un jugador se desconecta
Players.PlayerRemoving:Connect(function(player)
	-- Limpiar invitaciones pendientes
	pendingInvites[player] = nil

	-- Salir del party
	if playerParties[player] then
		PartyService.LeaveParty(player)
	end
end)

-- Limpiar invitaciones expiradas periódicamente
task.spawn(function()
	while true do
		task.wait(30)
		local now = tick()
		for player, invite in pairs(pendingInvites) do
			if now - invite.sentAt > CONFIG.InviteExpiration then
				pendingInvites[player] = nil
			end
		end
	end
end)

-- Inicializar remotes al cargar
PartyService._initRemotes()

return PartyService
