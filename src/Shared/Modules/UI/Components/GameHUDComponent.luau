--[[
	GameHUDComponent.luau
	-----------------------
	HUD de combate estilo KOF / juego de pelea clásico.

	LAYOUT:
	┌───────────────────────────────────────┐
	│ [P1 Name]  ██████████ [44] ██████████ [P2 Name] │
	│            ← HP Bar →  Timer ← HP Bar →         │
	│ [P1 Photo]                        [P2 Photo]     │
	│                                                   │
	│              [COMBO COUNTER]                       │
	└───────────────────────────────────────┘

	CÓMO EDITAR:
	- Colores de barras P1/P2: P1_BAR_COLOR, P2_BAR_COLOR
	- Color de barra baja vida: LOW_HEALTH_COLOR, CRITICAL_HEALTH_COLOR
	- Tamaño de la barra: HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT
	- Timer: TIMER_SIZE, TIMER_COLOR
	- Nombre de jugadores: se obtiene dinámicamente del player y oponente
	- Ghost bar (daño reciente): GHOST_BAR_COLOR, GHOST_DELAY

	FUNCIONALIDAD:
	- updatePlayerHealth(health): actualiza barra P1 (jugador local)
	- updateOpponentHealth(health): actualiza barra P2 (oponente)
	- Se conecta automáticamente al Humanoid.HealthChanged del jugador
	- Para el oponente, escucha el atributo "Health" del humanoid del oponente
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local GameHUDComponent = {}
GameHUDComponent.__index = GameHUDComponent

-- ============================================
-- 🎨 CONFIGURACIÓN VISUAL (editar aquí)
-- ============================================

-- Colores de las barras de vida
local P1_BAR_COLOR = Color3.fromRGB(40, 200, 80) -- Verde para P1
local P2_BAR_COLOR = Color3.fromRGB(40, 200, 80) -- Verde para P2
local LOW_HEALTH_COLOR = Color3.fromRGB(230, 200, 20) -- Amarillo (< 40%)
local CRITICAL_HEALTH_COLOR = Color3.fromRGB(220, 40, 40) -- Rojo (< 20%)
local GHOST_BAR_COLOR = Color3.fromRGB(220, 50, 50) -- Rojo fantasma (daño reciente)
local HEALTH_BG_COLOR = Color3.fromRGB(30, 30, 35) -- Fondo de la barra

-- Tiempos de animación
local GHOST_DELAY = 0.4 -- Segundos antes de que la ghost bar empiece a bajar
local GHOST_SPEED = 0.6 -- Duración del tween de la ghost bar
local FILL_SPEED = 0.25 -- Duración del tween de la barra principal

-- Borde de las barras
local BAR_BORDER_COLOR_P1 = Color3.fromRGB(200, 200, 40) -- Amarillo dorado P1
local BAR_BORDER_COLOR_P2 = Color3.fromRGB(200, 200, 40) -- Amarillo dorado P2
local BAR_BORDER_THICKNESS = 3

-- Dimensiones de las barras de vida
local HEALTH_BAR_WIDTH = 380 -- px ancho de cada barra
local HEALTH_BAR_HEIGHT = 28 -- px alto de cada barra
local HEALTH_BAR_Y = 30 -- px desde arriba

-- Timer central
local TIMER_SIZE = 60 -- px ancho y alto del recuadro del timer
local TIMER_COLOR = Color3.fromRGB(255, 230, 50) -- Amarillo dorado
local TIMER_BG = Color3.fromRGB(20, 20, 30)

-- Nombres de jugador
local NAME_TEXT_SIZE = 16
local NAME_COLOR = Color3.fromRGB(220, 220, 220)

-- Portraits (placeholders)
local PORTRAIT_SIZE = 55 -- px
local PORTRAIT_BG = Color3.fromRGB(25, 25, 35)

-- Combo counter
local COMBO_TEXT_SIZE = 50
local COMBO_LABEL_SIZE = 20
local COMBO_COLOR = Color3.fromRGB(255, 200, 0)

-- ============================================
-- CONSTRUCTOR
-- ============================================

-- Crea el HUD de combate. Recibe el playerGui y el player local.
function GameHUDComponent.new(parent, player)
	local self = setmetatable({}, GameHUDComponent)

	self.player = player
	self.character = player.Character or player.CharacterAdded:Wait()
	self.humanoid = self.character:WaitForChild("Humanoid")
	self.element = nil

	-- Referencias a elementos de P1
	self.p1HealthFill = nil
	self.p1GhostFill = nil
	self.p1HealthText = nil
	self.p1NameLabel = nil

	-- Referencias a elementos de P2
	self.p2HealthFill = nil
	self.p2GhostFill = nil
	self.p2HealthText = nil
	self.p2NameLabel = nil

	-- Combo
	self.comboContainer = nil
	self.comboText = nil

	-- Timer
	self.timerText = nil

	-- Estado interno
	self.isFlashing = false
	self.opponentHumanoid = nil
	self.opponentConnection = nil

	local success, err = pcall(function()
		self:render(parent)
		self:_setupPlayerHealth()
		self:_setupOpponentHealth()
	end)

	if not success then
		warn("❌ Error creating GameHUD:", err)
		return nil
	end

	return self
end

-- ============================================
-- RENDER
-- ============================================

-- Construye toda la UI del HUD
function GameHUDComponent:render(parent)
	local screenGui = UIBuilder.ScreenGui({
		Name = "GameHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = parent,
	})
	self.element = screenGui

	-- ============================================
	-- TOP BAR (contenedor superior para barras de vida + timer)
	-- ============================================
	local topBar = UIBuilder.Frame({
		Name = "TopBar",
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(8, 8, 12),
		BorderSizePixel = 0,
		Parent = screenGui,
		Children = {
			UIBuilder.UIGradient({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.8, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			}),
		},
	})

	-- ============================================
	-- TIMER CENTRAL
	-- ============================================
	local timerContainer = UIBuilder.Frame({
		Name = "TimerContainer",
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, TIMER_SIZE, 0, TIMER_SIZE),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = TIMER_BG,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = screenGui,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 6) }),
			UIBuilder.UIStroke({
				Color = TIMER_COLOR,
				Thickness = 3,
			}),
		},
	})

	self.timerText = UIBuilder.TextLabel({
		Name = "TimerText",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "99",
		TextColor3 = TIMER_COLOR,
		TextSize = 36,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = timerContainer,
	})

	-- ============================================
	-- P1 HEALTH BAR (izquierda, la barra crece hacia la izquierda desde el centro)
	-- ============================================
	self:_createHealthBar({
		name = "P1",
		-- Posicionada a la izquierda del timer
		position = UDim2.new(0.5, -(TIMER_SIZE / 2) - 10, 0, HEALTH_BAR_Y),
		anchorPoint = Vector2.new(1, 0), -- anclada por la derecha (crece hacia izquierda)
		borderColor = BAR_BORDER_COLOR_P1,
		barColor = P1_BAR_COLOR,
		fillFromRight = true, -- la barra se vacía desde la izquierda
		parent = screenGui,
	})

	-- Portrait P1 (izquierda)
	self:_createPortrait({
		name = "P1Portrait",
		position = UDim2.new(0, 15, 0, 10),
		anchorPoint = Vector2.new(0, 0),
		parent = screenGui,
		label = "P1",
	})

	-- Nombre P1
	self.p1NameLabel = UIBuilder.TextLabel({
		Name = "P1Name",
		Position = UDim2.new(0, 15, 0, PORTRAIT_SIZE + 15),
		Size = UDim2.new(0, 200, 0, 20),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 1,
		Text = string.upper(self.player.Name),
		TextColor3 = NAME_COLOR,
		TextSize = NAME_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = screenGui,
	})

	-- ============================================
	-- P2 HEALTH BAR (derecha, crece hacia la derecha desde el centro)
	-- ============================================
	self:_createHealthBar({
		name = "P2",
		-- Posicionada a la derecha del timer
		position = UDim2.new(0.5, (TIMER_SIZE / 2) + 10, 0, HEALTH_BAR_Y),
		anchorPoint = Vector2.new(0, 0), -- anclada por la izquierda (crece hacia derecha)
		borderColor = BAR_BORDER_COLOR_P2,
		barColor = P2_BAR_COLOR,
		fillFromRight = false,
		parent = screenGui,
	})

	-- Portrait P2 (derecha)
	self:_createPortrait({
		name = "P2Portrait",
		position = UDim2.new(1, -15, 0, 10),
		anchorPoint = Vector2.new(1, 0),
		parent = screenGui,
		label = "P2",
	})

	-- Nombre P2
	self.p2NameLabel = UIBuilder.TextLabel({
		Name = "P2Name",
		Position = UDim2.new(1, -15, 0, PORTRAIT_SIZE + 15),
		Size = UDim2.new(0, 200, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Text = "OPPONENT",
		TextColor3 = NAME_COLOR,
		TextSize = NAME_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = screenGui,
	})

	-- ============================================
	-- COMBO COUNTER
	-- ============================================
	self.comboContainer = UIBuilder.Frame({
		Name = "ComboContainer",
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.new(0, 200, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screenGui,
	})

	self.comboText = UIBuilder.TextLabel({
		Name = "ComboText",
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		Text = "0",
		TextColor3 = COMBO_COLOR,
		TextSize = COMBO_TEXT_SIZE,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = self.comboContainer,
	})

	UIBuilder.TextLabel({
		Name = "ComboLabel",
		Position = UDim2.new(0, 0, 0.6, 0),
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundTransparency = 1,
		Text = "HITS",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = COMBO_LABEL_SIZE,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.5,
		Parent = self.comboContainer,
	})
end

-- ============================================
-- CREAR BARRA DE VIDA
-- ============================================

-- Crea una barra de vida con ghost bar para un jugador
function GameHUDComponent:_createHealthBar(props)
	local isP1 = props.name == "P1"

	-- Fondo de la barra
	local bg = UIBuilder.Frame({
		Name = props.name .. "HealthBg",
		Position = props.position,
		Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT),
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = HEALTH_BG_COLOR,
		BorderSizePixel = 0,
		Parent = props.parent,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 4) }),
			UIBuilder.UIStroke({
				Color = props.borderColor,
				Thickness = BAR_BORDER_THICKNESS,
			}),
		},
	})

	-- Ghost bar (roja, se ve cuando baja la vida - desaparece con delay)
	local ghostAnchorX = props.fillFromRight and 1 or 0
	local ghostPosX = props.fillFromRight and -3 or 3

	local ghostFill = UIBuilder.Frame({
		Name = props.name .. "GhostFill",
		Position = UDim2.new(ghostAnchorX, ghostPosX, 0, 3),
		Size = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(ghostAnchorX, 0),
		BackgroundColor3 = GHOST_BAR_COLOR,
		BorderSizePixel = 0,
		Parent = bg,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 3) }),
		},
	})

	-- Health fill (barra principal de color)
	local fillAnchorX = props.fillFromRight and 1 or 0
	local fillPosX = props.fillFromRight and -3 or 3

	local healthFill = UIBuilder.Frame({
		Name = props.name .. "HealthFill",
		Position = UDim2.new(fillAnchorX, fillPosX, 0, 3),
		Size = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(fillAnchorX, 0),
		BackgroundColor3 = props.barColor,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bg,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 3) }),
			-- Brillo superior (efecto de reflexión)
			UIBuilder.Frame({
				Name = "Shine",
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.new(1, 0, 0.4, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.75,
				BorderSizePixel = 0,
				ZIndex = 3,
				Children = {
					UIBuilder.UICorner({ CornerRadius = UDim.new(0, 3) }),
				},
			}),
		},
	})

	-- Texto de HP (porcentaje)
	local healthText = UIBuilder.TextLabel({
		Name = props.name .. "HealthText",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		ZIndex = 4,
		Parent = bg,
	})

	if isP1 then
		self.p1HealthFill = healthFill
		self.p1GhostFill = ghostFill
		self.p1HealthText = healthText
	else
		self.p2HealthFill = healthFill
		self.p2GhostFill = ghostFill
		self.p2HealthText = healthText
	end
