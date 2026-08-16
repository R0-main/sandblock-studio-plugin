--!strict

-- Native GuiObject component library used by the Sandblock Studio plugin.
-- Every component can be parented to a DockWidgetPluginGui, ScreenGui, or
-- another GuiObject; no Roact runtime or web/CSS dependency is required.

local StudioService = game:GetService("StudioService")
local TweenService = game:GetService("TweenService")

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

	local root = Instance.new("TextButton")
	root.Name = props.Name or "Button"
	root.AutomaticSize = if props.Size then Enum.AutomaticSize.None else Enum.AutomaticSize.X
	root.BackgroundColor3 = normal
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.LayoutOrder = props.LayoutOrder or 0
	root.Size = props.Size or UDim2.fromOffset(0, props.Height or theme.Control.Regular)
	root.Text = ""
	root.ZIndex = props.ZIndex or 1
	root.Active = enabled
	root.Selectable = enabled
	Util.corner(root, props.Radius or theme.Radius.Medium)
	Util.padding(root, props.HorizontalPadding or theme.Spacing.Medium, 0)
	if borderColor then
		Util.stroke(root, borderColor, 0)
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
	refreshEnabled()
	root.Parent = props.Parent

	return {
		Root = root,
		Label = label,
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

function Components.Dropdown(props: any)
	local theme = getTheme(props)
	local options = props.Options or {}
	local selected = props.Selected or options[1] or ""
	local isOpen = false

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
	menu.Size = UDim2.new(1, 0, 0, #options * 30 + theme.Spacing.Small)
	menu.Visible = false
	menu.ZIndex = 50
	menu.Parent = root
	Util.corner(menu, theme.Radius.Medium)
	Util.stroke(menu, theme.Color.BorderStrong)
	Util.padding(menu, theme.Spacing.XSmall)
	Util.list(menu, Enum.FillDirection.Vertical, 0)

	local function setOpen(value: boolean)
		isOpen = value
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
		item.ZIndex = 51
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
	local bubble = Instance.new("Frame")
	bubble.Name = "Tooltip"
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.BackgroundColor3 = theme.Color.SurfaceMuted
	bubble.BorderSizePixel = 0
	bubble.Position = UDim2.new(0.5, 0, 1, 8)
	bubble.AnchorPoint = Vector2.new(0.5, 0)
	bubble.Visible = false
	bubble.ZIndex = 100
	bubble.Parent = target
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
	target.MouseEnter:Connect(function()
		hoverToken += 1
		local token = hoverToken
		task.delay(0.55, function()
			if hoverToken == token and bubble.Parent then
				bubble.Visible = true
			end
		end)
	end)
	target.MouseLeave:Connect(function()
		hoverToken += 1
		bubble.Visible = false
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
Components.TextButton = Components.Button
Components.ScrollingFrame = Components.ScrollView
Components.PatchVisualizer = Components.DiffPanel

return Components
