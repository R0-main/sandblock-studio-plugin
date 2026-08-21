--!strict

-- Native GuiObject component library used by the Sandblock Studio plugin.
-- Every component can be parented to a DockWidgetPluginGui, ScreenGui, or
-- another GuiObject; no Roact runtime or web/CSS dependency is required.

local StudioService = game:GetService("StudioService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local Components = {}

local function getTheme(props: any?)
	return if props and props.Theme then props.Theme else Theme.get()
end

local function makeText(
	parent: Instance,
	text: string,
	font: Font,
	textSize: number,
	color: Color3,
	properties: { [string]: any }?
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = font
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	if properties then
		for property, value in properties do
			(label :: any)[property] = value
		end
	end
	label.Parent = parent
	return label
end

local function findOverlayParent(anchor: GuiObject, preferredParent: Instance?): GuiObject?
	if preferredParent and preferredParent:IsA("GuiObject") then
		return preferredParent
	end

	local highestGui: GuiObject? = nil
	local current = anchor.Parent
	while current do
		if current:IsA("GuiObject") then
			highestGui = current
		end
		current = current.Parent
	end
	return highestGui
end

local function positionOverlayMenu(anchor: GuiObject, menu: GuiObject, overlayParent: GuiObject, height: number, gap: number)
	local overlayPosition = overlayParent.AbsolutePosition
	local overlaySize = overlayParent.AbsoluteSize
	local anchorPosition = anchor.AbsolutePosition
	local anchorSize = anchor.AbsoluteSize
	local width = math.min(anchorSize.X, math.max(overlaySize.X - 8, 0))
	local x = math.clamp(anchorPosition.X - overlayPosition.X, 4, math.max(overlaySize.X - width - 4, 4))
	local belowY = anchorPosition.Y - overlayPosition.Y + anchorSize.Y + gap
	local aboveY = anchorPosition.Y - overlayPosition.Y - height - gap
	local y = if belowY + height <= overlaySize.Y - 4 then belowY else math.max(aboveY, 4)
	menu.Position = UDim2.fromOffset(x, y)
	menu.Size = UDim2.fromOffset(width, height)
end

local function positionOverlayTooltip(anchor: GuiObject, tooltip: GuiObject, overlayParent: GuiObject, gap: number)
	local overlayPosition = overlayParent.AbsolutePosition
	local overlaySize = overlayParent.AbsoluteSize
	local anchorPosition = anchor.AbsolutePosition
	local anchorSize = anchor.AbsoluteSize
	local tooltipSize = tooltip.AbsoluteSize
	local centeredX = anchorPosition.X - overlayPosition.X + anchorSize.X / 2
	local minimumX = tooltipSize.X / 2 + 4
	local maximumX = overlaySize.X - tooltipSize.X / 2 - 4
	local x = if maximumX >= minimumX then math.clamp(centeredX, minimumX, maximumX) else overlaySize.X / 2
	local belowY = anchorPosition.Y - overlayPosition.Y + anchorSize.Y + gap
	local aboveY = anchorPosition.Y - overlayPosition.Y - tooltipSize.Y - gap
	local maximumY = math.max(overlaySize.Y - tooltipSize.Y - 4, 4)
	local y = if belowY + tooltipSize.Y <= overlaySize.Y - 4
		then belowY
		else math.clamp(aboveY, 4, maximumY)
	tooltip.Position = UDim2.fromOffset(x, y)
end

function Components.Surface(props: any)
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "Surface"
	root.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.Y
	root.BackgroundColor3 = props.BackgroundColor or theme.Color.SurfaceElevated
	root.BackgroundTransparency = props.Transparency or 0
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	root.ClipsDescendants = props.ClipsDescendants or false
	Util.corner(root, props.Radius or theme.Radius.Large)
	Util.stroke(root, props.BorderColor or theme.Color.Border, props.BorderTransparency or 0)
	Util.padding(root, props.Padding or theme.Spacing.Large)
	local rootLayout = Util.list(root, Enum.FillDirection.Vertical, props.Gap or theme.Spacing.Medium)

	if props.Title then
		makeText(root, props.Title, theme.Font.Semibold, theme.TextSize.Medium, theme.Color.TextPrimary, {
			Name = "Title",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 1,
		})
	end

	if props.Subtitle then
		makeText(root, props.Subtitle, theme.Font.Regular, theme.TextSize.Small, theme.Color.TextSecondary, {
			Name = "Subtitle",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.LayoutOrder = 3
	content.Size = UDim2.new(1, 0, 0, 0)
	content.Parent = root
	local contentLayout = Util.list(
		content,
		props.Direction or Enum.FillDirection.Vertical,
		props.ContentGap or theme.Spacing.Small,
		props.HorizontalAlignment,
		props.VerticalAlignment
	)

	root.Parent = props.Parent
	return {
		Root = root,
		Content = content,
		Layout = contentLayout,
		RootLayout = rootLayout,
	}
end

local BUTTON_STYLES = {
	Primary = "Primary",
	Secondary = "Secondary",
	Ghost = "Ghost",
	Danger = "Danger",
}

function Components.Button(props: any)
	local theme = getTheme(props)
	local style = props.Style or BUTTON_STYLES.Primary
	local enabled = props.Enabled ~= false
	local tactile = props.Tactile == true or string.lower(tostring(props.Appearance or "")) == "tactile"

	local normal = theme.Color.Accent
	local hover = theme.Color.AccentHover
	local pressed = theme.Color.AccentPressed
	local textColor = theme.Color.OnAccent
	local borderColor: Color3? = nil

	if style == BUTTON_STYLES.Secondary then
		normal = theme.Color.SurfaceMuted
		hover = theme.Color.SurfaceHover
		pressed = theme.Color.Surface
		textColor = theme.Color.TextPrimary
		borderColor = theme.Color.BorderStrong
	elseif style == BUTTON_STYLES.Ghost then
		normal = theme.Color.Surface
		hover = theme.Color.SurfaceMuted
		pressed = theme.Color.SurfaceHover
		textColor = theme.Color.TextSecondary
	elseif style == BUTTON_STYLES.Danger then
		normal = theme.Color.ErrorSurface
		hover = Color3.fromHex("542724")
		pressed = Color3.fromHex("2D1918")
		textColor = theme.Color.Error
		borderColor = Color3.fromHex("69403B")
	end

	local height = props.Height or theme.Control.Regular
	local baseZIndex = props.ZIndex or 1
	local container: Frame? = nil
	if tactile then
		container = Instance.new("Frame")
		container.Name = props.Name or "Button"
		container.AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.ClipsDescendants = false
		container.LayoutOrder = props.LayoutOrder or 0
		container.Size = props.Size or UDim2.fromOffset(0, height)
		container.ZIndex = baseZIndex
	end

	local root = Instance.new("TextButton")
	root.Name = if tactile then "Face" else props.Name or "Button"
	root.AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X
	root.BackgroundColor3 = normal
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.LayoutOrder = if tactile then 0 else props.LayoutOrder or 0
	root.Size = if tactile and props.Size then UDim2.fromScale(1, 1) else props.Size or UDim2.fromOffset(0, height)
	root.Text = ""
	root.ZIndex = if tactile then baseZIndex + 1 else baseZIndex
	root.Active = enabled
	root.Selectable = enabled
	Util.corner(root, props.Radius or theme.Radius.Medium)
	Util.padding(root, props.HorizontalPadding or theme.Spacing.Medium, 0)
	if borderColor then
		Util.stroke(root, borderColor, 0)
	end

	local depth: Frame? = nil
	local depthOffset = props.Depth or 5
	if tactile then
		local depthColor = theme.Color.OnAccent
		if style == BUTTON_STYLES.Secondary or style == BUTTON_STYLES.Ghost then
			depthColor = theme.Color.Canvas
		elseif style == BUTTON_STYLES.Danger then
			depthColor = Color3.fromHex("241312")
		end
		depth = Instance.new("Frame")
		depth.Name = "Depth"
		depth.Active = false
		depth.BackgroundColor3 = depthColor
		depth.BorderSizePixel = 0
		depth.Position = UDim2.fromOffset(0, depthOffset)
		depth.Size = UDim2.fromScale(1, 1)
		depth.ZIndex = baseZIndex
		depth.Parent = container
		Util.corner(depth, props.Radius or theme.Radius.Medium)
		if borderColor then
			Util.stroke(depth, borderColor, 0.25)
		end
	end

	local label = makeText(root, props.Text or "Button", theme.Font.Semibold, theme.TextSize.Body, textColor, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local ripple = Instance.new("Frame")
	ripple.Name = "TouchRipple"
	ripple.BackgroundColor3 = textColor
	ripple.BackgroundTransparency = 1
	ripple.BorderSizePixel = 0
	ripple.Position = UDim2.fromScale(0.5, 0.5)
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Size = UDim2.fromScale(1, 1)
	ripple.ZIndex = root.ZIndex + 1
	ripple.Parent = root
	Util.corner(ripple, props.Radius or theme.Radius.Medium)
	label.ZIndex = root.ZIndex + 2

	local function refreshEnabled()
		root.Active = enabled
		root.Selectable = enabled
		root.BackgroundColor3 = normal
		root.BackgroundTransparency = if enabled then 0 else 0.45
		label.TextTransparency = if enabled then 0 else 0.45
		if depth then
			depth.BackgroundTransparency = if enabled then 0 else 0.55
			if not enabled then
				root.Position = UDim2.fromOffset(0, 0)
			end
		end
	end

	Util.bindButtonColors(root, normal, hover, pressed, function()
		return enabled
	end)
	root.Activated:Connect(function()
		if not enabled then
			return
		end
		ripple.BackgroundTransparency = 0.84
		Util.tween(ripple, { BackgroundTransparency = 1 }, 0.28)
		if props.OnActivated then
			props.OnActivated()
		end
	end)
	if depth then
		local function pressFace()
			if enabled then
				Util.tween(root, { Position = UDim2.fromOffset(0, depthOffset) }, 0.06)
			end
		end
		local function restoreFace()
			Util.tween(root, { Position = UDim2.fromOffset(0, 0) }, 0.08)
		end
		root.MouseButton1Down:Connect(function()
			pressFace()
		end)
		root.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				pressFace()
			end
		end)
		root.MouseButton1Up:Connect(restoreFace)
		root.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				restoreFace()
			end
		end)
		local releaseConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				restoreFace()
			end
		end)
		root.Destroying:Connect(function()
			releaseConnection:Disconnect()
		end)
	end
	refreshEnabled()
	if container then
		root.Parent = container
		container.Parent = props.Parent
	else
		root.Parent = props.Parent
	end

	return {
		Root = container or root,
		Button = root,
		Label = label,
		Depth = depth,
		SetText = function(text: string)
			label.Text = text
		end,
		SetEnabled = function(value: boolean)
			enabled = value
			refreshEnabled()
		end,
	}
end

function Components.IconButton(props: any)
	local theme = getTheme(props)
	local size = props.Size or theme.Control.Regular
	local button = Components.Button({
		Parent = props.Parent,
		Name = props.Name or "IconButton",
		Text = props.Icon or "•",
		Style = props.Style or "Ghost",
		Size = UDim2.fromOffset(size, size),
		HorizontalPadding = 0,
		Enabled = props.Enabled,
		OnActivated = props.OnActivated,
		Theme = theme,
	})
	button.Label.FontFace = props.Font or theme.Font.Bold
	button.Label.TextSize = props.IconSize or theme.TextSize.Medium
	button.Label.Size = UDim2.fromScale(1, 1)
	button.Label.AutomaticSize = Enum.AutomaticSize.None
	if props.Tooltip then
		Components.Tooltip(button.Root, props.Tooltip, theme)
	end
	return button
end

function Components.Tag(props: any): Frame
	local theme = getTheme(props)
	local color = props.Color or theme.Color.TextSecondary
	local root = Instance.new("Frame")
	root.Name = props.Name or "Tag"
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = props.BackgroundColor or theme.Color.SurfaceMuted
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = UDim2.fromOffset(0, 24)
	Util.corner(root, theme.Radius.Pill)
	Util.padding(root, theme.Spacing.Small, 0)
	makeText(root, props.Text or "Tag", theme.Font.Medium, theme.TextSize.Small, color, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	root.Parent = props.Parent
	return root
end

local STATUS_COLORS = {
	connected = { "Success", "SuccessSurface" },
	success = { "Success", "SuccessSurface" },
	warning = { "Warning", "WarningSurface" },
	connecting = { "Warning", "WarningSurface" },
	error = { "Error", "ErrorSurface" },
	disconnected = { "Error", "ErrorSurface" },
	info = { "Info", "InfoSurface" },
	neutral = { "TextMuted", "SurfaceMuted" },
}

function Components.StatusBadge(props: any)
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "StatusBadge"
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = UDim2.fromOffset(0, 26)
	Util.corner(root, theme.Radius.Pill)

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.BorderSizePixel = 0
	dot.Position = UDim2.new(0, 9, 0.5, 0)
	dot.Size = UDim2.fromOffset(7, 7)
	dot.Parent = root
	Util.corner(dot, theme.Radius.Pill)

	local label = makeText(root, props.Text or "Unknown", theme.Font.Medium, theme.TextSize.Small, theme.Color.TextSecondary, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(23, 0),
		Size = UDim2.new(0, 0, 1, 0),
	})
	local rightPadding = Instance.new("Frame")
	rightPadding.Name = "RightPadding"
	rightPadding.BackgroundTransparency = 1
	rightPadding.Position = UDim2.new(1, 0, 0, 0)
	rightPadding.Size = UDim2.fromOffset(10, 1)
	rightPadding.Parent = label

	local function set(status: string, text: string?)
		local keys = STATUS_COLORS[string.lower(status)] or STATUS_COLORS.neutral
		local foreground = theme.Color[keys[1]]
		local background = theme.Color[keys[2]]
		dot.BackgroundColor3 = foreground
		label.TextColor3 = foreground
		root.BackgroundColor3 = background
		if text then
			label.Text = text
		end
	end

	set(props.Status or "neutral", props.Text)
	root.Parent = props.Parent
	return {
		Root = root,
		Dot = dot,
		Label = label,
		Set = set,
	}
end

function Components.Checkbox(props: any)
	local theme = getTheme(props)
	local checked = props.Checked == true
	local enabled = props.Enabled ~= false

	local root = Instance.new("TextButton")
	root.Name = props.Name or "Checkbox"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 30)
	root.Text = ""
	root.AutoButtonColor = false

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.BackgroundColor3 = theme.Color.SurfaceMuted
	box.BorderSizePixel = 0
	box.Position = UDim2.new(0, 0, 0.5, 0)
	box.Size = UDim2.fromOffset(20, 20)
	box.Parent = root
	Util.corner(box, theme.Radius.Small)
	local stroke = Util.stroke(box, theme.Color.BorderStrong)

	local check = makeText(box, "✓", theme.Font.Bold, 14, theme.Color.OnAccent, {
		Name = "Checkmark",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	})

	local label = makeText(root, props.Text or "Checkbox", theme.Font.Regular, theme.TextSize.Body, theme.Color.TextPrimary, {
		Name = "Label",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -30, 1, 0),
	})

	local function refresh()
		box.BackgroundColor3 = if checked then theme.Color.Accent else theme.Color.SurfaceMuted
		stroke.Color = if checked then theme.Color.Accent else theme.Color.BorderStrong
		check.Visible = checked
		root.Active = enabled
		root.Selectable = enabled
		root.BackgroundTransparency = 1
		label.TextTransparency = if enabled then 0 else 0.5
		box.BackgroundTransparency = if enabled then 0 else 0.5
	end

	local function set(value: boolean, silent: boolean?)
		checked = value
		refresh()
		if not silent and props.OnChanged then
			props.OnChanged(checked)
		end
	end

	root.Activated:Connect(function()
		if enabled then
			set(not checked)
		end
	end)
	root.MouseEnter:Connect(function()
		if enabled and not checked then
			Util.tween(box, { BackgroundColor3 = theme.Color.SurfaceHover })
		end
	end)
	root.MouseLeave:Connect(refresh)
	refresh()
	root.Parent = props.Parent

	return {
		Root = root,
		SetChecked = set,
		GetChecked = function()
			return checked
		end,
	}
