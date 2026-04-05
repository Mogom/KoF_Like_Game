--[[
	LobbyListComponent.luau
	-----------------------
	Pantalla para ver y unirse a lobbies disponibles.
	
	LAYOUT:
	┌──────────────────────────────────────────┐
	│  [← Back]      AVAILABLE LOBBIES         │
	├──────────────────────────────────────────┤
	│  ┌────────────────────────────────────┐  │
	│  │ Host: Player1  | FFA  | 3/4 players│  │
	│  │                        [JOIN]      │  │
	│  └────────────────────────────────────┘  │
	│  ┌────────────────────────────────────┐  │
	│  │ Host: Player2  | 1v1  | 1/2 players│  │
	│  │                        [JOIN]      │  │
	│  └────────────────────────────────────┘  │
	│                                          │
	│         [🔄 Refresh]                     │
	└──────────────────────────────────────────┘
	
	PROPS:
	  onBackClick: () -> ()
	  onJoinLobby: (lobbyId) -> ()
	  onRefresh: () -> () (opcional)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local LobbyListComponent = {}
LobbyListComponent.__index = LobbyListComponent

-- ============================================
-- CONFIGURACIÓN VISUAL
-- ============================================

local COLORS = {
	Background = Color3.fromRGB(12, 12, 18),
	Panel = Color3.fromRGB(30, 30, 40),
	PanelBorder = Color3.fromRGB(60, 60, 80),

	Title = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(200, 200, 210),
	TextMuted = Color3.fromRGB(140, 140, 160),

	LobbyCard = Color3.fromRGB(40, 40, 55),
	LobbyCardHover = Color3.fromRGB(50, 50, 70),

	JoinButton = Color3.fromRGB(50, 160, 50),
	JoinButtonHover = Color3.fromRGB(70, 200, 70),

	BackButton = Color3.fromRGB(60, 60, 70),
	BackButtonHover = Color3.fromRGB(90, 90, 100),

	RefreshButton = Color3.fromRGB(60, 100, 160),
	RefreshButtonHover = Color3.fromRGB(80, 130, 200),

	NoLobbies = Color3.fromRGB(100, 100, 120),
}

local SIZES = {
	TitleSize = 32,
	TextSize = 18,
	ButtonTextSize = 20,

	LobbyCardHeight = 80,
	LobbyCardSpacing = 12,

	Padding = 30,
	CornerRadius = 10,
}

-- ============================================
-- CONSTRUCTOR
-- ============================================

function LobbyListComponent.new(parent, props)
	local self = setmetatable({}, LobbyListComponent)

	self.props = props or {}
	self.element = nil
	self.lobbyCards = {}
	self.lobbiesContainer = nil

	self.onBackClick = self.props.onBackClick
	self.onJoinLobby = self.props.onJoinLobby
	self.onRefresh = self.props.onRefresh

	-- Lista inicial de lobbies (vacía)
	self.lobbies = self.props.lobbies or {}

	local success, err = pcall(function()
		self:render(parent)
	end)

	if not success then
		warn("❌ Error creating LobbyListComponent:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

function LobbyListComponent:render(parent)
	local screenGui = UIBuilder.ScreenGui({
		Name = "LobbyList",
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

	-- Header
	local header = UIBuilder.Frame({
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.new(0, 0, 0, 20),
		BackgroundTransparency = 1,
		Parent = background,
	})

	-- Botón Back
	local backButton = UIBuilder.TextButton({
		Name = "BackButton",
		Size = UDim2.new(0, 120, 0, 45),
		Position = UDim2.new(0, SIZES.Padding, 0.5, -22),
		BackgroundColor3 = COLORS.BackButton,
		Text = "← Back",
		TextColor3 = COLORS.Text,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamBold,
		Parent = header,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = backButton })

	backButton.MouseEnter:Connect(function()
		UIBuilder.tween(backButton, 0.15, { BackgroundColor3 = COLORS.BackButtonHover })
	end)
	backButton.MouseLeave:Connect(function()
		UIBuilder.tween(backButton, 0.15, { BackgroundColor3 = COLORS.BackButton })
	end)
	backButton.MouseButton1Click:Connect(function()
		if self.onBackClick then
			self.onBackClick()
		end
	end)

	-- Título
	UIBuilder.TextLabel({
		Name = "Title",
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.new(0.2, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = "AVAILABLE LOBBIES",
		TextColor3 = COLORS.Title,
		TextSize = SIZES.TitleSize,
		Font = Enum.Font.GothamBlack,
		Parent = header,
	})

	-- Botón Refresh
	local refreshButton = UIBuilder.TextButton({
		Name = "RefreshButton",
		Size = UDim2.new(0, 120, 0, 45),
		Position = UDim2.new(1, -SIZES.Padding - 120, 0.5, -22),
		BackgroundColor3 = COLORS.RefreshButton,
		Text = "🔄 Refresh",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamBold,
		Parent = header,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = refreshButton })

	refreshButton.MouseEnter:Connect(function()
		UIBuilder.tween(refreshButton, 0.15, { BackgroundColor3 = COLORS.RefreshButtonHover })
	end)
	refreshButton.MouseLeave:Connect(function()
		UIBuilder.tween(refreshButton, 0.15, { BackgroundColor3 = COLORS.RefreshButton })
	end)
	refreshButton.MouseButton1Click:Connect(function()
		if self.onRefresh then
			self.onRefresh()
		end
	end)

	-- Container de lobbies (scrollable)
	local lobbiesFrame = UIBuilder.Frame({
		Name = "LobbiesContainer",
		Size = UDim2.new(1, -SIZES.Padding * 2, 1, -150),
		Position = UDim2.new(0, SIZES.Padding, 0, 100),
		BackgroundColor3 = COLORS.Panel,
		ClipsDescendants = true,
		Parent = background,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, SIZES.CornerRadius), Parent = lobbiesFrame })
	UIBuilder.UIStroke({ Color = COLORS.PanelBorder, Thickness = 1, Parent = lobbiesFrame })

	-- Scrolling frame interno
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ScrollFrame"
	scrollFrame.Size = UDim2.new(1, -10, 1, -10)
	scrollFrame.Position = UDim2.new(0, 5, 0, 5)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = COLORS.PanelBorder
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = lobbiesFrame
	self.lobbiesContainer = scrollFrame

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SIZES.LobbyCardSpacing)
	layout.Parent = scrollFrame

	-- Mensaje de "no lobbies"
	self.noLobbiesLabel = UIBuilder.TextLabel({
		Name = "NoLobbies",
		Size = UDim2.new(1, 0, 0, 100),
		BackgroundTransparency = 1,
		Text = "No lobbies available.\nCreate one or wait for others!",
		TextColor3 = COLORS.NoLobbies,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamMedium,
		Visible = #self.lobbies == 0,
		Parent = scrollFrame,
	})

	-- Renderizar lobbies iniciales
	self:updateLobbies(self.lobbies)
end

-- Crea una card para un lobby
function LobbyListComponent:_createLobbyCard(lobbyData, layoutOrder)
	local card = UIBuilder.Frame({
		Name = "LobbyCard_" .. lobbyData.id,
		Size = UDim2.new(1, -10, 0, SIZES.LobbyCardHeight),
		BackgroundColor3 = COLORS.LobbyCard,
		LayoutOrder = layoutOrder,
		Parent = self.lobbiesContainer,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = card })

	-- Host name
	UIBuilder.TextLabel({
		Name = "Host",
		Size = UDim2.new(0.3, 0, 0, 30),
		Position = UDim2.new(0, 15, 0, 10),
		BackgroundTransparency = 1,
		Text = "👑 " .. (lobbyData.host or "Unknown"),
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamBold,
		Parent = card,
	})

	-- Mode
	UIBuilder.TextLabel({
		Name = "Mode",
		Size = UDim2.new(0.25, 0, 0, 30),
		Position = UDim2.new(0.35, 0, 0, 10),
		BackgroundTransparency = 1,
		Text = lobbyData.mode or "Unknown",
		TextColor3 = COLORS.TextMuted,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamMedium,
		Parent = card,
	})

	-- Player count
	local playerText = (lobbyData.players or 0) .. "/" .. (lobbyData.maxPlayers or 4)
	UIBuilder.TextLabel({
		Name = "PlayerCount",
		Size = UDim2.new(0.2, 0, 0, 30),
		Position = UDim2.new(0.6, 0, 0, 10),
		BackgroundTransparency = 1,
		Text = "👥 " .. playerText,
		TextColor3 = COLORS.Text,
		TextSize = SIZES.TextSize,
		Font = Enum.Font.GothamMedium,
		Parent = card,
	})

	-- Join button
	local joinButton = UIBuilder.TextButton({
		Name = "JoinButton",
		Size = UDim2.new(0, 100, 0, 40),
		Position = UDim2.new(1, -115, 0.5, -20),
		BackgroundColor3 = COLORS.JoinButton,
		Text = "JOIN",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = SIZES.ButtonTextSize,
		Font = Enum.Font.GothamBlack,
		Parent = card,
	})
	UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8), Parent = joinButton })

	joinButton.MouseEnter:Connect(function()
		UIBuilder.tween(joinButton, 0.15, { BackgroundColor3 = COLORS.JoinButtonHover })
		UIBuilder.tween(card, 0.15, { BackgroundColor3 = COLORS.LobbyCardHover })
	end)
	joinButton.MouseLeave:Connect(function()
		UIBuilder.tween(joinButton, 0.15, { BackgroundColor3 = COLORS.JoinButton })
		UIBuilder.tween(card, 0.15, { BackgroundColor3 = COLORS.LobbyCard })
	end)
	joinButton.MouseButton1Click:Connect(function()
		if self.onJoinLobby then
			self.onJoinLobby(lobbyData.id)
		end
	end)

	return card
end

-- ============================================
-- MÉTODOS PÚBLICOS
-- ============================================

-- Actualiza la lista de lobbies
function LobbyListComponent:updateLobbies(lobbies)
	self.lobbies = lobbies or {}

	-- Limpiar cards existentes
	for _, card in ipairs(self.lobbyCards) do
		card:Destroy()
	end
	self.lobbyCards = {}

	-- Mostrar/ocultar mensaje de "no lobbies"
	if self.noLobbiesLabel then
		self.noLobbiesLabel.Visible = #self.lobbies == 0
	end

	-- Crear nuevas cards
	for i, lobbyData in ipairs(self.lobbies) do
		local card = self:_createLobbyCard(lobbyData, i)
		table.insert(self.lobbyCards, card)
	end
end

-- Destruye el componente
function LobbyListComponent:destroy()
	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return LobbyListComponent
