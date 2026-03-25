--[[
	CharacterRegistry.luau
	-----------------------
	Registro central de todos los personajes disponibles.
	Todos los sistemas (UI, CombatController, CommandParser) consultan este módulo.

	CÓMO AGREGAR UN PERSONAJE:
	1. Crea su archivo en Characters/ (ver BaseCharacter.luau)
	2. Agrega una línea aquí en la sección REGISTRO

	CÓMO USAR:
	  local Registry = require(Characters:WaitForChild("CharacterRegistry"))
	  local lista    = Registry.GetAll()           -- { Ryu, Ken, ... }
	  local char     = Registry.Get("Ryu")         -- Tabla del personaje
	  local attacks  = Registry.GetAttacks("Ryu")  -- Tabla de ataques
	  local commands = Registry.GetCommands("Ryu") -- Lista de comandos ordenada
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Characters = Modules:WaitForChild("Characters")

local CharacterRegistry = {}

-- ============================================
-- REGISTRO DE PERSONAJES (agregar aquí)
-- ============================================

local registry = {
	require(Characters:WaitForChild("Ryu"):WaitForChild("Ryu")),
	require(Characters:WaitForChild("Ken"):WaitForChild("Ken")),
	-- Agregar más personajes aquí:
	-- require(Characters:WaitForChild("NuevoPersonaje"):WaitForChild("NuevoPersonaje")),
}

-- Índice por nombre para acceso rápido
local byName = {}
for _, char in ipairs(registry) do
	byName[char.Info.Name] = char
end

-- ============================================
-- API PÚBLICA
-- ============================================

-- Retorna la lista completa de personajes
function CharacterRegistry.GetAll()
	return registry
end

-- Retorna un personaje por nombre
function CharacterRegistry.Get(name)
	return byName[name]
end

-- Retorna la tabla de ataques de un personaje
function CharacterRegistry.GetAttacks(name)
	local char = byName[name]
	return char and char.Attacks or nil
end

-- Retorna los comandos ordenados por prioridad de un personaje
function CharacterRegistry.GetCommands(name)
	local char = byName[name]
	if not char then
		return nil
	end
	return char:GetSortedCommands()
end

-- Retorna el nombre del primer personaje (default)
function CharacterRegistry.GetDefault()
	return registry[1] and registry[1].Info.Name or nil
end

return CharacterRegistry
