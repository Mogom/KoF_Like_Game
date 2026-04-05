-- Server: Inicializa training dummies con hurtbox y atributos
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

-- =============================================
-- 🛡️ COLLISION GROUP (mismo que HurtboxServer)
-- =============================================
local CHARACTER_GROUP = "Characters"

-- Registrar solo si no existe (HurtboxServer puede cargar primero)
pcall(function()
	PhysicsService:RegisterCollisionGroup(CHARACTER_GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(CHARACTER_GROUP, CHARACTER_GROUP, false)
end)

local function setCharacterCollisionGroup(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = CHARACTER_GROUP
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = CHARACTER_GROUP
		end
	end)
end

local function keepDummyServerOwned(dummy)
	for _, part in ipairs(dummy:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end
end

-- Configura un dummy: marca como training dummy y crea su hurtbox
local function setupDummy(dummy)
	if not dummy or not dummy:IsA("Model") then
		return
	end

	local humanoid = dummy:FindFirstChild("Humanoid")
	local root = dummy:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		return
	end

	dummy:SetAttribute("IsTrainingDummy", true)
	dummy:SetAttribute("HitCounter", dummy:GetAttribute("HitCounter") or 0)

	Hurtbox.new(dummy)
	setCharacterCollisionGroup(dummy)
	keepDummyServerOwned(dummy)
	print("🤖 Server dummy hurtbox created for", dummy.Name)
end

local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
if dummy then
	setupDummy(dummy)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Enemy" or child.Name == "TrainingDummy" then
		task.wait(0.2)
		setupDummy(child)
	end
end)
