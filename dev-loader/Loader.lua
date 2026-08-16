--!strict

-- Development-only plugin loader.
--
-- Rojo syncs the real plugin tree into ReplicatedStorage. Every source change
-- is cloned before require(), so Roblox cannot return a stale ModuleScript from
-- its require cache. Only this small loader needs a real Plugin context.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SOURCE_NAME = "SandblockStudioPlugin"
local RELOAD_DELAY = 0.2
local PLUGIN_ICON = "rbxassetid://82545901411321"

local Loader = {}

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function Loader.start(pluginObject: Plugin)
	-- Studio reserves toolbar, button, and widget IDs for the lifetime of a
	-- Plugin. Keep this shell stable and only hot-swap its mounted application.
	local toolbar = pluginObject:CreateToolbar("Sandblock")
	local button = toolbar:CreateButton("Sandblock", "Open Sandblock Studio", PLUGIN_ICON)
	button.ClickableWhenViewportHidden = true
	local widgetInfo = DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Right,
		false,
		false,
		380,
		620,
		300,
		360
	)
	local widget = pluginObject:CreateDockWidgetPluginGui("SandblockStudio", widgetInfo)
	widget.Name = "SandblockStudio"
	widget.Title = "Sandblock Studio"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local host = {
		Toolbar = toolbar,
		Button = button,
		Widget = widget,
	}

	local destroyed = false
	local revision = 0
	local scheduledRevision = 0
	local watchedSource: Instance? = nil
	local activeClone: Instance? = nil
	local activeSession: any = nil
	local rootConnections: { RBXScriptConnection } = {}
	local sourceConnections: { RBXScriptConnection } = {}

	local function destroyActive()
		if activeSession then
			local session = activeSession
			activeSession = nil
			local ok, err = pcall(session.Destroy)
			if not ok then
				warn("[Sandblock Dev] cleanup failed: " .. tostring(err))
			end
		end
		if activeClone then
			activeClone:Destroy()
			activeClone = nil
		end
	end

	local scheduleReload
	local bindSource

	local function performReload()
		if destroyed then
			return
		end

		local source = ReplicatedStorage:FindFirstChild(SOURCE_NAME)
		if source ~= watchedSource then
			bindSource(source)
		end

		destroyActive()
		if not source then
			warn("[Sandblock Dev] waiting for ReplicatedStorage." .. SOURCE_NAME)
			return
		end

		revision += 1
		local clone = source:Clone()
		clone.Name = "_SandblockStudioRuntime_" .. tostring(revision)
		clone.Parent = ServerStorage
		activeClone = clone

		local mainModule = clone:FindFirstChild("Main")
		if not mainModule or not mainModule:IsA("ModuleScript") then
			warn("[Sandblock Dev] synced tree has no Main ModuleScript")
			return
		end

		local required, mainOrError = pcall(require, mainModule)
		if not required then
			warn("[Sandblock Dev] require failed: " .. tostring(mainOrError))
			return
		end
		if type(mainOrError) ~= "table" or type(mainOrError.start) ~= "function" then
			warn("[Sandblock Dev] Main must return a table with start(plugin)")
			return
		end

		local started, sessionOrError = pcall(mainOrError.start, pluginObject, {
			Host = host,
		})
		if not started then
			warn("[Sandblock Dev] startup failed: " .. tostring(sessionOrError))
			return
		end
		activeSession = sessionOrError
		source:SetAttribute("HotReloadRevision", revision)
		source:SetAttribute("HotReloadState", "Ready")
		print("[Sandblock Dev] hot reload " .. tostring(revision) .. " ready")
	end

	function scheduleReload(reason: string?)
		if destroyed then
			return
		end
		scheduledRevision += 1
		local scheduled = scheduledRevision
		task.delay(RELOAD_DELAY, function()
			if destroyed or scheduled ~= scheduledRevision then
				return
			end
			if reason then
				print("[Sandblock Dev] reloading after " .. reason)
			end
			performReload()
		end)
	end

	local function watchLuaSource(instance: Instance)
		if not instance:IsA("LuaSourceContainer") then
			return
		end
		table.insert(sourceConnections, instance:GetPropertyChangedSignal("Source"):Connect(function()
			scheduleReload(instance:GetFullName())
		end))
	end

	function bindSource(source: Instance?)
		disconnectAll(sourceConnections)
		watchedSource = source
		if not source then
			return
		end

		watchLuaSource(source)
		for _, descendant in source:GetDescendants() do
			watchLuaSource(descendant)
		end
		table.insert(sourceConnections, source.DescendantAdded:Connect(function(descendant)
			watchLuaSource(descendant)
			scheduleReload("instance added")
		end))
		table.insert(sourceConnections, source.DescendantRemoving:Connect(function()
			scheduleReload("instance removed")
		end))
	end

	table.insert(rootConnections, ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == SOURCE_NAME then
			bindSource(child)
			scheduleReload("source tree added")
		end
	end))
	table.insert(rootConnections, ReplicatedStorage.ChildRemoved:Connect(function(child)
		if child == watchedSource then
			bindSource(nil)
			scheduleReload("source tree removed")
		end
	end))

	bindSource(ReplicatedStorage:FindFirstChild(SOURCE_NAME))
	scheduleReload("loader startup")

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		scheduledRevision += 1
		disconnectAll(sourceConnections)
		disconnectAll(rootConnections)
		destroyActive()
		widget:Destroy()
		toolbar:Destroy()
	end

	return {
		Destroy = destroy,
		Reload = function()
			scheduledRevision += 1
			performReload()
		end,
	}
end

return Loader
