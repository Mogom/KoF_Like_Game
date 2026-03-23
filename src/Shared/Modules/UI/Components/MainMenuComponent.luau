local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local MainMenuComponent = {}
MainMenuComponent.__index = MainMenuComponent

function MainMenuComponent.new(parent, props)

	local self = setmetatable({}, MainMenuComponent)

	self.props = props or {}
	self.onTrainingClick = self.props.onTrainingClick
	self.onVersusClick = self.props.onVersusClick
	self.element = nil
	self.menuFrame = nil
	self.selectedIndex = 1


	-- Crear UI
	local success, err = pcall(function()
		self:render(parent)
		self:startSelectorAnimation()
	end)

	if not success then
		warn("❌ Error creating MainMenu:", err)
		return nil
	end


	return self
end

function MainMenuComponent:render(parent)

	-- ✅ Crear ScreenGui
	local screenGui = UIBuilder.ScreenGui({
		Name = "MainMenu",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,  
		Parent = parent
	})

	self.element = screenGui

	-- ✅ Background oscuro
	local background = UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 10, 15),
		BorderSizePixel = 0,
		Parent = screenGui
	})

	-- ✅ Frame principal con borde neón
	local menuFrame = UIBuilder.Frame({
		Name = "MenuFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 550, 0, 600),
		BackgroundColor3 = Color3.fromRGB(15, 15, 20),
		BorderSizePixel = 0,
		Parent = screenGui,

		Children = {
			-- Borde exterior verde neón
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(0, 255, 100),
				Thickness = 4,
				Transparency = 0
			}),
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) })
		}
	})

	self.menuFrame = menuFrame

	-- ✅ Borde interno (doble borde estilo arcade)
	local innerBorder = UIBuilder.Frame({
		Name = "InnerBorder",
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(1, -20, 1, -20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = menuFrame,

		Children = {
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(0, 200, 80),
				Thickness = 2,
				Transparency = 0.3
			})
		}
	})

	-- ✅ Decoración esquina superior izquierda
	self:createCornerDecoration(menuFrame, "TopLeft", UDim2.new(0, -10, 0, -10))
	self:createCornerDecoration(menuFrame, "TopRight", UDim2.new(1, 10, 0, -10))
	self:createCornerDecoration(menuFrame, "BottomLeft", UDim2.new(0, -10, 1, 10))
	self:createCornerDecoration(menuFrame, "BottomRight", UDim2.new(1, 10, 1, 10))

	-- ✅ Header "MAIN MENU" estilo arcade
	local header = UIBuilder.TextLabel({
		Name = "Header",
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.new(0.9, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(0, 255, 100),
		BorderSizePixel = 0,
		Text = "MAIN MENU",
		TextColor3 = Color3.fromRGB(0, 0, 0),
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 1,
		Parent = menuFrame,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 4) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(255, 255, 0),
				Thickness = 3
			})
		}
	})

	-- ✅ Efecto de sombra en header
	UIBuilder.TextLabel({
		Name = "HeaderShadow",
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "MAIN MENU",
		TextColor3 = Color3.fromRGB(0, 150, 50),
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		TextTransparency = 0.5,
		ZIndex = 0,
		Parent = header
	})

	-- ✅ Separador decorativo
	UIBuilder.Frame({
		Name = "Separator",
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.new(0.8, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(0, 255, 100),
		BorderSizePixel = 0,
		Parent = menuFrame,

		Children = {
			UIBuilder.UIGradient({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1)
				})
			})
		}
	})

	-- ✅ Selector animado (flecha)
	self.selector = UIBuilder.TextLabel({
		Name = "Selector",
		Position = UDim2.new(0, 50, 0, 200),
		Size = UDim2.new(0, 40, 0, 60),
		BackgroundTransparency = 1,
		Text = "▶",
		TextColor3 = Color3.fromRGB(0, 255, 100),
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		Parent = menuFrame
	})

	-- ✅ Botones estilo arcade con números
	local button1 = self:createArcadeButton({
		number = "1",
		text = "TRAINING MODE",
		position = UDim2.new(0.5, 0, 0, 200),
		onClick = self.onTrainingClick,
		parent = menuFrame
	})

	local button2 = self:createArcadeButton({
		number = "2",
		text = "1v1 VERSUS",
		position = UDim2.new(0.5, 0, 0, 300),
		onClick = self.onVersusClick,
		parent = menuFrame
	})

	-- ✅ Info box inferior (estilo KOF)
	local infoBox = UIBuilder.Frame({
		Name = "InfoBox",
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.new(0.9, 0, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BorderSizePixel = 0,
		Parent = menuFrame,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 4) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(0, 255, 100),
				Thickness = 2
			})
		}
	})

	-- ✅ Label "INFO" estilo arcade
	UIBuilder.TextLabel({
		Name = "InfoLabel",
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(0, 80, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 255, 100),
		BorderSizePixel = 0,
		Text = "INFO",
		TextColor3 = Color3.fromRGB(0, 0, 0),
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		Parent = infoBox
	})

	-- ✅ Texto de info
	UIBuilder.TextLabel({
		Name = "InfoText",
		Position = UDim2.new(0, 100, 0, 0),
		Size = UDim2.new(1, -110, 1, 0),
		BackgroundTransparency = 1,
		Text = "Select your game mode to begin",
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 16,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = infoBox
	})

	-- ✅ Animación de entrada (desde arriba)
	menuFrame.Position = UDim2.new(0.5, 0, -0.5, 0)
	UIBuilder.tween(menuFrame, 0.6, {
		Position = UDim2.new(0.5, 0, 0.5, 0)
	}, Enum.EasingStyle.Back)
