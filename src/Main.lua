-- Roblox Studio bridge plugin lifecycle.
--
-- Keeping startup behind Main.start lets the production entry point and the
-- ReplicatedStorage development loader use the exact same implementation.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Net = require(script.Parent.Net)
local Util = require(script.Parent.Util)
local Handlers = require(script.Parent.Handlers)
local Runtime = require(script.Parent.Runtime)
local RojoState = require(script.Parent.RojoState)
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
	settings.McpBaseUrl = settings.McpBaseUrl:gsub("/$", "")
	settings.RuntimeBaseUrl = settings.RuntimeBaseUrl:gsub("/$", "")

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
	-- Loopback route of the Rojo server Sandblock Code started for the place
	-- this Studio has open, and the project file behind it.
	local rojoUrl: string? = nil
	local rojoProjectFile: string? = nil
	-- The declared place this Studio holds, and the list it belongs to. Sent to
	-- the bridge on every claim: it is what lets several Studios share the
	-- gateway, one per place, and what bounds where an agent can switch to.
	local heldPlace: any = nil
	local declaredPlaces: { any } = {}
	local connecting = false
	-- Bumped whenever a connect attempt is abandoned, so one still waiting on
	-- Sandblock Code cannot finish after a disconnect or a newer attempt.
	local connectGeneration = 0
	-- Set when the person disconnects by hand, or when an automatic connect is
	-- refused: for the rest of this Studio session only a click connects again.
	local autoConnectStopped = false
	-- The copy this Studio is, once Sandblock Code has recognised it, and the
	-- runtime it belongs to. A copy is a local file with PlaceId 0; only its
	-- file name, which Studio uses as `game.Name`, tells it apart.
	local knownCopy: any = nil

	-- The key a copy reports itself with; nil while this Studio holds a real
	-- place, which its PlaceId already names.
	local function heldCopyKey(): string?
		return if heldPlace ~= nil and heldPlace.copyOf ~= nil then heldPlace.key else nil
	end

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
		local copyKey = heldCopyKey()
		task.spawn(function()
			Runtime.report(settings.RuntimeBaseUrl, runtimeId, event, copyKey)
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
			-- A click is the person's own decision: disconnecting keeps this
			-- Studio from connecting by itself again this session, connecting
			-- lets it.
			autoConnectStopped = not value
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

	-- A place as the bridge needs it: the descriptor also carries Rojo and
	-- sync state the gateway has no use for.
	local function claimPlace(place: any): any
		if place == nil then
			return nil
		end
		if place.copyOf ~= nil then
			-- A copy has no PlaceId: the bridge knows it by its key, and by the
			-- declared place and version it was made from.
			return {
				key = place.key,
				name = place.name,
				main = false,
				copyOf = place.copyOf,
				version = place.version,
				projectFile = place.projectFile,
			}
		end
		return {
			key = place.key,
			name = place.name,
			placeId = place.placeId,
			main = place.main,
			projectFile = place.projectFile,
		}
	end

	-- What this Studio tells the bridge about itself when it claims its place.
	local function claimPayload(): any
		local places = {}
		for _, place in declaredPlaces do
			table.insert(places, claimPlace(place))
		end
		return {
			runtimeId = selection and selection.runtimeId,
			projectName = selection and selection.displayName,
			place = claimPlace(heldPlace),
			places = places,
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
				-- Asking again by itself would only collide with that Studio.
				autoConnectStopped = true
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
			RojoState.clear()
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

		-- Rojo is part of Sandblock Code: the only server this plugin syncs with
		-- is the one the app serves for the selected project, at the address it
		-- handed back. There is no port to configure and no server to point at
		-- by hand — that was how a Rojo off the pinned protocol reached Studio.
		local baseUrl = rojoUrl
		if baseUrl == nil then
			panel.App.SetRojoState("error", "Error", "Choose a project so Sandblock Code can serve it.", false)
			return
		end

		rojoRunning = true
		panel.App.SetRojoState("connecting", "Connecting", nil, true)
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
				if destroyed or rojoSession ~= session then
					return
				end
				-- Even an empty patch carries the map: the initial sync of an
				-- unchanged tree is how package handlers learn what Rojo owns.
				RojoState.set(baseUrl, summary.instanceMap)
				if summary.appliedCount == 0 then
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
					panel.App.SetRojoDetail(string.format("%s · %s", projectName, rojoProjectFile or baseUrl))
					panel.App.MarkSynced({ projectName = projectName })
					panel.App.Notify("Rojo connected to " .. projectName .. ".", "success")
					print("[Sandblock Rojo] connected to " .. projectName)
					-- Sandblock Code checks the synced tree against the one this
					-- place declares. A mismatch is another place's code running
					-- here, so the sync stops and says which file it should be.
					local runtimeId = selection and selection.runtimeId
					if runtimeId then
						local copyKey = heldCopyKey()
						task.spawn(function()
							local reply = Runtime.report(
								settings.RuntimeBaseUrl,
								runtimeId,
								{ kind = "connected", projectName = projectName, url = baseUrl },
								copyKey
							)
							if destroyed or rojoSession ~= session or reply.code ~= "wrong_project" then
								return
							end
							local message = tostring(reply.message)
							warn("[Sandblock Rojo] " .. message)
							setRojoRunning(false)
							panel.App.SetRojoState("error", "Wrong project", message, false)
							panel.App.Notify(message, "error")
						end)
					end
				elseif status == RojoAdapter.Status.Disconnected then
					RojoState.clear()
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
	-- A copy is disposable, so connecting one leaves the remembered project as
	-- the next Studio on a real place expects it.
	local function applySelection(runtime: any, copy: any?)
		selection = runtime
		if copy == nil then
			saveSelection(runtime)
		end
		if runtime == nil then
			heldPlace = nil
			declaredPlaces = {}
			panel.App.SetProject(nil)
			return "unbound", nil
		end
		local placeState, place, placeMessage = Runtime.resolvePlace(runtime, copy)
		heldPlace = place
		declaredPlaces = Runtime.declaredPlaces(runtime)
		panel.App.SetProject(runtime, placeState, placeMessage, place)
		return placeState, placeMessage
	end

	panel.App.SetBridgeDetail(settings.McpBaseUrl)
	if selection then
		-- Only the remembered name; nothing is verified until this Studio
		-- connects, by hand or by itself.
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

	-- The copy this Studio is for `runtimeId`, if it is one. A Studio with no
	-- PlaceId that Sandblock Code has not recognised yet asks first, so a copy
	-- connected by hand still connects as the copy, not as an unpublished
	-- place. For PlaceId 0 the question has no side effect: no project declares
	-- that place and nothing launches it.
	local function copyFor(runtimeId: string): any?
		if knownCopy == nil and game.PlaceId == 0 then
			local answer = Runtime.hello(settings.RuntimeBaseUrl)
			if answer.status == "ok" and answer.copy ~= nil then
				knownCopy = { runtimeId = answer.runtimeId, copy = answer.copy }
			end
		end
		if knownCopy ~= nil and knownCopy.runtimeId == runtimeId then
			return knownCopy.copy
		end
		return nil
	end

	-- Starts this project's Rojo server through Sandblock Code, then connects
	-- both local services to it. `automatic` marks a connect Sandblock Code
	-- asked for rather than a click.
	local function connectTo(runtimeId: string, automatic: boolean?)
		if destroyed or connecting then
			return
		end
		connecting = true
		connectGeneration += 1
		local attempt = connectGeneration
		panel.App.SetBusy(true)
		task.spawn(function()
			-- A disconnect, a newer attempt, or a reload took over meanwhile and
			-- owns the panel now.
			local function superseded(): boolean
				return destroyed or connectGeneration ~= attempt
			end
			local function finish()
				connecting = false
				panel.App.SetBusy(false)
			end
			-- Sandblock Code refused what it had just offered. Asking again every
			-- few seconds would only repeat the refusal, so a click takes over.
			local function refused()
				finish()
				if automatic then
					autoConnectStopped = true
				end
			end

			local listed = Runtime.list(settings.RuntimeBaseUrl)
			if superseded() then
				return
			end
			if listed.status ~= "ok" then
				finish()
				if automatic then
					-- The app just answered; the next attempt will tell.
					return
				end
				-- Without Sandblock Code there is nothing to sync with: it is the
				-- one serving Rojo.
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
				refused()
				applySelection(nil)
				panel.App.SetProject(
					nil,
					nil,
					"That project is no longer registered in Sandblock Code. Choose another one."
				)
				return
			end

			local copy = copyFor(runtimeId)
			if superseded() then
				return
			end
			local placeState = applySelection(runtime, copy)
			if placeState == "mismatch" then
				-- Refusing before anything starts keeps a sync from writing this
				-- project's tree into a place nobody declared.
				refused()
				return
			end

			local started = Runtime.start(settings.RuntimeBaseUrl, runtimeId, copy and copy.key)
			if superseded() then
				return
			end
			if started.status ~= "ok" then
				if started.status ~= "unreachable" then
					refused()
				elseif automatic then
					finish()
					return
				else
					finish()
				end
				panel.App.SetProject(runtime, placeState, started.message, heldPlace)
				return
			end

			-- The session of the place this Studio has open, never the
			-- project's main one: a lobby and a game can sync different trees.
			local descriptor = started.runtime
			local rojo = started.rojo
			rojoUrl = rojo and rojo.url or nil
			rojoProjectFile = started.projectFile
			if rojoUrl == nil then
				refused()
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
			print(
				string.format(
					"[Sandblock] %s serving %s on %s",
					tostring(descriptor.displayName),
					tostring(rojoProjectFile),
					rojoUrl
				)
			)
			setRunning(true)
			setRojoRunning(true)
		end)
	end

	function selectRuntime(runtime: any)
		if destroyed or runtime == nil then
			return
		end
		-- Choosing a project is connecting by hand, and it replaces whatever
		-- this Studio was connected or connecting to.
		autoConnectStopped = false
		if running or rojoRunning or connecting then
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
			connectGeneration += 1
			panel.App.SetBusy(false)
			rojoUrl = nil
			rojoProjectFile = nil
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

	-- Automatic connection. Sandblock Code decides whether this Studio connects
	-- — a copy it opened, a place it launched moments ago, or a place exactly
	-- one open project declares with automatic connection on — and the plugin
	-- only follows the answer, through the same connect as the button and its
	-- PlaceId checks. It asks when Studio loads and every few seconds while
	-- nothing is connected, never from a playtest's DataModels, and stops for
	-- the session once the person disconnects by hand. An app that does not
	-- answer is not an error: it may simply not be open yet.
	local function autoConnect()
		if destroyed or autoConnectStopped or connecting or running or rojoRunning or not RunService:IsEdit() then
			return
		end
		local answer = Runtime.hello(settings.RuntimeBaseUrl)
		if destroyed or autoConnectStopped or connecting or running or rojoRunning or answer.status ~= "ok" then
			return
		end
		knownCopy = if answer.copy ~= nil then { runtimeId = answer.runtimeId, copy = answer.copy } else nil
		if answer.connect ~= true then
			return
		end
		print(string.format("[Sandblock] Sandblock Code connects this Studio (%s)", tostring(answer.reason)))
		connectTo(answer.runtimeId, true)
	end

	task.spawn(function()
		while not destroyed do
			autoConnect()
			task.wait(Config.AutoConnectInterval)
		end
	end)

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
