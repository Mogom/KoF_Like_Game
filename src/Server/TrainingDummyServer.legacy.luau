-- Server: Inicializa training dummies con hurtbox y atributos
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

-- Da network ownership del dummy root al jugador para que la posición
-- se sincronice correctamente con el servidor (evita hit rejection por distancia).
local function giveOwnershipToPlayer(dummy, player)
	local root = dummy:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
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
	print("🤖 Server dummy hurtbox created for", dummy.Name)

	-- Asignar ownership al primer jugador disponible
	local firstPlayer = Players:GetPlayers()[1]
	if firstPlayer then
		giveOwnershipToPlayer(dummy, firstPlayer)
	else
		-- Esperar al primer jugador
		Players.PlayerAdded:Once(function(player)
			giveOwnershipToPlayer(dummy, player)
		end)
	end
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
