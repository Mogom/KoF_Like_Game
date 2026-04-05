--[[
	LobbyComponent.luau
	-------------------
	UI de Lobby para salas multijugador.
	
	CARACTERÍSTICAS:
	- Lista de jugadores en el lobby (con estado ready)
	- Selector de personaje individual
	- Botón Ready/Not Ready
	- Controles de Host (Kick, Start, Settings)
	- Indicador de Party members
	- Chat de lobby (opcional)
	
	LAYOUT:
	┌─────────────────────────────────────────────────────────────┐
	│  [← Back]              LOBBY - Free For All           [⚙️]  │
	├─────────────────────────────────────────────────────────────┤
	│                                                             │
	│  ┌─────────────────┐  ┌─────────────────────────────────┐  │
	│  │   PLAYERS (3/4) │  │      CHARACTER SELECT           │  │
	│  │  ┌────────────┐ │  │  ┌─────┐ ┌─────┐ ┌─────┐       │  │
	│  │  │👑 Host   ✓│ │  │  │ RYU │ │ KEN │ │ ... │       │  │
	│  │  └────────────┘ │  │  └─────┘ └─────┘ └─────┘       │  │
	│  │  ┌────────────┐ │  │                                 │  │
	│  │  │  Player2 ✓│ │  │  Ryu - The Wandering Warrior    │  │
	│  │  └────────────┘ │  │                                 │  │
	│  │  ┌────────────┐ │  └─────────────────────────────────┘  │
	│  │  │  Player3 ○│ │                                        │
	│  │  └────────────┘ │    [ READY ]     (or [ START ] host) │
	│  │  ┌────────────┐ │                                        │
	│  │  │   Empty    │ │    [ Leave Lobby ]                    │
	│  │  └────────────┘ │                                        │
	│  └─────────────────┘                                        │
	│                                                             │
	└─────────────────────────────────────────────────────────────┘
	
	PROPS:
	  lobby: LobbyData (de LobbyManager)
	  isHost: boolean
	  onBackClick: () -> ()
	  onReadyClick: (isReady) -> ()
	  onStartClick: () -> () (solo host)
	  onKickClick: (player) -> () (solo host)
	  onLeaveClick: () -> ()
	  onCharacterSelect: (characterName) -> ()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")
local Characters = Modules:WaitForChild("Characters")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))
local CharacterRegistry = require(Characters:WaitForChild("CharacterRegistry"))

local LobbyComponent = {}
LobbyComponent.__index = LobbyComponent

-- ============================================
-- CONFIGURACIÓN VISUAL
-- ============================================

local COLORS = {
	Background = Color3.fromRGB(12, 12, 18),
	Panel = Color3.fromRGB(25, 25, 35),
	PanelBorder = Color3.fromRGB(50, 50, 70),

	Title = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(200, 200, 210),
	TextMuted = Color3.fromRGB(120, 120, 140),

	Ready = Color3.fromRGB(50, 200, 80),
	NotReady = Color3.fromRGB(180, 180, 190),
	Host = Color3.fromRGB(255, 215, 0),

	ButtonPrimary = Color3.fromRGB(50, 160, 50),
	ButtonPrimaryHover = Color3.fromRGB(70, 200, 70),
	ButtonDanger = Color3.fromRGB(180, 50, 50),
	ButtonDangerHover = Color3.fromRGB(220, 70, 70),
	ButtonSecondary = Color3.fromRGB(60, 60, 80),
	ButtonSecondaryHover = Color3.fromRGB(90, 90, 110),

	CardDefault = Color3.fromRGB(35, 35, 50),
	CardSelected = Color3.fromRGB(255, 215, 0),
	CardHover = Color3.fromRGB(180, 180, 200),

	PlayerSlotEmpty = Color3.fromRGB(20, 20, 30),
	PlayerSlotFilled = Color3.fromRGB(40, 40, 55),
}

