-- Small helpers shared by handlers.
local HttpService = game:GetService("HttpService")
local StudioService = game:GetService("StudioService")
local CaptureService = game:GetService("CaptureService")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local Util = {}

-- base64 lookup: index (0-63) -> single character
local B64 = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		B64[i - 1] = string.sub(alphabet, i, i)
	end
end

-- Encodes a Luau buffer as base64.
function Util.encodeBase64(buf: buffer): string
	local len = buffer.len(buf)
	local out = {}
	local outN = 0
	local i = 0
	while i < len do
		local rem = len - i
		local b1 = buffer.readu8(buf, i)
		local b2 = rem > 1 and buffer.readu8(buf, i + 1) or 0
		local b3 = rem > 2 and buffer.readu8(buf, i + 2) or 0
		local n = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2, 8), b3)
		outN += 1
		out[outN] = B64[bit32.band(bit32.rshift(n, 18), 63)]
			.. B64[bit32.band(bit32.rshift(n, 12), 63)]
			.. (rem > 1 and B64[bit32.band(bit32.rshift(n, 6), 63)] or "=")
			.. (rem > 2 and B64[bit32.band(n, 63)] or "=")
		i += 3
	end
	return table.concat(out)
end

-- Best-effort guard: errors if a script tab currently has editor focus.
-- Studio exposes no API to positively confirm the 3D viewport is active, only
-- StudioService.ActiveScript to detect the opposite (a script tab focused).
function Util.assertViewportActive()
	if StudioService.ActiveScript then
		error("the 3D viewport must be the active Studio tab (a script is currently focused) — click the viewport tab and retry")
	end
end

-- Hides every 2D overlay Studio composites on top of the 3D viewport, and
-- returns the function that puts them back. Studio renders StarterGui's
-- ScreenGuis in the Edit-mode viewport so you can lay UI out, and plugins can
-- add their own under CoreGui -- and CaptureScreenshot snapshots the *composited*
-- frame, so any of it lands in the capture on top of the model.
--
-- For the matting passes this is worse than cosmetic: an overlay renders
-- identically over both backdrops, so the difference is zero and it mattes as
-- fully opaque foreground -- a HUD baked into the icon at full alpha.
--
-- Only ScreenGui is touched, never LayerCollector at large: DockWidgetPluginGui
-- is also a LayerCollector, and disabling one closes another plugin's window.
function Util.hideViewportGuis(): () -> ()
	local hidden: { ScreenGui } = {}
	for _, serviceName in ipairs({ "StarterGui", "CoreGui" }) do
		local ok, service = pcall(function()
			return game:GetService(serviceName :: any)
		end)
		if not ok or not service then
			continue
		end
		for _, descendant in ipairs(service:GetDescendants()) do
			if descendant:IsA("ScreenGui") and descendant.Enabled then
				-- A plugin's UI may be locked to us; never let one failure abort
				-- the capture.
				local set = pcall(function()
					descendant.Enabled = false
				end)
				if set then
					table.insert(hidden, descendant)
				end
			end
		end
	end

	return function()
		for _, gui in ipairs(hidden) do
			pcall(function()
				if gui.Parent then
					gui.Enabled = true
				end
			end)
		end
	end
end

-- Bounds of a capture target: Model -> bounding box, BasePart -> its own CFrame/Size.
function Util.getBounds(inst: Instance): (CFrame, Vector3)
	if inst:IsA("Model") then
		return inst:GetBoundingBox()
	elseif inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame, (inst :: BasePart).Size
	end
	error("capture target must be a Model or BasePart, got " .. inst.ClassName)
end

-- Camera distance that fits a bounding sphere of the given size within fovDeg.
function Util.autoDistance(fovDeg: number, boundsSize: Vector3, fillMargin: number): number
	local radius = math.max(boundsSize.Magnitude / 2, 0.5)
	return (radius / math.tan(math.rad(fovDeg) / 2)) * fillMargin
end

-- World position on a sphere of `distance` around `center`, at the given orbit
-- angles. A *positive* pitch puts the camera above `center`, looking down.
--
-- The negation is load-bearing: fromEulerAnglesYXZ composes Ry*Rx*Rz, so
-- Rx(p) applied to (0, 0, d) yields (0, -d*sin(p), d*cos(p)) -- a positive
-- pitch would otherwise drop the camera *below* the subject and shoot it from
-- underneath.
function Util.orbitPosition(center: Vector3, distance: number, yawDeg: number, pitchDeg: number): Vector3
	local offset = CFrame.fromEulerAnglesYXZ(math.rad(-pitchDeg), math.rad(yawDeg), 0)
		:VectorToWorldSpace(Vector3.new(0, 0, distance))
	return center + offset
end

-- The 8 world-space corners of an oriented bounding box.
function Util.boundsCorners(cf: CFrame, size: Vector3): { Vector3 }
	local h = size / 2
	local corners = {}
	local n = 0
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				n += 1
				corners[n] = (cf * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
			end
		end
	end
	return corners
end

-- Screen-space rect (logical pixels) covering a set of world-space corners.
function Util.projectedRect(camera: Camera, corners: { Vector3 }): (Vector2, Vector2)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, world in ipairs(corners) do
		local v = camera:WorldToViewportPoint(world)
		minX, maxX = math.min(minX, v.X), math.max(maxX, v.X)
		minY, maxY = math.min(minY, v.Y), math.max(maxY, v.Y)
	end
	return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY)
end

