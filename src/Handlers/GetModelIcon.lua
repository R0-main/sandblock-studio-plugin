-- Renders a clean, cut-out icon of a Model/BasePart. Like CaptureTurntable it
-- clones the target into an isolated booth far in the sky, but it also strips
-- everything that isn't geometry (particles, billboards, lights, ...) and
-- captures the *exact same framing twice* against two different backdrop
-- colors. The server recovers an exact alpha channel from that pair
-- (difference matting), so the cutout never depends on the model's own colors
-- and keeps antialiased edges and see-through parts. The two colors only have
-- to differ -- there is no chroma key and therefore no spill, since the
-- backdrop's contribution is subtracted exactly rather than thresholded.
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")

local Util = require(script.Parent.Parent.Util)

local WARMUP_FRAMES = 8
local DEFAULT_FOV = 70
local DEFAULT_FILL_MARGIN = 1.35
local SKY_POS = Vector3.new(0, 100000, 0)
local BACKDROP_DISTANCE_MULT = 1.5
local BACKDROP_MARGIN = 1.15
local CAPTURE_TIMEOUT_FRAMES = 300

-- Anything here is removed from the *clone*, never from the real model.
-- Matched with IsA, so "Light" covers Point/Spot/SurfaceLight and "GuiBase3D"
-- covers SelectionBox and the handle adornments.
local STRIP_CLASSES = {
	"ParticleEmitter",
	"Trail",
	"Beam",
	"Smoke",
	"Fire",
	"Sparkles",
	"Explosion",
	"Light",
	"BillboardGui",
	"SurfaceGui",
	"GuiBase3D",
	"Highlight",
	"ProximityPrompt",
	"ClickDetector",
	"Sound",
}

local function toColor(rgb: any, fallback: Color3): Color3
	if type(rgb) == "table" and rgb.r and rgb.g and rgb.b then
		return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
	end
	return fallback
end

local function stripEffects(root: Instance): number
	local removed = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		for _, className in ipairs(STRIP_CLASSES) do
			if descendant:IsA(className) then
				descendant:Destroy()
				removed += 1
				break
			end
		end
	end
	return removed
end

-- A backdrop whose rendered color is as close as possible to the requested one:
-- a SurfaceGui frame with LightInfluence = 0 is unaffected by the scene's
-- lighting, and MaxDistance = 0 keeps it drawn however far the camera sits.
local function makeBackdrop(parent: Instance): (Part, Frame)
	local part = Instance.new("Part")
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(0, 0, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.MaxDistance = 0
	gui.AlwaysOnTop = false
	-- The backdrop part is thousands of studs wide; the default PixelsPerStud
	-- sizing would ask for a canvas of tens of thousands of pixels per side.
	-- A fixed tiny canvas stretches over the face just the same.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(64, 64)
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.Parent = gui

	part.Parent = parent
	return part, frame
end

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
	booth.Name = "MCPIconBooth"

	local clone = target:Clone()
	if clone:IsA("Model") then
		local model = clone :: Model
		model:PivotTo(model:GetPivot() + delta)
	else
		local part = clone :: BasePart
		part.CFrame = part.CFrame + delta
	end
	clone.Parent = booth

	local stripped = 0
	if args.strip ~= false then
		stripped = stripEffects(clone)
	end

	local backdrop, backdropFrame = makeBackdrop(booth)
	booth.Parent = workspace

	local camera = workspace.CurrentCamera
	local prevCFrame, prevType, prevFov = camera.CFrame, camera.CameraType, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = DEFAULT_FOV

	local prevSelection = Selection:Get()
	Selection:Set({})

	local center = SKY_POS
	local cloneCf, cloneSize = Util.getBounds(clone)
	local corners = Util.boundsCorners(cloneCf, cloneSize)

	local yawDeg = args.yawDeg or 30
	local pitchDeg = args.pitchDeg or 20
	local distance = args.distanceStuds or Util.autoDistance(DEFAULT_FOV, cloneSize, DEFAULT_FILL_MARGIN)
	local padding = args.padding or 32

	local camPos = Util.orbitPosition(center, distance, yawDeg, pitchDeg)
	local camCFrame = CFrame.lookAt(camPos, center)
	local function setCam()
		camera.CFrame = camCFrame
	end

	-- Cover the whole frustum at the backdrop's plane, aspect included: any
	-- sliver of real scene left uncovered renders identically in both passes,
	-- so the matte reads it as fully opaque foreground.
	local planeDist = distance * (1 + BACKDROP_DISTANCE_MULT)
	local behind = center + (center - camPos).Unit * (distance * BACKDROP_DISTANCE_MULT)
	local extents = Util.frustumExtents(camera, planeDist, BACKDROP_MARGIN)
	backdrop.CFrame = CFrame.lookAt(behind, camPos)
	backdrop.Size = Vector3.new(extents.X, extents.Y, 0.2)

	-- Any ScreenGui composited over the viewport renders identically over both
	-- backdrops, so the matte would read it as fully opaque foreground -- the
	-- game's HUD baked into the icon. Hidden last, so nothing above can error
	-- out and leave the user's UI switched off.
	local restoreGuis = Util.hideViewportGuis()

	local ok, resultOrErr = pcall(function()
		-- Settle the camera once, then keep the crop rect fixed so both passes
		-- are pixel-aligned; only the backdrop color changes between them.
		for _ = 1, WARMUP_FRAMES do
			setCam()
			RunService.RenderStepped:Wait()
		end

		local rectPos, rectSize = Util.projectedRect(camera, corners)
		local pxPos = Vector2.new(rectPos.X - padding, rectPos.Y - padding)
		local pxSize = Vector2.new(rectSize.X + padding * 2, rectSize.Y + padding * 2)

		local function shoot(color: Color3)
			backdropFrame.BackgroundColor3 = color
			for _ = 1, WARMUP_FRAMES do
				setCam()
				RunService.RenderStepped:Wait()
			end
			return Util.captureRegion(pxPos, pxSize, setCam, CAPTURE_TIMEOUT_FRAMES)
		end

		local viewport = camera.ViewportSize
		local passA = shoot(toColor(args.bgA, Color3.fromRGB(0, 255, 0)))
		local passB = shoot(toColor(args.bgB, Color3.fromRGB(0, 0, 255)))

		if passA.widthPx ~= passB.widthPx or passA.heightPx ~= passB.heightPx then
			error("the two backdrop passes returned different sizes — the viewport was resized mid-capture")
		end

		return {
			widthPx = passA.widthPx,
			heightPx = passA.heightPx,
			aBase64 = passA.rgbaBase64,
			bBase64 = passB.rgbaBase64,
			viewportPx = { x = math.floor(viewport.X), y = math.floor(viewport.Y) },
			cropLogicalPx = { x = math.floor(pxSize.X), y = math.floor(pxSize.Y) },
		}
	end)

	booth:Destroy()
	Util.restoreCamera(camera, prevCFrame, prevType, prevFov)
	Selection:Set(prevSelection)
	restoreGuis()

	if not ok then
		error(resultOrErr)
	end

	local result = resultOrErr :: any
	result.targetPath = target:GetFullName()
	result.distanceStuds = distance
	result.yawDeg = yawDeg
	result.pitchDeg = pitchDeg
	result.strippedCount = stripped
	return result
end
