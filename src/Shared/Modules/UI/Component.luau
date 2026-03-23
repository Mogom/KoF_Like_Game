local Component = {}
Component.__index = Component

function Component.new()
	local self = setmetatable({}, Component)

	self.element = nil
	self.children = {}
	self.state = {}

	return self
end

-- ✅ Similar a React setState
function Component:setState(newState)
	for key, value in pairs(newState) do
		self.state[key] = value
	end

	if self.render then
		self:render()
	end
end

-- ✅ Destruir componente
function Component:destroy()
	if self.element then
		self.element:Destroy()
	end

	for _, child in ipairs(self.children) do
		if child.destroy then
			child:destroy()
		end
	end
end

return Component