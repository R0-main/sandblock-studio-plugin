-- Captures a PNG-able image of a GUI: clones it in front of a solid colored
-- backdrop, screenshots, crops to the content, and returns the raw RGBA pixels
-- as base64. The MCP server turns those into a PNG.
--
-- Handles two target kinds:
--   * GuiObject  -> cropped to the element (centered on the backdrop).
--   * ScreenGui  -> cropped to the bounding box of its visible descendants.
--
-- Based on a validated Edit-mode capture flow. Key constraints handled:
--   * capture is in native pixels, GUI coords are logical -> apply a DPI scale
--   * the 3D viewport tab must NOT be active during capture -> focus a script doc
--   * CaptureScreenshot snapshots the already-composited frame -> warmup frames
--   * resize handles would show -> deselect during capture
local CaptureService = game:GetService("CaptureService")
local CoreGui = game:GetService("CoreGui")
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Util = require(script.Parent.Parent.Util)

local WARMUP_FRAMES = 8
local CAPTURE_TIMEOUT_FRAMES = 600
-- High enough to sit above any real GUI, low enough to leave room for the
-- cloned ScreenGui to render one step above the backdrop.
local BACKDROP_DISPLAY_ORDER = 2000000000

-- Union bounding box of all visible GuiObject descendants, in logical pixels.
local function boundingBox(root: Instance): (Vector2, Vector2)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") and d.Visible and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
			local p, s = d.AbsolutePosition, d.AbsoluteSize
			minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
			maxX, maxY = math.max(maxX, p.X + s.X), math.max(maxY, p.Y + s.Y)
		end
	end
	if minX == math.huge then
		local vp = workspace.CurrentCamera.ViewportSize
		return Vector2.zero, vp
	end
	return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY)
end

return function(args: any): any
	-- Resolve the target: explicit path, else current selection.
	local target: Instance?
	if args.target and args.target ~= "" then
		target = Util.resolvePath(args.target)
	else
		target = Selection:Get()[1]
	end
	local isScreenGui = target ~= nil and target:IsA("ScreenGui")
	if not (target and (target:IsA("GuiObject") or isScreenGui)) then
		error("target must be a GuiObject or ScreenGui, got " .. (target and target.ClassName or "nil"))
	end

	local bg = args.bgColor or {}
	local bgColor = Color3.fromRGB(bg.r or 255, bg.g or 0, bg.b or 255)
	local padding = args.padding or 24

	-- Temporary stage above everything (CoreGui renders in Edit mode).
	local stage = Instance.new("ScreenGui")
	stage.Name = "CaptureStage"
	stage.DisplayOrder = BACKDROP_DISPLAY_ORDER
	stage.IgnoreGuiInset = true
	stage.ResetOnSpawn = false
	stage.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = bgColor
	backdrop.BorderSizePixel = 0
	backdrop.Parent = stage
	stage.Parent = CoreGui

	local extraClone: Instance? -- a ScreenGui clone parented to CoreGui
	local getRegion: () -> (Vector2, Vector2)
	local waitReady: () -> ()

	if isScreenGui then
		-- Clone the whole ScreenGui one step above the backdrop and crop to its
		-- descendants' bounding box.
		local clone = (target :: ScreenGui):Clone()
		clone.Enabled = true
		clone.DisplayOrder = BACKDROP_DISPLAY_ORDER + 1
		clone.Parent = CoreGui
		extraClone = clone
		waitReady = function()
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
		end
		getRegion = function()
			return boundingBox(clone)
		end
	else
		-- Clone the element centered on the backdrop (renders in front of it).
		local gui = target :: GuiObject
		local clone = gui:Clone()
		clone.Position = UDim2.fromScale(0.5, 0.5)
		clone.AnchorPoint = Vector2.new(0.5, 0.5)
		clone.Size = UDim2.fromOffset(gui.AbsoluteSize.X, gui.AbsoluteSize.Y)
		clone.Visible = true
		clone.Parent = backdrop
		waitReady = function()
			while clone.AbsoluteSize.X == 0 do
				RunService.RenderStepped:Wait()
			end
		end
		getRegion = function()
			return clone.AbsolutePosition, clone.AbsoluteSize
		end
	end

	local previousSelection = Selection:Get()
	Selection:Set({}) -- hide resize handles

	-- Remember which script tabs are open so we can restore focus afterward.
	-- Studio exposes no API for the *active* tab or to focus the 3D viewport,
	-- so this is best-effort: if no scripts were open the user was on the
	-- viewport (closing our temp tab returns there); otherwise we re-focus a
	-- previously-open script.
	local openScriptsBefore = {}
	for _, doc in ipairs(ScriptEditorService:GetScriptDocuments()) do
		if not doc:IsCommandBar() then
			local scr = doc:GetScript()
			if scr then
				table.insert(openScriptsBefore, scr)
			end
		end
	end

	-- Switch focus off the 3D viewport (capture is garbage when it is active).
	local focusScript = Instance.new("Script")
	focusScript.Name = "CaptureFocusSwitch"
	focusScript.Parent = ServerStorage
	pcall(function()
		ScriptEditorService:OpenScriptDocumentAsync(focusScript)
	end)

	-- Wait for layout + compositing before the snapshot.
	waitReady()
	for _ = 1, WARMUP_FRAMES do
		RunService.RenderStepped:Wait()
	end

	local function cleanup()
		stage:Destroy()
		if extraClone then
			extraClone:Destroy()
		end
		pcall(function()
			ScriptEditorService:CloseScriptDocumentAsync(focusScript)
		end)
		focusScript:Destroy()
		Selection:Set(previousSelection)

		-- Restore editor focus. If scripts were open before, return to one of
		-- them; if none were, closing our temp tab already dropped us back on
		-- the 3D viewport (no API exists to focus the viewport explicitly).
		if #openScriptsBefore > 0 then
			pcall(function()
				ScriptEditorService:OpenScriptDocumentAsync(openScriptsBefore[1])
			end)
		end
	end

	local done = false
	local result: any
	local captureErr: any

	CaptureService:CaptureScreenshot(function(contentId)
		local ok, err = pcall(function()
			local fullImage = AssetService:CreateEditableImageAsync(Content.fromUri(contentId))
			local viewport = workspace.CurrentCamera.ViewportSize
			local capSize = fullImage.Size
			-- native-pixel capture vs logical GUI coords (handles Retina/DPI)
			local scale = Vector2.new(capSize.X / viewport.X, capSize.Y / viewport.Y)

			local absPos, absSize = getRegion()
			local pxPos = Vector2.new(
				math.floor((absPos.X - padding) * scale.X + 0.5),
				math.floor((absPos.Y - padding) * scale.Y + 0.5)
			)
			local pxSize = Vector2.new(
				math.floor((absSize.X + padding * 2) * scale.X + 0.5),
				math.floor((absSize.Y + padding * 2) * scale.Y + 0.5)
			)
			pxPos = Vector2.new(math.clamp(pxPos.X, 0, capSize.X), math.clamp(pxPos.Y, 0, capSize.Y))
			pxSize = Vector2.new(
				math.clamp(pxSize.X, 1, capSize.X - pxPos.X),
				math.clamp(pxSize.Y, 1, capSize.Y - pxPos.Y)
			)

			local pixels = fullImage:ReadPixelsBuffer(pxPos, pxSize) -- raw RGBA
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
	while not done do
		RunService.RenderStepped:Wait()
		frames += 1
		if frames > CAPTURE_TIMEOUT_FRAMES then
			break
		end
	end
	cleanup()

	if captureErr then
		error(captureErr)
	end
	if not result then
		error("capture timed out")
	end
	return result
end
