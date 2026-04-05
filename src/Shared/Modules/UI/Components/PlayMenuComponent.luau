--[[
	PlayMenuComponent.luau
	-----------------------
	Pantalla de selección de modo de juego (aparece al pulsar "Play").

	LAYOUT:
	┌──────────────────────────────────┐
	│         SELECT MODE              │
	│                                  │
	│       ┌─────────────┐            │
	│       │     1V1     │            │
	│       └─────────────┘            │
	│                                  │
	│   (Espacio para más botones)     │
	│                                  │
	│         [← Volver]               │
	└──────────────────────────────────┘

	CÓMO AGREGAR MÁS MODOS:
	1. Agregar una entrada a MODE_BUTTONS con Key, Text, Color, HoverColor
	2. Registrar el callback en self.callbacks[Key] = self.props.onMiModoClick
	3. Pasar onMiModoClick desde UIManager al crear este componente

	CÓMO EDITAR ASPECTO:
	- Colores de fondo: BACKGROUND_COLOR
	- Tamaño de botones de modo: MODE_BUTTON_WIDTH, MODE_BUTTON_HEIGHT
	- Espacio entre botones: MODE_BUTTON_SPACING
	- Texto del título: TITLE_TEXT
	- Color del título: TITLE_COLOR
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local PlayMenuComponent = {}
PlayMenuComponent.__index = PlayMenuComponent

-- ============================================
-- 🎨 CONFIGURACIÓN VISUAL (editar aquí)
-- ============================================

local BACKGROUND_COLOR = Color3.fromRGB(12, 12, 18)

-- Título
local TITLE_TEXT = "SELECT MODE"
local TITLE_COLOR = Color3.fromRGB(255, 255, 255)
local TITLE_SIZE = 40

-- Botones de modo
local MODE_BUTTON_WIDTH = 280
local MODE_BUTTON_HEIGHT = 70
local MODE_BUTTON_SPACING = 20
local MODE_BUTTON_CORNER = 10
local MODE_TEXT_SIZE = 30

-- Botón de volver
local BACK_BUTTON_COLOR = Color3.fromRGB(60, 60, 70)
local BACK_HOVER_COLOR = Color3.fromRGB(90, 90, 100)

--[[
	Tabla de modos de juego.
	Cada entrada define un botón de modo.
	El ORDEN determina el orden vertical.
	
	Para agregar un modo nuevo:
	1. Agrega una entrada aquí (Key, Text, Color, HoverColor)
	2. En el constructor, registra: self.callbacks["TuKey"] = self.props.onTuKeyClick
	3. Pasa onTuKeyClick desde UIManager
]]
local MODE_BUTTONS = {
	{
		Key = "Versus1v1",
		Text = "1 V 1",
		Color = Color3.fromRGB(119, 21, 21), -- Rojo
		HoverColor = Color3.fromRGB(240, 50, 50),
	},
	{
		Key = "FreeForAll",
		Text = "Free For All",
		Color = Color3.fromHSV(0.525445, 0.700535, 0.733333), -- Cyan
		HoverColor = Color3.fromRGB(63, 214, 214),
	},
	{
		Key = "JoinLobby",
		Text = "Join Lobby",
		Color = Color3.fromRGB(80, 60, 140), -- Púrpura
		HoverColor = Color3.fromRGB(120, 90, 200),
	},
}

-- ============================================
-- CONSTRUCTOR
-- ============================================

-- Crea la pantalla de selección de modo
function PlayMenuComponent.new(parent, props)
	local self = setmetatable({}, PlayMenuComponent)

	self.props = props or {}
	self.element = nil
	self.buttons = {}

	-- Mapeo Key → callback
	-- Para agregar: self.callbacks["Versus2v2"] = self.props.onVersus2v2Click
	self.callbacks = {
		Versus1v1 = self.props.onVersus1v1Click,
		FreeForAll = self.props.onFreeForAllClick,
		JoinLobby = self.props.onJoinLobbyClick,
	}

	self.onBack = self.props.onBackClick

	local success, err = pcall(function()
		self:render(parent)
	end)

	if not success then
		warn("❌ Error creating PlayMenu:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

-- Construye la pantalla de selección de modo
function PlayMenuComponent:render(parent)
	local screenGui = UIBuilder.ScreenGui({
		Name = "PlayMenu",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- Fondo negro
	UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BACKGROUND_COLOR,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	-- Título centrado arriba
	UIBuilder.TextLabel({
		Name = "Title",
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0, 400, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = TITLE_TEXT,
		TextColor3 = TITLE_COLOR,
		TextSize = TITLE_SIZE,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = screenGui,
	})

	-- Contenedor de botones de modo (centrado)
	local modeContainer = UIBuilder.Frame({
		Name = "ModeContainer",
		Position = UDim2.new(0.5, 0, 0.4, 0),
		Size = UDim2.new(0, MODE_BUTTON_WIDTH, 0, #MODE_BUTTONS * (MODE_BUTTON_HEIGHT + MODE_BUTTON_SPACING)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	-- Crear botones de modo
	for i, config in ipairs(MODE_BUTTONS) do
		local yOffset = (i - 1) * (MODE_BUTTON_HEIGHT + MODE_BUTTON_SPACING)
		self:_createModeButton(modeContainer, config, yOffset)
	end

	-- Botón de volver (abajo centrado)
	local backButton = UIBuilder.TextButton({
		Name = "BackButton",
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.new(0, 180, 0, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = BACK_BUTTON_COLOR,
		BorderSizePixel = 0,
		Text = "← Volver",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
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

	-- Animación de entrada: fade in
	screenGui.Enabled = true
	modeContainer.Position = UDim2.new(0.5, 0, 0.6, 0)
	UIBuilder.tween(modeContainer, 0.35, {
		Position = UDim2.new(0.5, 0, 0.4, 0),
	}, Enum.EasingStyle.Back)
end

-- Crea un botón de modo de juego
function PlayMenuComponent:_createModeButton(parent, config, yOffset)
	local button = UIBuilder.TextButton({
		Name = "Mode_" .. config.Key,
		Position = UDim2.new(0.5, 0, 0, yOffset),
		Size = UDim2.new(0, MODE_BUTTON_WIDTH, 0, MODE_BUTTON_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = config.Color,
		BorderSizePixel = 0,
		Text = config.Text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = MODE_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = parent,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, MODE_BUTTON_CORNER) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(255, 255, 255),
				Thickness = 2,
				Transparency = 0.7,
			}),
		},
	})

	button.MouseEnter:Connect(function()
		UIBuilder.tween(button, 0.12, {
			BackgroundColor3 = config.HoverColor,
			Size = UDim2.new(0, MODE_BUTTON_WIDTH + 10, 0, MODE_BUTTON_HEIGHT + 4),
		})
	end)

	button.MouseLeave:Connect(function()
		UIBuilder.tween(button, 0.12, {
			BackgroundColor3 = config.Color,
			Size = UDim2.new(0, MODE_BUTTON_WIDTH, 0, MODE_BUTTON_HEIGHT),
		})
	end)

	local callback = self.callbacks[config.Key]
	if callback then
		button.MouseButton1Click:Connect(callback)
	end

	self.buttons[config.Key] = button
	return button
end

-- ============================================
-- MÉTODOS PÚBLICOS
-- ============================================

-- Destruye la pantalla
function PlayMenuComponent:destroy()
	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return PlayMenuComponent