end

function Components.Switch(props: any)
	local theme = getTheme(props)
	local checked = props.Checked == true
	local enabled = props.Enabled ~= false
	local hasDescription = props.Description ~= nil and props.Description ~= ""

	local root = Instance.new("TextButton")
	root.Name = props.Name or "Switch"
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, if hasDescription then 44 else 30)
	root.Text = ""

	local copy = Instance.new("Frame")
	copy.Name = "Copy"
	copy.AnchorPoint = Vector2.new(0, 0.5)
	copy.AutomaticSize = Enum.AutomaticSize.Y
	copy.BackgroundTransparency = 1
	copy.Position = UDim2.fromScale(0, 0.5)
	copy.Size = UDim2.new(1, -58, 0, 0)
	copy.Parent = root
	Util.list(copy, Enum.FillDirection.Vertical, 3)

	local label = makeText(copy, props.Text or props.Label or "Switch", theme.Font.Semibold, theme.TextSize.Body, theme.Color.TextPrimary, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
		LayoutOrder = 1,
	})
	if hasDescription then
		makeText(copy, tostring(props.Description), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextMuted, {
			Name = "Description",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.BackgroundColor3 = theme.Color.Surface
	track.BorderSizePixel = 0
	track.Position = UDim2.new(1, 0, 0.5, 0)
	track.Size = UDim2.fromOffset(44, 25)
	track.Parent = root
	Util.corner(track, theme.Radius.Pill)
	local trackStroke = Util.stroke(track, theme.Color.BorderStrong)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.AnchorPoint = Vector2.new(0, 0.5)
	thumb.BackgroundColor3 = theme.Color.TextMuted
	thumb.BorderSizePixel = 0
	thumb.Position = UDim2.new(0, 4, 0.5, 0)
	thumb.Size = UDim2.fromOffset(17, 17)
	thumb.Parent = track
	Util.corner(thumb, theme.Radius.Pill)

	local function refresh(animated: boolean?)
		root.Active = enabled
		root.Selectable = enabled
		label.TextTransparency = if enabled then 0 else 0.5
		track.BackgroundTransparency = if enabled then 0 else 0.5
		thumb.BackgroundTransparency = if enabled then 0 else 0.5
		trackStroke.Transparency = if enabled then 0 else 0.5
		local trackColor = if checked then theme.Color.Accent else theme.Color.Surface
		local thumbColor = if checked then theme.Color.OnAccent else theme.Color.TextMuted
		local thumbPosition = if checked then UDim2.new(0, 23, 0.5, 0) else UDim2.new(0, 4, 0.5, 0)
		trackStroke.Color = if checked then theme.Color.Accent else theme.Color.BorderStrong
		if animated then
			Util.tween(track, { BackgroundColor3 = trackColor })
			Util.tween(thumb, { BackgroundColor3 = thumbColor, Position = thumbPosition })
		else
			track.BackgroundColor3 = trackColor
			thumb.BackgroundColor3 = thumbColor
			thumb.Position = thumbPosition
		end
	end

	local function setChecked(value: boolean, silent: boolean?)
		checked = value
		refresh(true)
		if not silent and props.OnChanged then
			props.OnChanged(checked)
		end
	end

	root.Activated:Connect(function()
		if enabled then
			setChecked(not checked)
		end
	end)
	refresh(false)
	root.Parent = props.Parent

	return {
		Root = root,
		Track = track,
		Thumb = thumb,
		SetChecked = setChecked,
		GetChecked = function()
			return checked
		end,
		SetEnabled = function(value: boolean)
			enabled = value
			refresh(false)
		end,
	}
end

function Components.Slider(props: any)
	local theme = getTheme(props)
	local minimum = props.Min or 0
	local maximum = props.Max or 100
	local step = math.max(props.Step or 1, 0.000001)
	local value = props.Value or props.DefaultValue or 50
	local enabled = props.Enabled ~= false
	local dragging = false
	local activeTouch: InputObject? = nil

	local root = Instance.new("Frame")
	root.Name = props.Name or "Slider"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 48)

	local label = makeText(root, props.Text or props.Label or "Slider", theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextSecondary, {
		Name = "Label",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -64, 0, 18),
	})
	local valueLabel = makeText(root, "", theme.Font.Code, theme.TextSize.Small, theme.Color.Accent, {
		Name = "Value",
		Position = UDim2.new(1, -64, 0, 0),
		Size = UDim2.fromOffset(64, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = props.ShowValue ~= false,
	})

	local hitbox = Instance.new("TextButton")
	hitbox.Name = "TrackHitbox"
	hitbox.AutoButtonColor = false
	hitbox.BackgroundTransparency = 1
	hitbox.BorderSizePixel = 0
	hitbox.Position = UDim2.fromOffset(0, 22)
	hitbox.Size = UDim2.new(1, 0, 0, 24)
	hitbox.Text = ""
	hitbox.Parent = root

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = theme.Color.SurfaceMuted
	track.BorderSizePixel = 0
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 5)
	track.Parent = hitbox
	Util.corner(track, theme.Radius.Pill)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = theme.Color.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.Parent = track
	Util.corner(fill, theme.Radius.Pill)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundColor3 = theme.Color.Accent
	thumb.BorderSizePixel = 0
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.Size = UDim2.fromOffset(19, 19)
	thumb.Parent = hitbox
	Util.corner(thumb, theme.Radius.Pill)
	Util.stroke(thumb, theme.Color.OnAccent, 0, 2)

	local function formatValue(current: number): string
		if props.FormatValue then
			return tostring(props.FormatValue(current))
		end
		return tostring(current)
	end

	local function setValue(nextValue: number, silent: boolean?)
		local range = maximum - minimum
		local stepped = minimum + math.round((nextValue - minimum) / step) * step
		local previousValue = value
		value = math.clamp(stepped, minimum, maximum)
		local progress = if range == 0 then 0 else math.clamp((value - minimum) / range, 0, 1)
		fill.Size = UDim2.fromScale(progress, 1)
		thumb.Position = UDim2.fromScale(progress, 0.5)
		valueLabel.Text = formatValue(value)
		if value ~= previousValue and not silent and props.OnChanged then
			props.OnChanged(value)
		end
	end

	local function updateFromX(x: number)
		if not enabled or hitbox.AbsoluteSize.X <= 0 then
			return
		end
		local progress = math.clamp((x - hitbox.AbsolutePosition.X) / hitbox.AbsoluteSize.X, 0, 1)
		setValue(minimum + (maximum - minimum) * progress)
	end

	-- UIDragDetector owns pointer capture once a drag begins, so movement keeps
	-- arriving after the cursor leaves the track or the slider's GuiObject.
	local dragDetector = Instance.new("UIDragDetector")
	dragDetector.Name = "PointerCapture"
	dragDetector.DragStyle = Enum.UIDragDetectorDragStyle.Scriptable
	dragDetector.Enabled = enabled
	dragDetector:SetDragStyleFunction(function(_inputPosition: Vector2)
		return nil
	end)
	dragDetector.DragStart:Connect(function(inputPosition: Vector2)
		dragging = true
		updateFromX(inputPosition.X)
	end)
	dragDetector.DragContinue:Connect(function(inputPosition: Vector2)
		updateFromX(inputPosition.X)
	end)
	dragDetector.DragEnd:Connect(function(inputPosition: Vector2)
		updateFromX(inputPosition.X)
		dragging = false
		activeTouch = nil
	end)
	dragDetector.Parent = hitbox

	-- Direct GUI and UserInputService signals remain as a compatibility fallback
	-- for Studio contexts that temporarily suppress UIDragDetector interactions.
	hitbox.MouseButton1Down:Connect(function(x: number)
		if not enabled then
			return
		end
		dragging = true
		activeTouch = nil
		updateFromX(x)
	end)
	hitbox.MouseMoved:Connect(function(x: number)
		if dragging and not activeTouch then
			updateFromX(x)
		end
	end)
	hitbox.MouseButton1Up:Connect(function(x: number)
		if dragging and not activeTouch then
			updateFromX(x)
			dragging = false
		end
	end)
	hitbox.InputBegan:Connect(function(input: InputObject)
		if enabled and input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			activeTouch = input
			updateFromX(input.Position.X)
		end
	end)
	local dragConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		local isTouchMovement = activeTouch ~= nil and input == activeTouch
		local isMouseMovement = activeTouch == nil and input.UserInputType == Enum.UserInputType.MouseMovement
		if isTouchMovement or isMouseMovement then
			updateFromX(input.Position.X)
		end
	end)
	local inputEndedConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeTouch then
			dragging = false
			activeTouch = nil
		end
	end)
	root.Destroying:Connect(function()
		dragConnection:Disconnect()
		inputEndedConnection:Disconnect()
	end)

	local function setEnabled(nextEnabled: boolean)
		enabled = nextEnabled
		dragDetector.Enabled = enabled
		if not enabled then
			dragging = false
			activeTouch = nil
		end
		hitbox.Active = enabled
		hitbox.Selectable = enabled
		label.TextTransparency = if enabled then 0 else 0.5
		valueLabel.TextTransparency = if enabled then 0 else 0.5
		track.BackgroundTransparency = if enabled then 0 else 0.5
		fill.BackgroundTransparency = if enabled then 0 else 0.5
		thumb.BackgroundTransparency = if enabled then 0 else 0.5
	end

	setValue(value, true)
	setEnabled(enabled)
	root.Parent = props.Parent
	return {
		Root = root,
		Track = track,
		Fill = fill,
		Thumb = thumb,
		DragDetector = dragDetector,
		SetValue = setValue,
		GetValue = function()
			return value
		end,
		SetEnabled = setEnabled,
	}
