-- Captures a turntable of a Model/BasePart: clones it into an isolated booth
-- moved far into the sky (nothing else up there to occlude it), orbits the
-- camera through a list of yaw angles against a solid backdrop, and returns
-- one shot per angle. Based on a validated Edit-mode command-bar script.
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")

local Util = require(script.Parent.Parent.Util)

local WARMUP_FRAMES = 8
local DEFAULT_FOV = 70
local DEFAULT_FILL_MARGIN = 1.35
local SKY_POS = Vector3.new(0, 100000, 0)
local BACKDROP_DISTANCE_MULT = 1.5
local BACKDROP_MARGIN = 1.15
local TURNTABLE_CAPTURE_TIMEOUT_FRAMES = 300

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
	target = target :: Instance

	local cf = Util.getBounds(target)
	local delta = SKY_POS - cf.Position

	local booth = Instance.new("Folder")
	booth.Name = "MCPPhotoBooth"

	local clone = target:Clone()
	if clone:IsA("Model") then
		local model = clone :: Model
		model:PivotTo(model:GetPivot() + delta)
	else
		local part = clone :: BasePart
		part.CFrame = part.CFrame + delta
	end
	clone.Parent = booth

	local bg = args.bgColor or {}
	local bgColor = Color3.fromRGB(bg.r or 60, bg.g or 60, bg.b or 70)
	local backdrop = Instance.new("Part")
	backdrop.Material = Enum.Material.SmoothPlastic
	backdrop.Color = bgColor
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CastShadow = false
	backdrop.Parent = booth

	booth.Parent = workspace

	local camera = workspace.CurrentCamera
	local prevCFrame, prevType, prevFov = camera.CFrame, camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = DEFAULT_FOV

	local prevSelection = Selection:Get()
	Selection:Set({})

	local newCenter = SKY_POS
	local cloneCf, cloneSize = Util.getBounds(clone)
	local corners = Util.boundsCorners(cloneCf, cloneSize)

	local yawDegs = args.yawDegs or { 0, 90, 180, 270 }
	local pitchDeg = args.pitchDeg or 20
	local distance = args.distanceStuds or Util.autoDistance(DEFAULT_FOV, cloneSize, DEFAULT_FILL_MARGIN)
	local padding = args.padding or 24

	-- StarterGui/CoreGui ScreenGuis render over the Edit-mode viewport and the
	-- capture is of the composited frame, so a HUD would sit on every shot.
	-- Hidden last, so nothing above can error out and leave the UI switched off.
	local restoreGuis = Util.hideViewportGuis()

	local shots = {}
	local ok, err = pcall(function()
		for _, yawDeg in ipairs(yawDegs) do
			local camPos = Util.orbitPosition(newCenter, distance, yawDeg, pitchDeg)
			local camCFrame = CFrame.lookAt(camPos, newCenter)

			-- Sized to cover the whole frustum at the backdrop's plane, aspect
			-- included: a square sized off the camera distance alone leaves the
			-- real scene visible in the corners of a wide viewport.
			local behind = newCenter + (newCenter - camPos).Unit * (distance * BACKDROP_DISTANCE_MULT)
			local extents = Util.frustumExtents(camera, distance * (1 + BACKDROP_DISTANCE_MULT), BACKDROP_MARGIN)
			backdrop.CFrame = CFrame.lookAt(behind, camPos)
			backdrop.Size = Vector3.new(extents.X, extents.Y, 0.2)

			local function setCam()
				camera.CFrame = camCFrame
			end
			for _ = 1, WARMUP_FRAMES do
				setCam()
				RunService.RenderStepped:Wait()
			end

			local rectPos, rectSize = Util.projectedRect(camera, corners)
			local pxPos = Vector2.new(rectPos.X - padding, rectPos.Y - padding)
			local pxSize = Vector2.new(rectSize.X + padding * 2, rectSize.Y + padding * 2)

			local shot: any = Util.captureRegion(pxPos, pxSize, setCam, TURNTABLE_CAPTURE_TIMEOUT_FRAMES)
			shot.yawDeg = yawDeg
			shot.pitchDeg = pitchDeg
			table.insert(shots, shot)
		end
	end)

	booth:Destroy()
	Util.restoreCamera(camera, prevCFrame, prevType, prevFov)
	Selection:Set(prevSelection)
	restoreGuis()

	if not ok then
		error(err)
	end

	return { shots = shots, targetPath = target:GetFullName(), distanceStuds = distance }
end