end

-- ============================================
-- CREAR PORTRAIT
-- ============================================

-- Crea un frame de portrait placeholder para un jugador
function GameHUDComponent:_createPortrait(props)
	local portrait = UIBuilder.Frame({
		Name = props.name,
		Position = props.position,
		Size = UDim2.new(0, PORTRAIT_SIZE, 0, PORTRAIT_SIZE),
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = PORTRAIT_BG,
		BorderSizePixel = 0,
		Parent = props.parent,
		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 6) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(180, 180, 50),
				Thickness = 2,
			}),
		},
	})

	-- Texto placeholder
	UIBuilder.TextLabel({
		Name = "Label",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = props.label,
		TextColor3 = Color3.fromRGB(120, 120, 120),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		Parent = portrait,
	})

	return portrait
end

-- ============================================
-- HEALTH TRACKING
-- ============================================

-- Conecta listener de HP del jugador local
function GameHUDComponent:_setupPlayerHealth()
	if not self.humanoid then
		return
	end

	self.humanoid.HealthChanged:Connect(function(health)
		self:updatePlayerHealth(health)
	end)

	self:updatePlayerHealth(self.humanoid.Health)
end

-- Busca y conecta listener de HP del oponente
function GameHUDComponent:_setupOpponentHealth()
	-- Buscar oponente: dummy o jugador rival
	task.spawn(function()
		-- Esperar un poco a que el sistema asigne oponente
		task.wait(1)
		self:_findAndBindOpponent()

		-- También re-chequear periódicamente si aún no lo encontramos
		while not self.opponentHumanoid do
			task.wait(2)
			if not self.element or not self.element.Parent then
				return
			end
			self:_findAndBindOpponent()
		end
	end)
