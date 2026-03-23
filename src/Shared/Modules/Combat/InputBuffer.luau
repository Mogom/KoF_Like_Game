local InputBuffer = {}
InputBuffer.__index = InputBuffer

function InputBuffer.new(bufferTime)

	local self = setmetatable({}, InputBuffer)

	self.bufferTime = bufferTime or 0.25
	self.buffer = {}

	return self
end


function InputBuffer:AddInput(input)

	local time = tick()

	-- evitar duplicados muy seguidos
	local last = self.buffer[#self.buffer]

	if last and last.input == input and (time - last.time) < 0.05 then
		return
	end

	table.insert(self.buffer,{
		input = input,
		time = time
	})

end

function InputBuffer:_Clean()

	local now = tick()

	for i = #self.buffer, 1, -1 do

		if now - self.buffer[i].time > self.bufferTime then
			table.remove(self.buffer, i)
		end

	end

end


function InputBuffer:GetBuffer()

	self:_Clean()

	return self.buffer
end


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

function InputBuffer:Consume(command)

	for i = #self.buffer, 1, -1 do
		if self.buffer[i].input == command then
			table.remove(self.buffer, i)
			return
		end
	end

end

function InputBuffer:MatchAndConsume(sequence)

	if self:Match(sequence) then

		-- borrar el buffer
		self.buffer = {}

		return true
	end

	return false

end


return InputBuffer