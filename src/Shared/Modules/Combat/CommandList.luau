-- Tabla de comandos especiales con secuencias de input y prioridad
-- Nota: usa direcciones relativas (Forward/Back) para que funcionen
-- en ambas orientaciones del personaje.
local Commands = {

	{
		Name = "Uppercut",
		Input = { "Forward", "Down", "Forward", "Punch" },
		Priority = 15,
	},

	{
		Name = "Fireball",
		Input = { "Down", "Forward", "Punch" },
		Priority = 10,
	},

	{
		Name = "Dash",
		Input = { "Forward", "Forward" },
		Priority = 5,
	},

	{
		Name = "Punch",
		Input = { "Punch" },
		Priority = 1,
	},

	{
		Name = "HeavyPunch",
		Input = { "HeavyPunch" },
		Priority = 1,
	},
}

return Commands
