--[[
	Ken.luau — Personaje template #2
	----------------------------------
	Rushdown agresivo: más rápido, dash ofensivo, menos vida.
	
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
	│ Uppercut        │ → ↓ → J (Fwd, Down, Fwd, Punch)│ Special  │
	└─────────────────┴────────────────────────────────┴──────────┘
	
	DIFERENCIAS CON RYU:
	- Más velocidad (WalkSpeed 19 vs 16)
	- Menos salud (90 vs 100)
	- HeavyPunch avanza (dash positivo) en vez de retroceder
	- Uppercut hace más daño pero más recovery
	- Fireball más lenta pero más daño
	
	TECLAS:
	  A/D = Back/Forward | S = Down | W/Space = Up/Jump
	  J / Click Izq = Punch | K / Click Der = HeavyPunch
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Characters = Modules:WaitForChild("Characters")
local BaseCharacter = require(Characters:WaitForChild("BaseCharacter"))

local Ken = BaseCharacter.extend("Ken")

-- ============================================
-- INFO
-- ============================================

Ken.Info = {
	Name = "Ken",
	Icon = "",
	Description = "Rushdown agresivo, rápido y ofensivo.",
	Health = 90,
	WalkSpeed = 19,
	Weight = 0.9, -- Ligero: vuela más lejos al ser lanzado, cae un poco más lento
	GravityScale = 0.5, -- Gravedad normal
	Color = Color3.fromRGB(200, 50, 50), -- Rojo
	JumpForce = 65, -- Más ligero = salta un poco más alto
	DoubleJumpForce = 58, -- Doble salto ligeramente menor
}

-- ============================================
-- ATAQUES DE SUELO
-- ============================================

Ken.Attacks = {}

-- Jab rápido — más rápido que Ryu
Ken.Attacks.Punch = {
	Id = "Punch",
	Startup = 3 / 60,
	Active = 3 / 60,
	Recovery = 9 / 60,
	AnimationBase = "Punch",
	SoundEffect = "Punch",
	SoundVolume = 0.7,
	HitType = "Light",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 8,
	HitstunDuration = 0.18,
	Pushback = 5,
	HitstopFrames = 5,
	BlockPushback = 1,
	BlockstunDuration = 0.12,
	ChipDamage = 0,
	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,
	CancelWindow = { Start = 6, End = 12 },
	Hitbox = {
		Size = Vector3.new(4, 5, 4),
		Offset = Vector3.new(0, 0, -2),
	},
	-- VFX: Startup sigue la extremidad, OnHit en posición de impacto
	VFX = {
		Startup = "Startup",
		Active = "Active",
		OnHit = "OnHit",
	},
	HitLimbFlash = {
		Enabled = true,
		Color = "Orange",
		FillTransparency = 0.2,
		OutlineTransparency = 0.7,
	},
	-- Para combos: cada golpe sucesivo usa la extremidad correspondiente
	-- Punch1 → puño derecho, Punch2 → puño izquierdo, Punch3 → patada derecha
	VFX_Limbs = { "LeftHand", "LeftHand", "RightFoot" },
}

-- Puño pesado con avance (dash positivo, agresivo)
Ken.Attacks.HeavyPunch = {
	Id = "HeavyPunch",
	Startup = 10 / 60,
	Active = 4 / 60,
	Recovery = 14 / 60,
	Animation = "HeavyPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.9,
	HitType = "Heavy",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 22,
	HitstunDuration = 0.38,
	Pushback = 6,
	HitstopFrames = 8,
	BlockPushback = 9,
	BlockstunDuration = 0.22,
	ChipDamage = 2,
	GroundOnly = false,
	Knockdown = false,
	LaunchForce = nil,
	-- Avanza al golpear (agresivo)
	AttackDash = true,
	DashDistance = 6,
	DashFrameStart = 2,
	DashDuration = 5,
	CancelWindow = { Start = 7, End = 13 },
	Hitbox = {
		Size = Vector3.new(4, 3, 5),
		Offset = Vector3.new(0, 0, -4),
	},
	-- VFX: Startup sigue la mano, OnHit en posición de impacto
	VFX = {
		Startup = "Startup",
		Active = "Active",
		OnHit = "OnHit",
	},
	VFX_Limb = "RightHand",
}

-- ============================================
-- ATAQUES DE SUELO (AGACHADO)
-- ============================================

Ken.Attacks.CrouchPunch = {
	Id = "CrouchPunch",
	Startup = 4 / 60,
	Active = 3 / 60,
	Recovery = 9 / 60,
	Animation = "CrouchPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.6,
	HitType = "Light",
	HitAnimation = "HurtLight",
	AttackHeight = "Low",
	Damage = 7,
	HitstunDuration = 0.18,
	Pushback = 7,
	HitstopFrames = 3,
	BlockPushback = 4,
	BlockstunDuration = 0.1,
	ChipDamage = 0,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = nil,
	CancelWindow = { Start = 6, End = 12 },
	Hitbox = {
		Size = Vector3.new(4, 3, 4),
		Offset = Vector3.new(0, -1, -2),
	},
}

-- Barrida con dash agresivo — tumba
Ken.Attacks.CrouchHeavy = {
	Id = "CrouchHeavy",
	Startup = 8 / 60,
	Active = 5 / 60,
	Recovery = 16 / 60,
	Animation = "CrouchHeavy",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Heavy",
	HitAnimation = "HurtLight",
	AttackHeight = "Low",
	Damage = 14,
	HitstunDuration = 0.32,
	Pushback = 7,
	HitstopFrames = 6,
	BlockPushback = 7,
	BlockstunDuration = 0.18,
	ChipDamage = 1,
	GroundOnly = true,
	Knockdown = true,
	LaunchForce = nil,
	AttackDash = true,
	DashDistance = 6,
	DashFrameStart = 2,
	DashDuration = 5,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(5, 3, 5),
		Offset = Vector3.new(0, -2, -3),
	},
	VFX = {
		Startup = "Startup",
	},
	VFX_Limb = "RightFoot", -- La barrida usa el pie
}

-- ============================================
-- ATAQUES AÉREOS
-- ============================================

Ken.Attacks.AirPunch = {
	Id = "AirPunch",
	Startup = 3 / 60,
	Active = 4 / 60,
	Recovery = 7 / 60,
	Animation = "AirPunch",
	SoundEffect = "Punch",
	SoundVolume = 0.6,
	HitType = "Light",
	HitAnimation = "AirHurt",
	AttackHeight = "High",
	Damage = 7,
	HitstunDuration = 0.18,
	Pushback = 5,
	HitstopFrames = 3,
	BlockPushback = 4,
	BlockstunDuration = 0.1,
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

Ken.Attacks.AirHeavy = {
	Id = "AirHeavy",
	Startup = 7 / 60,
	Active = 5 / 60,
	Recovery = 12 / 60,
	Animation = "AirHeavy",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Heavy",
	HitAnimation = "AirHurt",
	AttackHeight = "High",
	Damage = 16,
	HitstunDuration = 0.35,
	Pushback = 7,
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
	VFX = {
		Startup = "Startup",
	},
	VFX_Limb = "RightHand",
}

-- ============================================
-- MOVIMIENTOS ESPECIALES
-- ============================================

-- Fireball de Ken — más lenta pero más daño
-- Input: ↓ → J (Down, Forward, Punch)
Ken.Attacks.Fireball = {
	Id = "Fireball",
	Startup = 18 / 60,
	Active = 25 / 60,
	Recovery = 14 / 60,
	Animation = "Fireball",
	SoundEffect = "Punch",
	SoundVolume = 0.8,
	HitType = "Special",
	HitAnimation = "HurtLight",
	AttackHeight = "Mid",
	Damage = 15,
	HitstunDuration = 0.35,
	Pushback = 10,
	HitstopFrames = 7,
	BlockPushback = 9,
	BlockstunDuration = 0.22,
	ChipDamage = 4,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = nil,
	IsSpecial = true,
	IsProjectile = true,
	ProjectileSpeed = 35,
	ProjectileLifetime = 1.2,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(3, 3, 3),
		Offset = Vector3.new(0, 0, -3),
	},
}

-- Shoryuken de Ken — más daño, más recovery
-- Input: → ↓ → J (Forward, Down, Forward, Punch)
Ken.Attacks.Uppercut = {
	Id = "Uppercut",
	Startup = 5 / 60,
	Active = 7 / 60,
	Recovery = 24 / 60,
	Animation = "Uppercut",
	SoundEffect = "Punch",
	SoundVolume = 1.0,
	HitType = "Special",
	HitAnimation = "Launch",
	AttackHeight = "Mid",
	Damage = 22,
	HitstunDuration = 0.45,
	Pushback = 4,
	HitstopFrames = 12,
	BlockPushback = 14,
	BlockstunDuration = 0.35,
	ChipDamage = 3,
	GroundOnly = true,
	Knockdown = false,
	LaunchForce = 50,
	IsSpecial = true,
	AttackJump = true,
	JumpHeight = 45,
	JumpFrameStart = 2,
	CancelWindow = nil,
	Hitbox = {
		Size = Vector3.new(4, 7, 4),
		Offset = Vector3.new(0, 1, -2),
	},
}

-- ============================================
-- COMANDOS (input → ataque)
-- Mayor prioridad = se evalúa primero
-- ============================================

Ken.Commands = {
	{ Name = "Uppercut", Input = { "Forward", "Down", "Forward", "Punch" }, Priority = 15 },
	{ Name = "Fireball", Input = { "Down", "Forward", "Punch" }, Priority = 10 },
	{ Name = "Dash", Input = { "Forward", "Forward" }, Priority = 5 },
	{ Name = "Punch", Input = { "Punch" }, Priority = 1 },
	{ Name = "HeavyPunch", Input = { "HeavyPunch" }, Priority = 1 },
}

-- ============================================
-- SKINS
-- Nombre → rbxassetid del modelo (o "Dummy" para el modelo genérico)
-- ============================================

Ken.Skins = {
	Default = "Default", -- "Dummy" = usar avatar estándar, cambiar cuando exista el modelo exportado
}

return Ken