end

function Components.RadioGroup(props: any)
	local theme = getTheme(props)
	local options = props.Options or {}
	local selected = props.Value or props.DefaultValue
	local groupEnabled = props.Enabled ~= false
	local rows = {}

	local root = Instance.new("Frame")
	root.Name = props.Name or "RadioGroup"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	Util.list(root, Enum.FillDirection.Vertical, theme.Spacing.Small)

	makeText(root, props.Text or props.Label or "Options", theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextSecondary, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 1,
	})

	local optionsFrame = Instance.new("Frame")
	optionsFrame.Name = "Options"
	optionsFrame.AutomaticSize = Enum.AutomaticSize.Y
	optionsFrame.BackgroundTransparency = 1
	optionsFrame.LayoutOrder = 2
	optionsFrame.Size = UDim2.new(1, 0, 0, 0)
	optionsFrame.Parent = root
	Util.list(optionsFrame, Enum.FillDirection.Vertical, theme.Spacing.Small)

	local setValue
	for index, option in options do
		local rowEnabled = option.Enabled ~= false and option.Disabled ~= true
		local hasDescription = option.Description ~= nil and option.Description ~= ""
		local row = Instance.new("TextButton")
		row.Name = "Option" .. tostring(index)
		row.AutoButtonColor = false
		row.BackgroundColor3 = theme.Color.Surface
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, if hasDescription then 56 else 44)
		row.Text = ""
		row.Parent = optionsFrame
		Util.corner(row, theme.Radius.Medium)
		local stroke = Util.stroke(row, theme.Color.Border)

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.BackgroundColor3 = theme.Color.Surface
		dot.BorderSizePixel = 0
		dot.Position = UDim2.new(0, theme.Spacing.Medium, 0.5, 0)
		dot.Size = UDim2.fromOffset(20, 20)
		dot.Parent = row
		Util.corner(dot, theme.Radius.Pill)
		local dotStroke = Util.stroke(dot, theme.Color.BorderStrong)

		local inner = Instance.new("Frame")
		inner.Name = "Selection"
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.BackgroundColor3 = theme.Color.OnAccent
		inner.BorderSizePixel = 0
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromOffset(8, 8)
		inner.Visible = false
		inner.Parent = dot
		Util.corner(inner, theme.Radius.Pill)

		local copy = Instance.new("Frame")
		copy.Name = "Copy"
		copy.AnchorPoint = Vector2.new(0, 0.5)
		copy.AutomaticSize = Enum.AutomaticSize.Y
		copy.BackgroundTransparency = 1
		copy.Position = UDim2.new(0, 44, 0.5, 0)
		copy.Size = UDim2.new(1, -56, 0, 0)
		copy.Parent = row
		Util.list(copy, Enum.FillDirection.Vertical, 3)
		local optionLabel = makeText(copy, tostring(option.Text or option.Label or option.Value), theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextPrimary, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = 1,
		})
		if hasDescription then
			makeText(copy, tostring(option.Description), theme.Font.Regular, theme.TextSize.Caption, theme.Color.TextMuted, {
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				TextWrapped = true,
				LayoutOrder = 2,
			})
		end

		rows[option.Value] = {
			Root = row,
			Dot = dot,
			DotStroke = dotStroke,
			Inner = inner,
			Stroke = stroke,
			Label = optionLabel,
			Enabled = rowEnabled,
		}
		row.Activated:Connect(function()
			if groupEnabled and rowEnabled then
				setValue(option.Value)
			end
		end)
	end

	local function refresh()
		for optionValue, references in rows do
			local isSelected = optionValue == selected
			local isEnabled = groupEnabled and references.Enabled
			references.Root.Active = isEnabled
			references.Root.Selectable = isEnabled
			references.Root.BackgroundColor3 = if isSelected then theme.Color.WarningSurface else theme.Color.Surface
			references.Root.BackgroundTransparency = if isEnabled then 0 else 0.45
			references.Stroke.Color = if isSelected then theme.Color.Accent else theme.Color.Border
			references.Dot.BackgroundColor3 = if isSelected then theme.Color.Accent else theme.Color.Surface
			references.DotStroke.Color = if isSelected then theme.Color.Accent else theme.Color.BorderStrong
			references.Inner.Visible = isSelected
			references.Label.TextTransparency = if isEnabled then 0 else 0.5
		end
	end

	function setValue(nextValue: any, silent: boolean?)
		if rows[nextValue] == nil then
			return
		end
		selected = nextValue
		refresh()
		if not silent then
			local callback = props.OnChanged or props.OnValueChanged
			if callback then
				callback(selected)
			end
		end
	end

	refresh()
	root.Parent = props.Parent
	return {
		Root = root,
		SetValue = setValue,
		GetValue = function()
			return selected
		end,
	}