end

-- Busca el oponente (dummy o jugador) y conecta su HP
function GameHUDComponent:_findAndBindOpponent()
	-- Primero buscar dummy
	local dummy = workspace:FindFirstChild("Enemy") or workspace:FindFirstChild("TrainingDummy")
	if dummy then
		local dummyHumanoid = dummy:FindFirstChild("Humanoid")
		if dummyHumanoid then
			self:_bindOpponentHumanoid(dummyHumanoid, dummy.Name)
			return
		end
	end

	-- Buscar jugador oponente
	local localPlayer = Players.LocalPlayer
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer ~= localPlayer and otherPlayer.Character then
			local otherHumanoid = otherPlayer.Character:FindFirstChild("Humanoid")
			if otherHumanoid then
				self:_bindOpponentHumanoid(otherHumanoid, otherPlayer.Name)
				return
			end
		end
	end
end

-- Conecta el humanoid del oponente al HUD
function GameHUDComponent:_bindOpponentHumanoid(humanoid, name)
	-- Desconectar anterior si existe
	if self.opponentConnection then
		self.opponentConnection:Disconnect()
	end

	self.opponentHumanoid = humanoid

	-- Actualizar nombre
	if self.p2NameLabel then
		self.p2NameLabel.Text = string.upper(name)
	end

	-- Conectar HealthChanged
	self.opponentConnection = humanoid.HealthChanged:Connect(function(health)
		self:updateOpponentHealth(health)
	end)

	-- Actualizar inmediatamente
	self:updateOpponentHealth(humanoid.Health)
