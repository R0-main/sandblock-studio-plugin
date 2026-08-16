-- Roblox Studio bridge plugin (entry point).
--
-- Long-polls the local MCP server, dispatches each command to a handler, and
-- posts the result back. Build with Rojo (see README) and enable
-- "Allow HTTP Requests" in Game Settings > Security.

local HttpService = game:GetService("HttpService")

local Config = require(script.Config)
local Net = require(script.Net)
local Util = require(script.Util)
local Handlers = require(script.Handlers)

local toolbar = plugin:CreateToolbar("MCP Bridge")
local button = toolbar:CreateButton("Bridge", "Toggle the MCP bridge", "")
button.ClickableWhenViewportHidden = true

local running = false
-- Identifies this Studio session to the bridge, which only serves one plugin
-- at a time. Regenerated on every plugin load, so a reload reclaims the slot.
local clientId = HttpService:GenerateGUID(false)

local function execute(command: any)
	local handler = Handlers[command.tool]
	if not handler then
		Net.postResponse(command.id, false, "unknown tool: " .. tostring(command.tool))
		return
	end
	local ok, result = pcall(handler, command.args)
	if ok then
		Net.postResponse(command.id, true, Util.safeValue(result))
	else
		Net.postResponse(command.id, false, tostring(result))
	end
end

local setRunning

local function loop()
	while running do
		local status, command, message = Net.poll(clientId)
		if status == "busy" then
			-- The bridge serves a single Studio; refusing here keeps the two
			-- plugins from stealing each other's commands.
			warn("[MCP Bridge] " .. tostring(message) .. " Stop the bridge in the other Studio, then click Bridge again.")
			setRunning(false)
		elseif status == "unreachable" then
			task.wait(Config.ReconnectDelay)
		elseif command then
			execute(command)
		end
	end
end

function setRunning(value: boolean)
	running = value
	button:SetActive(value)
	if value then
		print("[MCP Bridge] connected to " .. Config.BaseUrl)
		task.spawn(loop)
	else
		Net.release(clientId)
		print("[MCP Bridge] stopped")
	end
end

button.Click:Connect(function()
	setRunning(not running)
end)

-- Deliberately does *not* auto-start: opening a place should not connect the
-- bridge (nor start polling the MCP server). Click the toolbar button to start.
button:SetActive(false)

plugin.Unloading:Connect(function()
	local wasRunning = running
	running = false
	if wasRunning then
		Net.release(clientId)
	end
end)