local SIZES = {
	TitleSize = 32,
	SubtitleSize = 20,
	TextSize = 16,
	ButtonTextSize = 20,

	PlayerListWidth = 280,
	CharSelectWidth = 500,

	PlayerSlotHeight = 50,
	CharCardSize = 100,

	ButtonHeight = 50,
	ButtonWidth = 200,

	Padding = 20,
	Spacing = 12,
	CornerRadius = 10,
}

-- ============================================
-- CONSTRUCTOR
-- ============================================

function LobbyComponent.new(parent, props)
	local self = setmetatable({}, LobbyComponent)

	self.props = props or {}
	self.lobby = self.props.lobby
	self.isHost = self.props.isHost or false
	self.isReady = false
	self.selectedCharacter = nil

	self.element = nil
	self.playerSlots = {}
	self.characterCards = {}
	self.readyButton = nil
	self.startButton = nil

	-- Callbacks
	self.onBackClick = self.props.onBackClick
	self.onReadyClick = self.props.onReadyClick
	self.onStartClick = self.props.onStartClick
	self.onKickClick = self.props.onKickClick
	self.onLeaveClick = self.props.onLeaveClick
	self.onCharacterSelect = self.props.onCharacterSelect

	local success, err = pcall(function()
		self:render(parent)
	end)

	if not success then
		warn("❌ Error creating LobbyComponent:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

function LobbyComponent:render(parent)
	-- ScreenGui principal
	local screenGui = UIBuilder.ScreenGui({
		Name = "LobbyUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- Fondo
	local background = UIBuilder.Frame({
		Name = "Background",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COLORS.Background,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	-- Container principal
	local mainContainer = UIBuilder.Frame({
		Name = "MainContainer",
		Size = UDim2.new(1, -SIZES.Padding * 2, 1, -SIZES.Padding * 2),
		Position = UDim2.new(0, SIZES.Padding, 0, SIZES.Padding),
		BackgroundTransparency = 1,
		Parent = background,
	})

	-- Header
	self:_renderHeader(mainContainer)

	-- Content area
	local contentArea = UIBuilder.Frame({
		Name = "ContentArea",
		Size = UDim2.new(1, 0, 1, -80),
		Position = UDim2.new(0, 0, 0, 70),
		BackgroundTransparency = 1,
		Parent = mainContainer,
	})

	-- Panel izquierdo: Lista de jugadores
	self:_renderPlayerList(contentArea)

	-- Panel derecho: Selector de personaje + botones
	self:_renderRightPanel(contentArea)
end

-- Renderiza el header con título y botón back
function LobbyComponent:_renderHeader(parent)
	local header = UIBuilder.Frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	-- Botón Back
	local backButton = UIBuilder.TextButton({
		Name = "BackButton",
		Size = UDim2.new(0, 100, 0, 40),
		Position = UDim2.new(0, 0, 0.5, -20),
		BackgroundColor3 = COLORS.ButtonSecondary,
		Text = "← Back",
		TextColor3 = COLORS.Text,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamBold,
		Parent = header,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = backButton })

	backButton.MouseEnter:Connect(function()
		UIBuilder.tween(backButton, 0.15, { BackgroundColor3 = COLORS.ButtonSecondaryHover })
	end)
	backButton.MouseLeave:Connect(function()
		UIBuilder.tween(backButton, 0.15, { BackgroundColor3 = COLORS.ButtonSecondary })
	end)
	backButton.MouseButton1Click:Connect(function()
		if self.onBackClick then
			self.onBackClick()
		end
	end)

	-- Título del lobby
	local modeName = self.lobby and self.lobby.mode or "Lobby"
	local maxPlayers = self.lobby and self.lobby.maxPlayers or 4

	UIBuilder.TextLabel({
		Name = "Title",
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.new(0.2, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "LOBBY - " .. modeName,
		TextColor3 = COLORS.Title,
		TextSize = SIZES.TitleSize,
		Font = Enum.Font.GothamBlack,
		Parent = header,
	})

	-- Indicador de jugadores
	local playerCount = self.lobby and #self.lobby.players or 0
	local playerIndicator = UIBuilder.TextLabel({
		Name = "PlayerCount",
		Size = UDim2.new(0, 100, 0, 30),
		Position = UDim2.new(1, -110, 0.5, -15),
		BackgroundColor3 = COLORS.Panel,
		Text = playerCount .. "/" .. maxPlayers,
		TextColor3 = COLORS.Text,
		TextSize = SIZES.SubtitleSize,
		Font = Enum.Font.GothamBold,
		Parent = header,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = playerIndicator })
	self.playerCountLabel = playerIndicator
end

-- Renderiza la lista de jugadores
function LobbyComponent:_renderPlayerList(parent)
	local panel = UIBuilder.Frame({
		Name = "PlayerListPanel",
		Size = UDim2.new(0, SIZES.PlayerListWidth, 1, -80),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = COLORS.Panel,
		Parent = parent,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = panel })
	UIBuilder.UIStroke({ Color = COLORS.PanelBorder, Thickness = 1, Parent = panel })

	-- Título
	UIBuilder.TextLabel({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "PLAYERS",
		TextColor3 = COLORS.Title,
		TextSize = SIZES.SubtitleSize,
		Font = Enum.Font.GothamBold,
		Parent = panel,
	})

	-- Container de slots
	local slotsContainer = UIBuilder.Frame({
		Name = "SlotsContainer",
		Size = UDim2.new(1, -SIZES.Spacing * 2, 1, -50),
		Position = UDim2.new(0, SIZES.Spacing, 0, 45),
		BackgroundTransparency = 1,
		Parent = panel,
	})

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = slotsContainer

	-- Crear slots para máximo de jugadores
	local maxPlayers = self.lobby and self.lobby.maxPlayers or 4
	for i = 1, maxPlayers do
		local slot = self:_createPlayerSlot(slotsContainer, i)
		self.playerSlots[i] = slot
	end

	-- Actualizar con datos actuales
	self:updatePlayerList()
end

-- Crea un slot de jugador
function LobbyComponent:_createPlayerSlot(parent, index)
	local slot = UIBuilder.Frame({
		Name = "PlayerSlot" .. index,
		Size = UDim2.new(1, 0, 0, SIZES.PlayerSlotHeight),
		BackgroundColor3 = COLORS.PlayerSlotEmpty,
		LayoutOrder = index,
		Parent = parent,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = slot })

	-- Icono de host/ready
	local statusIcon = UIBuilder.TextLabel({
		Name = "StatusIcon",
		Size = UDim2.new(0, 30, 0, 30),
		Position = UDim2.new(0, 8, 0.5, -15),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		Parent = slot,
	})

	-- Nombre del jugador
	local nameLabel = UIBuilder.TextLabel({
		Name = "PlayerName",
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.new(0, 45, 0, 0),
		BackgroundTransparency = 1,
		Text = "Empty",
		TextColor3 = COLORS.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamMedium,
		Parent = slot,
	})

	-- Ready indicator
	local readyIndicator = UIBuilder.TextLabel({
		Name = "ReadyIndicator",
		Size = UDim2.new(0, 40, 0, 30),
		Position = UDim2.new(1, -50, 0.5, -15),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = COLORS.NotReady,
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		Parent = slot,
	})

	-- Botón de kick (solo visible para host, sobre otros jugadores)
	local kickButton = UIBuilder.TextButton({
		Name = "KickButton",
		Size = UDim2.new(0, 24, 0, 24),
		Position = UDim2.new(1, -30, 0.5, -12),
		BackgroundColor3 = COLORS.ButtonDanger,
		Text = "✕",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Visible = false,
		Parent = slot,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 6), Parent = kickButton })

	return {
		frame = slot,
		nameLabel = nameLabel,
		statusIcon = statusIcon,
		readyIndicator = readyIndicator,
		kickButton = kickButton,
		player = nil,
	}
end

-- Renderiza el panel derecho (character select + botones)
function LobbyComponent:_renderRightPanel(parent)
	local rightPanel = UIBuilder.Frame({
		Name = "RightPanel",
		Size = UDim2.new(1, -SIZES.PlayerListWidth - SIZES.Spacing, 1, 0),
		Position = UDim2.new(0, SIZES.PlayerListWidth + SIZES.Spacing, 0, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	-- Character Select Panel
	self:_renderCharacterSelect(rightPanel)

	-- Botones de acción
	self:_renderActionButtons(rightPanel)
end

-- Renderiza el selector de personaje
function LobbyComponent:_renderCharacterSelect(parent)
	local panel = UIBuilder.Frame({
		Name = "CharacterSelectPanel",
		Size = UDim2.new(1, 0, 0.7, -SIZES.Spacing),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = COLORS.Panel,
		Parent = parent,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = panel })
	UIBuilder.UIStroke({ Color = COLORS.PanelBorder, Thickness = 1, Parent = panel })

	-- Título
	UIBuilder.TextLabel({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Text = "SELECT CHARACTER",
		TextColor3 = COLORS.Title,
		TextSize = SIZES.SubtitleSize,
		Font = Enum.Font.GothamBold,
		Parent = panel,
	})

	-- Grid de personajes
	local gridContainer = UIBuilder.Frame({
		Name = "CharacterGrid",
		Size = UDim2.new(1, -SIZES.Spacing * 2, 0.6, 0),
		Position = UDim2.new(0, SIZES.Spacing, 0, 50),
		BackgroundTransparency = 1,
		Parent = panel,
	})

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, SIZES.CharCardSize, 0, SIZES.CharCardSize + 30)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = gridContainer

	-- Crear cards de personajes
	local characters = CharacterRegistry.GetAll()
	local firstCharName = nil

	-- CharacterRegistry.GetAll() returns an array, iterate with ipairs
	for _, charData in ipairs(characters) do
		local name = charData.Info and charData.Info.Name or "Unknown"
		if not firstCharName then
			firstCharName = name
		end

		local card = self:_createCharacterCard(gridContainer, name, charData)
		self.characterCards[name] = card
	end

	-- Descripción del personaje seleccionado
	local descLabel = UIBuilder.TextLabel({
		Name = "Description",
		Size = UDim2.new(1, -SIZES.Spacing * 2, 0, 50),
		Position = UDim2.new(0, SIZES.Spacing, 1, -60),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = COLORS.TextMuted,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		Parent = panel,
	})
	self.descLabel = descLabel

	-- Seleccionar primero por defecto
	if firstCharName then
		self:selectCharacter(firstCharName)
	end
end

-- Crea una card de personaje
function LobbyComponent:_createCharacterCard(parent, charName, charData)
	local card = UIBuilder.Frame({
		Name = "Card_" .. charName,
		BackgroundColor3 = COLORS.CardDefault,
		Parent = parent,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = card })

	local stroke = UIBuilder.UIStroke({
		Color = COLORS.CardDefault,
		Thickness = 2,
		Parent = card,
	})

	-- Imagen del personaje (placeholder)
	local image = UIBuilder.Frame({
		Name = "Image",
		Size = UDim2.new(1, -10, 0, SIZES.CharCardSize - 10),
		Position = UDim2.new(0, 5, 0, 5),
		BackgroundColor3 = COLORS.Panel,
		Parent = card,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 6), Parent = image })

	-- Placeholder text
	UIBuilder.TextLabel({
		Name = "Placeholder",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = charName:sub(1, 1):upper(),
		TextColor3 = COLORS.Text,
		TextSize = 40,
		Font = Enum.Font.GothamBlack,
		Parent = image,
	})

	-- Nombre
	UIBuilder.TextLabel({
		Name = "Name",
		Size = UDim2.new(1, 0, 0, 25),
		Position = UDim2.new(0, 0, 1, -28),
		BackgroundTransparency = 1,
		Text = charName,
		TextColor3 = COLORS.Text,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Parent = card,
	})

	-- Click handler
	local button = UIBuilder.TextButton({
		Name = "ClickArea",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = card,
	})

	button.MouseEnter:Connect(function()
		if self.selectedCharacter ~= charName then
			UIBuilder.tween(stroke, 0.15, { Color = COLORS.CardHover })
		end
	end)

	button.MouseLeave:Connect(function()
		if self.selectedCharacter ~= charName then
			UIBuilder.tween(stroke, 0.15, { Color = COLORS.CardDefault })
		end
	end)

	button.MouseButton1Click:Connect(function()
		self:selectCharacter(charName)
	end)

	return {
		frame = card,
		stroke = stroke,
		name = charName,
	}
end

-- Renderiza los botones de acción
function LobbyComponent:_renderActionButtons(parent)
	local buttonPanel = UIBuilder.Frame({
		Name = "ActionButtons",
		Size = UDim2.new(1, 0, 0.3, 0),
		Position = UDim2.new(0, 0, 0.7, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	-- Ready Button (para no-hosts)
	local readyButton = UIBuilder.TextButton({
		Name = "ReadyButton",
		Size = UDim2.new(0, SIZES.ButtonWidth, 0, SIZES.ButtonHeight),
		Position = UDim2.new(0.5, -SIZES.ButtonWidth / 2, 0.3, 0),
		BackgroundColor3 = COLORS.ButtonPrimary,
		Text = "READY",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = SIZES.ButtonTextSize,
		Font = Enum.Font.GothamBlack,
		Visible = not self.isHost,
		Parent = buttonPanel,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = readyButton })
	self.readyButton = readyButton

	readyButton.MouseEnter:Connect(function()
		UIBuilder.tween(readyButton, 0.15, { BackgroundColor3 = COLORS.ButtonPrimaryHover })
	end)
	readyButton.MouseLeave:Connect(function()
		local color = self.isReady and COLORS.NotReady or COLORS.ButtonPrimary
		UIBuilder.tween(readyButton, 0.15, { BackgroundColor3 = color })
	end)
	readyButton.MouseButton1Click:Connect(function()
		self:toggleReady()
	end)

	-- Start Button (solo para host)
	local startButton = UIBuilder.TextButton({
		Name = "StartButton",
		Size = UDim2.new(0, SIZES.ButtonWidth, 0, SIZES.ButtonHeight),
		Position = UDim2.new(0.5, -SIZES.ButtonWidth / 2, 0.3, 0),
		BackgroundColor3 = COLORS.ButtonPrimary,
		Text = "START MATCH",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = SIZES.ButtonTextSize,
		Font = Enum.Font.GothamBlack,
		Visible = self.isHost,
		Parent = buttonPanel,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = startButton })
	self.startButton = startButton

	startButton.MouseEnter:Connect(function()
		UIBuilder.tween(startButton, 0.15, { BackgroundColor3 = COLORS.ButtonPrimaryHover })
	end)
	startButton.MouseLeave:Connect(function()
		UIBuilder.tween(startButton, 0.15, { BackgroundColor3 = COLORS.ButtonPrimary })
	end)
	startButton.MouseButton1Click:Connect(function()
		if self.onStartClick then
			self.onStartClick()
		end
	end)

	-- Leave Button
	local leaveButton = UIBuilder.TextButton({
		Name = "LeaveButton",
		Size = UDim2.new(0, 150, 0, 40),
		Position = UDim2.new(0.5, -75, 0.7, 0),
		BackgroundColor3 = COLORS.ButtonDanger,
		Text = "Leave Lobby",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamBold,
		Parent = buttonPanel,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = leaveButton })

	leaveButton.MouseEnter:Connect(function()
		UIBuilder.tween(leaveButton, 0.15, { BackgroundColor3 = COLORS.ButtonDangerHover })
	end)
	leaveButton.MouseLeave:Connect(function()
		UIBuilder.tween(leaveButton, 0.15, { BackgroundColor3 = COLORS.ButtonDanger })
	end)
	leaveButton.MouseButton1Click:Connect(function()
		if self.onLeaveClick then
			self.onLeaveClick()
		end
	end)
end

-- ============================================
-- MÉTODOS PÚBLICOS
-- ============================================

-- Selecciona un personaje
function LobbyComponent:selectCharacter(charName)
	-- Deseleccionar anterior
	if self.selectedCharacter and self.characterCards[self.selectedCharacter] then
		local oldCard = self.characterCards[self.selectedCharacter]
		UIBuilder.tween(oldCard.stroke, 0.2, { Color = COLORS.CardDefault })
	end

	-- Seleccionar nuevo
	self.selectedCharacter = charName

	if self.characterCards[charName] then
		local card = self.characterCards[charName]
		UIBuilder.tween(card.stroke, 0.2, { Color = COLORS.CardSelected })
	end

	-- Actualizar descripción
	local charData = CharacterRegistry.Get(charName)
	if charData and self.descLabel then
		self.descLabel.Text = charData.description or (charName .. " - Ready for battle!")
	end

	-- Callback
	if self.onCharacterSelect then
		self.onCharacterSelect(charName)
	end
end

-- Toggle estado ready
function LobbyComponent:toggleReady()
	self.isReady = not self.isReady

	if self.readyButton then
		self.readyButton.Text = self.isReady and "NOT READY" or "READY"
		local color = self.isReady and COLORS.NotReady or COLORS.ButtonPrimary
		UIBuilder.tween(self.readyButton, 0.2, { BackgroundColor3 = color })
	end

	if self.onReadyClick then
		self.onReadyClick(self.isReady)
	end
end

-- Actualiza la lista de jugadores
function LobbyComponent:updatePlayerList()
	if not self.lobby then
		return
	end

	local players = self.lobby.players
	local readyState = self.lobby.readyState or {}
	local hostPlayer = self.lobby.host

	for i, slot in ipairs(self.playerSlots) do
		local player = players[i]

		if player then
			-- Slot ocupado
			slot.frame.BackgroundColor3 = COLORS.PlayerSlotFilled
			slot.nameLabel.Text = player.Name
			slot.nameLabel.TextColor3 = COLORS.Text

			-- Indicador de host
			if player == hostPlayer then
				slot.statusIcon.Text = "👑"
				slot.statusIcon.TextColor3 = COLORS.Host
			else
				slot.statusIcon.Text = ""
			end

			-- Indicador de ready
			local isReady = readyState[player]
			slot.readyIndicator.Text = isReady and "✓" or "○"
			slot.readyIndicator.TextColor3 = isReady and COLORS.Ready or COLORS.NotReady

			-- Botón kick (solo para host, no sobre sí mismo)
			local localPlayer = Players.LocalPlayer
			local showKick = self.isHost and player ~= localPlayer and player ~= hostPlayer
			slot.kickButton.Visible = showKick

			if showKick then
				-- Conectar click (limpiar conexión anterior si existe)
				if slot.kickConnection then
					slot.kickConnection:Disconnect()
				end
				slot.kickConnection = slot.kickButton.MouseButton1Click:Connect(function()
					if self.onKickClick then
						self.onKickClick(player)
					end
				end)
			end

			slot.player = player
		else
			-- Slot vacío
			slot.frame.BackgroundColor3 = COLORS.PlayerSlotEmpty
			slot.nameLabel.Text = "Empty"
			slot.nameLabel.TextColor3 = COLORS.TextMuted
			slot.statusIcon.Text = ""
			slot.readyIndicator.Text = ""
			slot.kickButton.Visible = false
			slot.player = nil
		end
	end

	-- Actualizar contador
	if self.playerCountLabel then
		self.playerCountLabel.Text = #players .. "/" .. self.lobby.maxPlayers
	end
end

-- Actualiza los datos del lobby
function LobbyComponent:updateLobby(newLobby, newIsHost)
	self.lobby = newLobby

	if newIsHost ~= nil then
		self.isHost = newIsHost

		-- Mostrar/ocultar botones según rol
		if self.readyButton then
			self.readyButton.Visible = not self.isHost
		end
		if self.startButton then
			self.startButton.Visible = self.isHost
		end
	end

	self:updatePlayerList()
end

-- Destruye el componente
function LobbyComponent:destroy()
	-- Limpiar conexiones de kick
	for _, slot in ipairs(self.playerSlots) do
		if slot.kickConnection then
			slot.kickConnection:Disconnect()
		end
	end

	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

-- Alias para compatibilidad
LobbyComponent.Destroy = LobbyComponent.destroy

return LobbyComponent
