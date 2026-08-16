--!strict

-- Interactive component gallery. This is intentionally shipped inside the
-- Studio dock so the native Luau library can be inspected at real plugin
-- widths without relying on a web mockup.

local Components = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local Gallery = {}

local function horizontalRow(parent: Instance, gap: number, height: number?): Frame
	local row = Instance.new("Frame")
	row.AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, height or 0)
	row.Parent = parent
	Util.list(row, Enum.FillDirection.Horizontal, gap, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	return row
end

local function sampleRow(theme: any, index: number): GuiObject
	local row = Instance.new("Frame")
	row.BackgroundColor3 = if index % 2 == 0 then theme.Color.Surface else theme.Color.SurfaceElevated
	row.BackgroundTransparency = if index % 2 == 0 then 0.15 else 0
	row.BorderSizePixel = 0

	Components.ClassIcon({
		Parent = row,
		ClassName = if index % 3 == 0 then "ModuleScript" else if index % 2 == 0 then "Folder" else "Part",
		Color = theme.Color.TextSecondary,
		Size = UDim2.fromOffset(18, 18),
	}).Position = UDim2.new(0, 9, 0.5, -9)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = theme.Font.Regular
	label.Position = UDim2.fromOffset(36, 0)
	label.Size = UDim2.new(1, -44, 1, 0)
	label.Text = string.format("Workspace.Component_%02d", index)
	label.TextColor3 = theme.Color.TextSecondary
	label.TextSize = theme.TextSize.Small
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row
	return row
end

function Gallery.mount(parent: Instance, toastHost: any)
	local theme = Theme.get()
	local scroll = Components.ScrollView({
		Parent = parent,
		Name = "ComponentLibrary",
		Padding = theme.Spacing.Large,
		Gap = theme.Spacing.Medium,
		Theme = theme,
	})

	local intro = Components.Surface({
		Parent = scroll.Root,
		Title = "Native component library",
		Subtitle = "Sandblock primitives inspired by the complete Rojo Studio UI vocabulary, rebuilt for the Sandblock design system.",
		LayoutOrder = 1,
		Theme = theme,
	})
	Components.Tag({
		Parent = intro.Content,
		Text = "GuiObject · no Roact runtime",
		Color = theme.Color.Accent,
		Theme = theme,
	})

	local buttons = Components.Surface({
		Parent = scroll.Root,
		Title = "Buttons & actions",
		Subtitle = "Primary, bordered, quiet and destructive actions include hover, press, disabled and touch feedback.",
		LayoutOrder = 2,
		Theme = theme,
	})
	local buttonRow = horizontalRow(buttons.Content, theme.Spacing.Small)
	Components.Button({
		Parent = buttonRow,
		Text = "Primary",
		OnActivated = function()
			toastHost.Push("Primary action triggered", "success")
		end,
		Theme = theme,
	})
	Components.Button({
		Parent = buttonRow,
		Text = "Secondary",
		Style = "Secondary",
		OnActivated = function()
			toastHost.Push("Secondary action triggered", "info")
		end,
		Theme = theme,
	})
	local buttonRowTwo = horizontalRow(buttons.Content, theme.Spacing.Small)
	Components.Button({
		Parent = buttonRowTwo,
		Text = "Quiet",
		Style = "Ghost",
		Theme = theme,
	})
	Components.Button({
		Parent = buttonRowTwo,
		Text = "Remove",
		Style = "Danger",
		OnActivated = function()
			toastHost.Push("Destructive actions require confirmation in product flows", "warning")
		end,
		Theme = theme,
	})
	Components.IconButton({
		Parent = buttonRowTwo,
		Icon = "•••",
		Tooltip = "More actions",
		Theme = theme,
	})

	local controls = Components.Surface({
		Parent = scroll.Root,
		Title = "Forms & selection",
		Subtitle = "Inputs expose focus feedback and clear disabled/selected states.",
		LayoutOrder = 3,
		Theme = theme,
	})
	Components.TextInput({
		Parent = controls.Content,
		Placeholder = "Approved runtime name",
		OnSubmitted = function(value: string)
			toastHost.Push("Submitted: " .. value, "info")
		end,
		Theme = theme,
	})
	Components.Dropdown({
		Parent = controls.Content,
		Options = { "Main place", "Local test place", "Published place" },
		Selected = "Main place",
		OnChanged = function(value: string)
			toastHost.Push("Selected " .. value, "success")
		end,
		Theme = theme,
	})
	Components.Checkbox({
		Parent = controls.Content,
		Text = "Validate PlaceId before Studio mutations",
		Checked = true,
		Theme = theme,
	})
	Components.Checkbox({
		Parent = controls.Content,
		Text = "Unavailable option",
		Enabled = false,
		Theme = theme,
	})

	local status = Components.Surface({
		Parent = scroll.Root,
		Title = "Status, tags & icons",
		Subtitle = "Health never relies on color alone: every state keeps a text label.",
		LayoutOrder = 4,
		Theme = theme,
	})
	local statusRow = horizontalRow(status.Content, theme.Spacing.Small)
	Components.StatusBadge({ Parent = statusRow, Status = "connected", Text = "Connected", Theme = theme })
	Components.StatusBadge({ Parent = statusRow, Status = "warning", Text = "Mismatch", Theme = theme })
	local statusRowTwo = horizontalRow(status.Content, theme.Spacing.Small, 28)
	Components.StatusBadge({ Parent = statusRowTwo, Status = "error", Text = "Failed", Theme = theme })
	Components.StatusBadge({ Parent = statusRowTwo, Status = "neutral", Text = "Idle", Theme = theme })
	Components.Spinner({ Parent = statusRowTwo, Size = 18, Theme = theme })
	Components.Tag({ Parent = statusRowTwo, Text = "v0", Color = theme.Color.Accent, Theme = theme })
	Components.ClassIcon({ Parent = statusRowTwo, ClassName = "ModuleScript", Color = theme.Color.TextSecondary, Theme = theme })

	local feedback = Components.Surface({
		Parent = scroll.Root,
		Title = "Notifications & sync diffs",
		Subtitle = "Compact feedback and Rojo-style change inspection use the same semantic status palette.",
		LayoutOrder = 5,
		Theme = theme,
	})
	Components.DiffPanel({
		Parent = feedback.Content,
		Rows = {
			{ Kind = "add", Label = "+ ReplicatedStorage.Shared.Runtime" },
			{ Kind = "edit", Label = "~ StarterGui.Hud.Enabled: false → true" },
			{ Kind = "remove", Label = "− Workspace.LegacyBridge" },
		},
		Theme = theme,
	})
	Components.Button({
		Parent = feedback.Content,
		Text = "Show notification",
		Style = "Secondary",
		OnActivated = function()
			toastHost.Push("The component library is mounted inside Roblox Studio.", "success")
		end,
		Theme = theme,
	})

	local virtualization = Components.Surface({
		Parent = scroll.Root,
		Title = "Scrolling & virtual lists",
		Subtitle = "Large instance lists render only the visible rows, matching Rojo's virtual-scroller capability.",
		LayoutOrder = 6,
		Theme = theme,
	})
	Components.VirtualList({
		Parent = virtualization.Content,
		Count = 120,
		RowHeight = 30,
		Size = UDim2.new(1, 0, 0, 128),
		Render = function(index: number)
			return sampleRow(theme, index)
		end,
		Theme = theme,
	})

	return scroll.Root
end

return Gallery
