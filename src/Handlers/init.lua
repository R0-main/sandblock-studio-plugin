-- Registry mapping MCP tool names to their handler functions.
-- Add a new tool: create a module in this folder and wire it here.
return {
	get_selection = require(script.GetSelection),
	insert_instance = require(script.InsertInstance),
	render_gui_element = require(script.RenderGuiElement),
	view_raw_workspace = require(script.ViewRawWorkspace),
	capture_turntable = require(script.CaptureTurntable),
	get_model_icon = require(script.GetModelIcon),
}
