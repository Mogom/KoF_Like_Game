-- Server: Valida hits, aplica daño, gestiona NetworkOwnership y atributos de reacción
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")
local Characters = Modules:WaitForChild("Characters")
local Combat = Modules:WaitForChild("Combat")

local GameModeManager = require(Utilities:WaitForChild("GameModeManager"))
local NetworkOwnershipManager = require(script.Parent:WaitForChild("NetworkOwnershipManager"))
local CharacterRegistry = require(Characters:WaitForChild("CharacterRegistry"))
local DefaultAttacks = require(Combat:WaitForChild("Attacks"))

-- Resuelve los stats reales de un ataque desde el servidor (CharacterRegistry o fallback global)
local function resolveAttack(characterName, attackId)
	if characterName then
		local attacks = CharacterRegistry.GetAttacks(characterName)
		if attacks and attacks[attackId] then
			return attacks[attackId]
		end
	end
	return DefaultAttacks[attackId]
end

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

local function usesClassicHealth(character)
	if not character or not character:IsA("Model") then
		return false
	end

	local ownerPlayer = Players:GetPlayerFromCharacter(character)
	local mode = nil

	if ownerPlayer then
		mode = ownerPlayer:GetAttribute("GameMode") or GameModeManager.GetPlayerMode(ownerPlayer)
	end

	if not mode then
		mode = character:GetAttribute("GameMode")
	end

	return mode == "Classic"
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

	-- Validar AttackId: el cliente solo debe enviar el Id, el servidor resuelve los stats reales
	local attackId = attackData.Id
	if type(attackId) ~= "string" or attackId == "" then
		warn("❌ Missing or invalid AttackId from", attackerPlayer.Name)
		return
	end

	-- Resolver stats reales desde el servidor — nunca usar valores de daño del cliente
	local characterName = attackerCharacter:GetAttribute("AppliedCharacterName")
	local resolvedAttack = resolveAttack(characterName, attackId)
	if not resolvedAttack then
		warn("❌ Unknown AttackId:", attackId, "char:", tostring(characterName), "from", attackerPlayer.Name)
		return
	end

	-- Distance check: tolerancia generosa para el NetworkOwnership model (lag del atacante).
	-- Hitbox max reach ~8 studs + compensación de lag a 150ms a 20 studs/s = ~3 studs extra.
	-- 25 X cubre todos los ataques normales; 20 Y cubre saltos y ataques aéreos.
	local distanceX = math.abs(attackerRoot.Position.X - victimRoot.Position.X)
	local distanceY = math.abs(attackerRoot.Position.Y - victimRoot.Position.Y)
	if distanceX > 25 or distanceY > 20 then
		warn("❌ Hit rejected: too far. DistX:", distanceX, "DistY:", distanceY, "from", attackerPlayer.Name)
		return
	end

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

	-- Usar stats del servidor (valores del cliente ignorados)
	local damage = resolvedAttack.Damage
	local currentDamagePercent = victimCharacter:GetAttribute("DamagePercent") or 0
	local newDamagePercent = currentDamagePercent + damage
	victimCharacter:SetAttribute("DamagePercent", newDamagePercent)

	if usesClassicHealth(victimCharacter) then
		victimHumanoid:TakeDamage(damage)
	end

	local currentHitCounter = victimCharacter:GetAttribute("HitCounter") or 0
	victimCharacter:SetAttribute("HitCounter", currentHitCounter + 1)

	local hitResult = {
		Damage = damage,
		DamagePercent = newDamagePercent,
		HitType = resolvedAttack.HitType or "Light",
		HitAnimation = resolvedAttack.HitAnimation or "HurtLight",
		HitstunDuration = resolvedAttack.HitstunDuration or 0.25,
		Pushback = resolvedAttack.Pushback or 0,
		HitstopFrames = resolvedAttack.HitstopFrames or 0,
		AttackHeight = resolvedAttack.AttackHeight or "Mid",
		BlockPushback = resolvedAttack.BlockPushback or 0,
		BlockstunDuration = resolvedAttack.BlockstunDuration or 0,
		ChipDamage = resolvedAttack.ChipDamage or 0,
		Knockdown = resolvedAttack.Knockdown or false,
		LaunchForce = resolvedAttack.LaunchForce or 0,
		LaunchAngle = resolvedAttack.LaunchAngle or 0,
		BaseKnockback = resolvedAttack.BaseKnockback or 0,
		KnockbackGrowth = resolvedAttack.KnockbackGrowth or 0,
		AttackerPositionX = attackerRoot.Position.X,
		VictimPositionX = victimRoot.Position.X,
	}

	ApplyDamageEvent:FireClient(attackerPlayer, victimCharacter, hitResult)

	if victimPlayer then
		ApplyDamageEvent:FireClient(victimPlayer, victimCharacter, hitResult)
	end

	local currentHitResultId = victimCharacter:GetAttribute("HitResultId") or 0
	victimCharacter:SetAttribute("LastHitDamage", hitResult.Damage)
	victimCharacter:SetAttribute("LastDamagePercent", hitResult.DamagePercent)
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
	victimCharacter:SetAttribute("LastLaunchAngle", hitResult.LaunchAngle)
	victimCharacter:SetAttribute("LastBaseKnockback", hitResult.BaseKnockback)
	victimCharacter:SetAttribute("LastKnockbackGrowth", hitResult.KnockbackGrowth)
	victimCharacter:SetAttribute("LastAttackerPositionX", hitResult.AttackerPositionX)
	victimCharacter:SetAttribute("LastVictimPositionX", hitResult.VictimPositionX)
	victimCharacter:SetAttribute("HitResultId", currentHitResultId + 1)

	-- Network ownership temporal: atacante controla physics de la víctima durante la reacción.
	if victimPlayer then
		NetworkOwnershipManager.TransferDuringReaction(victimRoot, attackerPlayer, victimPlayer, hitResult)
	end
end)
