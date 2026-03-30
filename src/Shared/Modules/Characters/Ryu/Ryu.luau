--[[
	Ryu.luau — Personaje template #1
	----------------------------------
	Shoto clásico: equilibrado, buen fireball, dragon punch.
	
	LISTA DE ATAQUES Y CÓMO EJECUTARLOS:
	┌─────────────────┬────────────────────────────────┬──────────┐
	│ Ataque          │ Input (teclado)                │ Tipo     │
	├─────────────────┼────────────────────────────────┼──────────┤
	│ Punch           │ J                              │ Light    │
	│ HeavyPunch      │ K                              │ Heavy    │
	│ CrouchPunch     │ S + J  (agachado + puño)       │ Light    │
	│ CrouchHeavy     │ S + K  (agachado + pesado)     │ Heavy    │
	│ AirPunch        │ J (en el aire)                 │ Light    │
	│ AirHeavy        │ K (en el aire)                 │ Heavy    │
	│ Fireball        │ ↓ → J  (Down, Forward, Punch)  │ Special  │
	│ Uppercut        │ → ↓ → J (Fwd, Down, Fwd, Punch)│ Special │
	└─────────────────┴────────────────────────────────┴──────────┘
	
	TECLAS:
	  A/D = Back/Forward | S = Down | W/Space = Up/Jump
	  J / Click Izq = Punch | K / Click Der = HeavyPunch
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Characters = Modules:WaitForChild("Characters")
local BaseCharacter = require(Characters:WaitForChild("BaseCharacter"))

local Ryu = BaseCharacter.extend("Ryu")

-- ============================================
-- INFO
-- ============================================

Ryu.Info = {
	Name = "Ryu",
	Icon = "", -- Asignar rbxassetid cuando tengas el ícono
	Description = "Peleador equilibrado con proyectil y antiáereo.",
	Health = 100,
	WalkSpeed = 16,
	Weight = 1.0, -- Peso estándar
	GravityScale = 1.0, -- Gravedad normal
	Color = Color3.fromRGB(220, 220, 220), -- Color representativo (blanco)
}

-- ============================================
-- ATAQUES DE SUELO
-- ============================================

Ryu.Attacks = {}

-- Puño rápido (Standing Light)
Ryu.Attacks.Punch = {
	Id = "Punch",
	Startup = 4 / 60,
	Active = 4 / 60,
	Recovery = 10 / 60,
	AnimationBase = "Punch",
	SoundEffect = "Punch",
	SoundVolume = 0.7,
	HitType = "Light",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 10,
	HitstunDuration = 0.22,
	Pushback = 20,
	HitstopFrames = 40,
	BlockPushback = 6,
	BlockstunDuration = 0.15,
	ChipDamage = 0,
	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,
	CancelWindow = { Start = 8, End = 14 },
	Hitbox = {
		Size = Vector3.new(4, 5, 4),
		Offset = Vector3.new(0, 0, -2),
	},
	VFX = {
		Active = "Active",
	},
	VFX_Limbs = {"RightHand", "LeftHand", "RightFoot"}, 
}

-- Puño pesado con retroceso (Standing Heavy)
Ryu.Attacks.HeavyPunch = {
	Id = "HeavyPunch",
	Startup = 12 / 60,
	Active = 3 / 60,
	Recovery = 16 / 60,
	Animation = "HeavyPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.9,
	HitType = "Heavy",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 20,
	HitstunDuration = 0.4,
	Pushback = 5.5,
	HitstopFrames = 9,
	BlockPushback = 10,
	BlockstunDuration = 0.25,
	ChipDamage = 2,
	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,
	-- Retrocede al golpear
	AttackDash = true,
	DashDistance = -5,
	DashFrameStart = 2,
	DashDuration = 6,
	CancelWindow = { Start = 8, End = 14 },
	Hitbox = {
		Size = Vector3.new(4, 3, 5),
		Offset = Vector3.new(0, 0, -4),
	},
	VFX = {
		Startup = "Startup",
		Active = "Active",
		OnHit = "OnHit",
	},
	-- Para combos: cada golpe sucesivo usa la extremidad correspondiente
	-- Punch1 → puño derecho, Punch2 → puño izquierdo, Punch3 → patada derecha
	VFX_Limb = "RightHand",
}

-- ============================================
-- ATAQUES DE SUELO (AGACHADO)
-- ============================================

-- Puño agachado (Crouching Light)
Ryu.Attacks.CrouchPunch = {
	Id = "CrouchPunch",
	Startup = 5 / 60,
	Active = 3 / 60,
	Recovery = 10 / 60,
	Animation = "CrouchPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.6,
	HitType = "Light",
	HitAnimation = "HurtLight",
	AttackHeight = "Low",
	Damage = 8,
	HitstunDuration = 0.2,
	Pushback = 8,
	HitstopFrames = 4,
	BlockPushback = 5,
	BlockstunDuration = 0.12,
	ChipDamage = 0,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = nil,
	CancelWindow = { Start = 7, End = 13 },
	Hitbox = {
		Size = Vector3.new(4, 3, 4),
		Offset = Vector3.new(0, -1, -2),
	},
}

-- Barrida pesada (Crouching Heavy) — tumba
Ryu.Attacks.CrouchHeavy = {
	Id = "CrouchHeavy",
	Startup = 10 / 60,
	Active = 10 / 60,
	Recovery = 18 / 60,
	Animation = "CrouchHeavy",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Heavy",
	HitAnimation = "HurtLight",
	AttackHeight = "Low",
	Damage = 15,
	HitstunDuration = 0.35,
	Pushback = 6,
	HitstopFrames = 7,
	BlockPushback = 8,
	BlockstunDuration = 0.2,
	ChipDamage = 1,
	GroundOnly = true,
	Knockdown = true,
	LaunchForce = nil,
	AttackDash = true,
	DashDistance = 4,
	DashFrameStart = 3,
	DashDuration = 5,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(5, 3, 5),
		Offset = Vector3.new(0, -2, -3),
	},
	VFX = {
		Startup = "Startup",
		Active = "Active",
	},
	VFX_Limb = "RightFoot",
}

-- ============================================
-- ATAQUES AÉREOS
-- ============================================

Ryu.Attacks.AirPunch = {
	Id = "AirPunch",
	Startup = 3 / 60,
	Active = 5 / 60,
	Recovery = 8 / 60,
	Animation = "AirPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.6,
	HitType = "Light",
	HitAnimation = "AirHurt",
	AttackHeight = "High",
	Damage = 8,
	HitstunDuration = 0.2,
	Pushback = 4,
	HitstopFrames = 4,
	BlockPushback = 5,
	BlockstunDuration = 0.12,
	ChipDamage = 0,
	AirOk = true,
	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(4, 4, 4),
		Offset = Vector3.new(0, -1, -2),
	},
}