end

-- ============================================
-- ACTUALIZAR BARRAS DE VIDA
-- ============================================

-- Actualiza la barra de vida del jugador local (P1)
function GameHUDComponent:updatePlayerHealth(health)
	self:_updateHealthBar(health, self.humanoid.MaxHealth, self.p1HealthFill, self.p1GhostFill, self.p1HealthText, true)
end

-- Actualiza la barra de vida del oponente (P2)
function GameHUDComponent:updateOpponentHealth(health)
	if not self.opponentHumanoid then
		return
	end
	self:_updateHealthBar(
		health,
		self.opponentHumanoid.MaxHealth,
		self.p2HealthFill,
		self.p2GhostFill,
		self.p2HealthText,
		false
	)
end

-- Lógica compartida para actualizar una barra de vida con ghost bar
function GameHUDComponent:_updateHealthBar(health, maxHealth, fill, ghost, text, isP1)
	if not fill or not ghost then
		return
	end

	local percentage = math.clamp(health / maxHealth, 0, 1)

	-- Determinar color según porcentaje
	local barColor
	if percentage > 0.4 then
		barColor = isP1 and P1_BAR_COLOR or P2_BAR_COLOR
	elseif percentage > 0.2 then
		barColor = LOW_HEALTH_COLOR
	else
		barColor = CRITICAL_HEALTH_COLOR
		if isP1 then
			self:_startCriticalFlash()
		end
	end

	-- Animar barra principal
	UIBuilder.tween(fill, FILL_SPEED, {
		Size = UDim2.new(percentage, -6, 1, -6),
		BackgroundColor3 = barColor,
	}, Enum.EasingStyle.Quad)

	-- Ghost bar: esperar un momento y luego bajar
	task.spawn(function()
		task.wait(GHOST_DELAY)
		if ghost and ghost.Parent then
			UIBuilder.tween(ghost, GHOST_SPEED, {
				Size = UDim2.new(percentage, -6, 1, -6),
			}, Enum.EasingStyle.Quad)
		end
	end)

	-- Actualizar texto
	if text then
		text.Text = math.floor(percentage * 100) .. "%"
	end
