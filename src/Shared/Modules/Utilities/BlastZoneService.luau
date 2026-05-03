local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utilities = Modules:WaitForChild("Utilities")
local SpawnService = require(Utilities:WaitForChild("SpawnService"))

local BlastZoneService = {}

local CONFIG = {
	HorizontalMargin = 18,
	UpperMargin = 30,
	LowerMargin = 22,
	OutDebounce = 0.75,
}

local matches = {}
local heartbeatConnection = nil

local function getMapBounds(mapName)
	return SpawnService.GetMapBounds(mapName)
end

local function computeBlastZone(mapName)
	local center, size = getMapBounds(mapName)
	local halfX = size.X * 0.5
	local halfY = size.Y * 0.5

	return {
		LeftX = center.X - halfX - CONFIG.HorizontalMargin,
		RightX = center.X + halfX + CONFIG.HorizontalMargin,
		MinY = center.Y - halfY - CONFIG.LowerMargin,
		MaxY = center.Y + halfY + CONFIG.UpperMargin,
	}
end

local function isOutOfBounds(position, bounds)
	return position.X < bounds.LeftX
		or position.X > bounds.RightX
		or position.Y < bounds.MinY
		or position.Y > bounds.MaxY
end

local function ensureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		for matchId, state in pairs(matches) do
			if state.Active then
				for _, player in ipairs(state.Players) do
					if player and player.Parent then
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						if root then
							if isOutOfBounds(root.Position, state.Bounds) then
								local now = os.clock()
								local lastTime = state.LastOut[player] or 0
								if now - lastTime >= CONFIG.OutDebounce then
									state.LastOut[player] = now
									if state.OnOutOfBounds then
										task.spawn(state.OnOutOfBounds, player, root.Position)
									end
								end
							end
						end
					end
				end
			else
				matches[matchId] = nil
			end
		end

		if next(matches) == nil and heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end
	end)
end

function BlastZoneService.StartMatch(matchId, players, mapName, onOutOfBounds)
	if not matchId or type(players) ~= "table" then
		return false
	end

	matches[matchId] = {
		Active = true,
		Players = players,
		Bounds = computeBlastZone(mapName),
		MapName = mapName or "Map0",
		OnOutOfBounds = onOutOfBounds,
		LastOut = {},
	}

	ensureHeartbeat()
	return true
end

function BlastZoneService.StopMatch(matchId)
	local state = matches[matchId]
	if state then
		state.Active = false
		matches[matchId] = nil
	end
end

function BlastZoneService.StopAllForPlayer(player)
	for matchId, state in pairs(matches) do
		for _, participant in ipairs(state.Players) do
			if participant == player then
				matches[matchId] = nil
				break
			end
		end
	end
end

function BlastZoneService.Clear()
	matches = {}
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

return BlastZoneService
