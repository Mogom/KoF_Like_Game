-- Server: Valida hits, aplica daño, gestiona NetworkOwnership y atributos de reacción
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")

local GameModeManager = require(Utilities:WaitForChild("GameModeManager"))

local ApplyDamageEvent = RemoteEvents:FindFirstChild("ApplyDamage")
if not ApplyDamageEvent then
	ApplyDamageEvent = Instance.new("RemoteEvent")
	ApplyDamageEvent.Name = "ApplyDamage"
	ApplyDamageEvent.Parent = RemoteEvents
end

-- Verifica si el modelo es un dummy de entrenamiento
local function isTrainingDummy(model)
	if not model or not model:IsA("Model") then
		return false
	end

	return model.Name == "Enemy" or model.Name == "TrainingDummy" or model:GetAttribute("IsTrainingDummy") == true
end

ApplyDamageEvent.OnServerEvent:Connect(function(attackerPlayer, victimCharacter, attackData)
	if not victimCharacter or not victimCharacter:IsA("Model") then
		warn("❌ Invalid victimCharacter")
		return
	end

	local victimHumanoid = victimCharacter:FindFirstChild("Humanoid")
	local victimRoot = victimCharacter:FindFirstChild("HumanoidRootPart")

	if not victimHumanoid or not victimRoot then
		warn("❌ Victim missing Humanoid or HumanoidRootPart:", victimCharacter.Name)
		return
	end

	local attackerCharacter = attackerPlayer.Character
	if not attackerCharacter then
		warn("❌ Attacker has no character:", attackerPlayer.Name)
		return
	end

	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then
		warn("❌ Attacker missing HumanoidRootPart:", attackerPlayer.Name)
		return
	end

	if type(attackData) ~= "table" then
		warn("❌ Invalid attackData type:", typeof(attackData))
		return
	end

	local damage = tonumber(attackData.Damage)
	if not damage then
		warn("❌ Invalid damage in attackData from", attackerPlayer.Name)
		return
	end

	-- Usar distancia en X solamente (es un juego 2D/2.5D, Z está lockeado)
	-- Tolerancia amplia: el dummy no tiene NetworkOwner así que su posición
	-- en el servidor puede estar desincronizada con el cliente.
	-- local distanceX = math.abs(attackerRoot.Position.X - victimRoot.Position.X)
	-- local distanceY = math.abs(attackerRoot.Position.Y - victimRoot.Position.Y)
	-- if distanceX > 40 or distanceY > 20 then
	-- 	warn("❌ Hit rejected: too far. DistX:", distanceX, "DistY:", distanceY)
	-- 	return
	-- end

	local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
	local expectedOpponent = GameModeManager.GetOpponent(attackerPlayer)

	if expectedOpponent and victimPlayer then
		if victimPlayer ~= expectedOpponent then
			warn("❌ Attacker tried to hit someone who's not their opponent")
			return
		end
	end

	if not victimPlayer and not isTrainingDummy(victimCharacter) then
		warn("❌ Victim is neither a player nor a valid training dummy")
		return
	end

	if victimCharacter:GetAttribute("IsRespawnInvulnerable") == true then
		return
	end

	victimHumanoid:TakeDamage(damage)

	local currentHitCounter = victimCharacter:GetAttribute("HitCounter") or 0
	victimCharacter:SetAttribute("HitCounter", currentHitCounter + 1)

	local hitResult = {
		Damage = damage,
		HitType = attackData.HitType or "Light",
		HitAnimation = attackData.HitAnimation or "HurtLight",
		HitstunDuration = attackData.HitstunDuration or 0.25,
		Pushback = attackData.Pushback or 0,
		HitstopFrames = attackData.HitstopFrames or 0,
		AttackHeight = attackData.AttackHeight or "Mid",
		BlockPushback = attackData.BlockPushback or 0,
		BlockstunDuration = attackData.BlockstunDuration or 0,
		ChipDamage = attackData.ChipDamage or 0,
		Knockdown = attackData.Knockdown or false,
		LaunchForce = attackData.LaunchForce or 0,
		AttackerPositionX = attackerRoot.Position.X,
		VictimPositionX = victimRoot.Position.X,
	}

	ApplyDamageEvent:FireClient(attackerPlayer, victimCharacter, hitResult)

	if victimPlayer then
		ApplyDamageEvent:FireClient(victimPlayer, victimCharacter, hitResult)
	end

	local currentHitResultId = victimCharacter:GetAttribute("HitResultId") or 0
	victimCharacter:SetAttribute("LastHitDamage", hitResult.Damage)
	victimCharacter:SetAttribute("LastHitType", hitResult.HitType)
	victimCharacter:SetAttribute("LastHitAnimation", hitResult.HitAnimation)
	victimCharacter:SetAttribute("LastHitstunDuration", hitResult.HitstunDuration)
	victimCharacter:SetAttribute("LastHitPushback", hitResult.Pushback)
	victimCharacter:SetAttribute("LastHitstopFrames", hitResult.HitstopFrames)
	victimCharacter:SetAttribute("LastAttackHeight", hitResult.AttackHeight)
	victimCharacter:SetAttribute("LastBlockPushback", hitResult.BlockPushback)
	victimCharacter:SetAttribute("LastBlockstunDuration", hitResult.BlockstunDuration)
	victimCharacter:SetAttribute("LastChipDamage", hitResult.ChipDamage)
	victimCharacter:SetAttribute("LastKnockdown", hitResult.Knockdown)
	victimCharacter:SetAttribute("LastLaunchForce", hitResult.LaunchForce)
	victimCharacter:SetAttribute("LastAttackerPositionX", hitResult.AttackerPositionX)
	victimCharacter:SetAttribute("LastVictimPositionX", hitResult.VictimPositionX)
	victimCharacter:SetAttribute("HitResultId", currentHitResultId + 1)

	-- Network ownership temporal: dar control al atacante durante la reacción.
	-- El motor de la víctima cede CFrame durante hitstun/knockdown/wakeup
	-- (solo lee root.Position.X para mantener currentX sincronizado).
	-- Al devolver ownership, currentX ya está sincronizado → sin rubber-banding.
	if victimPlayer then
		local hitstunDuration = hitResult.HitstunDuration or 0.35
		local hitstopDuration = (hitResult.HitstopFrames or 0) / 60
		local knockdownExtra = 0
		if hitResult.Knockdown then
			knockdownExtra = 1.2 -- knockdownDuration (0.8) + wakeupDuration (0.4)
		end

		-- Paso 1: Ownership al servidor (neutral)
		pcall(function()
			victimRoot:SetNetworkOwner(nil)
		end)

		-- Paso 2: Inmediatamente al atacante
		task.defer(function()
			pcall(function()
				victimRoot:SetNetworkOwner(attackerPlayer)
			end)
		end)

		-- Paso 3: Devolver a la víctima al finalizar la cadena de reacción.
		local totalReactionTime = hitstopDuration + hitstunDuration + knockdownExtra
		task.delay(totalReactionTime + 0.15, function()
			if victimRoot and victimRoot.Parent then
				pcall(function()
					if victimPlayer and victimPlayer.Parent then
						victimRoot:SetNetworkOwner(victimPlayer)
					else
						victimRoot:SetNetworkOwnershipAuto()
					end
				end)
			end
		end)
	end
end)
