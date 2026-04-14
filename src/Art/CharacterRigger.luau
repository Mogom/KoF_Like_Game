-- Este script te ayuda a crear el rig. 
-- Ejecútalo una vez en la Command Bar de Studio.

local model = workspace.TuModelo -- Cambia al nombre de tu modelo
local torso = model.Torso
local head = model.Head
local leftArm = model["Left Arm"]
local rightArm = model["Right Arm"]
local leftLeg = model["Left Leg"]
local rightLeg = model["Right Leg"]

local HumanoidRootPart = Instance.new("Part")
HumanoidRootPart.Name = "HumanoidRootPart"
HumanoidRootPart.Size = Vector3.new(2, 2, 1)
HumanoidRootPart.Transparency = 1
HumanoidRootPart.CanCollide = false
HumanoidRootPart.Anchored = true
HumanoidRootPart.CFrame = torso.CFrame
HumanoidRootPart.Parent = model

local hrp = model.HumanoidRootPart

-- Root Joint: HumanoidRootPart → Torso
local rootJoint = Instance.new("Motor6D")
rootJoint.Name = "RootJoint"
rootJoint.Part0 = hrp
rootJoint.Part1 = torso
rootJoint.C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
rootJoint.C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
rootJoint.Parent = hrp

-- Neck: Torso → Head
local neck = Instance.new("Motor6D")
neck.Name = "Neck"
neck.Part0 = torso
neck.Part1 = head
neck.C0 = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
neck.C1 = CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
neck.Parent = torso

-- Left Shoulder: Torso → Left Arm
local leftShoulder = Instance.new("Motor6D")
leftShoulder.Name = "Left Shoulder"
leftShoulder.Part0 = torso
leftShoulder.Part1 = leftArm
leftShoulder.C0 = CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
leftShoulder.C1 = CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
leftShoulder.Parent = torso

-- Right Shoulder: Torso → Right Arm
local rightShoulder = Instance.new("Motor6D")
rightShoulder.Name = "Right Shoulder"
rightShoulder.Part0 = torso
rightShoulder.Part1 = rightArm
rightShoulder.C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
rightShoulder.C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
rightShoulder.Parent = torso

-- Left Hip: Torso → Left Leg
local leftHip = Instance.new("Motor6D")
leftHip.Name = "Left Hip"
leftHip.Part0 = torso
leftHip.Part1 = leftLeg
leftHip.C0 = CFrame.new(-1, -1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
leftHip.C1 = CFrame.new(-0.5, 1, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)
leftHip.Parent = torso

-- Right Hip: Torso → Right Leg
local rightHip = Instance.new("Motor6D")
rightHip.Name = "Right Hip"
rightHip.Part0 = torso
rightHip.Part1 = rightLeg
rightHip.C0 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
rightHip.C1 = CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)
rightHip.Parent = torso

-- Asignar PrimaryPart
model.PrimaryPart = hrp

print("✅ Rig R6 creado correctamente!")