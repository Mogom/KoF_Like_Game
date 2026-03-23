--[[
	HitstopService.lua
	-------------------
	Sistema de Hitstop (hitfreeze) para juegos de pelea.
	
	Congela al atacante y a la víctima por X frames al momento del impacto.
	Pausa animaciones, movimiento, pushback y timers.
	
	Uso:
		HitstopService:Apply(hitstopFrames)
	
	Desde cualquier módulo se puede consultar:
		HitstopService:IsInHitstop() → bool
	
	El motor, combat controller y dummy verifican esto para pausar su lógica.
]]

local RunService = game:GetService("RunService")

local HitstopService = {}
HitstopService.__index = HitstopService

-- Estado global del hitstop (uno por cliente)
local isActive = false
local remainingFrames = 0
local frozenAnimations = {} -- {track, speed} para restaurar velocidad
local onCompleteCallbacks = {}

--[[
	Aplicar hitstop.
	
	@param frames: número de frames de congelamiento (a 60fps, 6 frames = 100ms)
	@param animationsToFreeze: tabla opcional de AnimationTracks a pausar
	@param onComplete: callback opcional que se ejecuta al terminar el hitstop
]]
-- Aplica hitstop: congela animaciones por N frames, ejecuta callback al terminar
function HitstopService:Apply(frames, animationsToFreeze, onComplete)
	if not frames or frames <= 0 then
		return
	end

	-- Si ya estamos en hitstop, extender si el nuevo es mayor
	if isActive then
		if frames > remainingFrames then
			remainingFrames = frames
		end

		-- Agregar nuevas animaciones a congelar si las hay
		if animationsToFreeze then
			for _, track in ipairs(animationsToFreeze) do
				if track and track.IsPlaying then
					table.insert(frozenAnimations, {
						track = track,
						originalSpeed = track.Speed,
					})
					track:AdjustSpeed(0)
				end
			end
		end

		if onComplete then
			table.insert(onCompleteCallbacks, onComplete)
		end

		return
	end

	isActive = true
	remainingFrames = frames
	frozenAnimations = {}
	onCompleteCallbacks = {}

	-- Congelar animaciones proporcionadas
	if animationsToFreeze then
		for _, track in ipairs(animationsToFreeze) do
			if track and track.IsPlaying then
				table.insert(frozenAnimations, {
					track = track,
					originalSpeed = track.Speed,
				})
				track:AdjustSpeed(0)
			end
		end
	end

	if onComplete then
		table.insert(onCompleteCallbacks, onComplete)
	end
end

--[[
	¿Estamos en hitstop ahora mismo?
]]
-- Retorna true si hay un hitstop activo
function HitstopService:IsInHitstop()
	return isActive
end

--[[
	Obtener frames restantes (útil para debug)
]]
function HitstopService:GetRemainingFrames()
	return remainingFrames
end

--[[
	Forzar fin del hitstop (para casos especiales)
]]
function HitstopService:ForceEnd()
	if not isActive then
		return
	end

	self:_finish()
end

--[[
	Terminar hitstop: restaurar animaciones y ejecutar callbacks
]]
function HitstopService:_finish()
	isActive = false
	remainingFrames = 0

	-- Restaurar velocidad de animaciones congeladas
	for _, data in ipairs(frozenAnimations) do
		if data.track and data.track.IsPlaying then
			data.track:AdjustSpeed(data.originalSpeed)
		end
	end
	frozenAnimations = {}

	-- Ejecutar callbacks de completado
	local callbacks = onCompleteCallbacks
	onCompleteCallbacks = {}

	for _, cb in ipairs(callbacks) do
		local ok, err = pcall(cb)
		if not ok then
			warn("⚠️ HitstopService onComplete error:", err)
		end
	end
end

-- ============================================
-- LOOP: Decrementar frames cada RenderStepped
-- ============================================
-- Usamos RenderStepped para que sea frame-perfect
-- (independiente de dt, como en fighters reales)
RunService.RenderStepped:Connect(function()
	if not isActive then
		return
	end

	remainingFrames = remainingFrames - 1

	if remainingFrames <= 0 then
		HitstopService:_finish()
	end
end)

return HitstopService
