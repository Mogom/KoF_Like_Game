-- Buffer de inputs con ventana de tiempo para detectar secuencias de comandos
local InputBuffer = {}
InputBuffer.__index = InputBuffer

-- Constructor: crea buffer con ventana de tiempo configurable
function InputBuffer.new(bufferTime)
	local self = setmetatable({}, InputBuffer)

	self.bufferTime = bufferTime or 0.25
	self.buffer = {}

	return self
end

-- Agrega un input al buffer con timestamp
function InputBuffer:AddInput(input)
	local time = tick()

	-- evitar duplicados muy seguidos
	local last = self.buffer[#self.buffer]

	if last and last.input == input and (time - last.time) < 0.05 then
		return
	end

	table.insert(self.buffer, {
		input = input,
		time = time,
	})
end

-- Limpia inputs expirados fuera de la ventana de tiempo
function InputBuffer:_Clean()
	local now = tick()

	for i = #self.buffer, 1, -1 do
		if now - self.buffer[i].time > self.bufferTime then
			table.remove(self.buffer, i)
		end
	end
end

-- Retorna los inputs activos del buffer
function InputBuffer:GetBuffer()
	self:_Clean()

	return self.buffer
end

-- Verifica si la secuencia dada aparece en el buffer
function InputBuffer:Match(sequence)
	self:_Clean()

	local buffer = self.buffer
	local seqIndex = #sequence

	for i = #buffer, 1, -1 do
		if buffer[i].input == sequence[seqIndex] then
			seqIndex -= 1

			if seqIndex <= 0 then
				return true
			end
		end
	end

	return false
end

-- Consume (elimina) los inputs que formaron el comando
function InputBuffer:Consume(command)
	for i = #self.buffer, 1, -1 do
		if self.buffer[i].input == command then
			table.remove(self.buffer, i)
			return
		end
	end
end

-- Match + Consume en un solo paso
function InputBuffer:MatchAndConsume(sequence)
	if self:Match(sequence) then
		-- borrar el buffer
		self.buffer = {}

		return true
	end

	return false
end

return InputBuffer
