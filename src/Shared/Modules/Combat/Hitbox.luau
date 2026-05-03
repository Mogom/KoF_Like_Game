local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DamageService = require(Combat:WaitForChild("DamageService"))
local ControllerRegistry = require(Combat:WaitForChild("ControllerRegistry"))

-- Sistema de hitbox: crea Part temporal y detecta colisión con HurtboxBody
local Hitbox = {}
Hitbox.__index = Hitbox

-- Constructor: posiciona la hitbox relativa al root con offset y tamaño
function Hitbox.new(root, data)
	local self = setmetatable({}, Hitbox)

	self.root = root
	self.size = data.Size
	self.offset = data.Offset

	self.part = Instance.new("Part")
	self.part.Size = self.size
	self.part.Anchored = true
	self.part.CanCollide = false
	self.part.CanTouch = false
	self.part.CanQuery = true
	self.part.Transparency = .5
	self.part.Name = "DebugHitbox"
	self.part.Parent = workspace

	self.alreadyHit = {}

	return self
end

-- Chequea colisión con GetPartBoundsInBox y reporta hit si encuentra HurtboxBody
function Hitbox:Update()
	self.part.CFrame = self.root.CFrame * CFrame.new(self.offset)

	local parts = workspace:GetPartBoundsInBox(self.part.CFrame, self.part.Size)

	for _, p in pairs(parts) do
		if p.Name == "HurtboxBody" then
			local character = p:FindFirstAncestorOfClass("Model")

			if character and character ~= self.root.Parent and not self.alreadyHit[character] then
				local humanoid = character:FindFirstChild("Humanoid")
				if humanoid then
					self.alreadyHit[character] = true
					-- print("🎯 Hitbox detected HurtboxBody on:", character.Name)

					DamageService.ApplyHit(self.root.Parent, character, self.attackData)

					-- Predicción local: pushback + animación inmediata en el oponente (solo jugadores)
					if self.attackData then
						ControllerRegistry.TriggerHitPrediction(character, self.attackData)
					end

					-- =============================================
					-- 📍 CALLBACK onHit: posición del golpe para VFX
					-- El punto de impacto es el punto medio entre atacante y víctima
					-- =============================================
					if self.onHit then
						local victimRoot = character:FindFirstChild("HumanoidRootPart")
						local hitPosition = self.root.Position
						if victimRoot then
							hitPosition = (self.root.Position + victimRoot.Position) / 2
						end
						local rawDir = victimRoot
							and (victimRoot.Position - self.root.Position)
							or Vector3.new(0, 0, -1)
						local direction = rawDir.Magnitude > 0.001 and rawDir.Unit or Vector3.new(0, 0, -1)
						self.onHit(hitPosition, direction, character)
					end
				end
			end
		end
	end
end

-- Destruye la hitbox visual
function Hitbox:Destroy()
	if self.part then
		self.part:Destroy()
	end
end

return Hitbox
