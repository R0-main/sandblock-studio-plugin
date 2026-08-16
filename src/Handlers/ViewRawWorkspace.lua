-- Captures a single screenshot of a Model/BasePart in place, with the real
-- scene, lighting, and occlusion — as opposed to CaptureTurntable's isolated
-- photo booth. The camera orbits the target at an auto-fit-or-overridden
-- distance/yaw/pitch; an optional Highlight can outline the target.
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")

local Util = require(script.Parent.Parent.Util)

local WARMUP_FRAMES = 8
local DEFAULT_FOV = 70
local DEFAULT_FILL_MARGIN = 1.35

return function(args: any): any
	Util.assertViewportActive()

	local target: Instance?
	if args.target and args.target ~= "" then
		target = Util.resolvePath(args.target)
	else
		target = Selection:Get()[1]
	end
	if not (target and (target:IsA("Model") or target:IsA("BasePart"))) then
		error("target must be a Model or BasePart, got " .. (target and target.ClassName or "nil"))
	end

	local cf, size = Util.getBounds(target :: Instance)
	local center = cf.Position

	local camera = workspace.CurrentCamera
	local prevCFrame, prevType, prevFov = camera.CFrame, camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = DEFAULT_FOV

	local yawDeg = args.yawDeg or 45
	local pitchDeg = args.pitchDeg or 20
	local distance = args.distanceStuds or Util.autoDistance(DEFAULT_FOV, size, DEFAULT_FILL_MARGIN)
	local camPos = Util.orbitPosition(center, distance, yawDeg, pitchDeg)
	local camCFrame = CFrame.lookAt(camPos, center)

	local highlight: Highlight?
	if args.highlight then
		local hc = args.highlightColor or {}
		highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = Color3.fromRGB(hc.r or 255, hc.g or 200, hc.b or 0)
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = target
		highlight.Parent = target
	end

	local prevSelection = Selection:Get()
	Selection:Set({})

	local function setCam()
		camera.CFrame = camCFrame
	end

	for _ = 1, WARMUP_FRAMES do
		setCam()
		RunService.RenderStepped:Wait()
	end

	local corners = Util.boundsCorners(cf, size)
	local rectPos, rectSize = Util.projectedRect(camera, corners)
	local padding = args.padding or 32
	local pxPos = Vector2.new(rectPos.X - padding, rectPos.Y - padding)
	local pxSize = Vector2.new(rectSize.X + padding * 2, rectSize.Y + padding * 2)

	local ok, resultOrErr = pcall(function()
		return Util.captureRegion(pxPos, pxSize, setCam)
	end)

	if highlight then
		highlight:Destroy()
	end
	Util.restoreCamera(camera, prevCFrame, prevType, prevFov)
	Selection:Set(prevSelection)

	if not ok then
		error(resultOrErr)
	end

	local result = resultOrErr :: any
	result.targetPath = (target :: Instance):GetFullName()
	result.distanceStuds = distance
	result.yawDeg = yawDeg
	result.pitchDeg = pitchDeg
	return result
end
