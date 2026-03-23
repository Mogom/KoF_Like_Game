-- Server: Inicializa training dummies con hurtbox y atributos
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

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
