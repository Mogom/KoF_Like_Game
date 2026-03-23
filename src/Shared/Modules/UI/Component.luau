-- Clase base de componente UI estilo React: estado, hijos, render, destroy
local Component = {}
Component.__index = Component

-- Constructor: inicializa estado y lista de hijos
function Component.new()
	local self = setmetatable({}, Component)

	self.element = nil
	self.children = {}
	self.state = {}

	return self
end

-- ✅ Similar a React setState
-- Actualiza el estado del componente (merge parcial)
function Component:setState(newState)
	for key, value in pairs(newState) do
		self.state[key] = value
	end

	if self.render then
		self:render()
	end
end

-- ✅ Destruir componente
-- Destruye el elemento UI y todos sus hijos
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
