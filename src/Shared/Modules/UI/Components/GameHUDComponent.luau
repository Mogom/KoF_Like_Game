local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = Modules:WaitForChild("UI")

local UIBuilder = require(UI:WaitForChild("UIBuilder"))

local GameHUDComponent = {}
GameHUDComponent.__index = GameHUDComponent

function GameHUDComponent.new(parent, player)

	local self = setmetatable({}, GameHUDComponent)

	self.player = player
	self.character = player.Character or player.CharacterAdded:Wait()
	self.humanoid = self.character:WaitForChild("Humanoid")
	self.element = nil
	self.healthFillP1 = nil
	self.healthTextP1 = nil
	self.comboText = nil

	-- Crear UI
	local success, err = pcall(function()
		self:render(parent)
		self:setupHealthTracking()
	end)

	if not success then
		warn("❌ Error creating GameHUD:", err)
		return nil
	end


	return self
end

function GameHUDComponent:render(parent)

	local screenGui = UIBuilder.ScreenGui({
		Name = "GameHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,  
		Parent = parent
	})

	self.element = screenGui

	-- ============================================
	-- TOP BAR (Timer, Stage, etc.)
	-- ============================================

	local topBar = UIBuilder.Frame({
		Name = "TopBar",
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(10, 10, 15),
		BorderSizePixel = 0,
		Parent = screenGui,

		Children = {
			UIBuilder.UIGradient({
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.3),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 0.3)
				}),
				Rotation = 90
			})
		}
	})

	-- ✅ Timer/Stage central
	local timerContainer = UIBuilder.Frame({
		Name = "TimerContainer",
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 140, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(15, 15, 20),
		BorderSizePixel = 0,
		Parent = topBar,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
			UIBuilder.UIStroke({
				Color = Color3.fromRGB(255, 200, 0),
				Thickness = 3
			})
		}
	})

	-- Stage label
	UIBuilder.TextLabel({
		Name = "StageLabel",
		Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(0.9, 0, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "STAGE 1",
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Parent = timerContainer
	})

	-- Timer (cuenta regresiva)
	self.timerText = UIBuilder.TextLabel({
		Name = "TimerText",
		Position = UDim2.new(0.5, 0, 0, 25),
		Size = UDim2.new(0.9, 0, 0, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = "99",
		TextColor3 = Color3.fromRGB(255, 255, 0),
		TextSize = 42,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = timerContainer
	})

	-- ============================================
	-- PLAYER 1 (Izquierda)
	-- ============================================

	self:createPlayerHealthBar({
		name = "Player1Health",
		position = UDim2.new(0, 20, 0, 20),
		anchorPoint = Vector2.new(0, 0),
		fillDirection = "Right",
		playerName = self.player.Name,
		parent = screenGui,
		isPlayer1 = true
	})

	-- ============================================
	-- PLAYER 2 (Derecha) - Placeholder
	-- ============================================

	self:createPlayerHealthBar({
		name = "Player2Health",
		position = UDim2.new(1, -20, 0, 20),
		anchorPoint = Vector2.new(1, 0),
		fillDirection = "Left",
		playerName = "OPPONENT",
		parent = screenGui,
		isPlayer1 = false
	})

	-- ============================================
	-- COMBO COUNTER (Centro-Inferior)
	-- ============================================

	self.comboContainer = UIBuilder.Frame({
		Name = "ComboContainer",
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.new(0, 200, 0, 80),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,  -- Oculto por defecto
		Parent = screenGui
	})

	self.comboText = UIBuilder.TextLabel({
		Name = "ComboText",
		Size = UDim2.new(1, 0, 0.6, 0),
		BackgroundTransparency = 1,
		Text = "0",
		TextColor3 = Color3.fromRGB(255, 200, 0),
		TextSize = 60,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = self.comboContainer
	})

	self.comboLabel = UIBuilder.TextLabel({
		Name = "ComboLabel",
		Position = UDim2.new(0, 0, 0.6, 0),
		Size = UDim2.new(1, 0, 0.4, 0),
		BackgroundTransparency = 1,
		Text = "HITS",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.5,
		Parent = self.comboContainer
	})

end

-- ✅ Crear barra de vida de un jugador
function GameHUDComponent:createPlayerHealthBar(props)
	-- Container principal
	local container = UIBuilder.Frame({
		Name = props.name .. "Container",
		Position = props.position,
		Size = UDim2.new(0, 450, 0, 80),
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		Parent = props.parent
	})

	-- Avatar frame (placeholder)
	local avatarSize = 70
	local avatarPos = props.isPlayer1 and UDim2.new(0, 0, 0, 5) or UDim2.new(1, -avatarSize, 0, 5)

	local avatarFrame = UIBuilder.Frame({
		Name = "AvatarFrame",
		Position = avatarPos,
		Size = UDim2.new(0, avatarSize, 0, avatarSize),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BorderSizePixel = 0,
		Parent = container,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 8) }),
			UIBuilder.UIStroke({
				Color = props.isPlayer1 and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(255, 100, 0),
				Thickness = 3
			})
		}
	})

	-- Texto placeholder en avatar
	UIBuilder.TextLabel({
		Name = "AvatarText",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = props.isPlayer1 and "P1" or "P2",
		TextColor3 = Color3.fromRGB(150, 150, 150),
		TextSize = 32,
		Font = Enum.Font.GothamBold,
		Parent = avatarFrame
	})

	-- Health bar background
	local healthBarX = props.isPlayer1 and (avatarSize + 10) or 0
	local healthBarAnchor = props.isPlayer1 and 0 or 1

	local healthBg = UIBuilder.Frame({
		Name = "HealthBackground",
		Position = UDim2.new(healthBarAnchor, props.isPlayer1 and healthBarX or -healthBarX, 0, 5),
		Size = UDim2.new(0, 360, 0, 50),
		AnchorPoint = Vector2.new(healthBarAnchor, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 30),
		BorderSizePixel = 0,
		Parent = container,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 6) }),
			UIBuilder.UIStroke({
				Color = props.isPlayer1 and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(255, 100, 0),
				Thickness = 2
			})
		}
	})

	-- Health fill (la barra que se reduce)
	local healthFillAnchor = props.fillDirection == "Right" and 0 or 1

	local healthFill = UIBuilder.Frame({
		Name = "HealthFill",
		Position = UDim2.new(healthFillAnchor, props.isPlayer1 and 3 or -3, 0, 3),
		Size = UDim2.new(1, -6, 1, -6),
		AnchorPoint = Vector2.new(healthFillAnchor, 0),
		BackgroundColor3 = props.isPlayer1 and Color3.fromRGB(0, 255, 150) or Color3.fromRGB(255, 150, 0),
		BorderSizePixel = 0,
		Parent = healthBg,

		Children = {
			UIBuilder.UICorner({ CornerRadius = UDim.new(0, 4) }),

			-- Gradiente para efecto visual
			UIBuilder.UIGradient({
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(1, props.isPlayer1 and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(200, 100, 0))
				}),
				Rotation = props.isPlayer1 and 0 or 180
			})
		}
	})

	-- Guardar referencia solo para Player 1 (el jugador actual)
	if props.isPlayer1 then
		self.healthFillP1 = healthFill
	end

	-- Health percentage text
	local healthText = UIBuilder.TextLabel({
		Name = "HealthText",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "100%",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 24,
		Font = Enum.Font.GothamBold,
		TextStrokeTransparency = 0.5,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		Parent = healthBg
	})

	if props.isPlayer1 then
		self.healthTextP1 = healthText
	end

	-- Player name
	local nameLabel = UIBuilder.TextLabel({
		Name = "PlayerName",
		Position = UDim2.new(healthBarAnchor, props.isPlayer1 and healthBarX or -healthBarX, 0, 60),
		Size = UDim2.new(0, 360, 0, 20),
		AnchorPoint = Vector2.new(healthBarAnchor, 0),
		BackgroundTransparency = 1,
		Text = props.playerName,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		TextSize = 16,
		Font = Enum.Font.Gotham,
		TextXAlignment = props.isPlayer1 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
		Parent = container
	})

	return container
