-- Reproductor de sonidos posicionales via clones de Sound
local SoundManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Sounds = Modules:WaitForChild("Sounds")

-- ✅ Tabla de sonidos
local SoundLibrary = {
	Punch = Sounds:WaitForChild("Punch"),
	Punch2 = Sounds:WaitForChild("Punch"),
	Punch3 = Sounds:WaitForChild("Punch"),
	HeavyPunch = Sounds:WaitForChild("Punch"),
}

-- ✅ Función para reproducir sonido
-- Reproduce un sonido posicional clonando el Sound base
function SoundManager.PlaySound(soundName, position, volume)
	volume = volume or 1.0 -- Volumen por defecto

	if not SoundLibrary[soundName] then
		warn("❌ Sonido no encontrado:", soundName)
		return
	end

	-- ✅ Crea una copia del sonido para que se reproduzca simultáneamente
	local sound = SoundLibrary[soundName]:Clone()
	sound.Volume = volume
	sound.Parent = workspace

	-- ✅ Posiciona el sonido en la ubicación del personaje
	if position then
		sound.PlayOnRemove = false
		local part = Instance.new("Part")
		part.CanCollide = false
		part.Transparency = 1
		part.Position = position
		part.Parent = workspace
		sound.Parent = part
	end

	-- ✅ Reproduce el sonido
	sound:Play()

	-- ✅ Elimina después de que termine
	game:GetService("Debris"):AddItem(sound.Parent or sound, sound.TimeLength + 0.1)

	--print("🔊 Reproducing sound:", soundName)
end

return SoundManager
