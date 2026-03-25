--[[
	CharacterSelectComponent.luau
	------------------------------
	Pantalla de selección de personaje antes de entrar a un modo de juego.
	Soporta modo simple (1 personaje) y modo dual (jugador + dummy para Training).

	MODO SIMPLE (Versus, etc):
	┌──────────────────────────────────────────┐
	│          SELECCIONA TU PERSONAJE         │
	│   ┌──────────┐     ┌──────────┐          │
	│   │   RYU    │     │   KEN    │          │
	│   └──────────┘     └──────────┘          │
	│   Descripción del personaje aquí...      │
	│    [Confirmar]          [← Volver]        │
	└──────────────────────────────────────────┘

	MODO DUAL (Training):
	┌──────────────────────────────────────────┐
	│           TU PERSONAJE                   │
	│   ┌──────────┐     ┌──────────┐          │
	│   │   RYU    │     │   KEN    │          │
	│   └──────────┘     └──────────┘          │
	│                                          │
	│        PERSONAJE DEL DUMMY               │
	│   ┌──────────┐     ┌──────────┐          │
	│   │   RYU    │     │   KEN    │          │
	│   └──────────┘     └──────────┘          │
	│    [Confirmar]          [← Volver]        │
	└──────────────────────────────────────────┘

	PROPS (pasar al crear):
	  onConfirm(characterName)                   → modo simple
	  onConfirm(characterName, dummyCharName)     → modo dual
	  onBackClick()                               → se llama al pulsar Volver
	  dualSelect (bool)                           → true para Training (selección doble)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")
local Characters = Modules:WaitForChild("Characters")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))
local CharacterRegistry = require(Characters:WaitForChild("CharacterRegistry"))

local CharacterSelectComponent = {}
CharacterSelectComponent.__index = CharacterSelectComponent

-- ============================================
-- CONFIGURACIÓN VISUAL (editar aquí)
-- ============================================

local BACKGROUND_COLOR = Color3.fromRGB(10, 10, 16)
local TITLE_TEXT = "SELECCIONA TU PERSONAJE"
local TITLE_COLOR = Color3.fromRGB(255, 255, 255)
local TITLE_SIZE = 36

local CARD_WIDTH = 160
local CARD_HEIGHT = 200
local CARD_SPACING = 30
local CARD_CORNER = 12
local CARD_DEFAULT_COLOR = Color3.fromRGB(35, 35, 50)
local CARD_SELECTED_STROKE = Color3.fromRGB(255, 215, 0) -- Dorado
local CARD_HOVER_STROKE = Color3.fromRGB(180, 180, 200)

local NAME_TEXT_SIZE = 24
local DESC_TEXT_SIZE = 18
local STATS_TEXT_SIZE = 16

local CONFIRM_COLOR = Color3.fromRGB(50, 160, 50)
local CONFIRM_HOVER = Color3.fromRGB(70, 200, 70)
local BACK_COLOR = Color3.fromRGB(60, 60, 70)
local BACK_HOVER = Color3.fromRGB(90, 90, 100)

-- Colores para modo dual
local DUMMY_SELECTED_STROKE = Color3.fromRGB(100, 180, 255) -- Azul claro para dummy

-- ============================================
-- CONSTRUCTOR
-- ============================================