end

function GameHUDComponent:setupHealthTracking()

	if not self.humanoid then
		warn("❌ No humanoid found!")
		return
	end

	self.humanoid.HealthChanged:Connect(function(health)
		self:updateHealth(health)
	end)

	-- Actualizar inmediatamente
	self:updateHealth(self.humanoid.Health)
end

function GameHUDComponent:updateHealth(health)
	if not self.healthFillP1 or not self.healthTextP1 then
		return
	end

	local maxHealth = self.humanoid.MaxHealth
	local percentage = math.clamp(health / maxHealth, 0, 1)

	-- ✅ Animar el tamaño (desde la izquierda)
	UIBuilder.tween(self.healthFillP1, 0.3, {
		Size = UDim2.new(percentage, -6, 1, -6)
	}, Enum.EasingStyle.Quad)

	-- ✅ Actualizar texto
	self.healthTextP1.Text = math.floor(percentage * 100) .. "%"

	-- ✅ Cambiar color según salud (verde → amarillo → rojo)
	local color
	local gradientColor

	if percentage > 0.6 then
		color = Color3.fromRGB(0, 255, 150)
		gradientColor = Color3.fromRGB(0, 200, 100)
	elseif percentage > 0.3 then
		color = Color3.fromRGB(255, 220, 0)
		gradientColor = Color3.fromRGB(200, 160, 0)
	else
		color = Color3.fromRGB(255, 50, 50)
		gradientColor = Color3.fromRGB(200, 0, 0)

		-- ✅ Efecto de parpadeo cuando está crítico
		if percentage < 0.2 then
			self:startCriticalFlash()
		end
	end

	UIBuilder.tween(self.healthFillP1, 0.3, {
		BackgroundColor3 = color
	})

	-- Actualizar gradiente
	local gradient = self.healthFillP1:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, gradientColor)
		})
	end
