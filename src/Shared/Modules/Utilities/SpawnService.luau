-- Lógica centralizada de spawn: bounds del mapa, posiciones de jugadores/equipos, teleport.
-- Compartido por GameModeManager, LobbyManager y BlastZoneService.
local Players = game:GetService("Players")

local SpawnService = {}

local CONFIG = {
	BaseDistance = 8,
	SpawnHeight = 3,
	MapWidthUsage = 0.8,
	DefaultMap = "Map0",
}

-- Retorna el centro (Position) y tamaño (Size) del BasePlate del mapa indicado.
function SpawnService.GetMapBounds(mapName)
	mapName = mapName or CONFIG.DefaultMap

	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		warn("⚠️ [SpawnService] Maps folder not found — create workspace/Maps/" .. mapName .. "/BasePlate")
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	local mapFolder = maps:FindFirstChild(mapName)
	if not mapFolder then
		warn("⚠️ [SpawnService] Map not found:", mapName)
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	local basePlate = mapFolder:FindFirstChild("BasePlate")
	if not basePlate then
		warn("⚠️ [SpawnService] BasePlate not found in map:", mapName)
		return Vector3.new(0, 5, 0), Vector3.new(100, 1, 100)
	end

	return basePlate.Position, basePlate.Size
end

-- Distribuye N jugadores horizontalmente desde el centro del mapa. Eje Z fijo (juego 2D).
function SpawnService.CalculateSpawnPositions(playerCount, mapName)
	local center, size = SpawnService.GetMapBounds(mapName)
	local fixedZ = center.Z
	local spawnY = center.Y + (size.Y / 2) + CONFIG.SpawnHeight

	local totalWidth = CONFIG.BaseDistance * (playerCount - 1)
	local maxWidth = size.X * CONFIG.MapWidthUsage
	if totalWidth > maxWidth then
		totalWidth = maxWidth
	end

	local startX = center.X - (totalWidth / 2)
	local spacing = playerCount > 1 and (totalWidth / (playerCount - 1)) or 0

	local positions = {}
	for i = 1, playerCount do
		positions[i] = Vector3.new(startX + spacing * (i - 1), spawnY, fixedZ)
	end

	return positions
end

-- Posiciones de spawn para dos equipos (equipo 1 a la izquierda, equipo 2 a la derecha).
function SpawnService.CalculateTeamSpawnPositions(team1Count, team2Count, mapName)
	local center, size = SpawnService.GetMapBounds(mapName)
	local fixedZ = center.Z
	local spawnY = center.Y + (size.Y / 2) + CONFIG.SpawnHeight

	local positions = { team1 = {}, team2 = {} }

	local team1StartX = center.X - (size.X * 0.3)
	for i = 1, team1Count do
		positions.team1[i] = Vector3.new(team1StartX - (i - 1) * CONFIG.BaseDistance, spawnY, fixedZ)
	end

	local team2StartX = center.X + (size.X * 0.3)
	for i = 1, team2Count do
		positions.team2[i] = Vector3.new(team2StartX + (i - 1) * CONFIG.BaseDistance, spawnY, fixedZ)
	end

	return positions
end

-- Replica la posición de spawn a través de atributos para sincronización cliente/servidor.
function SpawnService.SetReplicatedSpawnState(character, position, facingRight)
	if not character then return end
	character:SetAttribute("ReplicatedSpawnX", position.X)
	character:SetAttribute("ReplicatedSpawnY", position.Y)
	character:SetAttribute("ReplicatedSpawnZ", position.Z)
	character:SetAttribute("ReplicatedSpawnFacingRight", facingRight == true)
	character:SetAttribute("ReplicatedSpawnVersion", os.clock())
end

-- Teleporta un character/dummy a position con la rotación indicada.
-- SetNetworkOwner solo está disponible en el servidor — no llamar desde el cliente.
function SpawnService.MoveCharacterToPosition(character, position, facingRight, isDummy)
	if not character then
		warn("⚠️ [SpawnService] No character provided to MoveCharacterToPosition")
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", 5)
	if not root then
		warn("⚠️ [SpawnService] HumanoidRootPart not found in", character.Name)
		return false
	end

	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end
	elseif root.Anchored then
		root.Anchored = false
	end

	pcall(function() root:SetNetworkOwner(nil) end)

	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and not part.Anchored then
				pcall(function() part:SetNetworkOwner(nil) end)
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	local rotation = facingRight and math.rad(-90) or math.rad(90)
	local targetCFrame = CFrame.new(position) * CFrame.Angles(0, rotation, 0)

	SpawnService.SetReplicatedSpawnState(character, position, facingRight)
	character:PivotTo(targetCFrame)
	root.CFrame = targetCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	if isDummy then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end

	if not isDummy then
		task.defer(function()
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				pcall(function() root:SetNetworkOwner(player) end)
			end
		end)
	end

	return true
end

return SpawnService
