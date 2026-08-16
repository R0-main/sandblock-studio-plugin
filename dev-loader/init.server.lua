-- One-time installed development bootstrap. The real plugin source lives in
-- ReplicatedStorage.SandblockStudioPlugin and is hot-reloaded by Loader.

local Loader = require(script.Loader)
local session = Loader.start(plugin)

plugin.Unloading:Connect(function()
	session.Destroy()
end)