end

-- ✅ Efecto de parpadeo cuando la vida está crítica
function GameHUDComponent:startCriticalFlash()
	if self.isFlashing then return end

	self.isFlashing = true

	task.spawn(function()
		for i = 1, 3 do
			if not self.healthFillP1 then break end

			UIBuilder.tween(self.healthFillP1, 0.15, {
				BackgroundTransparency = 0.5
			})
			task.wait(0.15)
			UIBuilder.tween(self.healthFillP1, 0.15, {
				BackgroundTransparency = 0
			})
			task.wait(0.15)
		end

		self.isFlashing = false
	end)
end

-- ✅ Mostrar combo (se puede llamar desde DamageService)
function GameHUDComponent:showCombo(count)
	if not self.comboContainer then return end

	self.comboText.Text = tostring(count)
	self.comboContainer.Visible = true

	-- Animación de entrada (scale)
	self.comboContainer.Size = UDim2.new(0, 0, 0, 0)
	UIBuilder.tween(self.comboContainer, 0.3, {
		Size = UDim2.new(0, 200, 0, 80)
	}, Enum.EasingStyle.Back)
end

-- ✅ Ocultar combo
function GameHUDComponent:hideCombo()
	if not self.comboContainer then return end

	UIBuilder.tween(self.comboContainer, 0.2, {
		Size = UDim2.new(0, 0, 0, 0)
	}):Play()

	task.wait(0.2)
	self.comboContainer.Visible = false
end

function GameHUDComponent:destroy()
	if self.element then
		self.element:Destroy()
	end
end

return GameHUDComponent