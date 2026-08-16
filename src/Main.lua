-- Roblox Studio bridge plugin lifecycle.
--
-- Keeping startup behind Main.start lets the production entry point and the
-- ReplicatedStorage development loader use the exact same implementation.

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)
local Net = require(script.Parent.Net)
local Util = require(script.Parent.Util)
local Handlers = require(script.Parent.Handlers)
local UI = require(script.Parent.UI)
local RojoAdapter = require(script.Parent.Rojo.Plugin.SandblockAdapter)

local Main = {}

local function isLoopbackUrl(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value:match("^https?://127%.0%.0%.1:%d+/?$") ~= nil or value:match("^https?://localhost:%d+/?$") ~= nil
end

local function normalizeSettings(candidate: any): (any?, string?)
	if type(candidate) ~= "table" then
		return nil, "Settings must be a table."
	end

	local defaults = Config.DefaultSettings
	local settings = table.clone(defaults)
	for name in defaults do
		if candidate[name] ~= nil then
			settings[name] = candidate[name]
		end
	end

	if not isLoopbackUrl(settings.McpBaseUrl) then
		return nil, "MCP URL must use http(s)://127.0.0.1:<port> or localhost."
	end
	if not isLoopbackUrl(settings.RojoBaseUrl) then
		return nil, "Rojo URL must use http(s)://127.0.0.1:<port> or localhost."
	end
	settings.McpBaseUrl = settings.McpBaseUrl:gsub("/$", "")
	settings.RojoBaseUrl = settings.RojoBaseUrl:gsub("/$", "")

	if type(settings.ReconnectDelay) ~= "number" then
		return nil, "Reconnect delay must be a number."
	end
	settings.ReconnectDelay = math.clamp(settings.ReconnectDelay, 0.25, 30)

	for _, name in
		{
			"TwoWaySync",
			"EnableSyncFallback",
			"TypecheckingEnabled",
			"OpenScriptsExternally",
			"TimingLogsEnabled",
		}
	do
		if type(settings[name]) ~= "boolean" then
			return nil, name .. " must be enabled or disabled."
		end
	end

	return settings, nil
end

local function loadSettings(pluginObject: Plugin): any
	local saved
	pcall(function()
		saved = pluginObject:GetSetting(Config.SettingsKey)
	end)
	local settings = normalizeSettings(saved or Config.DefaultSettings)
	return settings or table.clone(Config.DefaultSettings)
end

function Main.start(pluginObject: Plugin, options: any?)
	options = options or {}
	local host = options.Host
	local ownsHost = host == nil
	local toolbar
	local button
	if host then
		toolbar = host.Toolbar
		button = host.Button
	else
		toolbar = pluginObject:CreateToolbar("Sandblock")
		button = toolbar:CreateButton("Sandblock", "Open Sandblock Studio", Config.PluginIcon)
		button.ClickableWhenViewportHidden = true
	end

	local running = false
	local rojoRunning = false
	local rojoSession = nil
	local destroyed = false
	local runGeneration = 0
	local connections = {}
	local settings = loadSettings(pluginObject)
	-- Identifies this Studio session to the bridge, which only serves one plugin
	-- at a time. Regenerated on every reload, so the fresh code reclaims its slot.
	local clientId = HttpService:GenerateGUID(false)

	local function execute(command: any)
		local handler = Handlers[command.tool]
		if not handler then
			Net.postResponse(settings.McpBaseUrl, command.id, false, "unknown tool: " .. tostring(command.tool))
			return
		end
		local ok, result = pcall(handler, command.args)
		if ok then
			Net.postResponse(settings.McpBaseUrl, command.id, true, Util.safeValue(result))
		else
			Net.postResponse(settings.McpBaseUrl, command.id, false, tostring(result))
		end
	end

	local setRunning
	local setRojoRunning
	local setAllRunning
	local applySettings
	local panel
	local rojoCompatibility = RojoAdapter.getCompatibility()
	panel = UI.create(pluginObject, {
		Icon = Config.PluginIcon,
		Widget = if host then host.Widget else nil,
		RojoDescription = string.format(
			"Pinned Sandblock fork · client %s · protocol %d",
			rojoCompatibility.clientVersion,
			rojoCompatibility.protocolVersion
		),
		InitialSettings = settings,
		DefaultSettings = Config.DefaultSettings,
		OnToggleConnection = function(value: boolean)
			setAllRunning(value)
		end,
		OnApplySettings = function(nextSettings: any)
			return applySettings(nextSettings)
		end,
	})

	local function loop(generation: number)
		local claimed = false
		while not destroyed and running and runGeneration == generation do
			local status
			local command
			local message
			if claimed then
				status, command, message = Net.poll(settings.McpBaseUrl, clientId)
			else
				status, message = Net.claim(settings.McpBaseUrl, clientId)
			end
			if destroyed or runGeneration ~= generation then
				return
			end
			if status == "busy" then
				-- The bridge serves a single Studio; refusing here keeps the two
				-- plugins from stealing each other's commands.
				local detail = tostring(message) .. " Stop the bridge in the other Studio, then retry from this panel."
				warn("[Sandblock] " .. detail)
				setAllRunning(false)
				panel.App.SetBridgeState("busy", detail, false)
			elseif status == "unreachable" then
				panel.App.SetBridgeState(
					"disconnected",
					"The local gateway is unreachable. Start the Sandblock Code runtime and ensure Studio HTTP requests are enabled.",
					true
				)
				claimed = false
				task.wait(settings.ReconnectDelay)
			else
				claimed = true
				panel.App.SetBridgeState("connected", nil, true)
				if command then
					execute(command)
				end
			end
		end
	end

	function setRunning(value: boolean, status: string?, message: string?)
		if destroyed or (running == value and status == nil) then
			return
		end

		runGeneration += 1
		running = value
		if value then
			panel.App.SetBridgeState("connecting", nil, true)
			print("[Sandblock] connecting MCP bridge to " .. settings.McpBaseUrl)
			local generation = runGeneration
			task.spawn(function()
				loop(generation)
			end)
		else
			Net.release(settings.McpBaseUrl, clientId)
			panel.App.SetBridgeState(status or "neutral", message, false)
			print("[Sandblock] MCP bridge stopped")
		end
	end

	function setRojoRunning(value: boolean)
		if destroyed or (rojoRunning == value and (value == false or rojoSession ~= nil)) then
			return
		end

		if not value then
			rojoRunning = false
			local session = rojoSession
			rojoSession = nil
			if session then
				session:stop()
			end
			panel.App.SetRojoState("neutral", "Stopped", nil, false)
			print("[Sandblock Rojo] sync stopped")
			return
		end

		rojoRunning = true
		panel.App.SetRojoState("connecting", "Connecting", nil, true)

		local session
		session = RojoAdapter.new({
			baseUrl = settings.RojoBaseUrl,
			twoWaySync = settings.TwoWaySync,
			settings = {
				enableSyncFallback = settings.EnableSyncFallback,
				openScriptsExternally = settings.OpenScriptsExternally,
				timingLogsEnabled = settings.TimingLogsEnabled,
				typecheckingEnabled = settings.TypecheckingEnabled,
			},
			onLoading = function(text: string)
				if not destroyed and rojoSession == session then
					panel.App.SetRojoState("connecting", text, nil, true)
				end
			end,
			onPatch = function(summary: any)
				if destroyed or rojoSession ~= session or summary.appliedCount == 0 then
					return
				end
				local status = if summary.hasUnapplied then "warning" else "success"
				panel.App.Notify(string.format("Rojo applied %d instance change(s).", summary.appliedCount), status)
			end,
			onStatusChanged = function(status: string, detail: any)
				if destroyed or rojoSession ~= session then
					return
				end

				if status == RojoAdapter.Status.Connecting then
					panel.App.SetRojoState("connecting", "Connecting", nil, true)
				elseif status == RojoAdapter.Status.Connected then
					local projectName = tostring(detail)
					panel.App.SetRojoState("connected", "Connected", nil, true)
					panel.App.SetProjectName(projectName)
					panel.App.SetPlaceState("connected", "Accepted by Rojo server")
					panel.App.Notify("Rojo connected to " .. projectName .. ".", "success")
					print("[Sandblock Rojo] connected to " .. projectName)
				elseif status == RojoAdapter.Status.Disconnected then
					rojoSession = nil
					rojoRunning = false
					if running then
						setRunning(false)
					end
					if detail ~= nil then
						local message = tostring(detail)
						panel.App.SetRojoState("error", "Error", message, false)
						warn("[Sandblock Rojo] " .. message)
					else
						panel.App.SetRojoState("neutral", "Stopped", nil, false)
					end
				end
			end,
		})
		rojoSession = session
		session:start()
		print("[Sandblock Rojo] connecting to " .. settings.RojoBaseUrl)
	end

	function setAllRunning(value: boolean)
		if destroyed then
			return
		end
		setRunning(value)
		setRojoRunning(value)
	end

	function applySettings(candidate: any): (boolean, string?)
		local normalized, message = normalizeSettings(candidate)
		if not normalized then
			return false, message
		end

		local shouldReconnect = running or rojoRunning
		if shouldReconnect then
			setAllRunning(false)
		end
		settings = normalized
		pcall(function()
			pluginObject:SetSetting(Config.SettingsKey, settings)
		end)
		if shouldReconnect then
			task.defer(function()
				setAllRunning(true)
			end)
		end
		return true, nil
	end

	table.insert(
		connections,
		button.Click:Connect(function()
			panel.Toggle()
		end)
	)

	local function updateToolbarState()
		button:SetActive(panel.Widget.Enabled)
	end

	table.insert(connections, panel.Widget:GetPropertyChangedSignal("Enabled"):Connect(updateToolbarState))
	updateToolbarState()

	-- Deliberately does *not* auto-start: opening a place should not connect the
	-- bridge or Rojo. One explicit action starts both local services together.

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		local wasRunning = running
		running = false
		runGeneration += 1
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		if wasRunning then
			Net.release(settings.McpBaseUrl, clientId)
		end
		local activeRojoSession = rojoSession
		rojoSession = nil
		rojoRunning = false
		if activeRojoSession then
			activeRojoSession:stop()
		end
		pcall(panel.Destroy)
		if ownsHost then
			pcall(function()
				toolbar:Destroy()
			end)
		end
	end

	return {
		Destroy = destroy,
		SetConnectionRunning = setAllRunning,
		SetBridgeRunning = setRunning,
		SetRojoRunning = setRojoRunning,
	}
end

return Main