function CharacterSelectComponent.new(parent, props)
	local self = setmetatable({}, CharacterSelectComponent)

	self.props = props or {}
	self.dualSelect = self.props.dualSelect or false
	self.element = nil
	self.cards = {} -- Tarjetas del jugador
	self.dummyCards = {} -- Tarjetas del dummy (solo en dualSelect)
	self.selectedName = nil
	self.selectedStroke = nil
	self.dummySelectedName = nil
	self.dummySelectedStroke = nil
	self.descLabel = nil
	self.statsLabel = nil
	self.confirmButton = nil

	local characters = CharacterRegistry.GetAll()

	-- Seleccionar el primero por defecto
	if #characters > 0 then
		self.selectedName = characters[1].Info.Name
		if self.dualSelect then
			self.dummySelectedName = characters[1].Info.Name
		end
	end

	local success, err = pcall(function()
		self:render(parent, characters)
	end)

	if not success then
		warn("Error creating CharacterSelect:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

function CharacterSelectComponent:render(parent, characters)
	local screenGui = UIBuilder.ScreenGui({
		Name = "CharacterSelect",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- Fondo
	UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BACKGROUND_COLOR,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	if self.dualSelect then
		self:_renderDualSelect(screenGui, characters)
	else
		self:_renderSingleSelect(screenGui, characters)
	end
end

-- ============================================
-- RENDER MODO SIMPLE (Versus, etc.)
-- ============================================

function CharacterSelectComponent:_renderSingleSelect(screenGui, characters)
	-- Título
	UIBuilder.TextLabel({
		Name = "Title",
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.new(0, 600, 0, 50),
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

	-- Contenedor de tarjetas (centrado)
	local totalWidth = #characters * CARD_WIDTH + (#characters - 1) * CARD_SPACING
	local cardContainer = UIBuilder.Frame({
		Name = "CardContainer",
		Position = UDim2.new(0.5, 0, 0.35, 0),
		Size = UDim2.new(0, totalWidth, 0, CARD_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	-- Crear tarjetas de personaje
	for i, character in ipairs(characters) do
		local xOffset = (i - 1) * (CARD_WIDTH + CARD_SPACING)
		self:_createCharacterCard(cardContainer, character, xOffset, "player")
	end

	-- Panel de info
	local infoPanel = UIBuilder.Frame({
		Name = "InfoPanel",
		Position = UDim2.new(0.5, 0, 0.58, 0),
		Size = UDim2.new(0, 500, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
		},
	})

	self.descLabel = UIBuilder.TextLabel({
		Name = "Description",
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.9, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(200, 200, 210),
		TextSize = DESC_TEXT_SIZE,
		Font = Enum.Font.Gotham,
		Parent = infoPanel,
	})

	self.statsLabel = UIBuilder.TextLabel({
		Name = "Stats",
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(0.9, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(160, 160, 180),
		TextSize = STATS_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		Parent = infoPanel,
	})

	-- Botones
	self:_renderButtons(screenGui, 0.82)

	-- Animación de entrada
	cardContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	UIBuilder.tween(cardContainer, 0.35, {
		Position = UDim2.new(0.5, 0, 0.35, 0),
	}, Enum.EasingStyle.Back)

	self:_updateInfo()
end

-- ============================================
-- RENDER MODO DUAL (Training: jugador + dummy)
-- ============================================

function CharacterSelectComponent:_renderDualSelect(screenGui, characters)
	local SMALL_CARD_HEIGHT = 140
	local SMALL_CARD_WIDTH = 120

	-- Título: Tu personaje
	UIBuilder.TextLabel({
		Name = "PlayerTitle",
		Position = UDim2.new(0.5, 0, 0, 25),
		Size = UDim2.new(0, 600, 0, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "TU PERSONAJE",
		TextColor3 = CARD_SELECTED_STROKE,
		TextSize = 28,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = screenGui,
	})

	-- Tarjetas del jugador (arriba)
	local totalWidth = #characters * SMALL_CARD_WIDTH + (#characters - 1) * CARD_SPACING
	local playerContainer = UIBuilder.Frame({
		Name = "PlayerCardContainer",
		Position = UDim2.new(0.5, 0, 0.22, 0),
		Size = UDim2.new(0, totalWidth, 0, SMALL_CARD_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	for i, character in ipairs(characters) do
		local xOffset = (i - 1) * (SMALL_CARD_WIDTH + CARD_SPACING)
		self:_createCharacterCard(playerContainer, character, xOffset, "player", SMALL_CARD_WIDTH, SMALL_CARD_HEIGHT)
	end

	-- Título: Personaje del dummy
	UIBuilder.TextLabel({
		Name = "DummyTitle",
		Position = UDim2.new(0.5, 0, 0.38, 0),
		Size = UDim2.new(0, 600, 0, 36),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "PERSONAJE DEL DUMMY",
		TextColor3 = DUMMY_SELECTED_STROKE,
		TextSize = 28,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = screenGui,
	})

	-- Tarjetas del dummy (abajo)
	local dummyContainer = UIBuilder.Frame({
		Name = "DummyCardContainer",
		Position = UDim2.new(0.5, 0, 0.55, 0),
		Size = UDim2.new(0, totalWidth, 0, SMALL_CARD_HEIGHT),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	for i, character in ipairs(characters) do
		local xOffset = (i - 1) * (SMALL_CARD_WIDTH + CARD_SPACING)
		self:_createCharacterCard(dummyContainer, character, xOffset, "dummy", SMALL_CARD_WIDTH, SMALL_CARD_HEIGHT)
	end

	-- Panel de info (compacto, debajo de ambas selecciones)
	local infoPanel = UIBuilder.Frame({
		Name = "InfoPanel",
		Position = UDim2.new(0.5, 0, 0.68, 0),
		Size = UDim2.new(0, 500, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
		},
	})

	self.descLabel = UIBuilder.TextLabel({
		Name = "Description",
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.9, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(200, 200, 210),
		TextSize = DESC_TEXT_SIZE - 2,
		Font = Enum.Font.Gotham,
		Parent = infoPanel,
	})

	self.statsLabel = UIBuilder.TextLabel({
		Name = "Stats",
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.new(0.9, 0, 0, 22),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(160, 160, 180),
		TextSize = STATS_TEXT_SIZE - 2,
		Font = Enum.Font.GothamBold,
		Parent = infoPanel,
	})

	-- Botones
	self:_renderButtons(screenGui, 0.85)

	-- Animaciones de entrada
	playerContainer.Position = UDim2.new(0.5, 0, 0.30, 0)
	UIBuilder.tween(playerContainer, 0.35, {
		Position = UDim2.new(0.5, 0, 0.22, 0),
	}, Enum.EasingStyle.Back)

	dummyContainer.Position = UDim2.new(0.5, 0, 0.63, 0)
	UIBuilder.tween(dummyContainer, 0.35, {
		Position = UDim2.new(0.5, 0, 0.55, 0),
	}, Enum.EasingStyle.Back)

	self:_updateInfo()
end

-- ============================================
-- BOTONES (compartidos entre modos)
-- ============================================

function CharacterSelectComponent:_renderButtons(screenGui, yPos)
	self.confirmButton = UIBuilder.TextButton({
		Name = "ConfirmButton",
		Position = UDim2.new(0.35, 0, yPos, 0),
		Size = UDim2.new(0, 200, 0, 55),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = CONFIRM_COLOR,
		BorderSizePixel = 0,
		Text = "CONFIRMAR",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 10) }),
			UIBuilder.UIStroke({ Color = Color3.fromRGB(255, 255, 255), Thickness = 2, Transparency = 0.7 }),
		},
	})

	self.confirmButton.MouseEnter:Connect(function()
		UIBuilder.tween(self.confirmButton, 0.12, { BackgroundColor3 = CONFIRM_HOVER })
	end)
	self.confirmButton.MouseLeave:Connect(function()
		UIBuilder.tween(self.confirmButton, 0.12, { BackgroundColor3 = CONFIRM_COLOR })
	end)

	if self.props.onConfirm then
		self.confirmButton.MouseButton1Click:Connect(function()
			if self.selectedName then
				if self.dualSelect then
					self.props.onConfirm(self.selectedName, self.dummySelectedName)
				else
					self.props.onConfirm(self.selectedName)
				end
			end
		end)
	end

	local backButton = UIBuilder.TextButton({
		Name = "BackButton",
		Position = UDim2.new(0.65, 0, yPos, 0),
		Size = UDim2.new(0, 180, 0, 55),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = BACK_COLOR,
		BorderSizePixel = 0,
		Text = "← VOLVER",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 10) }),
		},
	})

	backButton.MouseEnter:Connect(function()
		UIBuilder.tween(backButton, 0.12, { BackgroundColor3 = BACK_HOVER })
	end)
	backButton.MouseLeave:Connect(function()
		UIBuilder.tween(backButton, 0.12, { BackgroundColor3 = BACK_COLOR })
	end)

	if self.props.onBackClick then
		backButton.MouseButton1Click:Connect(self.props.onBackClick)
	end
end

-- ============================================
-- TARJETA DE PERSONAJE
-- selectType: "player" o "dummy"
-- ============================================

function CharacterSelectComponent:_createCharacterCard(parent, character, xOffset, selectType, cardWidth, cardHeight)
	cardWidth = cardWidth or CARD_WIDTH
	cardHeight = cardHeight or CARD_HEIGHT
	local info = character.Info
	local charColor = info.Color or CARD_DEFAULT_COLOR

	local isDummy = selectType == "dummy"
	local selectedStrokeColor = isDummy and DUMMY_SELECTED_STROKE or CARD_SELECTED_STROKE
	local cardsTable = isDummy and self.dummyCards or self.cards
	local currentSelected = isDummy and self.dummySelectedName or self.selectedName

	local card = UIBuilder.Frame({
		Name = "Card_" .. selectType .. "_" .. info.Name,
		Position = UDim2.new(0, xOffset, 0, 0),
		Size = UDim2.new(0, cardWidth, 0, cardHeight),
		BackgroundColor3 = CARD_DEFAULT_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, CARD_CORNER) }),
		},
	})

	-- Barra de color del personaje (arriba)
	UIBuilder.Frame({
		Name = "ColorBar",
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = charColor,
		BorderSizePixel = 0,
		Parent = card,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, CARD_CORNER) }),
		},
	})

	-- Ícono placeholder (cuadrado con inicial)
	local iconSize = math.floor(cardHeight * 0.45)
	local iconFrame = UIBuilder.Frame({
		Name = "IconFrame",
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0, iconSize, 0, iconSize),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = charColor,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = card,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 10) }),
		},
	})

	UIBuilder.TextLabel({
		Name = "Initial",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = string.sub(info.Name, 1, 1),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = math.floor(iconSize * 0.6),
		Font = Enum.Font.GothamBold,
		Parent = iconFrame,
	})

	if info.Icon and info.Icon ~= "" then
		UIBuilder.ImageLabel({
			Name = "Icon",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Image = info.Icon,
			ScaleType = Enum.ScaleType.Fit,
			Parent = iconFrame,
		})
	end

	-- Nombre
	UIBuilder.TextLabel({
		Name = "CharName",
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0.9, 0, 0, 26),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = string.upper(info.Name),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = math.floor(NAME_TEXT_SIZE * (cardWidth / CARD_WIDTH)),
		Font = Enum.Font.GothamBold,
		Parent = card,
	})

	-- Stroke para selección
	local stroke = UIBuilder.UIStroke({
		Name = "SelectStroke",
		Color = Color3.fromRGB(80, 80, 100),
		Thickness = 2,
		Transparency = 0.5,
		Parent = card,
	})

	-- Si este es el seleccionado por defecto, marcar
	if info.Name == currentSelected then
		stroke.Color = selectedStrokeColor
		stroke.Thickness = 3
		stroke.Transparency = 0
		if isDummy then
			self.dummySelectedStroke = stroke
		else
			self.selectedStroke = stroke
		end
	end

	-- Interacción: crear botón invisible encima
	local clickArea = UIBuilder.TextButton({
		Name = "ClickArea",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = card,
	})

	clickArea.MouseEnter:Connect(function()
		local curSelected = isDummy and self.dummySelectedName or self.selectedName
		if info.Name ~= curSelected then
			UIBuilder.tween(stroke, 0.12, { Color = CARD_HOVER_STROKE, Transparency = 0.2 })
			UIBuilder.tween(card, 0.12, { Size = UDim2.new(0, cardWidth + 6, 0, cardHeight + 6) })
		end
	end)

	clickArea.MouseLeave:Connect(function()
		local curSelected = isDummy and self.dummySelectedName or self.selectedName
		if info.Name ~= curSelected then
			UIBuilder.tween(stroke, 0.12, { Color = Color3.fromRGB(80, 80, 100), Transparency = 0.5 })
			UIBuilder.tween(card, 0.12, { Size = UDim2.new(0, cardWidth, 0, cardHeight) })
		end
	end)

	clickArea.MouseButton1Click:Connect(function()
		self:_selectCharacter(info.Name, stroke, card, selectType, cardWidth, cardHeight)
	end)

	cardsTable[info.Name] = { card = card, stroke = stroke }
