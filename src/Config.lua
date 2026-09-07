-- Shared plugin defaults. User overrides are stored through Plugin settings.
return {
	BaseUrl = "http://127.0.0.1:3070",
	RojoBaseUrl = "http://127.0.0.1:34872",
	SettingsKey = "SandblockStudio.ConnectionSettings.v1",
	-- Remembers the approved runtime picked last time so reconnecting is one
	-- click. Only the opaque id is stored, never a repository path.
	RuntimeKey = "SandblockStudio.SelectedRuntime.v1",
	DefaultSettings = {
		McpBaseUrl = "http://127.0.0.1:3070",
		-- Sandblock Code's local runtime service: the only place this plugin
		-- learns which projects exist and which port serves one.
		RuntimeBaseUrl = "http://127.0.0.1:3071",
		-- Used only by the manual fallback, when the runtime service is not
		-- answering and a Rojo server is already running by other means.
		RojoBaseUrl = "http://127.0.0.1:34872",
		ReconnectDelay = 2,
		TwoWaySync = false,
		EnableSyncFallback = true,
		TypecheckingEnabled = true,
		OpenScriptsExternally = false,
		TimingLogsEnabled = false,
	},
	-- Uploaded from sandblock-code/build/icon.png for the Studio toolbar and UI.
	PluginIcon = "rbxassetid://82545901411321",
	-- Seconds to back off when the MCP server is unreachable.
	ReconnectDelay = 2,
}
