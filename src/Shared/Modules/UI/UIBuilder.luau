-- Fábrica de elementos UI: crea instancias con props y métodos shortcut
local UIBuilder = {}

local TweenService = game:GetService("TweenService")

-- ✅ Crear elemento base
-- Crea un elemento UI con className y aplica todas las propiedades
function UIBuilder.create(className, props)
	local element = Instance.new(className)

	if props then
		for key, value in pairs(props) do
			if key == "Children" then
				-- Agregar hijos al final
			elseif key == "Events" then
				-- Conectar eventos
			else
				-- Propiedades normales
				pcall(function()
					element[key] = value
				end)
			end
		end

		-- Agregar hijos
		if props.Children then
			for _, child in ipairs(props.Children) do
				child.Parent = element
			end
		end

		-- Conectar eventos
		if props.Events then
			for eventName, callback in pairs(props.Events) do
				if element[eventName] then
					element[eventName]:Connect(callback)
				end
			end
		end
	end

	return element
end

-- ✅ Shorthand helpers (como React.createElement shortcuts)
-- Shortcut: crea ScreenGui
function UIBuilder.ScreenGui(props)
	return UIBuilder.create("ScreenGui", props)
end

-- Shortcut: crea Frame
function UIBuilder.Frame(props)
	return UIBuilder.create("Frame", props)
end

-- Shortcut: crea TextLabel
function UIBuilder.TextLabel(props)
	return UIBuilder.create("TextLabel", props)
end

-- Shortcut: crea TextButton
function UIBuilder.TextButton(props)
	return UIBuilder.create("TextButton", props)
end

-- Shortcut: crea ImageLabel
function UIBuilder.ImageLabel(props)
	return UIBuilder.create("ImageLabel", props)
end

-- Shortcut: crea UICorner
function UIBuilder.UICorner(props)
	return UIBuilder.create("UICorner", props)
end

-- Shortcut: crea UIStroke
function UIBuilder.UIStroke(props)
	return UIBuilder.create("UIStroke", props)
end

-- Shortcut: crea UIGradient
function UIBuilder.UIGradient(props)
	return UIBuilder.create("UIGradient", props)
end

-- ✅ Tween helper (como CSS transitions)
-- Ejecuta un tween sobre un elemento UI
function UIBuilder.tween(element, duration, props, easingStyle, easingDirection)
	local tweenInfo = TweenInfo.new(
		duration or 0.3,
		easingStyle or Enum.EasingStyle.Quad,
		easingDirection or Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(element, tweenInfo, props)
	tween:Play()
	return tween
end

return UIBuilder
