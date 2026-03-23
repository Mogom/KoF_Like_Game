local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Combat = Modules:WaitForChild("Combat")

local DamageService = require(Combat:WaitForChild("DamageService"))

local Hitbox = {}
Hitbox.__index = Hitbox

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
	self.part.Transparency = 1
	self.part.Name = "DebugHitbox"
	self.part.Parent = workspace

	self.alreadyHit = {}

	return self
end

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
					print("🎯 Hitbox detected HurtboxBody on:", character.Name)

					DamageService.ApplyHit(self.root.Parent, character, self.attackData)

					-- =============================================
					-- 🎯 PREDICCIÓN LOCAL: pushback + animación
					-- inmediata en el oponente (solo para jugadores)
					-- =============================================
					if _G.LocalHitPrediction and self.attackData then
						_G.LocalHitPrediction(character, self.attackData)
					end
				end
			end
		end
	end
end

function Hitbox:Destroy()
	if self.part then
		self.part:Destroy()
	end
end

return Hitbox