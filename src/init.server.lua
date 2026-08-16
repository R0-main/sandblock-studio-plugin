-- Production plugin entry point. Development uses dev-loader/Loader.lua to
-- start the same Main module from a fresh ReplicatedStorage clone.

local Main = require(script.Main)
local session = Main.start(plugin)

plugin.Unloading:Connect(function()
	session.Destroy()
end)