end

-- ✅ Crear decoración de esquina estilo arcade
function MainMenuComponent:createCornerDecoration(parent, corner, position)
	local decoration = UIBuilder.Frame({
		Name = corner .. "Decoration",
		Position = position,
		Size = UDim2.new(0, 20, 0, 20),
		BackgroundColor3 = Color3.fromRGB(0, 255, 100),
		BorderSizePixel = 0,
		Rotation = 45,
		ZIndex = 10,
		Parent = parent
	})
end

-- ✅ Crear botón estilo arcade (con número y texto)
function MainMenuComponent:createArcadeButton(props)
	local container = UIBuilder.Frame({
		Name = "ButtonContainer_" .. props.number,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = UDim2.new(0, 450, 0, 70),
		BackgroundTransparency = 1,
		Parent = props.parent
	})

	-- ✅ Número (estilo arcade)
	local numberLabel = UIBuilder.TextLabel({
		Name = "Number",
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 50, 0, 50),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		Text = props.number,
		TextColor3 = Color3.fromRGB(0, 255, 100),
		TextSize = 32,
		Font = Enum.Font.GothamBold,
		Parent = container,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(0, 200, 80),
				Thickness = 2
			})
		}
	})

	-- ✅ Botón principal
	local button = UIBuilder.TextButton({
		Name = "Button",
		Position = UDim2.new(0, 70, 0.5, 0),
		Size = UDim2.new(1, -70, 1, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		Text = props.text,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = container,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(0, 200, 80),
				Thickness = 2
			})
		}
	})

	-- ✅ Hover effect (brillo verde)
	button.MouseEnter:Connect(function()
		UIBuilder.tween(button, 0.2, {
			BackgroundColor3 = Color3.fromRGB(0, 100, 50)
		})
		UIBuilder.tween(button, 0.2, {
			TextColor3 = Color3.fromRGB(255, 255, 255)
		})

		-- Animar número también
		UIBuilder.tween(numberLabel, 0.2, {
			BackgroundColor3 = Color3.fromRGB(0, 255, 100),
			TextColor3 = Color3.fromRGB(0, 0, 0)
		})
	end)

	button.MouseLeave:Connect(function()
		UIBuilder.tween(button, 0.2, {
			BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		})
		UIBuilder.tween(button, 0.2, {
			TextColor3 = Color3.fromRGB(200, 200, 200)
		})

		UIBuilder.tween(numberLabel, 0.2, {
			BackgroundColor3 = Color3.fromRGB(20, 20, 30),
			TextColor3 = Color3.fromRGB(0, 255, 100)
		})
	end)

	-- ✅ Click
	if props.onClick then
		button.MouseButton1Click:Connect(props.onClick)
	end

	return container
end

-- ✅ Animación del selector (flecha parpadeante)
function MainMenuComponent:startSelectorAnimation()
	task.spawn(function()
		while self.selector and self.selector.Parent do
			-- Parpadeo
			UIBuilder.tween(self.selector, 0.5, {
				TextTransparency = 0.3
			})
			task.wait(0.5)
			UIBuilder.tween(self.selector, 0.5, {
				TextTransparency = 0
			})
			task.wait(0.5)
		end
	end)
end

-- ✅ Hide con animación
function MainMenuComponent:hide()

	if not self.menuFrame then
		warn("❌ menuFrame is nil!")
		return
	end

	local tween = UIBuilder.tween(self.menuFrame, 0.4, {
		Position = UDim2.new(0.5, 0, -1, 0)
	}, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	tween.Completed:Wait()

	if self.element then
		self.element.Enabled = false
	end

end

-- ✅ Destruir componente
function MainMenuComponent:destroy()
	if self.element then
		self.element:Destroy()
	end
end

return MainMenuComponent