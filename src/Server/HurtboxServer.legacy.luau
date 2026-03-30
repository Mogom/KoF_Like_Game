-- Server: Crea hurtboxes para todos los jugadores al spawnear
-- y configura collision groups para que los personajes no colisionen entre sí
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

-- =============================================
-- 🛡️ COLLISION GROUPS: Personajes no colisionan entre sí
-- =============================================
local CHARACTER_GROUP = "Characters"

PhysicsService:RegisterCollisionGroup(CHARACTER_GROUP)
PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)

-- Asigna todas las BaseParts del personaje al grupo "Characters"
local function setCharacterCollisionGroup(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = CHARACTER_GROUP
		end
	end
	-- Partes que se agreguen después (hurtbox, accesorios, etc.)
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = CHARACTER_GROUP
		end
	end)
end

-- Crea una hurtbox para el personaje dado
local function setupCharacterHurtbox(character)
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		character:WaitForChild("Humanoid")
		character:WaitForChild("HumanoidRootPart")
	end

	Hurtbox.new(character)
	setCharacterCollisionGroup(character)
	print("🟩 Server hurtbox created for", character.Name)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacterHurtbox(character)
	end)

	if player.Character then
		setupCharacterHurtbox(player.Character)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupCharacterHurtbox(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		setupCharacterHurtbox(character)
	end)
end
