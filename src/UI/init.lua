--!strict

local App = require(script.App)

local UI = {}

function UI.create(plugin: Plugin, options: any?)
	options = options or {}
	local widget = options.Widget
	local ownsWidget = widget == nil
	if not widget then
		local widgetInfo = DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Right,
			false,
			false,
			380,
			620,
			300,
			360
		)
		widget = plugin:CreateDockWidgetPluginGui("SandblockStudio", widgetInfo)
		widget.Name = "SandblockStudio"
		widget.Title = "Sandblock Studio"
		widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end

	local app = App.mount(widget, options)

	return {
		Widget = widget,
		App = app,
		SetVisible = function(visible: boolean)
			widget.Enabled = visible
		end,
		Toggle = function()
			widget.Enabled = not widget.Enabled
		end,
		Destroy = function()
			app.Destroy()
			if ownsWidget then
				widget:Destroy()
			end
		end,
	}
end

return UI
