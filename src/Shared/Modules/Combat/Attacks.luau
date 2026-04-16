-- Tabla GLOBAL de ataques (fallback). Los personajes definen sus propios ataques.
-- Ver Characters/Ryu.luau y Characters/Ken.luau para ataques por personaje.
local Attacks = {}

--[[
	AttackDash:
	- AttackDash = true     → El ataque tiene desplazamiento
	- DashDistance = 6       → Studs hacia adelante (positivo = al oponente, negativo = retroceder)
	- DashFrameStart = 2    → Frame del ataque donde empieza el dash
	- DashDuration = 4      → Cuántos frames dura el desplazamiento
	
	El dash se ejecuta HACIA ADELANTE (hacia el oponente).
	La distancia se reparte uniformemente entre los frames de duración.
]]

-- ============================================
-- ATAQUES DE SUELO (PARADO)
-- ============================================

Attacks.Punch = {
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
	LaunchAngle = 20,
	BaseKnockback = 6,
	KnockbackGrowth = 0.8,
	HitstopFrames = 40,
	BlockPushback = 6,
	BlockstunDuration = 0.15,
	ChipDamage = 0,

	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,

	CancelWindow = {
		Start = 8,
		End = 14,
	},

	Hitbox = {
		Size = Vector3.new(4, 5, 4),
		Offset = Vector3.new(0, 0, -2),
	},
}

Attacks.HeavyPunch = {
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
	LaunchAngle = 35,
	BaseKnockback = 10,
	KnockbackGrowth = 1.2,
	HitstopFrames = 9,
	BlockPushback = 10,
	BlockstunDuration = 0.25,
	ChipDamage = 2,

	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,

	-- Dash: avanza mientras golpea
	AttackDash = true,
	DashDistance = -5,
	DashFrameStart = 2,
	DashDuration = 6,

	CancelWindow = {
		Start = 8,
		End = 14,
	},

	Hitbox = {
		Size = Vector3.new(4, 3, 5),
		Offset = Vector3.new(0, 0, -4),
	},
}

-- ============================================
-- ATAQUES DE SUELO (AGACHADO)
-- ============================================

Attacks.CrouchPunch = {
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

	CancelWindow = {
		Start = 7,
		End = 13,
	},

	Hitbox = {
		Size = Vector3.new(4, 3, 4),
		Offset = Vector3.new(0, -1, -2),
	},
}

Attacks.CrouchHeavy = {
	Id = "CrouchHeavy",

	Startup = 10 / 60,
	Active = 4 / 60,
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

	-- Dash: sweep deslizante
	AttackDash = true,
	DashDistance = 4,
	DashFrameStart = 3,
	DashDuration = 5,

	CancelWindow = nil,

	Hitbox = {
		Size = Vector3.new(5, 3, 5),
		Offset = Vector3.new(0, -2, -3),
	},
}

-- ============================================
-- ATAQUES AÉREOS
-- ============================================

Attacks.AirPunch = {
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

Attacks.AirHeavy = {
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

Attacks.Fireball = {
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

	-- Propiedades de proyectil (para sistema futuro)
	IsProjectile = true,
	ProjectileSpeed = 40,
	ProjectileLifetime = 1.5,

	CancelWindow = nil,

	Hitbox = {
		Size = Vector3.new(3, 3, 3),
		Offset = Vector3.new(0, 0, -3),
	},
}

Attacks.Uppercut = {
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

	-- AttackJump: el personaje sube con el uppercut
	AttackJump = true,
	JumpHeight = 40,
	JumpFrameStart = 3,

	-- AttackDash: avance rápido al inicio del uppercut
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

return Attacks
