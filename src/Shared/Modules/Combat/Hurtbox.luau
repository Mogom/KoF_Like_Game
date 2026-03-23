local Hurtbox = {}
Hurtbox.__index = Hurtbox

function Hurtbox.new(character)
	local self = setmetatable({}, Hurtbox)

	self.character = character
	self.root = character:WaitForChild("HumanoidRootPart")
	self.parts = {}

	self:Create()

	return self
end

function Hurtbox:Create()
	if self.character:FindFirstChild("HurtboxBody") then
		table.insert(self.parts, self.character.HurtboxBody)
		return
	end

	local body = Instance.new("Part")
	body.Name = "HurtboxBody"
	body.Size = Vector3.new(4, 4, 3)
	body.Transparency = 1
	body.Color = Color3.fromRGB(0, 255, 0)
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = true
	body.Massless = true
	body.Anchored = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = self.root
	weld.Parent = body

	body.CFrame = self.root.CFrame
	body.Parent = self.character

	table.insert(self.parts, body)
end

function Hurtbox:GetParts()
	return self.parts
end

function Hurtbox:SetHeightScale(scale)
	if not self.parts or #self.parts == 0 then
		return
	end

	local body = self.parts[1]

	if not self.originalSize then
		self.originalSize = body.Size
	end

	body.Size = Vector3.new(
		self.originalSize.X * 1.2,
		self.originalSize.Y * scale,
		self.originalSize.Z
	)
end

function Hurtbox:Reset()
	if not self.parts or #self.parts == 0 or not self.originalSize then
		return
	end

	local body = self.parts[1]
	body.Size = self.originalSize
end

return Hurtbox