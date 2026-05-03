-- Registry centralizado para callbacks del sistema de control de personaje.
-- Reemplaza _G.LocalHitPrediction, _G.ForceResolveMovement y _G.GetCurrentController.
-- Cada cliente tiene su propia instancia (un VM por cliente en Roblox).
local ControllerRegistry = {}

local _hitPrediction = nil
local _forceResolveMovement = nil
local _activeController = nil

-- Registra el callback de predicción local de hit.
-- Llamado desde CharacterController al inicializar.
function ControllerRegistry.SetHitPrediction(fn)
	_hitPrediction = fn
	print("✅ [ControllerRegistry] HitPrediction registered")
end

-- Dispara la predicción local cuando una hitbox confirma un golpe.
-- Llamado desde Hitbox:Update().
function ControllerRegistry.TriggerHitPrediction(victimCharacter, attackData)
	if _hitPrediction then
		_hitPrediction(victimCharacter, attackData)
	end
end

-- Registra el callback para forzar re-evaluación del movimiento tras un estado bloqueante.
-- Llamado desde GameInputController al inicializar.
function ControllerRegistry.SetForceResolveMovement(fn)
	_forceResolveMovement = fn
	print("✅ [ControllerRegistry] ForceResolveMovement registered")
end

-- Fuerza re-evaluación del estado de teclas tras salir de hitstun/knockdown/ataque.
-- Llamado desde CombatController y CharacterMotor.
function ControllerRegistry.ForceResolveMovement()
	if _forceResolveMovement then
		_forceResolveMovement()
	end
end

-- Registra el controlador activo del jugador local.
-- Llamado desde GameInputController al crear un nuevo CharacterController.
function ControllerRegistry.SetActiveController(controller)
	_activeController = controller
end

-- Retorna el CharacterController activo del jugador local.
function ControllerRegistry.GetActiveController()
	return _activeController
end

return ControllerRegistry
