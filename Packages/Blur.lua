local Lighting          = game:GetService("Lighting")
local runService        = game:GetService("RunService")
local workspace			= game:GetService("Workspace")

local camera			= workspace.CurrentCamera

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function(...: any) 
	camera = workspace.CurrentCamera
end)

local BLUR_SIZE         = Vector2.one * 8.5
local PART_SIZE         = 1e-3
local PART_TRANSPARENCY = 1 - 1e-7

local BLUR_OBJ          = Instance.new("DepthOfFieldEffect")
BLUR_OBJ.FarIntensity   = 0
BLUR_OBJ.NearIntensity  = 1
BLUR_OBJ.FocusDistance  = 0
BLUR_OBJ.InFocusRadius  = 0
BLUR_OBJ.Parent         = camera

local PartsList         = {}
local BlursList         = {}
local BlurObjects       = {}
local BlurredGui        = {}

local onCFrameChanged   = nil :: RBXScriptConnection?

BlurredGui.__index      = BlurredGui

function rayPlaneIntersect(planePos, planeNormal, rayOrigin, rayDirection)
	local n: vector = planeNormal
	local d: vector = rayDirection
	local v: vector = rayOrigin - planePos

	local num = vector.dot(n, v)
	local den = vector.dot(n, d)
	
	local a = -num / den

	return rayOrigin + a * rayDirection, a
end

function rebuildPartsList()
	PartsList = {}
	BlursList = {}
	for blurObj, part in (BlurObjects) do
		table.insert(PartsList, part)
		table.insert(BlursList, blurObj)
	end
end

function BlurredGui.new(guiObject: GuiObject, shape)

	local blurPart        = Instance.new("Part")
	blurPart.Size         = vector.create(PART_SIZE, PART_SIZE, PART_SIZE)
	blurPart.Anchored     = true
	blurPart.CanCollide   = false
	blurPart.CanTouch     = false
	blurPart.Material     = Enum.Material.Glass
	blurPart.Transparency = PART_TRANSPARENCY
	blurPart.Parent       = camera

	local mesh
	if (shape == "Rectangle") then
		mesh        = Instance.new("BlockMesh")
		mesh.Parent = blurPart
	elseif (shape == "Oval") then
		mesh          = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent   = blurPart
	end

	local ignoreInset = false
	local currentObj  = guiObject

	while true do
		currentObj = currentObj.Parent
		if (currentObj and currentObj:IsA("ScreenGui")) then
			ignoreInset = not currentObj.IgnoreGuiInset
			break
		elseif (currentObj == nil) then
			break
		end
	end

	local new = setmetatable({
		Frame          = guiObject;
		Part           = blurPart;
		Mesh           = mesh;
		IgnoreGuiInset = ignoreInset;
	}, BlurredGui)

	BlurObjects[new] = blurPart
	rebuildPartsList()

	runService:BindToRenderStep("...", Enum.RenderPriority.Camera.Value + 1, function()
		--blurPart.CFrame = camera.CFrame
		BlurredGui.updateAll()
	end)

	guiObject.Destroying:Once(function()
		blurPart:Destroy()
		BlurObjects[new] = nil
		rebuildPartsList()
	end)

	return new
end

function updateGui(blurObj)
	if (not blurObj.Mesh or not blurObj.Frame.Visible or not blurObj.Frame.Parent.Visible) then
		blurObj.Part.Transparency = 1
		return
	end

	local cframe = camera:GetRenderCFrame()
	local frame  = blurObj.Frame
	local part   = blurObj.Part
	local mesh   = blurObj.Mesh

	part.Transparency = PART_TRANSPARENCY

	local corner0 = frame.AbsolutePosition + BLUR_SIZE
	local corner1 = corner0 + frame.AbsoluteSize - BLUR_SIZE*2
	local ray0, ray1

	if (blurObj.IgnoreGuiInset) then
		ray0 = camera:ViewportPointToRay(corner0.X, corner0.Y, 1)
		ray1 = camera:ViewportPointToRay(corner1.X, corner1.Y, 1)
	else
		ray0 = camera:ScreenPointToRay(corner0.X, corner0.Y, 1)
		ray1 = camera:ScreenPointToRay(corner1.X, corner1.Y, 1)
	end

	local planeOrigin = cframe.Position + cframe.LookVector * (5e-2 - camera.NearPlaneZ)
	local planeNormal = cframe.LookVector
	
	local pos0 = rayPlaneIntersect(planeOrigin, planeNormal, ray0.Origin, ray0.Direction)
	local pos1 = rayPlaneIntersect(planeOrigin, planeNormal, ray1.Origin, ray1.Direction)

	local pos0 = cframe:PointToObjectSpace(pos0)
	local pos1 = cframe:PointToObjectSpace(pos1)

	local size   = pos1 - pos0
	local center = (pos0 + pos1)/2

	mesh.Offset = center
	mesh.Scale  = size / PART_SIZE
end

function BlurredGui.updateAll()
	
	local numBlurList = table.maxn(BlursList)

	for i = 1, numBlurList do
		updateGui(BlursList[i])
	end

	local cframes = table.create(numBlurList, camera:GetRenderCFrame())
	workspace:BulkMoveTo(PartsList, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	--BLUR_OBJ.FocusDistance = 0.25 - camera.NearPlaneZ
end

function BlurredGui.updateTransparency(transparency: number)
	PART_TRANSPARENCY = transparency
end

function BlurredGui.updateIntensity(nearIntensity: number)
	BLUR_OBJ.NearIntensity = nearIntensity
end

function BlurredGui:Destroy()
	self.Part:Destroy()
	BlurObjects[self] = nil
	rebuildPartsList()
end

onCFrameChanged = camera:GetPropertyChangedSignal("CFrame"):Connect(function(...: any) 
	BlurredGui.updateAll()
end)

return BlurredGui
