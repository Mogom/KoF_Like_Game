local CommandParser = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local Commands = require(Combat:WaitForChild("CommandList"))

-- ordenar por prioridad
table.sort(Commands,function(a,b)
	return a.Priority > b.Priority
end)

function CommandParser.Parse(buffer)

	for _,command in ipairs(Commands) do

		if buffer:MatchAndConsume(command.Input) then
			return command.Name
		end

	end

	return nil

end

return CommandParser