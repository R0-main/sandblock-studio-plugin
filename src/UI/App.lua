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

	return {
		Set = badge.Set,
		SetDetail = function(text: string)
			descriptionLabel.Text = text
		end,
	}
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

	-- One page, three facts and one action: which project Studio is bound to,
	-- how the MCP bridge and the Rojo server are doing, and a single control
	-- that starts or stops both.
	local project = Components.Surface({
		Parent = runtimePage,
		Title = "Project",
		Subtitle = "Sandblock Code owns repository paths; the plugin only ever names an approved runtime.",
		LayoutOrder = 1,
		Theme = theme,
	})
	local projectName = makeLabel(project.Content, theme, "No project selected")
	projectName.FontFace = theme.Font.Semibold
	local placeLabel = makeLabel(
		project.Content,
		theme,
		string.format("This Studio place · %s (%s)", game.Name, tostring(game.PlaceId)),
		true
	)
	placeLabel.TextSize = theme.TextSize.Small
	local placeStatus = Components.StatusBadge({
		Parent = project.Content,
		Status = "neutral",
		Text = "No project selected",
		Theme = theme,
	})
	local chooseButton = Components.Button({
		Parent = project.Content,
		Name = "ChooseProject",
		Text = "Choose project",
		Style = "Secondary",
		Size = UDim2.new(1, 0, 0, theme.Control.Regular),
		OnActivated = function()
			if options.OnChooseProject then
				options.OnChooseProject()
			end
		end,
		Theme = theme,
	})

	local services = Components.Surface({
		Parent = runtimePage,
		Title = "Services",
		LayoutOrder = 2,
		Theme = theme,
	})
	local bridgeStatus =
		healthRow(services.Content, theme, "MCP bridge", "Outbound connection to the Sandblock gateway", 1)
	Components.Divider({ Parent = services.Content, LayoutOrder = 2, Theme = theme })
	local rojoStatus =
		healthRow(services.Content, theme, "Rojo sync", options.RojoDescription or "Pinned sync client integration", 3)
	rojoStatus.Set("neutral", "Stopped")

	local bridgeEnabled = false
	local rojoEnabled = false
	local connectButton = Components.Button({
		Parent = services.Content,
		Name = "ConnectServices",
		Text = "Connect",
		Style = "Primary",
		Appearance = "Tactile",
		LayoutOrder = 4,
		Height = theme.Control.Large,
		Size = UDim2.new(1, 0, 0, theme.Control.Large),
		OnActivated = function()
			if options.OnToggleConnection then
				options.OnToggleConnection(not (bridgeEnabled or rojoEnabled))
			end
		end,
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

	-- Project picker. It lists what Sandblock Code approved, nothing the plugin
	-- discovered by itself, so there is no path to type in anywhere.
	local pickerPage = Components.ScrollView({
		Parent = content,
		Name = "ProjectPicker",
		Padding = theme.Spacing.Large,
		Gap = theme.Spacing.Medium,
		Theme = theme,
	}).Root
	pickerPage.Visible = false

	local picker = Components.Surface({
		Parent = pickerPage,
		Title = "Select a project",
		Subtitle = "Projects registered in Sandblock Code. Connecting starts this project's Rojo server in its own repository.",
		LayoutOrder = 1,
		Theme = theme,
	})
	local pickerList = Instance.new("Frame")
	pickerList.Name = "Runtimes"
	pickerList.AutomaticSize = Enum.AutomaticSize.Y
	pickerList.BackgroundTransparency = 1
	pickerList.Size = UDim2.new(1, 0, 0, 0)
	pickerList.Parent = picker.Content
	Util.list(pickerList, Enum.FillDirection.Vertical, theme.Spacing.Small)

	local pickerFooter = Instance.new("Frame")
	pickerFooter.Name = "PickerActions"
	pickerFooter.AutomaticSize = Enum.AutomaticSize.Y
	pickerFooter.BackgroundTransparency = 1
	pickerFooter.LayoutOrder = 2
	pickerFooter.Size = UDim2.new(1, 0, 0, 0)
	pickerFooter.Parent = picker.Content
	Util.list(pickerFooter, Enum.FillDirection.Horizontal, theme.Spacing.Small)
	Components.Button({
		Parent = pickerFooter,
		Name = "RefreshRuntimes",
		Text = "Refresh",
		Style = "Secondary",
		OnActivated = function()
			if options.OnChooseProject then
				options.OnChooseProject()
			end
		end,
		Theme = theme,
	})
	local closePicker
	Components.Button({
		Parent = pickerFooter,
		Name = "CancelPicker",
		Text = "Cancel",
		Style = "Ghost",
		OnActivated = function()
			closePicker()
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
	local currentPage = "Runtime"
	local pickerOpen = false
	local function applyVisibility()
		local showRuntime = currentPage == "Runtime"
		local showLibrary = currentPage == "Components"
		runtimePage.Visible = showRuntime and not pickerOpen
		pickerPage.Visible = showRuntime and pickerOpen
		galleryPage.Visible = showLibrary
		settingsPage.Visible = currentPage == "Settings"
		runtimeTab.SetSelected(showRuntime)
		libraryTab.SetSelected(showLibrary)
		settingsTab.SetSelected(currentPage == "Settings")
	end
	local function showPage(name: string)
		currentPage = name
		applyVisibility()
	end
	local function setPickerOpen(value: boolean)
		pickerOpen = value
		applyVisibility()
	end
	closePicker = function()
		setPickerOpen(false)
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
	local runtimeError: string? = nil
	local busy = false
	local selectedRuntime: any = nil

	local function updateConnectButton()
		local connected = bridgeEnabled or rojoEnabled
		connectButton.SetText(if busy then "Working…" elseif connected then "Disconnect" else "Connect")
		connectButton.SetEnabled(not busy)
	end
	local function updateErrorSurface()
		local messages = {}
		if runtimeError and runtimeError ~= "" then
			table.insert(messages, runtimeError)
		end
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

	local PLACE_LABELS = {
		verified = { "success", "Place verified" },
		unbound = { "warning", "No place declared" },
		mismatch = { "error", "Place not declared" },
	}

	-- The plugin shows the project it will act on before anything connects, so a
	-- Studio opened on a place the project does not declare is visible instead
	-- of being discovered halfway through a sync.
	--
	-- `place` is the declared place this Studio matched, which is also the place
	-- the bridge will route an agent's commands to — naming it here is what
	-- makes "which of my Studios is this?" answerable at a glance.
	local function setProject(runtime: any, placeState: string?, placeMessage: string?, place: any?)
		selectedRuntime = runtime
		projectName.Text = if runtime then tostring(runtime.displayName) else "No project selected"
		chooseButton.SetText(if runtime then "Change project" else "Choose project")
		local label = PLACE_LABELS[placeState or ""]
		if runtime == nil then
			placeStatus.Set("neutral", "No project selected")
		elseif label then
			local text = label[2]
			if placeState == "verified" and place ~= nil then
				text = string.format("%s%s", tostring(place.name), if place.main then " · main place" else "")
			end
			placeStatus.Set(label[1], text)
		else
			placeStatus.Set("neutral", "Not validated")
		end
		runtimeError = placeMessage
		updateErrorSurface()
	end

	-- Sync freshness, refreshed once a second while a sync has happened. Seeing
	-- "Synced just now" age into "2 minutes ago" is how you notice a server that
	-- stopped answering without any error being raised.
	local lastSyncAt: number? = nil
	local lastSyncCount = 0
	local lastSyncProject: string? = nil
	local staticRojoDetail = options.RojoDescription or "Pinned sync client integration"

	local function renderRojoDetail()
		if lastSyncAt == nil then
			rojoStatus.SetDetail(staticRojoDetail)
			return
		end
		local parts = { "Synced " .. Util.elapsedText(os.time() - lastSyncAt) }
		if lastSyncProject then
			table.insert(parts, lastSyncProject)
		end
		if lastSyncCount > 0 then
			table.insert(parts, string.format("%d change%s", lastSyncCount, if lastSyncCount > 1 then "s" else ""))
		end
		rojoStatus.SetDetail(table.concat(parts, " · "))
	end

	local function setRuntimeDetail(text: string)
		lastSyncAt = nil
		staticRojoDetail = text
		rojoStatus.SetDetail(text)
	end

	local function markSynced(info: any)
		info = info or {}
		lastSyncAt = os.time()
		lastSyncCount = tonumber(info.appliedCount) or 0
		lastSyncProject = info.projectName or lastSyncProject
		renderRojoDetail()
	end

	local ticking = true
	task.spawn(function()
		while ticking do
			task.wait(1)
			if ticking and lastSyncAt ~= nil then
				renderRojoDetail()
			end
		end
	end)

	local function clearPicker()
		for _, child in pickerList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function describeRuntime(runtime: any): string
		local parts = {}
		if runtime.mainPlaceId then
			table.insert(parts, "Main place " .. tostring(runtime.mainPlaceId))
		else
			table.insert(parts, "No place bound")
		end
		if runtime.projectFile then
			table.insert(parts, tostring(runtime.projectFile))
		end
		local rojo = runtime.rojo
		if rojo and (rojo.state == "running" or rojo.state == "external") then
			local prefix = if rojo.state == "external" then "already served on " else "serving on "
			table.insert(parts, prefix .. tostring(rojo.url))
		end
		if runtime.issue then
			table.insert(parts, tostring(runtime.issue))
		end
		return table.concat(parts, " · ")
	end

	-- Renders the approved runtime list. `message` replaces the list when
	-- Sandblock Code could not be reached, so the panel always says what to do
	-- next instead of showing an empty box.
	local function setRuntimes(runtimes: { any }?, message: string?)
		clearPicker()
		if message then
			Components.Alert({
				Parent = pickerList,
				Tone = "danger",
				Title = "Sandblock Code unavailable",
				Message = message,
				Theme = theme,
			})
		elseif runtimes == nil or #runtimes == 0 then
			Components.EmptyState({
				Parent = pickerList,
				Title = "No project registered",
				Description = "Add a game repository in Sandblock Code, then refresh this list.",
				Theme = theme,
			})
		else
			for index, runtime in runtimes do
				local isSelected = selectedRuntime ~= nil and selectedRuntime.runtimeId == runtime.runtimeId
				Components.ChoiceButton({
					Parent = pickerList,
					Name = "Runtime" .. index,
					LayoutOrder = index,
					Icon = if runtime.rojo
							and (runtime.rojo.state == "running" or runtime.rojo.state == "external")
						then "▶"
						else "◇",
					Text = tostring(runtime.displayName),
					Description = describeRuntime(runtime),
					Selected = isSelected,
					OnActivated = function()
						setPickerOpen(false)
						if options.OnSelectRuntime then
							options.OnSelectRuntime(runtime)
						end
					end,
					Theme = theme,
				})
			end
		end
		setPickerOpen(true)
	end

	setBridgeState("neutral", nil, false)
	setProject(nil)
	bridgeStatus.SetDetail("Outbound connection to the Sandblock gateway")

	return {
		Root = root,
		SetBridgeState = setBridgeState,
		SetBridgeDetail = bridgeStatus.SetDetail,
		SetRojoState = setRojoState,
		SetRojoDetail = setRuntimeDetail,
		MarkSynced = markSynced,
		SetProject = setProject,
		SetRuntimes = setRuntimes,
		SetPickerOpen = setPickerOpen,
		SetBusy = function(value: boolean)
			busy = value
			updateConnectButton()
		end,
		ShowPage = showPage,
		Notify = toastHost.Push,
		Destroy = function()
			ticking = false
			root:Destroy()
		end,
	}
end

return App
