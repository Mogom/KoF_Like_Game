--[[
	BaseCharacter.luau
	-------------------
	Clase padre de todos los personajes del juego.
	Cada personaje hereda de esta clase y define sus propios ataques y comandos.

	CÓMO CREAR UN PERSONAJE NUEVO:
	1. Crea un archivo "NombrePersonaje.luau" en esta carpeta
	2. Usa BaseCharacter como clase padre:
	      local Base = require(script.Parent:WaitForChild("BaseCharacter"))
	      local MiPersonaje = Base.extend("MiPersonaje")
	3. Define Info (nombre, ícono, stats)
	4. Define Attacks (tabla de ataques con todos los datos de frame/hitbox)
	5. Define Commands (secuencias de input → nombre de ataque, con prioridad)
	6. Retorna el personaje con return MiPersonaje

	ESTRUCTURA DE UN PERSONAJE:
	  .Info     → { Name, Icon, Health, WalkSpeed, Description }
	  .Attacks  → { Punch = {...}, HeavyPunch = {...}, ... }
	  .Commands → { { Name, Input, Priority }, ... }

	ESTRUCTURA DE UN ATAQUE (dentro de .Attacks):
	  {
	    Id              = "Punch",              -- Identificador único
	    Startup         = 4 / 60,              -- Frames de inicio (en segundos)
	    Active          = 4 / 60,              -- Frames activos
	    Recovery        = 10 / 60,             -- Frames de recuperación
	    AnimationBase   = "Punch",             -- Nombre de la animación (o Animation)
	    SoundEffect     = "Punch",             -- Sonido al golpear
	    SoundVolume     = 0.7,                 -- Volumen del sonido
	    HitType         = "Light",             -- Light / Heavy / Special
	    HitAnimation    = "HurtLight",         -- Animación de reacción en la víctima
	    AttackHeight    = "Mid",               -- High / Mid / Low
	    Damage          = 10,                  -- Daño
	    HitstunDuration = 0.22,                -- Segundos de hitstun
	    Pushback        = 20,                  -- Fuerza de empuje
	    HitstopFrames   = 40,                  -- Frames de congelamiento
	    BlockPushback   = 6,                   -- Empuje al bloquear
	    BlockstunDuration = 0.15,              -- Tiempo de blockstun
	    ChipDamage      = 0,                   -- Daño al bloquear
	    GroundOnly      = false,               -- Solo se puede usar en suelo
	    AirOk           = false,               -- Se puede usar en el aire
	    Knockdown       = false,               -- Tumba al oponente
	    LaunchForce     = nil,                 -- Fuerza de lanzamiento (nil = no lanza)
	    IsSpecial       = false,               -- Es un movimiento especial
	    -- Dash durante ataque (opcional):
	    AttackDash      = false,               -- Activa desplazamiento
	    DashDistance     = 0,                   -- Studs (positivo = adelante, negativo = atrás)
	    DashFrameStart  = 1,                   -- Frame donde comienza
	    DashDuration    = 4,                   -- Frames que dura
	    -- Salto durante ataque (opcional):
	    AttackJump      = false,
	    JumpHeight      = 0,
	    JumpFrameStart  = 1,
	    -- Cancel window (opcional):
	    CancelWindow    = nil,                 -- { Start = N, End = N } o nil
	    -- VFX de swing (opcional, se reproduce al INICIAR el ataque, NO requiere conectar):
	    VFX_Name        = nil,                 -- Nombre del VFX registrado en VFXService
	    -- VFX de impacto (opcional, se reproduce SOLO al conectar):
	    AttackVFX       = nil,                 -- { Type = "FireHand", Color, CoreColor, Size, ... }
	    -- Hitbox:
	    Hitbox = {
	      Size   = Vector3.new(4, 5, 4),
	      Offset = Vector3.new(0, 0, -2),
	    },
	  }

	ESTRUCTURA DE UN COMANDO (dentro de .Commands):
	  {
	    Name     = "Punch",                            -- Nombre del ataque a ejecutar
	    Input    = { "Punch" },                        -- Secuencia de inputs requerida
	    Priority = 1,                                  -- Mayor = se evalúa primero
	  }

	  INPUTS VÁLIDOS:
	    Direcciones: "Forward", "Back", "Down", "Up"
	    Ataques:     "Punch", "HeavyPunch"

	  EJEMPLOS DE SECUENCIAS:
	    { "Punch" }                               → Golpe simple
	    { "Down", "Forward", "Punch" }            → Cuarto de círculo + puño (Fireball)
	    { "Forward", "Down", "Forward", "Punch" } → Doble cuarto de círculo (Dragon Punch)
]]

local BaseCharacter = {}
BaseCharacter.__index = BaseCharacter

-- Info por defecto (sobreescribir en cada personaje)
BaseCharacter.Info = {
	Name = "Base",
	Icon = "",
	Description = "Personaje base",
	Health = 100,
	WalkSpeed = 16,
}

BaseCharacter.Attacks = {}
BaseCharacter.Commands = {}

-- Skins disponibles: { SkinName = "rbxassetid://...", ... }
-- La primera es la default. Si no existe la skin, se usa "Dummy" como fallback.
BaseCharacter.Skins = {}

-- Crea una subclase de BaseCharacter con un nombre dado
function BaseCharacter.extend(name)
	local Character = {}
	Character.__index = Character
	setmetatable(Character, { __index = BaseCharacter })

	Character.Info = {
		Name = name,
		Icon = "",
		Description = "",
		Health = 100,
		WalkSpeed = 16,
	}
	Character.Attacks = {}
	Character.Commands = {}
	Character.Skins = {}

	return Character
end

-- Retorna el ataque por Id
function BaseCharacter:GetAttack(attackId)
	return self.Attacks[attackId]
end

-- Retorna la lista de comandos ordenada por prioridad (mayor primero)
function BaseCharacter:GetSortedCommands()
	local sorted = table.clone(self.Commands)
	table.sort(sorted, function(a, b)
		return a.Priority > b.Priority
	end)
	return sorted
end

-- Retorna todos los ataques como tabla plana
function BaseCharacter:GetAllAttacks()
	return self.Attacks
end

-- Retorna la carpeta de animaciones del personaje (Characters/<Name>/Animations/Test)
function BaseCharacter:GetAnimationsFolder()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Modules = ReplicatedStorage:WaitForChild("Modules")
	local Characters = Modules:WaitForChild("Characters")
	local charFolder = Characters:FindFirstChild(self.Info.Name)
	if charFolder then
		local anims = charFolder:FindFirstChild("Animations")
		if anims then
			return anims:FindFirstChild("Test")
		end
	end
	return nil
end

-- Retorna la skin activa del personaje. Si no tiene, usa fallback "Dummy".
-- skinName: nombre de la skin deseada (nil = "Default")
function BaseCharacter:GetSkin(skinName)
	skinName = skinName or "Default"
	local skin = self.Skins[skinName]
	if skin then
		return skin
	end
	-- Fallback: intentar Default
	if skinName ~= "Default" and self.Skins["Default"] then
		return self.Skins["Default"]
	end
	-- Fallback final: Dummy skin (modelo genérico del workspace)
	return "Dummy"
end

return BaseCharacter