Ryu.Attacks.AirHeavy = {
	Id = "AirHeavy",
	Startup = 8 / 60,
	Active = 4 / 60,
	Recovery = 14 / 60,
	Animation = "AirHeavy",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Heavy",
	HitAnimation = "AirHurt",
	AttackHeight = "High",
	Damage = 15,
	HitstunDuration = 0.35,
	Pushback = 6,
	HitstopFrames = 7,
	BlockPushback = 8,
	BlockstunDuration = 0.2,
	ChipDamage = 1,
	AirOk = true,
	GroundOnly = false,
	Knockdown = true,
	LaunchForce = nil,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(5, 4, 5),
		Offset = Vector3.new(0, -2, -3),
	},
}

-- ============================================
-- MOVIMIENTOS ESPECIALES
-- ============================================

-- Hadouken — proyectil a distancia
-- Input: ↓ → J (Down, Forward, Punch)
Ryu.Attacks.Fireball = {
	Id = "Fireball",
	Startup = 15 / 60,
	Active = 30 / 60,
	Recovery = 12 / 60,
	Animation = "Fireball",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Special",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 12,
	HitstunDuration = 0.3,
	Pushback = 12,
	HitstopFrames = 6,
	BlockPushback = 8,
	BlockstunDuration = 0.2,
	ChipDamage = 3,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = nil,
	IsSpecial = true,
	IsProjectile = true,
	ProjectileSpeed = 40,
	ProjectileLifetime = 1.5,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(3, 3, 3),
		Offset = Vector3.new(0, 0, -3),
	},
}

-- Shoryuken — uppercut con salto, antiáereo
-- Input: → ↓ → J (Forward, Down, Forward, Punch)
Ryu.Attacks.Uppercut = {
	Id = "Uppercut",
	Startup = 6 / 60,
	Active = 6 / 60,
	Recovery = 20 / 60,
	Animation = "Uppercut",
	SoundEffect = "Punch",
	SoundVolume = 1.0,
	HitType = "Special",
	HitAnimation = "Launch",
	AttackHeight = "Mid",
	Damage = 18,
	HitstunDuration = 0.4,
	Pushback = 3,
	HitstopFrames = 10,
	BlockPushback = 12,
	BlockstunDuration = 0.3,
	ChipDamage = 2,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = 45,
	IsSpecial = true,
	AttackJump = true,
	JumpHeight = 40,
	JumpFrameStart = 3,
	-- AttackDash: avance rápido al inicio del shoryuken
	AttackDash = true,
	DashDistance = 3,
	DashFrameStart = 1,
	DashDuration = 4,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(4, 6, 4),
		Offset = Vector3.new(0, 1, -2),
	},
}

-- ============================================
-- COMANDOS (input → ataque)
-- Mayor prioridad = se evalúa primero
-- ============================================

Ryu.Commands = {
	-- Especiales (prioridad alta, requieren secuencia)
	{ Name = "Uppercut", Input = { "Forward", "Down", "Forward", "Punch" }, Priority = 15 },
	{ Name = "Fireball", Input = { "Down", "Forward", "Punch" }, Priority = 10 },

	-- Movimiento especial
	{ Name = "Dash", Input = { "Forward", "Forward" }, Priority = 5 },

	-- Normales (prioridad baja, un solo botón)
	{ Name = "Punch", Input = { "Punch" }, Priority = 1 },
	{ Name = "HeavyPunch", Input = { "HeavyPunch" }, Priority = 1 },
}

-- ============================================
-- SKINS
-- Nombre → rbxassetid del modelo (o "Dummy" para el modelo genérico)
-- ============================================

Ryu.Skins = {
	Default = "Dummy", -- Cambiar por rbxassetid cuando exista el modelo de Ryu
}

return Ryu
