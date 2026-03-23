local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Hurtbox = require(Combat:WaitForChild("Hurtbox"))

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