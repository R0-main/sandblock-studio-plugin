-- Shared plugin defaults. User overrides are stored through Plugin settings.
return {
	BaseUrl = "http://127.0.0.1:3070",
	RojoBaseUrl = "http://127.0.0.1:34872",
	SettingsKey = "SandblockStudio.ConnectionSettings.v1",
	DefaultSettings = {
		McpBaseUrl = "http://127.0.0.1:3070",
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
