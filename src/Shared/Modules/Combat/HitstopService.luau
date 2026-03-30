--[[
	HitstopService.lua
	-------------------
	Sistema de Hitstop (hitfreeze) per-character para juegos de pelea.
	
	Congela SOLO al atacante y a la víctima por X frames al momento del impacto.
	Los demás personajes siguen moviéndose normalmente (compatible con 4v4).
	
	Uso:
		HitstopService:Apply(character, hitstopFrames, animsToFreeze, onComplete)
	
	Desde cualquier módulo se puede consultar:
		HitstopService:IsInHitstop(character) → bool
	
	El motor, combat controller y dummy verifican esto para pausar su lógica.
]]

local RunService = game:GetService("RunService")

local HitstopService = {}
HitstopService.__index = HitstopService

-- Tabla de hitstops activos por personaje: { [character] = { remainingFrames, frozenAnimations, onCompleteCallbacks } }
local activeHitstops = {}

--[[
	Aplicar hitstop a un personaje específico.
	
	@param character: Model del personaje a congelar
	@param frames: número de frames de congelamiento (a 60fps, 6 frames = 100ms)
	@param animationsToFreeze: tabla opcional de AnimationTracks a pausar
	@param onComplete: callback opcional que se ejecuta al terminar el hitstop
]]
function HitstopService:Apply(character, frames, animationsToFreeze, onComplete)
	if not character or not frames or frames <= 0 then
		return
	end

	local existing = activeHitstops[character]

	if existing then
		-- Si ya está en hitstop, extender si el nuevo es mayor
		if frames > existing.remainingFrames then
			existing.remainingFrames = frames
		end

		-- Agregar nuevas animaciones a congelar
		if animationsToFreeze then
			for _, track in ipairs(animationsToFreeze) do
				if track and track.IsPlaying then
					table.insert(existing.frozenAnimations, {
						track = track,
						originalSpeed = track.Speed,
					})
					track:AdjustSpeed(0)
				end
			end
		end

		if onComplete then
			table.insert(existing.onCompleteCallbacks, onComplete)
		end

		return
	end

	-- Nuevo hitstop para este personaje
	local hitstopData = {
		remainingFrames = frames,
		frozenAnimations = {},
		onCompleteCallbacks = {},
	}

	-- Congelar animaciones proporcionadas
	if animationsToFreeze then
		for _, track in ipairs(animationsToFreeze) do
			if track and track.IsPlaying then
				table.insert(hitstopData.frozenAnimations, {
					track = track,
					originalSpeed = track.Speed,
				})
				track:AdjustSpeed(0)
			end
		end
	end

	if onComplete then
		table.insert(hitstopData.onCompleteCallbacks, onComplete)
	end

	activeHitstops[character] = hitstopData
end

--[[
	¿Este personaje está en hitstop ahora mismo?
	Si no se pasa character, retorna true si CUALQUIER hitstop está activo (compat legacy).
]]
function HitstopService:IsInHitstop(character)
	if character then
		return activeHitstops[character] ~= nil
	end
	-- Legacy: retorna true si hay cualquier hitstop activo
	return next(activeHitstops) ~= nil
end

--[[
	Obtener frames restantes para un personaje (útil para debug)
]]
function HitstopService:GetRemainingFrames(character)
	if character and activeHitstops[character] then
		return activeHitstops[character].remainingFrames
	end
	return 0
end

--[[
	Forzar fin del hitstop para un personaje específico
]]
function HitstopService:ForceEnd(character)
	if character and activeHitstops[character] then
		self:_finishCharacter(character)
	end
end

--[[
	Terminar hitstop de un personaje: restaurar animaciones y ejecutar callbacks
]]
function HitstopService:_finishCharacter(character)
	local data = activeHitstops[character]
	if not data then
		return
	end

	activeHitstops[character] = nil

	-- Restaurar velocidad de animaciones congeladas
	for _, animData in ipairs(data.frozenAnimations) do
		if animData.track and animData.track.IsPlaying then
			animData.track:AdjustSpeed(animData.originalSpeed)
		end
	end

	-- Ejecutar callbacks de completado
	for _, cb in ipairs(data.onCompleteCallbacks) do
		local ok, err = pcall(cb)
		if not ok then
			warn("⚠️ HitstopService onComplete error:", err)
		end
	end
end

-- ============================================
-- LOOP: Decrementar frames cada RenderStepped per-character
-- ============================================
RunService.RenderStepped:Connect(function()
	for character, data in pairs(activeHitstops) do
		data.remainingFrames = data.remainingFrames - 1

		if data.remainingFrames <= 0 then
			HitstopService:_finishCharacter(character)
		end
	end
end)

return HitstopService