end

function Components.ChoiceButton(props: any)
	local theme = getTheme(props)
	local selected = props.Selected == true
	local enabled = props.Enabled ~= false

	local root = Instance.new("TextButton")
	root.Name = props.Name or "ChoiceButton"
	root.AutoButtonColor = false
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 78)
	root.Text = ""
	Util.corner(root, theme.Radius.Large)
	local stroke = Util.stroke(root, theme.Color.Border)

	local icon = makeText(root, props.Icon or "◇", theme.Font.Bold, theme.TextSize.Title, theme.Color.TextSecondary, {
		Name = "Icon",
		Position = UDim2.new(0, theme.Spacing.Large, 0, 0),
		Size = UDim2.fromOffset(24, 78),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local copy = Instance.new("Frame")
	copy.Name = "Copy"
	copy.AnchorPoint = Vector2.new(0, 0.5)
	copy.AutomaticSize = Enum.AutomaticSize.Y
	copy.BackgroundTransparency = 1
	copy.Position = UDim2.new(0, 54, 0.5, 0)
	copy.Size = UDim2.new(1, -94, 0, 0)
	copy.Parent = root
	Util.list(copy, Enum.FillDirection.Vertical, 4)
	local label = makeText(copy, props.Text or props.Label or "Choice", theme.Font.Semibold, theme.TextSize.Body, theme.Color.TextPrimary, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
		LayoutOrder = 1,
	})
	local description
	if props.Description then
		description = makeText(copy, tostring(props.Description), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextSecondary, {
			Name = "Description",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end
	local state = makeText(root, "✓", theme.Font.Bold, theme.TextSize.Medium, theme.Color.OnAccent, {
		Name = "State",
		Position = UDim2.new(1, -36, 0, 0),
		Size = UDim2.fromOffset(24, 78),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local function refresh()
		root.Active = enabled
		root.Selectable = enabled
		root.BackgroundColor3 = if selected then theme.Color.Accent else theme.Color.Surface
		root.BackgroundTransparency = if enabled then 0 else 0.48
		stroke.Color = if selected then theme.Color.Accent else theme.Color.Border
		icon.TextColor3 = if selected then theme.Color.OnAccent else theme.Color.TextSecondary
		label.TextColor3 = if selected then theme.Color.OnAccent else theme.Color.TextPrimary
		if description then
			description.TextColor3 = if selected then Color3.fromHex("5A4817") else theme.Color.TextSecondary
		end
		state.Visible = selected
	end

	local function setSelected(value: boolean)
		selected = value
		refresh()
	end
	root.Activated:Connect(function()
		if enabled and props.OnActivated then
			props.OnActivated()
		end
	end)
	refresh()
	root.Parent = props.Parent
	return {
		Root = root,
		SetSelected = setSelected,
		GetSelected = function()
			return selected
		end,
	}
end

function Components.TextInput(props: any)
	local theme = getTheme(props)
	local enabled = props.Enabled ~= false
	local root = Instance.new("Frame")
	root.Name = props.Name or "TextInput"
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, theme.Control.Regular)
	Util.corner(root, theme.Radius.Medium)
	local stroke = Util.stroke(root, theme.Color.BorderStrong)

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.ClearTextOnFocus = props.ClearTextOnFocus == true
	input.FontFace = theme.Font.Regular
	input.MultiLine = props.MultiLine == true
	input.PlaceholderColor3 = theme.Color.TextMuted
	input.PlaceholderText = props.Placeholder or ""
	input.Position = UDim2.fromOffset(theme.Spacing.Medium, 0)
	input.Size = UDim2.new(1, -theme.Spacing.Medium * 2, 1, 0)
	input.Text = props.Text or ""
	input.TextColor3 = theme.Color.TextPrimary
	input.TextEditable = enabled
	input.TextSize = theme.TextSize.Body
	input.TextWrapped = props.MultiLine == true
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = if props.MultiLine then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	input.Parent = root

	input.Focused:Connect(function()
		stroke.Color = theme.Color.Focus
		stroke.Thickness = 1.5
	end)
	input.FocusLost:Connect(function(enterPressed: boolean)
		stroke.Color = theme.Color.BorderStrong
		stroke.Thickness = 1
		if props.OnChanged then
			props.OnChanged(input.Text)
		end
		if enterPressed and props.OnSubmitted then
			props.OnSubmitted(input.Text)
		end
	end)
	root.Parent = props.Parent

	return {
		Root = root,
		Input = input,
		SetText = function(text: string)
			input.Text = text
		end,
	}
end

function Components.TextArea(props: any)
	local theme = getTheme(props)
	local nextProps = table.clone(props)
	nextProps.MultiLine = true
	nextProps.Size = props.Size or UDim2.new(1, 0, 0, 96)
	local textArea = Components.TextInput(nextProps)
	textArea.Root.Name = props.Name or "TextArea"
	textArea.Input.Position = UDim2.fromOffset(theme.Spacing.Medium, theme.Spacing.Small)
	textArea.Input.Size = UDim2.new(1, -theme.Spacing.Medium * 2, 1, -theme.Spacing.Small * 2)
	textArea.Input.TextYAlignment = Enum.TextYAlignment.Top
	return textArea
end

function Components.SearchField(props: any)
	local theme = getTheme(props)
	local enabled = props.Enabled ~= false
	local root = Instance.new("Frame")
	root.Name = props.Name or "SearchField"
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, theme.Control.Regular)
	Util.corner(root, theme.Radius.Medium)
	local stroke = Util.stroke(root, theme.Color.BorderStrong)

	local searchIcon = Instance.new("Frame")
	searchIcon.Name = "SearchIcon"
	searchIcon.AnchorPoint = Vector2.new(0, 0.5)
	searchIcon.BackgroundTransparency = 1
	searchIcon.Position = UDim2.new(0, theme.Spacing.Medium, 0.5, 0)
	searchIcon.Size = UDim2.fromOffset(16, 16)
	searchIcon.Parent = root
	local lens = Instance.new("Frame")
	lens.Name = "Lens"
	lens.BackgroundTransparency = 1
	lens.Position = UDim2.fromOffset(1, 1)
	lens.Size = UDim2.fromOffset(10, 10)
	lens.Parent = searchIcon
	Util.corner(lens, theme.Radius.Pill)
	Util.stroke(lens, theme.Color.TextMuted, 0, 1.5)
	local handle = Instance.new("Frame")
	handle.Name = "Handle"
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.BackgroundColor3 = theme.Color.TextMuted
	handle.BorderSizePixel = 0
	handle.Position = UDim2.fromOffset(12, 12)
	handle.Rotation = 45
	handle.Size = UDim2.fromOffset(6, 1.5)
	handle.Parent = searchIcon
	Util.corner(handle, theme.Radius.Pill)

	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.ClearTextOnFocus = false
	input.FontFace = theme.Font.Regular
	input.PlaceholderColor3 = theme.Color.TextMuted
	input.PlaceholderText = props.Placeholder or "Search"
	input.Position = UDim2.fromOffset(38, 0)
	input.Size = UDim2.new(1, -50, 1, 0)
	input.Text = props.Text or ""
	input.TextColor3 = theme.Color.TextPrimary
	input.TextEditable = enabled
	input.TextSize = theme.TextSize.Body
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.Parent = root

	input.Focused:Connect(function()
		stroke.Color = theme.Color.Focus
		stroke.Thickness = 1.5
	end)
	input.FocusLost:Connect(function(enterPressed: boolean)
		stroke.Color = theme.Color.BorderStrong
		stroke.Thickness = 1
		if enterPressed and props.OnSubmitted then
			props.OnSubmitted(input.Text)
		end
	end)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if props.OnChanged then
			props.OnChanged(input.Text)
		end
	end)
	root.Parent = props.Parent
	return {
		Root = root,
		Input = input,
		SetText = function(text: string)
			input.Text = text
		end,
	}
end

function Components.Dropdown(props: any)
	local theme = getTheme(props)
	local options = props.Options or {}
	local selected = props.Selected or options[1] or ""
	local isOpen = false
	local menuHeight = #options * 30 + theme.Spacing.Small
	local overlayParent: GuiObject? = nil

	local root = Instance.new("TextButton")
	root.Name = props.Name or "Dropdown"
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, theme.Control.Regular)
	root.Text = ""
	root.AutoButtonColor = false
	root.ClipsDescendants = false
	Util.corner(root, theme.Radius.Medium)
	local rootStroke = Util.stroke(root, theme.Color.BorderStrong)

	local label = makeText(root, tostring(selected), theme.Font.Regular, theme.TextSize.Body, theme.Color.TextPrimary, {
		Name = "Selection",
		Position = UDim2.fromOffset(theme.Spacing.Medium, 0),
		Size = UDim2.new(1, -44, 1, 0),
	})
	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.new(1, -18, 0.5, 0)
	arrow.Size = UDim2.fromOffset(14, 14)
	arrow.Parent = root
	for index, rotation in { 42, -42 } do
		local segment = Instance.new("Frame")
		segment.Name = if index == 1 then "Left" else "Right"
		segment.AnchorPoint = Vector2.new(0.5, 0.5)
		segment.BackgroundColor3 = theme.Color.TextSecondary
		segment.BorderSizePixel = 0
		segment.Position = UDim2.fromOffset(if index == 1 then 4.5 else 9.5, 7)
		segment.Rotation = rotation
		segment.Size = UDim2.fromOffset(7, 1.5)
		segment.Parent = arrow
		Util.corner(segment, theme.Radius.Pill)
	end

	local menu = Instance.new("Frame")
	menu.Name = "Options"
	menu.BackgroundColor3 = theme.Color.SurfaceElevated
	menu.BorderSizePixel = 0
	menu.Position = UDim2.new(0, 0, 1, 6)
	menu.Size = UDim2.new(1, 0, 0, menuHeight)
	menu.Visible = false
	menu.ZIndex = 1000
	menu.Parent = root
	Util.corner(menu, theme.Radius.Medium)
	Util.stroke(menu, theme.Color.BorderStrong)
	Util.padding(menu, theme.Spacing.XSmall)
	Util.list(menu, Enum.FillDirection.Vertical, 0)

	local function updateMenuPosition()
		if not isOpen then
			return
		end
		overlayParent = findOverlayParent(root, props.OverlayParent) or overlayParent
		if overlayParent then
			if menu.Parent ~= overlayParent then
				menu.Parent = overlayParent
			end
			positionOverlayMenu(root, menu, overlayParent, menuHeight, 6)
		end
	end

	local function setOpen(value: boolean)
		isOpen = value
		if value then
			updateMenuPosition()
		end
		menu.Visible = value
		Util.tween(arrow, { Rotation = if value then 180 else 0 })
		rootStroke.Color = if value then theme.Color.Focus else theme.Color.BorderStrong
	end

	local function selectOption(option: any, silent: boolean?)
		selected = option
		label.Text = tostring(option)
		setOpen(false)
		if not silent and props.OnChanged then
			props.OnChanged(option)
		end
	end

	for index, option in options do
		local item = Instance.new("TextButton")
		item.Name = "Option" .. tostring(index)
		item.BackgroundColor3 = theme.Color.SurfaceElevated
		item.BorderSizePixel = 0
		item.LayoutOrder = index
		item.Size = UDim2.new(1, 0, 0, 30)
		item.Text = tostring(option)
		item.TextColor3 = theme.Color.TextPrimary
		item.TextSize = theme.TextSize.Body
		item.FontFace = theme.Font.Regular
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.ZIndex = menu.ZIndex + 1
		Util.corner(item, theme.Radius.Small)
		Util.padding(item, theme.Spacing.Small, 0)
		Util.bindButtonColors(
			item,
			theme.Color.SurfaceElevated,
			theme.Color.SurfaceHover,
			theme.Color.SurfaceMuted
		)
		item.Activated:Connect(function()
			selectOption(option)
		end)
		item.Parent = menu
	end

	root.Activated:Connect(function()
		setOpen(not isOpen)
	end)
	local positionConnection = RunService.RenderStepped:Connect(updateMenuPosition)
	root.Destroying:Connect(function()
		positionConnection:Disconnect()
		if menu.Parent and menu.Parent ~= root then
			menu:Destroy()
		end
	end)
	root.Parent = props.Parent

	return {
		Root = root,
		Menu = menu,
		SetOpen = setOpen,
		SetSelected = selectOption,
		GetSelected = function()
			return selected
		end,
	}
end

function Components.DropdownMenu(props: any)
	local theme = getTheme(props)
	local items = props.Items or {}
	local isOpen = false
	local width = props.Width or 180
	local menuHeight = #items * 34 + theme.Spacing.Small
	local overlayParent: GuiObject? = nil

	local root = Instance.new("Frame")
	root.Name = props.Name or "DropdownMenu"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ClipsDescendants = false
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.fromOffset(width, theme.Control.Regular)
	root.ZIndex = props.ZIndex or 10

	local trigger = Instance.new("TextButton")
	trigger.Name = "Trigger"
	trigger.AutoButtonColor = false
	trigger.BackgroundColor3 = theme.Color.SurfaceMuted
	trigger.BorderSizePixel = 0
	trigger.Size = UDim2.fromScale(1, 1)
	trigger.Text = ""
	trigger.ZIndex = root.ZIndex
	trigger.Parent = root
	Util.corner(trigger, theme.Radius.Medium)
	local triggerStroke = Util.stroke(trigger, theme.Color.BorderStrong)
	Util.bindButtonColors(trigger, theme.Color.SurfaceMuted, theme.Color.SurfaceHover, theme.Color.Surface)
	makeText(trigger, props.Text or props.Label or "Actions", theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextPrimary, {
		Name = "Label",
		Position = UDim2.fromOffset(theme.Spacing.Medium, 0),
		Size = UDim2.new(1, -38, 1, 0),
	})
	local arrow = makeText(trigger, "›", theme.Font.Bold, theme.TextSize.Medium, theme.Color.TextSecondary, {
		Name = "Arrow",
		Position = UDim2.new(1, -29, 0, 0),
		Rotation = 90,
		Size = UDim2.fromOffset(20, theme.Control.Regular),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.BackgroundColor3 = theme.Color.SurfaceElevated
	menu.BorderSizePixel = 0
	menu.Position = UDim2.new(0, 0, 1, theme.Spacing.Small)
	menu.Size = UDim2.new(1, 0, 0, menuHeight)
	menu.Visible = false
	menu.ZIndex = 1000
	menu.Parent = root
	Util.corner(menu, theme.Radius.Medium)
	Util.stroke(menu, theme.Color.BorderStrong)
	Util.padding(menu, theme.Spacing.XSmall)
	Util.list(menu, Enum.FillDirection.Vertical, 0)

	local function updateMenuPosition()
		if not isOpen then
			return
		end
		overlayParent = findOverlayParent(root, props.OverlayParent) or overlayParent
		if overlayParent then
			if menu.Parent ~= overlayParent then
				menu.Parent = overlayParent
			end
			positionOverlayMenu(root, menu, overlayParent, menuHeight, theme.Spacing.Small)
		end
	end

	local function setOpen(value: boolean)
		isOpen = value
		if value then
			updateMenuPosition()
		end
		menu.Visible = value
		arrow.Rotation = if value then -90 else 90
		arrow.TextColor3 = if value then theme.Color.Accent else theme.Color.TextSecondary
		triggerStroke.Color = if value then theme.Color.Accent else theme.Color.BorderStrong
	end

	for index, item in items do
		local enabled = item.Enabled ~= false and item.Disabled ~= true
		local option = Instance.new("TextButton")
		option.Name = tostring(item.Id or "Item" .. tostring(index))
		option.AutoButtonColor = false
		option.BackgroundColor3 = theme.Color.SurfaceElevated
		option.BackgroundTransparency = 0
		option.BorderSizePixel = 0
		option.LayoutOrder = index
		option.Size = UDim2.new(1, 0, 0, 34)
		option.Text = tostring(item.Text or item.Label or item.Id)
		option.TextColor3 = if item.Danger then theme.Color.Error else theme.Color.TextSecondary
		option.TextSize = theme.TextSize.Small
		option.FontFace = theme.Font.Medium
		option.TextTransparency = if enabled then 0 else 0.5
		option.TextXAlignment = Enum.TextXAlignment.Left
		option.ZIndex = menu.ZIndex + 1
		option.Active = enabled
		option.Selectable = enabled
		option.Parent = menu
		Util.corner(option, theme.Radius.Small)
		Util.padding(option, theme.Spacing.Small, 0)
		Util.bindButtonColors(
			option,
			theme.Color.SurfaceElevated,
			theme.Color.SurfaceHover,
			theme.Color.SurfaceMuted,
			function()
				return enabled
			end
		)
		option.Activated:Connect(function()
			if not enabled then
				return
			end
			setOpen(false)
			local callback = item.OnSelected or item.OnActivated
			if callback then
				callback()
			end
		end)
	end

	trigger.Activated:Connect(function()
		setOpen(not isOpen)
	end)
	local positionConnection = RunService.RenderStepped:Connect(updateMenuPosition)
	root.Destroying:Connect(function()
		positionConnection:Disconnect()
		if menu.Parent and menu.Parent ~= root then
			menu:Destroy()
		end
	end)
	root.Parent = props.Parent
	return {
		Root = root,
		Trigger = trigger,
		Menu = menu,
		SetOpen = setOpen,
		GetOpen = function()
			return isOpen
		end,
	}
end

function Components.Divider(props: any): Frame
	local theme = getTheme(props)
	local divider = Instance.new("Frame")
	divider.Name = props.Name or "Divider"
	divider.BackgroundColor3 = props.Color or theme.Color.Border
	divider.BackgroundTransparency = props.Transparency or 0
	divider.BorderSizePixel = 0
	divider.LayoutOrder = props.LayoutOrder or 0
	divider.Size = props.Size or UDim2.new(1, 0, 0, 1)
	divider.Parent = props.Parent
	return divider
end

function Components.Spinner(props: any): Frame
	local theme = getTheme(props)
	local size = props.Size or 20
	local root = Instance.new("Frame")
	root.Name = props.Name or "Spinner"
	root.BackgroundTransparency = 1
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = UDim2.fromOffset(size, size)
	local ring = Util.stroke(root, props.Color or theme.Color.Accent, 0, props.Thickness or 2)
	Util.corner(root, theme.Radius.Pill)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = ring
	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 }
	)
	tween:Play()
	root.Destroying:Connect(function()
		tween:Cancel()
	end)
	root.Parent = props.Parent
	return root
end

function Components.Alert(props: any)
	local theme = getTheme(props)
	local tone = string.lower(props.Tone or props.Status or "info")
	if tone == "danger" then
		tone = "error"
	end
	local keys = STATUS_COLORS[tone] or STATUS_COLORS.info
	local foreground = theme.Color[keys[1]]
	local background = theme.Color[keys[2]]
	local symbols = {
		info = "i",
		success = "✓",
		warning = "!",
		error = "×",
	}

	local root = Instance.new("Frame")
	root.Name = props.Name or "Alert"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = background
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	Util.corner(root, theme.Radius.Medium)
	Util.stroke(root, foreground, 0.62)
	Util.padding(root, theme.Spacing.Medium)
	Util.list(root, Enum.FillDirection.Horizontal, theme.Spacing.Medium, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundColor3 = foreground
	icon.BackgroundTransparency = 0.84
	icon.BorderSizePixel = 0
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromOffset(30, 30)
	icon.Parent = root
	Util.corner(icon, theme.Radius.Medium)
	makeText(icon, props.Icon or symbols[tone] or "i", theme.Font.Bold, theme.TextSize.Body, foreground, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	local copy = Instance.new("Frame")
	copy.Name = "Copy"
	copy.AutomaticSize = Enum.AutomaticSize.Y
	copy.BackgroundTransparency = 1
	copy.LayoutOrder = 2
	copy.Size = UDim2.new(1, -42, 0, 0)
	copy.Parent = root
	Util.list(copy, Enum.FillDirection.Vertical, theme.Spacing.XSmall)
	makeText(copy, props.Title or "Notice", theme.Font.Semibold, theme.TextSize.Body, theme.Color.TextPrimary, {
		Name = "Title",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextWrapped = true,
		LayoutOrder = 1,
	})
	if props.Message or props.Description then
		makeText(copy, tostring(props.Message or props.Description), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextSecondary, {
			Name = "Message",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			LayoutOrder = 2,
		})
	end
	if props.ActionText then
		local action = Components.Button({
			Parent = copy,
			Text = props.ActionText,
			Style = "Ghost",
			Height = theme.Control.Compact,
			LayoutOrder = 3,
			OnActivated = props.OnAction,
			Theme = theme,
		})
		action.Root.LayoutOrder = 3
	end
	root.Parent = props.Parent
	return {
		Root = root,
		Icon = icon,
		Copy = copy,
	}
end

function Components.Progress(props: any)
	local theme = getTheme(props)
	local maximum = props.Max or 100
	local value = props.Value or 0
	local indeterminate = props.Indeterminate == true
	local activeTween: Tween? = nil

	local root = Instance.new("Frame")
	root.Name = props.Name or "Progress"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 40)

	makeText(root, props.Text or props.Label or "Progress", theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextSecondary, {
		Name = "Label",
		Size = UDim2.new(1, -64, 0, 18),
	})
	local valueLabel = makeText(root, "", theme.Font.Code, theme.TextSize.Small, theme.Color.Accent, {
		Name = "Value",
		Position = UDim2.new(1, -64, 0, 0),
		Size = UDim2.fromOffset(64, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = props.ShowValue ~= false,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = theme.Color.SurfaceMuted
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Position = UDim2.fromOffset(0, 28)
	track.Size = UDim2.new(1, 0, 0, 7)
	track.Parent = root
	Util.corner(track, theme.Radius.Pill)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = theme.Color.Accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	Util.corner(fill, theme.Radius.Pill)

	local function stopTween()
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
	end
	local function refresh()
		stopTween()
		if indeterminate then
			valueLabel.Visible = false
			fill.Position = UDim2.fromScale(-0.42, 0)
			fill.Size = UDim2.fromScale(0.42, 1)
			activeTween = TweenService:Create(
				fill,
				TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1),
				{ Position = UDim2.fromScale(1, 0) }
			)
			activeTween:Play()
		else
			local safeValue = math.clamp(value, 0, maximum)
			local progress = if maximum <= 0 then 0 else safeValue / maximum
			fill.Position = UDim2.fromScale(0, 0)
			fill.Size = UDim2.fromScale(progress, 1)
			valueLabel.Visible = props.ShowValue ~= false
			valueLabel.Text = string.format("%d%%", math.round(progress * 100))
		end
	end
	local function setValue(nextValue: number)
		value = nextValue
		indeterminate = false
		refresh()
	end
	local function setIndeterminate(nextValue: boolean)
		indeterminate = nextValue
		refresh()
	end
	root.Destroying:Connect(stopTween)
	refresh()
	root.Parent = props.Parent
	return {
		Root = root,
		Track = track,
		Fill = fill,
		SetValue = setValue,
		SetIndeterminate = setIndeterminate,
		GetValue = function()
			return value
		end,
	}
end

function Components.Skeleton(props: any): Frame
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "Skeleton"
	root.BackgroundColor3 = theme.Color.SurfaceMuted
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 18)
	Util.corner(root, props.Radius or theme.Radius.Small)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.Color.SurfaceMuted),
		ColorSequenceKeypoint.new(0.5, theme.Color.SurfaceHover),
		ColorSequenceKeypoint.new(1, theme.Color.SurfaceMuted),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = root
	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Offset = Vector2.new(1, 0) }
	)
	tween:Play()
	root.Destroying:Connect(function()
		tween:Cancel()
	end)
	root.Parent = props.Parent
	return root
