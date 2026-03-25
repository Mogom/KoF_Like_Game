-- Parser de comandos: evalua el InputBuffer contra la CommandList por prioridad
-- Soporta comandos globales (CommandList) o por personaje (CharacterRegistry)
local CommandParser = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DefaultCommands = require(Combat:WaitForChild("CommandList"))

-- ordenar por prioridad
table.sort(DefaultCommands, function(a, b)
	return a.Priority > b.Priority
end)

-- Busca el primer comando que hace match con el buffer actual
-- Si se pasan comandos personalizados, los usa en vez de los globales
function CommandParser.Parse(buffer, customCommands)
	local commands = customCommands or DefaultCommands
	for _, command in ipairs(commands) do
		if buffer:MatchAndConsume(command.Input) then
			return command.Name
		end
	end

	return nil
end

return CommandParser
