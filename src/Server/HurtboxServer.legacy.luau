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

	print(
		"🔍 [Hurtbox] Setting up hurtbox for",
		character.Name,
		"| Parent:",
		character.Parent and character.Parent.Name or "nil"
	)

	-- Wait for character to be fully parented and initialized
	local maxWait = 5
	local elapsed = 0
	while not character.Parent and elapsed < maxWait do
		task.wait(0.1)
		elapsed = elapsed + 0.1
	end

	if not character.Parent then
		print("🔍 [Hurtbox] Character was destroyed before setup completed:", character.Name)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	-- Retry loop if components aren't ready yet
	local attempts = 0
	while (not humanoid or not root) and attempts < 50 and character.Parent do
		task.wait(0.1)
		attempts = attempts + 1
		if not humanoid then
			humanoid = character:FindFirstChildOfClass("Humanoid")
		end
		if not root then
			root = character:FindFirstChild("HumanoidRootPart")
		end
	end

	if not humanoid or not root then
		warn(
			"⚠️ Hurtbox skipped: missing Humanoid/HumanoidRootPart in",
			character.Name,
			"after",
			attempts * 0.1,
			"seconds"
		)
		print(
			"🔍 [Hurtbox] Character children:",
			table.concat(
				(function()
					local names = {}
					for _, child in ipairs(character:GetChildren()) do
						table.insert(names, child.Name)
					end
					return names
				end)(),
				", "
			)
		)
		return
	end

	Hurtbox.new(character)
	setCharacterCollisionGroup(character)
	print("🟩 Server hurtbox created for", character.Name)
end

-- Track characters we've already set up to avoid duplicates
local setupCharacters = {}

local function onCharacterAvailable(player, character)
	if not character or setupCharacters[character] then
		return
	end
	setupCharacters[character] = true
	setupCharacterHurtbox(character)

	-- Cleanup tracking when character is destroyed
	character.Destroying:Connect(function()
		setupCharacters[character] = nil
	end)
end

local function setupPlayerHooks(player)
	-- CharacterAdded for LoadCharacter() calls
	player.CharacterAdded:Connect(function(character)
		onCharacterAvailable(player, character)
	end)

	-- PropertyChanged for manual Character assignment (skin swaps)
	player:GetPropertyChangedSignal("Character"):Connect(function()
		local character = player.Character
		if character then
			-- Small delay to let the skin fully initialize
			task.defer(function()
				onCharacterAvailable(player, character)
			end)
		end
	end)

	-- Current character
	if player.Character then
		onCharacterAvailable(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayerHooks)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayerHooks(player)
end
