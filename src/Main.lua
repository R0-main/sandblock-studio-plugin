-- Roblox Studio bridge plugin lifecycle.
--
-- Keeping startup behind Main.start lets the production entry point and the
-- ReplicatedStorage development loader use the exact same implementation.

local HttpService = game:GetService("HttpService")

local Config = require(script.Parent.Config)
local Net = require(script.Parent.Net)
local Util = require(script.Parent.Util)
local Handlers = require(script.Parent.Handlers)
local Runtime = require(script.Parent.Runtime)
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
	if not isLoopbackUrl(settings.RuntimeBaseUrl) then
		return nil, "Sandblock Code URL must use http(s)://127.0.0.1:<port> or localhost."
	end
	if not isLoopbackUrl(settings.RojoBaseUrl) then
		return nil, "Rojo URL must use http(s)://127.0.0.1:<port> or localhost."
	end
	settings.McpBaseUrl = settings.McpBaseUrl:gsub("/$", "")
	settings.RuntimeBaseUrl = settings.RuntimeBaseUrl:gsub("/$", "")
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
	-- The project this panel acts on. Only Sandblock Code can turn the id back
	-- into a repository, so remembering it here leaks no path.
	local selection: any = nil
	-- Loopback URL of the Rojo server Sandblock Code started for `selection`.
	local rojoUrl: string? = nil
	-- The declared place this Studio holds, and the list it belongs to. Sent to
	-- the bridge on every claim: it is what lets several Studios share the
	-- gateway, one per place, and what bounds where an agent can switch to.
	local heldPlace: any = nil
	local declaredPlaces: { any } = {}
	local connecting = false

	local function loadSelection(): any
		local saved
		pcall(function()
			saved = pluginObject:GetSetting(Config.RuntimeKey)
		end)
		if type(saved) == "table" and type(saved.runtimeId) == "string" then
			return { runtimeId = saved.runtimeId, displayName = saved.displayName or saved.runtimeId }
		end
		return nil
	end

	local function saveSelection(runtime: any)
		pcall(function()
			pluginObject:SetSetting(
				Config.RuntimeKey,
				if runtime then { runtimeId = runtime.runtimeId, displayName = runtime.displayName } else nil
			)
		end)
	end

	selection = loadSelection()

	-- Studio is the only side that knows a patch was applied, so it tells the
	-- app. Fire and forget: a lost event is a missing history line, never a
	-- reason to interrupt a sync.
	local function reportEvent(kind: string, payload: any?)
		local runtimeId = selection and selection.runtimeId
		if runtimeId == nil then
			return
		end
		local event = if payload then table.clone(payload) else {}
		event.kind = kind
		task.spawn(function()
			Runtime.report(settings.RuntimeBaseUrl, runtimeId, event)
		end)
	end

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
	local chooseProject
	local selectRuntime
	local panel
	local rojoCompatibility = RojoAdapter.getCompatibility()
	local rojoDescription = string.format(
		"Pinned Sandblock fork · client %s · protocol %d",
		rojoCompatibility.clientVersion,
		rojoCompatibility.protocolVersion
	)
	panel = UI.create(pluginObject, {
		Icon = Config.PluginIcon,
		Widget = if host then host.Widget else nil,
		RojoDescription = rojoDescription,
		InitialSettings = settings,
		DefaultSettings = Config.DefaultSettings,
		OnToggleConnection = function(value: boolean)
			setAllRunning(value)
		end,
		OnChooseProject = function()
			chooseProject()
		end,
		OnSelectRuntime = function(runtime: any)
			selectRuntime(runtime)
		end,
		OnApplySettings = function(nextSettings: any)
			return applySettings(nextSettings)
		end,
	})

	-- What this Studio tells the bridge about itself when it claims its place.
	local function claimPayload(): any
		return {
			runtimeId = selection and selection.runtimeId,
			projectName = selection and selection.displayName,
			place = heldPlace,
			places = declaredPlaces,
		}
	end

	local function loop(generation: number)
		local claimed = false
		while not destroyed and running and runGeneration == generation do
			local status
			local command
			local message
			if claimed then
				status, command, message = Net.poll(settings.McpBaseUrl, clientId)
			else
				status, message = Net.claim(settings.McpBaseUrl, clientId, claimPayload())
			end
			if destroyed or runGeneration ~= generation then
				return
			end
			if status == "busy" then
				-- One Studio per place: refusing here keeps two plugins on the
				-- same place from stealing each other's commands. Studios on
				-- *different* declared places connect side by side.
				local detail = tostring(message) .. " Stop the bridge in the other Studio, then retry from this panel."
				warn("[Sandblock] " .. detail)
				setAllRunning(false)
				panel.App.SetBridgeState("busy", detail, false)
			elseif status == "reclaim" then
				-- The gateway restarted, or this session timed out while Studio
				-- was busy. Claiming again is the whole recovery.
				claimed = false
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
			panel.App.SetRojoDetail(rojoDescription)
			print("[Sandblock Rojo] sync stopped")
			return
		end

		rojoRunning = true
		panel.App.SetRojoState("connecting", "Connecting", nil, true)

		-- Sandblock Code decides which port serves this project; the manual URL
		-- is only used by the fallback path below.
		local baseUrl = rojoUrl or settings.RojoBaseUrl
		panel.App.SetRojoDetail(baseUrl)

		local session
		session = RojoAdapter.new({
			baseUrl = baseUrl,
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
				panel.App.MarkSynced({ appliedCount = summary.appliedCount })
				panel.App.Notify(string.format("Rojo applied %d instance change(s).", summary.appliedCount), status)
				reportEvent("sync", { appliedCount = summary.appliedCount, hasUnapplied = summary.hasUnapplied })
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
					panel.App.SetRojoDetail(string.format("%s · %s", projectName, baseUrl))
					panel.App.MarkSynced({ projectName = projectName })
					panel.App.Notify("Rojo connected to " .. projectName .. ".", "success")
					reportEvent("connected", { projectName = projectName, url = baseUrl })
					print("[Sandblock Rojo] connected to " .. projectName)
				elseif status == RojoAdapter.Status.Disconnected then
					rojoSession = nil
					rojoRunning = false
					reportEvent("disconnected", if detail ~= nil then { error = tostring(detail) } else nil)
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
		print("[Sandblock Rojo] connecting to " .. baseUrl)
	end

	-- Applies a runtime descriptor to the panel and remembers it for next time.
	local function applySelection(runtime: any)
		selection = runtime
		saveSelection(runtime)
		if runtime == nil then
			heldPlace = nil
			declaredPlaces = {}
			panel.App.SetProject(nil)
			return "unbound", nil
		end
		local placeState, place, placeMessage = Runtime.resolvePlace(runtime)
		heldPlace = place
		declaredPlaces = Runtime.declaredPlaces(runtime)
		panel.App.SetProject(runtime, placeState, placeMessage, place)
		return placeState, placeMessage
	end

	panel.App.SetBridgeDetail(settings.McpBaseUrl)
	if selection then
		-- Only the remembered name; nothing is verified until the user connects.
		panel.App.SetProject(selection)
	end

	function chooseProject()
		if destroyed or connecting then
			return
		end
		task.spawn(function()
			panel.App.SetBusy(true)
			local result = Runtime.list(settings.RuntimeBaseUrl)
			panel.App.SetBusy(false)
			if destroyed then
				return
			end
			if result.status == "ok" then
				panel.App.SetRuntimes(result.runtimes)
			else
				panel.App.SetRuntimes(nil, result.message)
			end
		end)
	end

	-- Starts this project's Rojo server through Sandblock Code, then connects
	-- both local services to it.
	local function connectTo(runtimeId: string)
		if destroyed or connecting then
			return
		end
		connecting = true
		panel.App.SetBusy(true)
		task.spawn(function()
			local function finish()
				connecting = false
				panel.App.SetBusy(false)
			end

			local listed = Runtime.list(settings.RuntimeBaseUrl)
			if destroyed then
				finish()
				return
			end
			if listed.status ~= "ok" then
				finish()
				-- Manual recovery: with no project chosen and the app unavailable,
				-- the saved Rojo URL still lets someone connect to a server they
				-- started themselves. It never overrides an explicit project.
				if selection == nil then
					rojoUrl = nil
					panel.App.Notify("Connecting to the manual Rojo URL.", "warning")
					setRunning(true)
					setRojoRunning(true)
					return
				end
				panel.App.SetProject(selection, "unbound", listed.message)
				return
			end

			local runtime
			for _, candidate in listed.runtimes or {} do
				if candidate.runtimeId == runtimeId then
					runtime = candidate
					break
				end
			end
			if runtime == nil then
				finish()
				applySelection(nil)
				panel.App.SetProject(
					nil,
					nil,
					"That project is no longer registered in Sandblock Code. Choose another one."
				)
				return
			end

			local placeState = applySelection(runtime)
			if placeState == "mismatch" then
				-- Refusing before anything starts keeps a sync from writing this
				-- project's tree into a place nobody declared.
				finish()
				return
			end

			local started = Runtime.start(settings.RuntimeBaseUrl, runtimeId)
			if destroyed then
				finish()
				return
			end
			if started.status ~= "ok" then
				finish()
				panel.App.SetProject(runtime, placeState, started.message, heldPlace)
				return
			end

			local descriptor = started.runtime
			local rojo = descriptor and descriptor.rojo
			rojoUrl = rojo and rojo.url or nil
			if rojoUrl == nil then
				finish()
				panel.App.SetProject(
					runtime,
					placeState,
					(rojo and rojo.error) or "Sandblock Code did not report a Rojo URL.",
					heldPlace
				)
				return
			end
			if rojo.compatible == false then
				panel.App.Notify(
					string.format("Rojo protocol %s does not match the pinned client.", tostring(rojo.protocolVersion)),
					"warning"
				)
			end

			finish()
			print(string.format("[Sandblock] %s serving on %s", tostring(descriptor.displayName), rojoUrl))
			setRunning(true)
			setRojoRunning(true)
		end)
	end

	function selectRuntime(runtime: any)
		if destroyed or runtime == nil then
			return
		end
		if running or rojoRunning then
			setAllRunning(false)
		end
		applySelection(runtime)
		connectTo(runtime.runtimeId)
	end

	function setAllRunning(value: boolean)
		if destroyed then
			return
		end
		if not value then
			connecting = false
			panel.App.SetBusy(false)
			rojoUrl = nil
			setRunning(false)
			setRojoRunning(false)
			return
		end
		-- Connecting always goes through a project: without one there is nothing
		-- to serve, so the picker is the first thing the button does.
		if selection == nil then
			chooseProject()
			return
		end
		connectTo(selection.runtimeId)
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
		panel.App.SetBridgeDetail(settings.McpBaseUrl)
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
