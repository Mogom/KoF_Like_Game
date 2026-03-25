-- Cliente: inicializa DummyController cuando se detecta un dummy en workspace
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DummyController = require(Combat:WaitForChild("DummyController"))

local player = Players.LocalPlayer

-- Intenta crear DummyController para el dummy existente (solo en Training)
local function tryInitializeDummy()
	if player:GetAttribute("GameMode") == "Versus" then
		return
	end

	local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
	if not dummy then
		return
	end

	if dummy:GetAttribute("DummyInitializedClient") then
		return
	end

	local humanoid = dummy:FindFirstChild("Humanoid")
	if not humanoid then
		warn("❌ Dummy no tiene Humanoid")
		return
	end

	dummy:SetAttribute("DummyInitializedClient", true)

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	-- Leer personaje seleccionado para el dummy
	local dummyCharName = player:GetAttribute("SelectedDummyCharacter")

	DummyController.new(dummy, dummyCharName)

	print("✅ Training Dummy initialized! Character:", dummyCharName or "default")
end

task.delay(1, tryInitializeDummy)

workspace.ChildAdded:Connect(function(child)
	if child.Name == "Enemy" or child.Name == "TrainingDummy" then
		task.delay(0.5, tryInitializeDummy)
	end
end)

player:GetAttributeChangedSignal("GameMode"):Connect(function()
	if player:GetAttribute("GameMode") ~= "Versus" then
		task.delay(0.5, tryInitializeDummy)
	end
end)