end

-- ============================================
-- SELECCIÓN
-- ============================================

function CharacterSelectComponent:_selectCharacter(name, stroke, card, selectType, cardWidth, cardHeight)
	cardWidth = cardWidth or CARD_WIDTH
	cardHeight = cardHeight or CARD_HEIGHT
	local isDummy = selectType == "dummy"
	local selectedStrokeColor = isDummy and DUMMY_SELECTED_STROKE or CARD_SELECTED_STROKE
	local cardsTable = isDummy and self.dummyCards or self.cards
	local prevStroke = isDummy and self.dummySelectedStroke or self.selectedStroke

	-- Deseleccionar anterior
	if prevStroke and prevStroke ~= stroke then
		UIBuilder.tween(prevStroke, 0.15, {
			Color = Color3.fromRGB(80, 80, 100),
			Thickness = 2,
			Transparency = 0.5,
		})
	end

	-- Restaurar tamaño de tarjetas anteriores
	for charName, data in pairs(cardsTable) do
		if charName ~= name then
			UIBuilder.tween(data.card, 0.12, {
				Size = UDim2.new(0, cardWidth, 0, cardHeight),
			})
		end
	end

	-- Seleccionar nueva
	if isDummy then
		self.dummySelectedName = name
		self.dummySelectedStroke = stroke
	else
		self.selectedName = name
		self.selectedStroke = stroke
	end

	UIBuilder.tween(stroke, 0.15, {
		Color = selectedStrokeColor,
		Thickness = 3,
		Transparency = 0,
	})

	UIBuilder.tween(card, 0.12, {
		Size = UDim2.new(0, cardWidth + 6, 0, cardHeight + 6),
	})

	if not isDummy then
		self:_updateInfo()
	end
end

-- Actualiza panel de descripción y stats
function CharacterSelectComponent:_updateInfo()
	if not self.selectedName then
		return
	end

	local char = CharacterRegistry.Get(self.selectedName)
	if not char then
		return
	end

	local info = char.Info

	if self.descLabel then
		self.descLabel.Text = info.Description or ""
	end

	if self.statsLabel then
		self.statsLabel.Text = string.format(
			"HP: %d   |   Speed: %d   |   Ataques: %d",
			info.Health or 100,
			info.WalkSpeed or 16,
			self:_countAttacks(char)
		)
	end
end

function CharacterSelectComponent:_countAttacks(char)
	local count = 0
	for _ in pairs(char.Attacks) do
		count += 1
	end
	return count
end

-- ============================================
-- MÉTODOS PÚBLICOS
-- ============================================

function CharacterSelectComponent:GetSelected()
	return self.selectedName
end

function CharacterSelectComponent:GetDummySelected()
	return self.dummySelectedName
end

function CharacterSelectComponent:destroy()
	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return CharacterSelectComponent