end

function Components.EmptyState(props: any)
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "EmptyState"
	root.BackgroundColor3 = theme.Color.Surface
	root.BackgroundTransparency = 0.42
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 166)
	Util.corner(root, theme.Radius.Medium)
	Util.stroke(root, theme.Color.BorderStrong, 0.3)
	Util.padding(root, theme.Spacing.Large)
	Util.list(root, Enum.FillDirection.Vertical, theme.Spacing.Small, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	if props.Icon then
		makeText(root, tostring(props.Icon), theme.Font.Bold, theme.TextSize.Title, theme.Color.TextMuted, {
			Name = "Icon",
			Size = UDim2.new(1, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 1,
		})
	end
	if props.Title then
		makeText(root, tostring(props.Title), theme.Font.Semibold, theme.TextSize.Body, theme.Color.TextPrimary, {
			Name = "Title",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 2,
		})
	end
	if props.Description then
		makeText(root, tostring(props.Description), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextMuted, {
			Name = "Description",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 3,
		})
	end
	local action
	if props.ActionText then
		action = Components.Button({
			Parent = root,
			Text = props.ActionText,
			Style = props.ActionStyle or "Secondary",
			Height = theme.Control.Compact,
			OnActivated = props.OnAction,
			Theme = theme,
		})
		action.Root.LayoutOrder = 4
	end
	root.Parent = props.Parent
	return {
		Root = root,
		Action = action,
	}
end

function Components.ClassIcon(props: any): ImageLabel
	local theme = getTheme(props)
	local icon = Instance.new("ImageLabel")
	icon.Name = props.Name or "ClassIcon"
	icon.BackgroundTransparency = 1
	icon.ImageColor3 = props.Color or theme.Color.TextSecondary
	icon.LayoutOrder = props.LayoutOrder or 0
	icon.Size = props.Size or UDim2.fromOffset(20, 20)

	local ok, data = pcall(function()
		return StudioService:GetClassIcon(props.ClassName or "Folder")
	end)
	if ok and data then
		icon.Image = data.Image
		icon.ImageRectOffset = data.ImageRectOffset
		icon.ImageRectSize = data.ImageRectSize
	end
	icon.Parent = props.Parent
	return icon
end

function Components.EditableImage(props: any): EditableImage
	local image = Instance.new("EditableImage")
	image.Name = props.Name or "EditableImage"
	image.Size = props.Size
	if props.Pixels then
		image:WritePixelsBuffer(Vector2.zero, props.Size, props.Pixels)
	end
	image.Parent = props.Parent
	return image
end

function Components.SlicedImage(props: any): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = props.Name or "SlicedImage"
	image.AnchorPoint = props.AnchorPoint or Vector2.zero
	image.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None
	image.BackgroundTransparency = 1
	image.Image = props.Image or ""
	image.ImageColor3 = props.Color or Color3.new(1, 1, 1)
	image.ImageTransparency = props.Transparency or 0
	image.LayoutOrder = props.LayoutOrder or 0
	image.Position = props.Position or UDim2.fromOffset(0, 0)
	image.ScaleType = Enum.ScaleType.Slice
	image.Size = props.Size or UDim2.fromScale(1, 1)
	image.SliceCenter = props.SliceCenter or Rect.new(0, 0, 0, 0)
	image.SliceScale = props.SliceScale or 1
	image.Parent = props.Parent
	return image
end

function Components.Tooltip(target: GuiObject, text: string, themeOverride: any?)
	local theme = themeOverride or Theme.get()
	local overlayParent = findOverlayParent(target, nil) or target
	local bubble = Instance.new("Frame")
	bubble.Name = "Tooltip"
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.BackgroundColor3 = theme.Color.SurfaceMuted
	bubble.BorderSizePixel = 0
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.Size = UDim2.fromOffset(0, 0)
	bubble.Visible = false
	bubble.ZIndex = 100
	bubble.Parent = overlayParent
	Util.corner(bubble, theme.Radius.Small)
	Util.stroke(bubble, theme.Color.BorderStrong)
	Util.padding(bubble, theme.Spacing.Small, theme.Spacing.XSmall)
	makeText(bubble, text, theme.Font.Regular, theme.TextSize.Small, theme.Color.TextPrimary, {
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = false,
		ZIndex = 101,
	})

	local hoverToken = 0
	local positionConnection: RBXScriptConnection? = nil
	local function stopPositioning()
		if positionConnection then
			positionConnection:Disconnect()
			positionConnection = nil
		end
	end
	local function positionBubble()
		if bubble.Parent and target.Parent and overlayParent.Parent then
			positionOverlayTooltip(target, bubble, overlayParent, 8)
		end
	end
	local function hideBubble()
		stopPositioning()
		bubble.Visible = false
	end
	target.MouseEnter:Connect(function()
		hoverToken += 1
		local token = hoverToken
		task.delay(0.55, function()
			if hoverToken == token and bubble.Parent and target.Parent then
				bubble.Visible = true
				positionBubble()
				stopPositioning()
				positionConnection = RunService.RenderStepped:Connect(positionBubble)
				task.defer(positionBubble)
			end
		end)
	end)
	target.MouseLeave:Connect(function()
		hoverToken += 1
		hideBubble()
	end)
	target.Destroying:Connect(function()
		hoverToken += 1
		stopPositioning()
		bubble:Destroy()
	end)
	return bubble
end

function Components.ScrollView(props: any)
	local theme = getTheme(props)
	local root = Instance.new("ScrollingFrame")
	root.Name = props.Name or "ScrollView"
	root.AutomaticCanvasSize = Enum.AutomaticSize.None
	root.BackgroundColor3 = props.BackgroundColor or theme.Color.Canvas
	root.BackgroundTransparency = props.BackgroundTransparency or 1
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.fromOffset(0, 0)
	root.LayoutOrder = props.LayoutOrder or 0
	root.ScrollBarImageColor3 = theme.Color.BorderStrong
	root.ScrollBarThickness = props.ScrollBarThickness or 4
	root.ScrollingDirection = Enum.ScrollingDirection.Y
	root.Size = props.Size or UDim2.fromScale(1, 1)
	root.Parent = props.Parent
	local padding = Util.padding(root, props.Padding or theme.Spacing.Large)
	local layout = Util.list(root, Enum.FillDirection.Vertical, props.Gap or theme.Spacing.Medium)
	Util.autoCanvas(root, layout, (props.Padding or theme.Spacing.Large) * 2)
	return {
		Root = root,
		Layout = layout,
		Padding = padding,
	}
end

function Components.VirtualList(props: any)
	local theme = getTheme(props)
	local rowHeight = props.RowHeight or 30
	local count = props.Count or 0
	local root = Instance.new("ScrollingFrame")
	root.Name = props.Name or "VirtualList"
	root.BackgroundColor3 = props.BackgroundColor or theme.Color.Surface
	root.BorderSizePixel = 0
	root.CanvasSize = UDim2.fromOffset(0, count * rowHeight)
	root.ScrollBarImageColor3 = theme.Color.BorderStrong
	root.ScrollBarThickness = 4
	root.Size = props.Size or UDim2.new(1, 0, 0, 160)
	Util.corner(root, theme.Radius.Medium)
	Util.stroke(root, theme.Color.Border)

	local rendered: { [number]: GuiObject } = {}
	local function refresh()
		local first = math.max(1, math.floor(root.CanvasPosition.Y / rowHeight) + 1)
		local visible = math.ceil(root.AbsoluteSize.Y / rowHeight) + 2
		local last = math.min(count, first + visible)
		for index, row in rendered do
			if index < first or index > last then
				row:Destroy()
				rendered[index] = nil
			end
		end
		for index = first, last do
			if not rendered[index] then
				local row = props.Render(index)
				row.Name = "Row" .. tostring(index)
				row.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
				row.Size = UDim2.new(1, 0, 0, rowHeight)
				row.Parent = root
				rendered[index] = row
			end
		end
	end
	root:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	root.Parent = props.Parent
	task.defer(refresh)
	return {
		Root = root,
		Refresh = refresh,
	}
end

local DIFF_STYLES = {
	add = { "Success", "SuccessSurface", "+" },
	remove = { "Error", "ErrorSurface", "−" },
	edit = { "Info", "InfoSurface", "~" },
	warning = { "Warning", "WarningSurface", "!" },
	remain = { "TextMuted", "Surface", "·" },
}

function Components.DiffPanel(props: any): Frame
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "DiffPanel"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	Util.corner(root, theme.Radius.Medium)
	Util.stroke(root, theme.Color.Border)
	Util.padding(root, theme.Spacing.Small)
	Util.list(root, Enum.FillDirection.Vertical, 3)

	for index, rowData in props.Rows or {} do
		local keys = DIFF_STYLES[string.lower(rowData.Kind or "remain")] or DIFF_STYLES.remain
		local foreground = theme.Color[keys[1]]
		local background = theme.Color[keys[2]]
		local row = Instance.new("Frame")
		row.Name = "DiffRow" .. tostring(index)
		row.BackgroundColor3 = background
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 30)
		row.Parent = root
		Util.corner(row, theme.Radius.Small)
		makeText(row, keys[3], theme.Font.Bold, theme.TextSize.Body, foreground, {
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(18, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		makeText(row, rowData.Label or "Change", theme.Font.Code, theme.TextSize.Code, theme.Color.TextPrimary, {
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(1, -42, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	root.Parent = props.Parent
	return root
end

local function splitLines(value: string): { string }
	local lines = {}
	for line in string.gmatch(value .. "\n", "(.-)\n") do
		table.insert(lines, line)
	end
	return lines
end

function Components.StringDiff(props: any): Frame
	local before = splitLines(props.Before or "")
	local after = splitLines(props.After or "")
	local rows = {}
	local count = math.max(#before, #after)
	for index = 1, count do
		local oldLine = before[index]
		local newLine = after[index]
		if oldLine == newLine then
			table.insert(rows, { Kind = "remain", Label = string.format("%03d  %s", index, oldLine or "") })
		elseif oldLine == nil then
			table.insert(rows, { Kind = "add", Label = string.format("%03d  %s", index, newLine or "") })
		elseif newLine == nil then
			table.insert(rows, { Kind = "remove", Label = string.format("%03d  %s", index, oldLine) })
		else
			table.insert(rows, {
				Kind = "edit",
				Label = string.format("%03d  %s  →  %s", index, oldLine, newLine),
			})
		end
	end
	local nextProps = table.clone(props)
	nextProps.Rows = rows
	return Components.DiffPanel(nextProps)
end

function Components.TableDiff(props: any): Frame
	local before = props.Before or {}
	local after = props.After or {}
	local keys = {}
	local seen = {}
	for key in before do
		seen[key] = true
		table.insert(keys, key)
	end
	for key in after do
		if not seen[key] then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a: any, b: any)
		return tostring(a) < tostring(b)
	end)

	local rows = {}
	for _, key in keys do
		local oldValue = before[key]
		local newValue = after[key]
		local kind = "remain"
		if oldValue == nil then
			kind = "add"
		elseif newValue == nil then
			kind = "remove"
		elseif oldValue ~= newValue then
			kind = "edit"
		end
		table.insert(rows, {
			Kind = kind,
			Label = string.format("%s: %s  →  %s", tostring(key), tostring(oldValue), tostring(newValue)),
		})
	end
	local nextProps = table.clone(props)
	nextProps.Rows = rows
	return Components.DiffPanel(nextProps)
end

function Components.Tabs(props: any)
	local theme = getTheme(props)
	local tabs = props.Tabs or {}
	local selected = props.Value or props.DefaultValue
	local buttons = {}

	if selected == nil then
		for _, tab in tabs do
			if tab.Enabled ~= false and tab.Disabled ~= true then
				selected = tab.Id or tab.Value
				break
			end
		end
	end

	local root = Instance.new("Frame")
	root.Name = props.Name or "Tabs"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	Util.list(root, Enum.FillDirection.Vertical, theme.Spacing.Medium)

	local tabList = Instance.new("Frame")
	tabList.Name = "TabList"
	tabList.BackgroundColor3 = theme.Color.Surface
	tabList.BorderSizePixel = 0
	tabList.LayoutOrder = 1
	tabList.Size = UDim2.new(1, 0, 0, 42)
	tabList.Parent = root
	Util.corner(tabList, theme.Radius.Medium)
	Util.stroke(tabList, theme.Color.Border)
	Util.padding(tabList, theme.Spacing.XSmall)
	local tabLayout = Util.list(tabList, Enum.FillDirection.Horizontal, theme.Spacing.XSmall)
	tabLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.LayoutOrder = 2
	content.Size = UDim2.new(1, 0, 0, 0)
	content.Parent = root

	local function renderContent()
		Util.clear(content)
		for _, tab in tabs do
			local tabValue = tab.Id or tab.Value
			if tabValue == selected then
				if tab.Render then
					tab.Render(content)
				elseif tab.Content ~= nil then
					makeText(content, tostring(tab.Content), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextSecondary, {
						AutomaticSize = Enum.AutomaticSize.Y,
						Size = UDim2.new(1, 0, 0, 0),
						TextWrapped = true,
					})
				end
				break
			end
		end
	end

	local setValue
	local function refresh()
		for tabValue, references in buttons do
			local isSelected = tabValue == selected
			references.Root.BackgroundColor3 = if isSelected then theme.Color.Accent else theme.Color.Surface
			references.Label.TextColor3 = if isSelected then theme.Color.OnAccent else theme.Color.TextMuted
		end
		renderContent()
	end

	for index, tab in tabs do
		local tabValue = tab.Id or tab.Value
		local enabled = tab.Enabled ~= false and tab.Disabled ~= true
		local button = Instance.new("TextButton")
		button.Name = "Tab" .. tostring(index)
		button.AutoButtonColor = false
		button.BackgroundColor3 = theme.Color.Surface
		button.BorderSizePixel = 0
		button.LayoutOrder = index
		button.Size = UDim2.fromOffset(0, 34)
		button.Text = ""
		button.Active = enabled
		button.Selectable = enabled
		button.BackgroundTransparency = if enabled then 0 else 0.45
		button.Parent = tabList
		Util.corner(button, theme.Radius.Small)
		local buttonLabel = makeText(button, tostring(tab.Text or tab.Label or tabValue), theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextMuted, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if enabled then 0 else 0.5,
		})
		buttons[tabValue] = { Root = button, Label = buttonLabel }
		button.Activated:Connect(function()
			if enabled then
				setValue(tabValue)
			end
		end)
	end

	function setValue(nextValue: any, silent: boolean?)
		if buttons[nextValue] == nil then
			return
		end
		selected = nextValue
		refresh()
		if not silent then
			local callback = props.OnChanged or props.OnValueChanged
			if callback then
				callback(selected)
			end
		end
	end

	refresh()
	root.Parent = props.Parent
	return {
		Root = root,
		TabList = tabList,
		Content = content,
		SetValue = setValue,
		GetValue = function()
			return selected
		end,
	}
end

function Components.Accordion(props: any)
	local theme = getTheme(props)
	local items = props.Items or {}
	local allowMultiple = props.AllowMultiple == true
	local openIds = {}
	local references = {}

	for _, id in props.DefaultOpenIds or {} do
		openIds[id] = true
	end

	local root = Instance.new("Frame")
	root.Name = props.Name or "Accordion"
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 0)
	Util.list(root, Enum.FillDirection.Vertical, 0)

	local function refresh()
		for id, itemReferences in references do
			local isOpen = openIds[id] == true
			itemReferences.Content.Visible = isOpen
			itemReferences.Arrow.Rotation = if isOpen then -90 else 90
			itemReferences.Arrow.TextColor3 = if isOpen then theme.Color.Accent else theme.Color.TextMuted
		end
	end

	local function setOpen(id: any, isOpen: boolean, silent: boolean?)
		if references[id] == nil then
			return
		end
		if isOpen and not allowMultiple then
			table.clear(openIds)
		end
		openIds[id] = if isOpen then true else nil
		refresh()
		if not silent and props.OnChanged then
			props.OnChanged(id, isOpen)
		end
	end

	for index, item in items do
		local id = item.Id or item.Value or tostring(index)
		local enabled = item.Enabled ~= false and item.Disabled ~= true
		if item.Open == true then
			openIds[id] = true
		end
		local section = Instance.new("Frame")
		section.Name = "Item" .. tostring(index)
		section.AutomaticSize = Enum.AutomaticSize.Y
		section.BackgroundTransparency = 1
		section.BorderSizePixel = 0
		section.LayoutOrder = index
		section.Size = UDim2.new(1, 0, 0, 0)
		section.Parent = root
		Util.list(section, Enum.FillDirection.Vertical, 0)

		local trigger = Instance.new("TextButton")
		trigger.Name = "Trigger"
		trigger.AutoButtonColor = false
		trigger.BackgroundTransparency = 1
		trigger.BorderSizePixel = 0
		trigger.LayoutOrder = 1
		trigger.Size = UDim2.new(1, 0, 0, 46)
		trigger.Text = ""
		trigger.Active = enabled
		trigger.Selectable = enabled
		trigger.Parent = section
		local title = makeText(trigger, tostring(item.Text or item.Title or id), theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextPrimary, {
			Position = UDim2.fromOffset(theme.Spacing.XSmall, 0),
			Size = UDim2.new(1, -38, 1, 0),
			TextTransparency = if enabled then 0 else 0.5,
		})
		local arrow = makeText(trigger, "›", theme.Font.Bold, theme.TextSize.Medium, theme.Color.TextMuted, {
			Position = UDim2.new(1, -28, 0, 0),
			Rotation = 90,
			Size = UDim2.fromOffset(20, 46),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if enabled then 0 else 0.5,
		})
		local divider = Instance.new("Frame")
		divider.Name = "Divider"
		divider.AnchorPoint = Vector2.new(0, 1)
		divider.BackgroundColor3 = theme.Color.Border
		divider.BorderSizePixel = 0
		divider.Position = UDim2.fromScale(0, 1)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.Parent = trigger

		local itemContent = Instance.new("Frame")
		itemContent.Name = "Content"
		itemContent.AutomaticSize = Enum.AutomaticSize.Y
		itemContent.BackgroundTransparency = 1
		itemContent.LayoutOrder = 2
		itemContent.Size = UDim2.new(1, 0, 0, 0)
		itemContent.Parent = section
		Util.padding(itemContent, theme.Spacing.XSmall, theme.Spacing.Medium)
		if item.Render then
			item.Render(itemContent)
		elseif item.Content ~= nil then
			makeText(itemContent, tostring(item.Content), theme.Font.Regular, theme.TextSize.Small, theme.Color.TextSecondary, {
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -theme.Spacing.Small * 2, 0, 0),
				TextWrapped = true,
			})
		end

		references[id] = {
			Section = section,
			Trigger = trigger,
			Title = title,
			Arrow = arrow,
			Content = itemContent,
		}
		trigger.Activated:Connect(function()
			if enabled then
				setOpen(id, openIds[id] ~= true)
			end
		end)
	end

	refresh()
	root.Parent = props.Parent
	return {
		Root = root,
		SetOpen = setOpen,
		IsOpen = function(id: any)
			return openIds[id] == true
		end,
	}
end

function Components.Modal(props: any)
	local theme = getTheme(props)
	local overlay = Instance.new("TextButton")
	overlay.Name = props.Name or "Modal"
	overlay.AutoButtonColor = false
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.28
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Text = ""
	overlay.ZIndex = 300
	overlay.Parent = props.Parent

	local surface = Components.Surface({
		Parent = overlay,
		Title = props.Title or "Notice",
		Subtitle = props.Message,
		Size = props.Size or UDim2.new(1, -48, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Theme = theme,
	})
	surface.Root.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Root.Position = UDim2.fromScale(0.5, 0.5)
	surface.Root.ZIndex = 301
	for _, descendant in surface.Root:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(descendant.ZIndex, 302)
		end
	end

	local closeButton = Components.Button({
		Parent = surface.Content,
		Text = props.ActionText or "Okay",
		Style = props.ActionStyle or "Primary",
		ZIndex = 303,
		OnActivated = function()
			overlay:Destroy()
			if props.OnClose then
				props.OnClose()
			end
		end,
		Theme = theme,
	})
	overlay.Activated:Connect(function()
		if props.DismissOnBackdrop then
			overlay:Destroy()
		end
	end)

	return {
		Root = overlay,
		Surface = surface.Root,
		Close = function()
			overlay:Destroy()
		end,
	}
end

function Components.ToastHost(props: any)
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "ToastHost"
	root.AnchorPoint = Vector2.new(1, 0)
	root.BackgroundTransparency = 1
	root.Position = UDim2.new(1, -theme.Spacing.Medium, 0, theme.Spacing.Medium)
	root.Size = UDim2.new(0, math.min(props.Width or 300, 300), 1, -theme.Spacing.XLarge)
	root.ZIndex = 200
	root.Parent = props.Parent
	Util.list(root, Enum.FillDirection.Vertical, theme.Spacing.Small, Enum.HorizontalAlignment.Right)

	local nextOrder = 0
	local function push(message: string, status: string?, duration: number?)
		nextOrder += 1
		local keys = STATUS_COLORS[string.lower(status or "info")] or STATUS_COLORS.info
		local foreground = theme.Color[keys[1]]
		local background = theme.Color[keys[2]]
		local toast = Instance.new("Frame")
		toast.Name = "Toast"
		toast.AutomaticSize = Enum.AutomaticSize.Y
		toast.BackgroundColor3 = background
		toast.BorderSizePixel = 0
		toast.LayoutOrder = nextOrder
		toast.Size = UDim2.new(1, 0, 0, 0)
		toast.ZIndex = 201
		toast.Parent = root
		Util.corner(toast, theme.Radius.Medium)
		Util.stroke(toast, foreground, 0.6)
		Util.padding(toast, theme.Spacing.Medium)
		makeText(toast, message, theme.Font.Medium, theme.TextSize.Small, theme.Color.TextPrimary, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			TextWrapped = true,
			ZIndex = 202,
		})
		toast.BackgroundTransparency = 1
		Util.tween(toast, { BackgroundTransparency = 0 }, 0.16)
		task.delay(duration or 3.5, function()
			if toast.Parent then
				local tween = Util.tween(toast, { BackgroundTransparency = 1 }, 0.18)
				tween.Completed:Wait()
				toast:Destroy()
			end
		end)
		return toast
	end

	return {
		Root = root,
		Push = push,
	}
end

function Components.Header(props: any): Frame
	local theme = getTheme(props)
	local root = Instance.new("Frame")
	root.Name = props.Name or "Header"
	root.BackgroundColor3 = theme.Color.Surface
	root.BorderSizePixel = 0
	root.Size = props.Size or UDim2.new(1, 0, 0, 58)

	local titleOffset = 36
	if props.Icon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "BrandIcon"
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = props.Icon
		icon.Position = UDim2.new(0, theme.Spacing.Medium, 0.5, 0)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Size = UDim2.fromOffset(34, 34)
		icon.Parent = root
		titleOffset = 54
	else
		local mark = Instance.new("Frame")
		mark.Name = "BrandMark"
		mark.AnchorPoint = Vector2.new(0, 0.5)
		mark.BackgroundColor3 = theme.Color.Accent
		mark.BorderSizePixel = 0
		mark.Position = UDim2.new(0, theme.Spacing.Large, 0.5, 0)
		mark.Size = UDim2.fromOffset(8, 28)
		mark.Parent = root
		Util.corner(mark, theme.Radius.Pill)
	end

	makeText(root, props.Title or "SANDBLOCK", theme.Font.Bold, theme.TextSize.Medium, theme.Color.TextPrimary, {
		Name = "Title",
		Position = UDim2.fromOffset(titleOffset, 7),
		Size = UDim2.new(1, -titleOffset - 12, 0, 24),
	})
	makeText(root, props.Subtitle or "STUDIO", theme.Font.Medium, theme.TextSize.Caption, theme.Color.TextMuted, {
		Name = "Subtitle",
		Position = UDim2.fromOffset(titleOffset, 29),
		Size = UDim2.new(1, -titleOffset - 12, 0, 18),
	})
	local divider = Instance.new("Frame")
	divider.AnchorPoint = Vector2.new(0, 1)
	divider.BackgroundColor3 = theme.Color.Border
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromScale(0, 1)
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.Parent = root
	root.Parent = props.Parent
	return root
end

function Components.TabButton(props: any)
	local theme = getTheme(props)
	local selected = props.Selected == true
	local root = Instance.new("TextButton")
	root.Name = props.Name or "TabButton"
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = UDim2.fromOffset(0, 38)
	root.Text = ""
	root.AutoButtonColor = false
	Util.padding(root, theme.Spacing.Medium, 0)
	local label = makeText(root, props.Text or "Tab", theme.Font.Semibold, theme.TextSize.Small, theme.Color.TextSecondary, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local indicator = Instance.new("Frame")
	indicator.AnchorPoint = Vector2.new(0, 1)
	indicator.BackgroundColor3 = theme.Color.Accent
	indicator.BorderSizePixel = 0
	indicator.Position = UDim2.fromScale(0, 1)
	indicator.Size = UDim2.new(1, 0, 0, 2)
	indicator.Parent = root

	local function setSelected(value: boolean)
		selected = value
		label.TextColor3 = if selected then theme.Color.TextPrimary else theme.Color.TextSecondary
		indicator.Visible = selected
	end
	root.Activated:Connect(function()
		if props.OnActivated then
			props.OnActivated()
		end
	end)
	setSelected(selected)
	root.Parent = props.Parent
	return {
		Root = root,
		SetSelected = setSelected,
	}
end

Components.ButtonStyles = BUTTON_STYLES
Components.BorderedContainer = Components.Surface
Components.Dialog = Components.Modal
Components.Select = Components.Dropdown
Components.TextButton = Components.Button
Components.TextField = Components.TextInput
Components.Toggle = Components.Switch
Components.ScrollingFrame = Components.ScrollView
Components.PatchVisualizer = Components.DiffPanel

return Components
