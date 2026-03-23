local UIBuilder = {}

local TweenService = game:GetService("TweenService")

-- ✅ Crear elemento base
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
function UIBuilder.ScreenGui(props)
	return UIBuilder.create("ScreenGui", props)
end

function UIBuilder.Frame(props)
	return UIBuilder.create("Frame", props)
end

function UIBuilder.TextLabel(props)
	return UIBuilder.create("TextLabel", props)
end

function UIBuilder.TextButton(props)
	return UIBuilder.create("TextButton", props)
end

function UIBuilder.ImageLabel(props)
	return UIBuilder.create("ImageLabel", props)
end

function UIBuilder.UICorner(props)
	return UIBuilder.create("UICorner", props)
end

function UIBuilder.UIStroke(props)
	return UIBuilder.create("UIStroke", props)
end

function UIBuilder.UIGradient(props)
	return UIBuilder.create("UIGradient", props)
end

-- ✅ Tween helper (como CSS transitions)
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