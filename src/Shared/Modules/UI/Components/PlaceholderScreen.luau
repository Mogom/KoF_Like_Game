--[[
	PlaceholderScreen.luau
	-----------------------
	Pantalla placeholder genérica: fondo negro con título y botón "Volver".
	Se usa para secciones en construcción (Create Sala, Shop, etc.)

	CÓMO EDITAR:
	- Color de fondo: BACKGROUND_COLOR
	- Color del botón volver: BACK_BUTTON_COLOR, BACK_HOVER_COLOR
	- Texto del título: se pasa como parámetro en .new(parent, props)
	  → props.title = "SHOP" (por ejemplo)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local PlaceholderScreen = {}
PlaceholderScreen.__index = PlaceholderScreen

-- ============================================
-- 🎨 CONFIGURACIÓN VISUAL
-- ============================================

local BACKGROUND_COLOR = Color3.fromRGB(5, 5, 8)
local TITLE_COLOR = Color3.fromRGB(180, 180, 180)
local SUBTITLE_COLOR = Color3.fromRGB(100, 100, 110)
local BACK_BUTTON_COLOR = Color3.fromRGB(60, 60, 70)
local BACK_HOVER_COLOR = Color3.fromRGB(90, 90, 100)

-- ============================================
-- CONSTRUCTOR
-- ============================================

-- Crea pantalla placeholder con título y botón volver
-- props.title: texto del título (ej: "SHOP", "CREATE SALA")
-- props.onBackClick: callback del botón volver
function PlaceholderScreen.new(parent, props)
	local self = setmetatable({}, PlaceholderScreen)

	self.props = props or {}
	self.element = nil
	self.onBack = self.props.onBackClick

	local success, err = pcall(function()
		self:render(parent)
	end)

	if not success then
		warn("❌ Error creating PlaceholderScreen:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

-- Construye la pantalla placeholder
function PlaceholderScreen:render(parent)
	local screenGui = UIBuilder.ScreenGui({
		Name = "PlaceholderScreen_" .. (self.props.title or "Unknown"),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- Fondo negro completo
	UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BACKGROUND_COLOR,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	-- Título centrado
	UIBuilder.TextLabel({
		Name = "Title",
		Position = UDim2.new(0.5, 0, 0.35, 0),
		Size = UDim2.new(0, 500, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = self.props.title or "COMING SOON",
		TextColor3 = TITLE_COLOR,
		TextSize = 44,
		Font = Enum.Font.GothamBold,
		Parent = screenGui,
	})

	-- Subtítulo
	UIBuilder.TextLabel({
		Name = "Subtitle",
		Position = UDim2.new(0.5, 0, 0.43, 0),
		Size = UDim2.new(0, 500, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Text = "En construcción...",
		TextColor3 = SUBTITLE_COLOR,
		TextSize = 20,
		Font = Enum.Font.Gotham,
		Parent = screenGui,
	})

	-- Botón de volver
	local backButton = UIBuilder.TextButton({
		Name = "BackButton",
		Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.new(0, 200, 0, 55),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BACK_BUTTON_COLOR,
		BorderSizePixel = 0,
		Text = "← Volver",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 10) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(120, 120, 130),
				Thickness = 2,
				Transparency = 0.5,
			}),
		},
	})

	backButton.MouseEnter:Connect(function()
		UIBuilder.tween(backButton, 0.12, { BackgroundColor3 = BACK_HOVER_COLOR })
	end)
	backButton.MouseLeave:Connect(function()
		UIBuilder.tween(backButton, 0.12, { BackgroundColor3 = BACK_BUTTON_COLOR })
	end)

	if self.onBack then
		backButton.MouseButton1Click:Connect(self.onBack)
	end
end

-- ============================================
-- MÉTODOS PÚBLICOS
-- ============================================

-- Destruye la pantalla
function PlaceholderScreen:destroy()
	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return PlaceholderScreen
