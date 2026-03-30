local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DamageService = require(Combat:WaitForChild("DamageService"))
local VFXService = require(Combat:WaitForChild("VFXService"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RemoteEvents = Remotes:WaitForChild("Events")
local ReplicateVFXEvent = RemoteEvents:WaitForChild("ReplicateVFX")

-- Sistema de proyectiles: crea una Part que vuela y daña al primer enemigo que toca
local ProjectileService = {}

-- Spawn: lanza un proyectil desde root en la dirección indicada (dir = 1 derecha, -1 izquierda)
function ProjectileService.Spawn(root, attackData, dir)
	if not root or not root.Parent then
		return
	end

	local character = root.Parent
	local speed = attackData.ProjectileSpeed or 40
	local lifetime = attackData.ProjectileLifetime or 1.5
	local hitboxData = attackData.Hitbox or {}
	local size = hitboxData.Size or Vector3.new(3, 3, 3)
	local offset = hitboxData.Offset or Vector3.new(0, 0, -3)

	-- Crear la Part visual del proyectil
	local proj = Instance.new("Part")
	proj.Name = "Projectile"
	proj.Size = size
	proj.Shape = Enum.PartType.Ball
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanTouch = false
	proj.CanQuery = true
	proj.Material = Enum.Material.Neon
	proj.Color = Color3.fromRGB(255, 200, 50)
	proj.Transparency = 0.2
	proj.CastShadow = false
	proj.Parent = Workspace

	-- Posición inicial: offset en el espacio local del personaje (igual que el Hitbox)
	proj.CFrame = root.CFrame * CFrame.new(offset)

	local alreadyHit = false
	local elapsed = 0

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.MaxParts = 20

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if alreadyHit or not proj or not proj.Parent then
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		elapsed = elapsed + dt

		if elapsed >= lifetime then
			proj:Destroy()
			if connection then
				connection:Disconnect()
				connection = nil
			end
			return
		end

		-- Mover proyectil en el eje X (dirección del personaje)
		proj.CFrame = proj.CFrame + Vector3.new(dir * speed * dt, 0, 0)

		-- Detectar colisión con HurtboxBody
		local parts = Workspace:GetPartBoundsInBox(proj.CFrame, proj.Size, overlapParams)
		for _, part in ipairs(parts) do
			if part.Name == "HurtboxBody" then
				local victimChar = part:FindFirstAncestorOfClass("Model")
				if victimChar and victimChar ~= character then
					local humanoid = victimChar:FindFirstChild("Humanoid")
					if humanoid then
						alreadyHit = true

						-- VFX en el punto de impacto
						local rawDir = Vector3.new(dir, 0, 0)
						VFXService.PlayHitEffect(proj.Position, attackData.HitType or "Special", rawDir)

						-- Replicar HitEffect a otros jugadores
						ReplicateVFXEvent:FireServer("HitEffect", {
							Position = proj.Position,
							HitType = attackData.HitType or "Special",
							Direction = rawDir,
						})

						-- Aplicar daño vía servidor
						DamageService.ApplyHit(character, victimChar, attackData)

						-- Predicción local (visual inmediato)
						if _G.LocalHitPrediction then
							_G.LocalHitPrediction(victimChar, attackData)
						end

						-- Destruir proyectil al impactar
						proj:Destroy()
						if connection then
							connection:Disconnect()
							connection = nil
						end
						return
					end
				end
			end
		end
	end)

	-- Cleanup de seguridad al expirar el lifetime
	task.delay(lifetime + 0.1, function()
		if proj and proj.Parent then
			proj:Destroy()
		end
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end)
end

return ProjectileService
