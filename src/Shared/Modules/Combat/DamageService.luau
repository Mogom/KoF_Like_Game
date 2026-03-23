local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local ApplyDamageEvent = RemoteEvents:WaitForChild("ApplyDamage")

local DamageService = {}

function DamageService.ApplyHit(attackerCharacter, victimCharacter, attackData)
	if not attackerCharacter or not victimCharacter or not attackData then
		warn("❌ DamageService.ApplyHit invalid args")
		return false
	end

	print("📤 FireServer ApplyDamage:", attackerCharacter.Name, "=>", victimCharacter.Name)

	ApplyDamageEvent:FireServer(victimCharacter, attackData)
	return true
end

ApplyDamageEvent.OnClientEvent:Connect(function(victimCharacter, damage, hitType)
	print("📩 ApplyDamageEvent.OnClientEvent:", victimCharacter and victimCharacter.Name, damage, hitType)
end)

return DamageService