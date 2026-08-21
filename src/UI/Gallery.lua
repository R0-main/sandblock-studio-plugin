--!strict

-- Interactive component gallery. This is intentionally shipped inside the
-- Studio dock so the native Luau library can be inspected at real plugin
-- widths without relying on a web mockup.

local Components = require(script.Parent.Components)
local Assets = require(script.Parent.Assets)
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

local function imageTile(parent: Instance, imageId: string, name: string, background: Color3, size: number): Frame
	local tile = Instance.new("Frame")
	tile.Active = true
	tile.BackgroundColor3 = background
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(size, size)
	tile.Parent = parent
	Util.corner(tile, 10)

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = imageId
	image.Position = UDim2.fromOffset(6, 6)
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.new(1, -12, 1, -12)
	image.Parent = tile
	Components.Tooltip(tile, name)
	return tile
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
		Appearance = "Tactile",
		OnActivated = function()
			toastHost.Push("Primary action triggered", "success")
		end,
		Theme = theme,
	})
	Components.Button({
		Parent = buttonRow,
		Text = "Secondary",
		Style = "Secondary",
		Appearance = "Tactile",
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
		Title = "Text fields & selection",
		Subtitle = "Search, text, textarea and select controls expose focus feedback and explicit states.",
		LayoutOrder = 3,
		Theme = theme,
	})
	Components.SearchField({
		Parent = controls.Content,
		Placeholder = "Search components",
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
	Components.TextArea({
		Parent = controls.Content,
		Placeholder = "Describe a generated asset or Studio action…",
		Size = UDim2.new(1, 0, 0, 76),
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

	local advancedControls = Components.Surface({
		Parent = scroll.Root,
		Title = "Switches, sliders & radio groups",
		Subtitle = "Native Studio equivalents keep the same state language as Sandblock UI.",
		LayoutOrder = 4,
		Theme = theme,
	})
	Components.Switch({
		Parent = advancedControls.Content,
		Text = "Live Studio sync",
		Description = "Apply source changes through the active Rojo session.",
		Checked = true,
		OnChanged = function(value: boolean)
			toastHost.Push(if value then "Live sync enabled" else "Live sync disabled", if value then "success" else "warning")
		end,
		Theme = theme,
	})
	Components.Switch({
		Parent = advancedControls.Content,
		Text = "Unavailable toggle",
		Checked = false,
		Enabled = false,
		Theme = theme,
	})
	local detailProgress = Components.Progress({
		Parent = advancedControls.Content,
		Text = "Preview detail",
		Value = 68,
		Theme = theme,
	})
	Components.Slider({
		Parent = advancedControls.Content,
		Text = "Detail level",
		Value = 68,
		Step = 1,
		FormatValue = function(value: number)
			return string.format("%d%%", value)
		end,
		OnChanged = function(value: number)
			detailProgress.SetValue(value)
		end,
		Theme = theme,
	})
	Components.RadioGroup({
		Parent = advancedControls.Content,
		Text = "Runtime target",
		DefaultValue = "main",
		Options = {
			{ Value = "main", Label = "Main place", Description = "Configured production place" },
			{ Value = "local", Label = "Local test", Description = "Temporary development session" },
			{ Value = "published", Label = "Published place", Disabled = true },
		},
		OnChanged = function(value: string)
			toastHost.Push("Runtime target: " .. value, "info")
		end,
		Theme = theme,
	})

	local navigation = Components.Surface({
		Parent = scroll.Root,
		Title = "Choices & navigation",
		Subtitle = "Full-surface choices, segmented tabs, disclosure and action menus mirror the web primitives.",
		LayoutOrder = 5,
		Theme = theme,
	})
	local assetChoice
	local codeChoice
	assetChoice = Components.ChoiceButton({
		Parent = navigation.Content,
		Text = "Asset production",
		Description = "Generate and inspect project-local images.",
		Icon = "◇",
		Selected = true,
		OnActivated = function()
			assetChoice.SetSelected(true)
			codeChoice.SetSelected(false)
		end,
		Theme = theme,
	})
	codeChoice = Components.ChoiceButton({
		Parent = navigation.Content,
		Text = "Studio automation",
		Description = "Run project-bound Studio tools.",
		Icon = "⌘",
		OnActivated = function()
			assetChoice.SetSelected(false)
			codeChoice.SetSelected(true)
		end,
		Theme = theme,
	})
	Components.Tabs({
		Parent = navigation.Content,
		DefaultValue = "overview",
		Tabs = {
			{ Id = "overview", Label = "Overview", Content = "Runtime and project state stay visible at a glance." },
			{ Id = "activity", Label = "Activity", Content = "Recent sync and bridge events appear here." },
			{ Id = "logs", Label = "Logs", Content = "Detailed diagnostics remain secondary." },
		},
		Theme = theme,
	})
	Components.Accordion({
		Parent = navigation.Content,
		DefaultOpenIds = { "binding" },
		Items = {
			{ Id = "binding", Title = "Project binding", Content = "The selected runtime must match the current Studio PlaceId." },
			{ Id = "diagnostics", Title = "Advanced diagnostics", Content = "Connection timing and payload validation live behind disclosure." },
		},
		Theme = theme,
	})
	Components.DropdownMenu({
		Parent = navigation.Content,
		Text = "More actions",
		Items = {
			{ Id = "refresh", Label = "Refresh runtime", OnSelected = function() toastHost.Push("Runtime refreshed", "success") end },
			{ Id = "copy", Label = "Copy diagnostics", OnSelected = function() toastHost.Push("Diagnostics copied", "info") end },
			{ Id = "disconnect", Label = "Disconnect", Danger = true, OnSelected = function() toastHost.Push("Disconnect requested", "warning") end },
		},
		Theme = theme,
	})

	local status = Components.Surface({
		Parent = scroll.Root,
		Title = "Status, tags & icons",
		Subtitle = "Health never relies on color alone: every state keeps a text label.",
		LayoutOrder = 6,
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
		Title = "Feedback, loading & empty states",
		Subtitle = "Alerts, progress, skeletons and empty states use the same semantic status palette.",
		LayoutOrder = 7,
		Theme = theme,
	})
	Components.Alert({
		Parent = feedback.Content,
		Tone = "success",
		Title = "Studio is ready",
		Message = "The project runtime and current PlaceId have been validated.",
		Theme = theme,
	})
	Components.Alert({
		Parent = feedback.Content,
		Tone = "warning",
		Title = "Review required",
		Message = "Two-way sync can write Studio changes back to disk.",
		ActionText = "Review",
		OnAction = function()
			toastHost.Push("Review action opened", "info")
		end,
		Theme = theme,
	})
	Components.Progress({
		Parent = feedback.Content,
		Text = "Syncing project",
		Indeterminate = true,
		Theme = theme,
	})
	Components.Skeleton({ Parent = feedback.Content, Size = UDim2.new(1, 0, 0, 18), Theme = theme })
	Components.Skeleton({ Parent = feedback.Content, Size = UDim2.new(0.68, 0, 0, 14), Theme = theme })
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
	Components.EmptyState({
		Parent = feedback.Content,
		Icon = "□",
		Title = "No generated captures",
		Description = "Workspace captures and rendered GUI previews will appear here.",
		ActionText = "Capture selection",
		OnAction = function()
			toastHost.Push("Capture action triggered", "info")
		end,
		Theme = theme,
	})

	local virtualization = Components.Surface({
		Parent = scroll.Root,
		Title = "Scrolling & virtual lists",
		Subtitle = "Large instance lists render only the visible rows, matching Rojo's virtual-scroller capability.",
		LayoutOrder = 8,
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

	local media = Components.Surface({
		Parent = scroll.Root,
		Title = "Illustrations & brand",
		Subtitle = "Roblox-hosted Sandblock marks, wordmarks and illustration assets are exposed through stable names.",
		LayoutOrder = 9,
		Theme = theme,
	})
	local marks = horizontalRow(media.Content, theme.Spacing.Small, 60)
	imageTile(marks, Assets.Brand.Mark.Black, "Brand.Mark.Black", theme.Color.Accent, 56)
	imageTile(marks, Assets.Brand.Mark.White, "Brand.Mark.White", theme.Color.SurfaceMuted, 56)
	imageTile(marks, Assets.Brand.Mark.Yellow, "Brand.Mark.Yellow", theme.Color.SurfaceMuted, 56)

	local wordmark = Instance.new("ImageLabel")
	wordmark.BackgroundColor3 = theme.Color.SurfaceMuted
	wordmark.BorderSizePixel = 0
	wordmark.Image = Assets.Brand.WordmarkCompact.Yellow
	wordmark.ScaleType = Enum.ScaleType.Fit
	wordmark.Size = UDim2.new(1, 0, 0, 58)
	wordmark.Parent = media.Content
	Util.corner(wordmark, theme.Radius.Medium)

	local audience = Assets.Illustrations.Audience
	local audienceRows = {
		{
			{ "Audience.Artist", audience.Artist },
			{ "Audience.Association", audience.Association },
			{ "Audience.Festival", audience.Festival },
			{ "Audience.LeisureCenter", audience.LeisureCenter },
			{ "Audience.Museum", audience.Museum },
		},
		{
			{ "Audience.PrivateCompany", audience.PrivateCompany },
			{ "Audience.PublicInstitution", audience.PublicInstitution },
			{ "Audience.School", audience.School },
			{ "Audience.VideoGame", audience.VideoGame },
			{ "Audience.YouTube", audience.YouTube },
		},
	}
	for _, entries in audienceRows do
		local row = horizontalRow(media.Content, theme.Spacing.XSmall, 42)
		for _, entry in entries do
			imageTile(row, entry[2], entry[1], theme.Color.SurfaceElevated, 40)
		end
	end

	return scroll.Root
end

return Gallery
