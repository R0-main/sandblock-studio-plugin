--!strict

local Components = require(script.Parent.Components)
local Gallery = require(script.Parent.Gallery)
local Theme = require(script.Parent.Theme)
local Util = require(script.Parent.Util)

local App = {}

local function makeLabel(parent: Instance, theme: any, text: string, muted: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.FontFace = theme.Font.Regular
	label.Size = UDim2.new(1, 0, 0, 0)
	label.Text = text
	label.TextColor3 = if muted then theme.Color.TextSecondary else theme.Color.TextPrimary
	label.TextSize = theme.TextSize.Body
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function healthRow(parent: Instance, theme: any, title: string, description: string, layoutOrder: number)
	local row = Instance.new("Frame")
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Size = UDim2.new(1, 0, 0, 0)
	row.Parent = parent

	local copy = Instance.new("Frame")
	copy.AutomaticSize = Enum.AutomaticSize.Y
	copy.BackgroundTransparency = 1
	copy.Size = UDim2.new(1, -118, 0, 0)
	copy.Parent = row
	Util.list(copy, Enum.FillDirection.Vertical, 2)

	local titleLabel = makeLabel(copy, theme, title)
	titleLabel.FontFace = theme.Font.Semibold
	local descriptionLabel = makeLabel(copy, theme, description, true)
	descriptionLabel.TextSize = theme.TextSize.Small

	local badge = Components.StatusBadge({
		Parent = row,
		Status = "neutral",
		Text = "Unknown",
		Theme = theme,
	})
	badge.Root.AnchorPoint = Vector2.new(1, 0)
	badge.Root.Position = UDim2.fromScale(1, 0)

	return badge
end

function App.mount(parent: Instance, options: any?)
	options = options or {}
	local theme = Theme.get()
	local root = Instance.new("Frame")
	root.Name = "SandblockStudio"
	root.BackgroundColor3 = theme.Color.Canvas
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	Components.Header({
		Parent = root,
		Title = "SANDBLOCK",
		Subtitle = "STUDIO · NATIVE UI",
		Icon = options.Icon,
		Theme = theme,
	})

	local nav = Instance.new("Frame")
	nav.Name = "Navigation"
	nav.BackgroundColor3 = theme.Color.Surface
	nav.BorderSizePixel = 0
	nav.Position = UDim2.fromOffset(0, 58)
	nav.Size = UDim2.new(1, 0, 0, 40)
	nav.Parent = root
	Util.padding(nav, theme.Spacing.Small, 0)
	Util.list(
		nav,
		Enum.FillDirection.Horizontal,
		theme.Spacing.XSmall,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)

	local content = Instance.new("Frame")
	content.Name = "Pages"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, 98)
	content.Size = UDim2.new(1, 0, 1, -98)
	content.Parent = root

	local toastHost = Components.ToastHost({ Parent = root, Theme = theme })

	local runtimePage = Components.ScrollView({
		Parent = content,
		Name = "RuntimePage",
		Padding = theme.Spacing.Large,
		Gap = theme.Spacing.Medium,
		Theme = theme,
	}).Root

	local overview = Components.Surface({
		Parent = runtimePage,
		Title = "Studio connection",
		Subtitle = "The plugin keeps outbound loopback communication local and exposes explicit recovery controls.",
		LayoutOrder = 1,
		Theme = theme,
	})

	local bridgeStatus =
		healthRow(overview.Content, theme, "MCP bridge", "Outbound connection to the Sandblock gateway", 1)
	Components.Divider({ Parent = overview.Content, LayoutOrder = 2, Theme = theme })
	local rojoStatus = healthRow(
		overview.Content,
		theme,
		"Rojo adapter",
		options.RojoDescription or "Pinned sync client integration",
		3
	)
	rojoStatus.Set("neutral", "Stopped")

	local project = Components.Surface({
		Parent = runtimePage,
		Title = "Project binding",
		Subtitle = "Sandblock Code remains the source of truth for approved runtimes and repository paths.",
		LayoutOrder = 2,
		Theme = theme,
	})
	local projectName = makeLabel(project.Content, theme, options.ProjectName or "No approved runtime selected")
	projectName.FontFace = theme.Font.Semibold
	local place = makeLabel(
		project.Content,
		theme,
		string.format("Current Studio place · %s (%s)", game.Name, tostring(game.PlaceId)),
		true
	)
	place.TextSize = theme.TextSize.Small
	local placeStatus = Components.StatusBadge({
		Parent = project.Content,
		Status = "warning",
		Text = "PlaceId not validated",
		Theme = theme,
	})

	local errorSurface = Components.Surface({
		Parent = runtimePage,
		Name = "ActionableError",
		Title = "Action required",
		LayoutOrder = 3,
		BackgroundColor = theme.Color.ErrorSurface,
		BorderColor = theme.Color.Error,
		Theme = theme,
	})
	errorSurface.Root.Visible = false
	local errorText = makeLabel(errorSurface.Content, theme, "")
	errorText.TextColor3 = theme.Color.Error
	errorText.FontFace = theme.Font.Code
	errorText.TextSize = theme.TextSize.Code

	local actions = Components.Surface({
		Parent = runtimePage,
		Title = "Local services",
		Subtitle = "One action connects the MCP bridge and the pinned Rojo client together.",
		LayoutOrder = 4,
		Theme = theme,
	})
	local actionRow = Instance.new("Frame")
	actionRow.AutomaticSize = Enum.AutomaticSize.Y
	actionRow.BackgroundTransparency = 1
	actionRow.Size = UDim2.new(1, 0, 0, 0)
	actionRow.Parent = actions.Content
	Util.list(actionRow, Enum.FillDirection.Horizontal, theme.Spacing.Small)

	local bridgeEnabled = false
	local rojoEnabled = false
	local connectButton = Components.Button({
		Parent = actionRow,
		Name = "ConnectServices",
		Text = "Connect services",
		Style = "Primary",
		OnActivated = function()
			if options.OnToggleConnection then
				options.OnToggleConnection(not (bridgeEnabled or rojoEnabled))
			end
		end,
		Theme = theme,
	})

	local galleryPage = Gallery.mount(content, toastHost)
	galleryPage.Visible = false

	local settingsPage = Components.ScrollView({
		Parent = content,
		Name = "SettingsPage",
		Padding = theme.Spacing.Large,
		Gap = theme.Spacing.Medium,
		Theme = theme,
	}).Root
	settingsPage.Visible = false

	local defaultSettings = table.clone(options.DefaultSettings or {})
	local draftSettings = table.clone(options.InitialSettings or defaultSettings)

	local endpoints = Components.Surface({
		Parent = settingsPage,
		Title = "Connection endpoints",
		Subtitle = "Only loopback URLs are accepted. Changes are persisted for this Studio plugin.",
		LayoutOrder = 1,
		Theme = theme,
	})
	local mcpLabel = makeLabel(endpoints.Content, theme, "MCP gateway URL")
	mcpLabel.FontFace = theme.Font.Semibold
	local mcpInput = Components.TextInput({
		Parent = endpoints.Content,
		Name = "McpBaseUrl",
		Text = tostring(draftSettings.McpBaseUrl or ""),
		Placeholder = "http://127.0.0.1:3070",
		OnChanged = function(value: string)
			draftSettings.McpBaseUrl = value
		end,
		Theme = theme,
	})
	local rojoLabel = makeLabel(endpoints.Content, theme, "Rojo server URL")
	rojoLabel.FontFace = theme.Font.Semibold
	local rojoInput = Components.TextInput({
		Parent = endpoints.Content,
		Name = "RojoBaseUrl",
		Text = tostring(draftSettings.RojoBaseUrl or ""),
		Placeholder = "http://127.0.0.1:34872",
		OnChanged = function(value: string)
			draftSettings.RojoBaseUrl = value
		end,
		Theme = theme,
	})
	local delayLabel = makeLabel(endpoints.Content, theme, "MCP reconnect delay (seconds)")
	delayLabel.FontFace = theme.Font.Semibold
	local delayInput = Components.TextInput({
		Parent = endpoints.Content,
		Name = "ReconnectDelay",
		Text = tostring(draftSettings.ReconnectDelay or 2),
		Placeholder = "2",
		OnChanged = function(value: string)
			draftSettings.ReconnectDelay = tonumber(value) or value
		end,
		Theme = theme,
	})

	local sync = Components.Surface({
		Parent = settingsPage,
		Title = "Rojo sync",
		Subtitle = "Advanced fork settings apply the next time services connect.",
		LayoutOrder = 2,
		Theme = theme,
	})
	local twoWaySync = Components.Checkbox({
		Parent = sync.Content,
		Text = "Two-way sync (Studio changes may write to disk)",
		Checked = draftSettings.TwoWaySync == true,
		OnChanged = function(value: boolean)
			draftSettings.TwoWaySync = value
		end,
		Theme = theme,
	})
	local syncFallback = Components.Checkbox({
		Parent = sync.Content,
		Text = "Enable sync fallback",
		Checked = draftSettings.EnableSyncFallback == true,
		OnChanged = function(value: boolean)
			draftSettings.EnableSyncFallback = value
		end,
		Theme = theme,
	})
	local typechecking = Components.Checkbox({
		Parent = sync.Content,
		Text = "Validate protocol payloads",
		Checked = draftSettings.TypecheckingEnabled == true,
		OnChanged = function(value: boolean)
			draftSettings.TypecheckingEnabled = value
		end,
		Theme = theme,
	})
	local openScripts = Components.Checkbox({
		Parent = sync.Content,
		Text = "Open active scripts externally",
		Checked = draftSettings.OpenScriptsExternally == true,
		OnChanged = function(value: boolean)
			draftSettings.OpenScriptsExternally = value
		end,
		Theme = theme,
	})
	local timingLogs = Components.Checkbox({
		Parent = sync.Content,
		Text = "Enable Rojo timing logs",
		Checked = draftSettings.TimingLogsEnabled == true,
		OnChanged = function(value: boolean)
			draftSettings.TimingLogsEnabled = value
		end,
		Theme = theme,
	})

	local settingsActions = Components.Surface({
		Parent = settingsPage,
		Title = "Apply configuration",
		Subtitle = "Saving restarts active services so every option takes effect together.",
		LayoutOrder = 3,
		Theme = theme,
	})
	local settingsError = makeLabel(settingsActions.Content, theme, "", true)
	settingsError.Name = "SettingsError"
	settingsError.TextColor3 = theme.Color.Error
	settingsError.Visible = false
	local settingsActionRow = Instance.new("Frame")
	settingsActionRow.AutomaticSize = Enum.AutomaticSize.Y
	settingsActionRow.BackgroundTransparency = 1
	settingsActionRow.Size = UDim2.new(1, 0, 0, 0)
	settingsActionRow.Parent = settingsActions.Content
	Util.list(settingsActionRow, Enum.FillDirection.Horizontal, theme.Spacing.Small)
	Components.Button({
		Parent = settingsActionRow,
		Name = "SaveSettings",
		Text = "Save settings",
		Style = "Primary",
		OnActivated = function()
			local success = true
			local message: string? = nil
			if options.OnApplySettings then
				success, message = options.OnApplySettings(table.clone(draftSettings))
			end
			settingsError.Visible = not success
			settingsError.Text = message or ""
			if success then
				toastHost.Push("Connection settings saved.", "success")
			end
		end,
		Theme = theme,
	})
	Components.Button({
		Parent = settingsActionRow,
		Name = "ResetSettings",
		Text = "Reset defaults",
		Style = "Secondary",
		OnActivated = function()
			draftSettings = table.clone(defaultSettings)
			mcpInput.SetText(tostring(draftSettings.McpBaseUrl or ""))
			rojoInput.SetText(tostring(draftSettings.RojoBaseUrl or ""))
			delayInput.SetText(tostring(draftSettings.ReconnectDelay or 2))
			twoWaySync.SetChecked(draftSettings.TwoWaySync == true, true)
			syncFallback.SetChecked(draftSettings.EnableSyncFallback == true, true)
			typechecking.SetChecked(draftSettings.TypecheckingEnabled == true, true)
			openScripts.SetChecked(draftSettings.OpenScriptsExternally == true, true)
			timingLogs.SetChecked(draftSettings.TimingLogsEnabled == true, true)
			settingsError.Visible = false
		end,
		Theme = theme,
	})

	local runtimeTab
	local libraryTab
	local settingsTab
	local function showPage(name: string)
		local showRuntime = name == "Runtime"
		local showLibrary = name == "Components"
		runtimePage.Visible = showRuntime
		galleryPage.Visible = showLibrary
		settingsPage.Visible = name == "Settings"
		runtimeTab.SetSelected(showRuntime)
		libraryTab.SetSelected(showLibrary)
		settingsTab.SetSelected(name == "Settings")
	end

	runtimeTab = Components.TabButton({
		Parent = nav,
		Text = "Runtime",
		Selected = true,
		LayoutOrder = 1,
		OnActivated = function()
			showPage("Runtime")
		end,
		Theme = theme,
	})
	libraryTab = Components.TabButton({
		Parent = nav,
		Text = "Components",
		Selected = false,
		LayoutOrder = 2,
		OnActivated = function()
			showPage("Components")
		end,
		Theme = theme,
	})
	settingsTab = Components.TabButton({
		Parent = nav,
		Text = "Settings",
		Selected = false,
		LayoutOrder = 3,
		OnActivated = function()
			showPage("Settings")
		end,
		Theme = theme,
	})

	local bridgeError: string? = nil
	local rojoError: string? = nil
	local function updateConnectButton()
		connectButton.SetText(if bridgeEnabled or rojoEnabled then "Disconnect services" else "Connect services")
	end
	local function updateErrorSurface()
		local messages = {}
		if bridgeError and bridgeError ~= "" then
			table.insert(messages, "MCP: " .. bridgeError)
		end
		if rojoError and rojoError ~= "" then
			table.insert(messages, "Rojo: " .. rojoError)
		end
		errorSurface.Root.Visible = #messages > 0
		errorText.Text = table.concat(messages, "\n\n")
	end

	local function setBridgeState(status: string, message: string?, enabled: boolean?)
		if enabled ~= nil then
			bridgeEnabled = enabled
		end
		local labels = {
			connected = "Connected",
			connecting = "Connecting",
			disconnected = "Unavailable",
			error = "Error",
			busy = "Busy",
			neutral = "Stopped",
		}
		bridgeStatus.Set(if status == "busy" then "error" else status, labels[status] or status)
		updateConnectButton()
		bridgeError = message
		updateErrorSurface()
	end

	local function setRojoState(status: string, text: string, message: string?, enabled: boolean?)
		if enabled ~= nil then
			rojoEnabled = enabled
		end
		rojoStatus.Set(status, text)
		updateConnectButton()
		rojoError = message
		updateErrorSurface()
	end

	setBridgeState("neutral", nil, false)

	return {
		Root = root,
		SetBridgeState = setBridgeState,
		SetPlaceState = function(status: string, text: string)
			placeStatus.Set(status, text)
		end,
		SetProjectName = function(text: string)
			projectName.Text = text
		end,
		SetRojoState = setRojoState,
		ShowPage = showPage,
		Notify = toastHost.Push,
		Destroy = function()
			root:Destroy()
		end,
	}
end

return App
