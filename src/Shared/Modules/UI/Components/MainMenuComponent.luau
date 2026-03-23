--[[
	MainMenuComponent.luau
	-----------------------
	Menú principal del juego estilo fighting game.

	LAYOUT:
	┌──────────────────────────────────┐
	│  [Botones]         [Zona PNG]    │
	│   Play                           │
	│   Training                       │
	│   Create Sala                    │
	│   Shop                           │
	│                                  │
	└──────────────────────────────────┘

	CÓMO EDITAR:
	- Colores de botones: tabla BUTTON_CONFIG más abajo (Color, HoverColor)
	- Texto de botones: campo "Text" en BUTTON_CONFIG
	- Tamaño de botones: BUTTON_WIDTH, BUTTON_HEIGHT
	- Espacio entre botones: BUTTON_SPACING
	- Posición del panel de botones: PANEL_PADDING_LEFT, PANEL_PADDING_TOP
	- Color de fondo: BACKGROUND_COLOR
	- Zona PNG (derecha): buscar "CharacterDisplayArea" en render()
	  → Para poner imagen: cambiar Frame por ImageLabel y usar Image = "rbxassetid://TU_ID"
	- Para agregar un botón nuevo: agregar entrada a BUTTON_CONFIG con Key único
	  y registrar su callback en self.callbacks dentro del constructor

	CALLBACKS (se pasan via props):
	- onPlayClick       → Al pulsar "Play"
	- onTrainingClick   → Al pulsar "Training"
	- onCreateSalaClick → Al pulsar "Create Sala"
	- onShopClick       → Al pulsar "Shop"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local MainMenuComponent = {}
MainMenuComponent.__index = MainMenuComponent

-- ============================================
-- 🎨 CONFIGURACIÓN VISUAL (editar aquí)
-- ============================================

-- Color de fondo general del menú
local BACKGROUND_COLOR = Color3.fromRGB(20, 20, 25)

-- Zona derecha (placeholder para personaje/PNG): color gris
local DISPLAY_AREA_COLOR = Color3.fromRGB(100, 100, 105)

-- Qué tanto del ancho ocupa el panel de botones (0.35 = 35% izquierda)
local BUTTON_PANEL_WIDTH_SCALE = 0.35

-- Padding del panel de botones
local PANEL_PADDING_LEFT = 30 -- px desde la izquierda
local PANEL_PADDING_TOP = 80 -- px desde arriba

-- Tamaño de cada botón
local BUTTON_WIDTH = 230 -- px ancho
local BUTTON_HEIGHT = 60 -- px alto
local BUTTON_SPACING = 14 -- px entre botones
local BUTTON_CORNER = 10 -- radio de esquinas redondeadas

-- Tamaño del texto en botones
local BUTTON_TEXT_SIZE = 28

--[[
	Tabla de botones del menú.
	Cada entrada define:
	- Key: identificador interno (debe coincidir con self.callbacks)
	- Text: texto que se muestra en el botón
	- Color: color de fondo del botón
	- HoverColor: color al pasar el mouse encima
	
	El ORDEN de esta tabla define el orden vertical de los botones.
	Para agregar un botón nuevo, agrega una entrada aquí y registra
	su callback en self.callbacks dentro del constructor.
]]
local BUTTON_CONFIG = {
	{
		Key = "Play",
		Text = "Play",
		Color = Color3.fromRGB(140, 15, 20), -- Rojo oscuro
		HoverColor = Color3.fromRGB(180, 25, 30),
	},
	{
		Key = "Training",
		Text = "Training",
		Color = Color3.fromRGB(120, 10, 15), -- Vino / burdeos
		HoverColor = Color3.fromRGB(160, 20, 25),
	},
	{
		Key = "CreateSala",
		Text = "Create Sala",
		Color = Color3.fromRGB(160, 210, 20), -- Verde lima
		HoverColor = Color3.fromRGB(190, 240, 40),
	},
	{
		Key = "Shop",
		Text = "Shop",
		Color = Color3.fromRGB(150, 60, 170), -- Morado
		HoverColor = Color3.fromRGB(180, 80, 200),
	},
	{
		Key = "Settings",
		Text = "Settings",
		Color = Color3.fromRGB(125, 122, 126), -- Gris
		HoverColor = Color3.fromRGB(166, 165, 167),
	},
}

-- ============================================
-- CONSTRUCTOR
-- ============================================

-- Crea el menú principal y bindea callbacks
function MainMenuComponent.new(parent, props)
	local self = setmetatable({}, MainMenuComponent)

	self.props = props or {}
	self.element = nil -- ScreenGui raíz
	self.buttonPanel = nil -- Frame que contiene los botones
	self.buttons = {} -- { [Key] = TextButton }

	-- Mapeo de Key de BUTTON_CONFIG → función callback
	-- Para agregar un callback nuevo: self.callbacks["MiKey"] = self.props.onMiKeyClick
	self.callbacks = {
		Play = self.props.onPlayClick,
		Training = self.props.onTrainingClick,
		CreateSala = self.props.onCreateSalaClick,
		Shop = self.props.onShopClick,
	}

	local success, err = pcall(function()
		self:render(parent)
	end)

	if not success then
		warn("❌ Error creating MainMenu:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

-- Construye toda la UI del menú principal
function MainMenuComponent:render(parent)
	local screenGui = UIBuilder.ScreenGui({
		Name = "MainMenu",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- Fondo oscuro completo
	UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BACKGROUND_COLOR,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	-- ============================================
	-- ZONA DERECHA: Área para personaje / PNG
	-- Para poner una imagen en vez del color gris:
	--   1. Cambia UIBuilder.Frame por UIBuilder.ImageLabel
	--   2. Agrega: Image = "rbxassetid://TU_ASSET_ID",
	--   3. Agrega: ScaleType = Enum.ScaleType.Crop (o Fit),
	-- ============================================
	local displayArea = UIBuilder.ImageLabel({
		Name = "CharacterDisplayArea",
		Image = "rbxassetid://2867269", -- Reemplaza con tu imagen o deja vacío para solo color
		ScaleType = Enum.ScaleType.Crop,
		Position = UDim2.new(BUTTON_PANEL_WIDTH_SCALE, 0, 0, 0),
		Size = UDim2.new(1 - BUTTON_PANEL_WIDTH_SCALE, 0, 1, 0),
		BackgroundColor3 = DISPLAY_AREA_COLOR,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = screenGui,
	})


	-- local displayArea = UIBuilder.Frame({
	-- 	Name = "CharacterDisplayArea",
	-- 	Position = UDim2.new(BUTTON_PANEL_WIDTH_SCALE, 0, 0, 0),
	-- 	Size = UDim2.new(1 - BUTTON_PANEL_WIDTH_SCALE, 0, 1, 0),
	-- 	BackgroundColor3 = DISPLAY_AREA_COLOR,
	-- 	BorderSizePixel = 0,
	-- 	ClipsDescendants = true,
	-- 	Parent = screenGui,
	-- })


	-- Diagonal decorativa: crea el efecto de corte en ángulo
	-- entre la zona de botones y la zona del personaje
	UIBuilder.Frame({
		Name = "DiagonalOverlay",
		Position = UDim2.new(-0.25, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1.2, 0),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = BACKGROUND_COLOR,
		BorderSizePixel = 0,
		Rotation = 12,
		Parent = displayArea,
	})

	-- ============================================
	-- PANEL IZQUIERDO: Contenedor de botones
	-- ============================================
	local buttonPanel = UIBuilder.Frame({
		Name = "ButtonPanel",
		Position = UDim2.new(0, PANEL_PADDING_LEFT, 0, PANEL_PADDING_TOP),
		Size = UDim2.new(BUTTON_PANEL_WIDTH_SCALE, -PANEL_PADDING_LEFT, 1, -PANEL_PADDING_TOP),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	self.buttonPanel = buttonPanel

	-- Crear cada botón desde la tabla de configuración
	for i, config in ipairs(BUTTON_CONFIG) do
		local yOffset = (i - 1) * (BUTTON_HEIGHT + BUTTON_SPACING)
		self:_createMenuButton(buttonPanel, config, yOffset)
	end

	-- Animación de entrada: botones se deslizan desde la izquierda
	buttonPanel.Position = UDim2.new(-0.4, 0, 0, PANEL_PADDING_TOP)
	UIBuilder.tween(buttonPanel, 0.5, {
		Position = UDim2.new(0, PANEL_PADDING_LEFT, 0, PANEL_PADDING_TOP),
	}, Enum.EasingStyle.Back)
end

-- ============================================
-- CREAR BOTÓN DE MENÚ
-- ============================================

-- Crea un botón individual con color, hover effect y callback
function MainMenuComponent:_createMenuButton(parent, config, yOffset)
	local button = UIBuilder.TextButton({
		Name = "Btn_" .. config.Key,
		Position = UDim2.new(0, 0, 0, yOffset),
		Size = UDim2.new(0, BUTTON_WIDTH, 0, BUTTON_HEIGHT),
		BackgroundColor3 = config.Color,
		BorderSizePixel = 0,
		Text = config.Text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = BUTTON_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = parent,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, BUTTON_CORNER) }),
		},
	})

	-- Sombra sutil debajo del botón
	UIBuilder.Frame({
		Name = "Shadow",
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = button,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, BUTTON_CORNER) }),
		},
	})

	-- Hover: agranda ligeramente el botón y cambia color
	button.MouseEnter:Connect(function()
		UIBuilder.tween(button, 0.12, {
			BackgroundColor3 = config.HoverColor,
			Size = UDim2.new(0, BUTTON_WIDTH + 10, 0, BUTTON_HEIGHT + 4),
		})
	end)

	button.MouseLeave:Connect(function()
		UIBuilder.tween(button, 0.12, {
			BackgroundColor3 = config.Color,
			Size = UDim2.new(0, BUTTON_WIDTH, 0, BUTTON_HEIGHT),
		})
	end)

	-- Conectar callback si existe
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

-- Oculta el menú con animación de salida hacia la izquierda
function MainMenuComponent:hide()
	if not self.buttonPanel then
		return
	end

	local tween = UIBuilder.tween(self.buttonPanel, 0.3, {
		Position = UDim2.new(-0.5, 0, 0, PANEL_PADDING_TOP),
	}, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	tween.Completed:Wait()

	if self.element then
		self.element.Enabled = false
	end
end

-- Muestra el menú (re-entrada después de volver de sub-pantalla)
function MainMenuComponent:show()
	if not self.element then
		return
	end

	self.element.Enabled = true

	if self.buttonPanel then
		self.buttonPanel.Position = UDim2.new(-0.4, 0, 0, PANEL_PADDING_TOP)
		UIBuilder.tween(self.buttonPanel, 0.4, {
			Position = UDim2.new(0, PANEL_PADDING_LEFT, 0, PANEL_PADDING_TOP),
		}, Enum.EasingStyle.Back)
	end
end

-- Destruye toda la UI del menú
function MainMenuComponent:destroy()
	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return MainMenuComponent
