-- Registry mapping MCP tool names to their handler functions.
-- Add a new tool: create a module in this folder and wire it here.
local Packages = require(script.Packages)

return {
	get_selection = require(script.GetSelection),
	insert_instance = require(script.InsertInstance),
	render_gui_element = require(script.RenderGuiElement),
	view_raw_workspace = require(script.ViewRawWorkspace),
	capture_turntable = require(script.CaptureTurntable),
	get_model_icon = require(script.GetModelIcon),
	-- Steps of the gateway's package tools (transfer_model_between_places and
	-- the package lifecycle tools); the gateway sequences them.
	package_inspect_source = Packages.package_inspect_source,
	package_inspect_destination = Packages.package_inspect_destination,
	package_publish = Packages.package_publish,
	package_insert = Packages.package_insert,
	package_clone_local = Packages.package_clone_local,
	package_update_copy = Packages.package_update_copy,
}