end

-- ============================================
-- EFECTOS VISUALES
-- ============================================

-- Parpadeo cuando la vida está crítica
function GameHUDComponent:_startCriticalFlash()
	if self.isFlashing then
		return
	end
	self.isFlashing = true

	task.spawn(function()
		for _ = 1, 3 do
			if not self.p1HealthFill then
				break
			end
			UIBuilder.tween(self.p1HealthFill, 0.12, { BackgroundTransparency = 0.4 })
			task.wait(0.12)
			UIBuilder.tween(self.p1HealthFill, 0.12, { BackgroundTransparency = 0 })
			task.wait(0.12)
		end
		self.isFlashing = false
	end)
end

-- ============================================
-- COMBO COUNTER
-- ============================================

-- Muestra el combo counter con animación de entrada
function GameHUDComponent:showCombo(count)
	if not self.comboContainer then
		return
	end

	self.comboText.Text = tostring(count)
	self.comboContainer.Visible = true

	self.comboContainer.Size = UDim2.new(0, 0, 0, 0)
	UIBuilder.tween(self.comboContainer, 0.25, {
		Size = UDim2.new(0, 200, 0, 80),
	}, Enum.EasingStyle.Back)
end

-- Oculta el combo counter
function GameHUDComponent:hideCombo()
	if not self.comboContainer then
		return
	end

	UIBuilder.tween(self.comboContainer, 0.2, {
		Size = UDim2.new(0, 0, 0, 0),
	})

	task.delay(0.2, function()
		if self.comboContainer then
			self.comboContainer.Visible = false
		end
	end)
end

-- ============================================
-- TIMER
-- ============================================

-- Actualiza el texto del timer central
function GameHUDComponent:setTimer(seconds)
	if self.timerText then
		self.timerText.Text = tostring(math.floor(seconds))
	end
end

-- ============================================
-- CLEANUP
-- ============================================

-- Destruye toda la UI del HUD y desconecta listeners
function GameHUDComponent:destroy()
	if self.opponentConnection then
		self.opponentConnection:Disconnect()
		self.opponentConnection = nil
	end

	if self.element then
		self.element:Destroy()
		self.element = nil
	end
end

return GameHUDComponent
