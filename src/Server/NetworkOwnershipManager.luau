-- Server-only: gestiona transferencia temporal de NetworkOwnership durante reacciones de hit.
-- Patrón: servidor neutro → atacante → víctima (al finalizar la reacción completa).
-- SetNetworkOwner solo existe en el servidor, este módulo nunca debe requerirse desde el cliente.
local NetworkOwnershipManager = {}

-- Transfiere victimRoot al atacante durante hitstun/knockdown y la devuelve a la víctima al terminar.
-- hitResult debe contener HitstopFrames, HitstunDuration y Knockdown.
function NetworkOwnershipManager.TransferDuringReaction(victimRoot, attackerPlayer, victimPlayer, hitResult)
	local hitstunDuration = hitResult.HitstunDuration or 0.35
	local hitstopDuration = (hitResult.HitstopFrames or 0) / 60
	local knockdownExtra = hitResult.Knockdown and 1.2 or 0

	-- Paso 1: Servidor neutro para evitar conflicto entre propietarios
	pcall(function()
		victimRoot:SetNetworkOwner(nil)
	end)

	-- Paso 2: Atacante obtiene ownership para aplicar pushback con autoridad
	task.defer(function()
		pcall(function()
			victimRoot:SetNetworkOwner(attackerPlayer)
		end)
	end)

	-- Paso 3: Devolver ownership a la víctima al terminar la cadena de reacción
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

return NetworkOwnershipManager