-- Width/height of a plane that fully covers the camera frustum at `planeDist`
-- studs in front of the camera. The vertical half-angle is FieldOfView/2 and
-- the horizontal one follows the viewport's aspect ratio -- a square backdrop
-- sized off the camera distance alone under-covers a wide viewport, letting the
-- real scene (skybox, Studio overlays) leak into the corners of a capture.
function Util.frustumExtents(camera: Camera, planeDist: number, margin: number): Vector2
	local viewport = camera.ViewportSize
	local halfY = planeDist * math.tan(math.rad(camera.FieldOfView) / 2)
	local halfX = halfY * (viewport.X / math.max(viewport.Y, 1))
	return Vector2.new(halfX * 2 * margin, halfY * 2 * margin)
end

-- Captures the current viewport (or a crop of it), returning raw RGBA pixels
-- as base64. `onFrame`, if given, runs every render step (including while
-- waiting on the async capture callback) so a caller can keep re-asserting a
-- scriptable camera CFrame against Studio's own camera reset.
--
-- `regionPos`/`regionSize` are in *logical* pixels (the space of ViewportSize
-- and WorldToViewportPoint). The capture comes back in *native* pixels, which
-- on this setup is not the same resolution in either direction, so the region
-- is rescaled by capSize/viewport before cropping -- exactly as
-- RenderGuiElement does for GUI AbsolutePosition/AbsoluteSize.
function Util.captureRegion(
	regionPos: Vector2?,
	regionSize: Vector2?,
	onFrame: (() -> ())?,
	timeoutFrames: number?
): { widthPx: number, heightPx: number, rgbaBase64: string }
	local done = false
	local result: { widthPx: number, heightPx: number, rgbaBase64: string }
	local captureErr: any

	CaptureService:CaptureScreenshot(function(contentId)
		local ok, err = pcall(function()
			local fullImage = AssetService:CreateEditableImageAsync(Content.fromUri(contentId))
			local capSize = fullImage.Size

			local pxPos = Vector2.zero
			local pxSize = capSize
			if regionPos and regionSize then
				local viewport = workspace.CurrentCamera.ViewportSize
				local scale = Vector2.new(capSize.X / math.max(viewport.X, 1), capSize.Y / math.max(viewport.Y, 1))
				pxPos = Vector2.new(
					math.clamp(math.floor(regionPos.X * scale.X + 0.5), 0, capSize.X),
					math.clamp(math.floor(regionPos.Y * scale.Y + 0.5), 0, capSize.Y)
				)
				pxSize = Vector2.new(
					math.clamp(math.floor(regionSize.X * scale.X + 0.5), 1, capSize.X - pxPos.X),
					math.clamp(math.floor(regionSize.Y * scale.Y + 0.5), 1, capSize.Y - pxPos.Y)
				)
			end

			local pixels = fullImage:ReadPixelsBuffer(pxPos, pxSize)
			result = {
				widthPx = pxSize.X,
				heightPx = pxSize.Y,
				rgbaBase64 = Util.encodeBase64(pixels),
			}
		end)
		if not ok then
			captureErr = err
		end
		done = true
	end)

	local frames = 0
	local maxFrames = timeoutFrames or 600
	while not done do
		if onFrame then
			onFrame()
		end
		RunService.RenderStepped:Wait()
		frames += 1
		if frames > maxFrames then
			break
		end
	end

	if captureErr then
		error(captureErr)
	end
	if not result then
		error("capture timed out")
	end
	return result
end

-- Restores a camera's CFrame/CameraType/FieldOfView after a capture. Setting
-- all three in one multiple-assignment (no yield between CFrame and
-- CameraType) silently drops the *rotation*: Studio's Custom/Fixed camera
-- reclaims the camera on the CameraType flip using whichever pose last
-- rendered while still Scriptable, re-leveling it -- position sticks (it was
-- already the target, from the tail end of the capture loop) but any roll or
-- pitch beyond that gets discarded, which is exactly what made this look like
-- "the camera doesn't return to where it was". One RenderStepped after the
-- CFrame write (still Scriptable) lets that frame render before Studio
-- reclaims the camera, and the pose comes back intact. Measured live: without
-- the yield the restored CFrame's rotation columns differ from the original
-- by tens of degrees; with it, only float noise (~1e-7) remains.
function Util.restoreCamera(camera: Camera, prevCFrame: CFrame, prevType: Enum.CameraType, prevFov: number)
	camera.CFrame = prevCFrame
	RunService.RenderStepped:Wait()
	camera.CameraType = prevType
	camera.FieldOfView = prevFov
end

-- Resolves a dotted path like "Workspace.MyModel.Part" to an Instance, or nil.
function Util.resolvePath(path: string?): Instance?
	if path == nil or path == "" then
		return game:GetService("Workspace")
	end
	local current: Instance = game
	for segment in string.gmatch(path, "[^%.]+") do
		local nextInst: Instance? = current:FindFirstChild(segment)
		if not nextInst then
			-- Fall back to GetService for top-level services (e.g. "Workspace").
			local ok, service = pcall(function()
				return game:GetService(segment :: any)
			end)
			nextInst = (ok and service) or nil
		end
		if not nextInst then
			return nil
		end
		current = nextInst
	end
	return current
end

-- Returns a value guaranteed to be JSON-encodable, degrading to tostring().
function Util.safeValue(value: any): any
	local ok = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok then
		return value
	end
	return { result = tostring(value) }
end

return Util
