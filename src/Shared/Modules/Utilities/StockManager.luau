local StockManager = {}

local DEFAULT_INVULN = 2.5

local playerState = {}

local function setInvulnerability(character, enabled)
	if not character then
		return
	end
	character:SetAttribute("IsRespawnInvulnerable", enabled)

	local aura = character:FindFirstChild("RespawnInvulnAura")
	if enabled then
		if not aura then
			aura = Instance.new("Highlight")
			aura.Name = "RespawnInvulnAura"
			aura.FillColor = Color3.fromRGB(110, 180, 255)
			aura.FillTransparency = 0.55
			aura.OutlineColor = Color3.fromRGB(220, 245, 255)
			aura.OutlineTransparency = 0.1
			aura.Adornee = character
			aura.Parent = character
		end
	else
		if aura then
			aura:Destroy()
		end
	end
end

local function blinkInvulnAura(character, duration)
	local aura = character and character:FindFirstChild("RespawnInvulnAura")
	if not aura then
		return
	end

	local startTime = os.clock()
	task.spawn(function()
		while character and character.Parent and aura.Parent and (os.clock() - startTime) < duration do
			aura.Enabled = not aura.Enabled
			task.wait(0.12)
		end
		if aura and aura.Parent then
			aura.Enabled = true
		end
	end)
end

function StockManager.InitPlayer(player, maxStocks)
	maxStocks = maxStocks or 3
	playerState[player] = {
		Stocks = maxStocks,
		MaxStocks = maxStocks,
	}

	player:SetAttribute("Stocks", maxStocks)
	player:SetAttribute("MaxStocks", maxStocks)
	player:SetAttribute("IsEliminated", false)
	player:SetAttribute("IsRespawnInvulnerable", false)
	if player.Character then
		player.Character:SetAttribute("Stocks", maxStocks)
		player.Character:SetAttribute("MaxStocks", maxStocks)
		player.Character:SetAttribute("IsRespawnInvulnerable", false)
	end
end

function StockManager.GetStocks(player)
	local state = playerState[player]
	return state and state.Stocks or 0
end

function StockManager.LoseStock(player)
	local state = playerState[player]
	if not state then
		return false
	end

	state.Stocks = math.max(0, state.Stocks - 1)
	player:SetAttribute("Stocks", state.Stocks)
	if player.Character then
		player.Character:SetAttribute("Stocks", state.Stocks)
		player.Character:SetAttribute("MaxStocks", state.MaxStocks)
	end

	local isAlive = state.Stocks > 0
	player:SetAttribute("IsEliminated", not isAlive)
	return isAlive
end

function StockManager.RespawnPlayerAt(player, position, facingRight, invulnSeconds)
	invulnSeconds = invulnSeconds or DEFAULT_INVULN
	if not player or not player.Parent then
		return nil
	end

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if root then
		local rotation = facingRight and math.rad(-90) or math.rad(90)
		local targetCFrame = CFrame.new(position) * CFrame.Angles(0, rotation, 0)
		character:PivotTo(targetCFrame)
		root.CFrame = targetCFrame
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		character:SetAttribute("ReplicatedSpawnX", position.X)
		character:SetAttribute("ReplicatedSpawnY", position.Y)
		character:SetAttribute("ReplicatedSpawnZ", position.Z)
		character:SetAttribute("ReplicatedSpawnFacingRight", facingRight == true)
		character:SetAttribute("ReplicatedSpawnVersion", os.clock())
		local state = playerState[player]
		if state then
			character:SetAttribute("Stocks", state.Stocks)
			character:SetAttribute("MaxStocks", state.MaxStocks)
		end
	end

	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end

	-- Reset daño acumulado (percent) al respawnear
	if character then
		character:SetAttribute("DamagePercent", 0)
	end

	player:SetAttribute("IsRespawnInvulnerable", true)
	setInvulnerability(character, true)
	blinkInvulnAura(character, invulnSeconds)

	task.delay(invulnSeconds, function()
		if player and player.Parent then
			player:SetAttribute("IsRespawnInvulnerable", false)
		end
		if character and character.Parent then
			setInvulnerability(character, false)
		end
	end)

	return character
end

function StockManager.ClearPlayer(player)
	playerState[player] = nil
	if player and player.Parent then
		player:SetAttribute("Stocks", nil)
		player:SetAttribute("MaxStocks", nil)
		player:SetAttribute("IsEliminated", nil)
		player:SetAttribute("IsRespawnInvulnerable", false)
	end
	if player and player.Character then
		setInvulnerability(player.Character, false)
	end
end

return StockManager
