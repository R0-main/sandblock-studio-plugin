--!strict

local TweenService = game:GetService("TweenService")

local Util = {}

function Util.create(className: string, properties: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	if properties then
		for property, value in properties do
			(instance :: any)[property] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	return instance
end

function Util.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Util.stroke(parent: Instance, color: Color3, transparency: number?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

function Util.padding(parent: Instance, horizontal: number, vertical: number?): UIPadding
	local y = vertical or horizontal
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, horizontal)
	padding.PaddingRight = UDim.new(0, horizontal)
	padding.PaddingTop = UDim.new(0, y)
	padding.PaddingBottom = UDim.new(0, y)
	padding.Parent = parent
	return padding
end

function Util.list(
	parent: Instance,
	direction: Enum.FillDirection,
	spacing: number,
	horizontalAlignment: Enum.HorizontalAlignment?,
	verticalAlignment: Enum.VerticalAlignment?
): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = verticalAlignment or Enum.VerticalAlignment.Top
	layout.Parent = parent
	return layout
end

function Util.tween(instance: Instance, properties: { [string]: any }, duration: number?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

function Util.bindButtonColors(
	button: GuiButton,
	normal: Color3,
	hover: Color3,
	pressed: Color3,
	isEnabled: (() -> boolean)?
)
	button.AutoButtonColor = false
	button.MouseEnter:Connect(function()
		if not isEnabled or isEnabled() then
			Util.tween(button, { BackgroundColor3 = hover })
		end
	end)
	button.MouseLeave:Connect(function()
		if not isEnabled or isEnabled() then
			Util.tween(button, { BackgroundColor3 = normal })
		end
	end)
	button.MouseButton1Down:Connect(function()
		if not isEnabled or isEnabled() then
			Util.tween(button, { BackgroundColor3 = pressed }, 0.06)
		end
	end)
	button.MouseButton1Up:Connect(function()
		if not isEnabled or isEnabled() then
			Util.tween(button, { BackgroundColor3 = hover }, 0.08)
		end
	end)
end

function Util.autoCanvas(scroller: ScrollingFrame, layout: UIListLayout, extra: number?)
	local function update()
		scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + (extra or 0))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	update()
end

function Util.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

-- Age of an event in the words Rojo's own panel uses, so the two plugins read
-- the same way to someone switching between them.
local AGE_STEPS = {
	{ seconds = 31556909, unit = "year" },
	{ seconds = 2629743, unit = "month" },
	{ seconds = 604800, unit = "week" },
	{ seconds = 86400, unit = "day" },
	{ seconds = 3600, unit = "hour" },
	{ seconds = 60, unit = "minute" },
}

function Util.elapsedText(elapsed: number): string
	if elapsed < 3 then
		return "just now"
	end
	for _, step in AGE_STEPS do
		if elapsed >= step.seconds then
			local count = math.floor(elapsed / step.seconds)
			return string.format("%d %s%s ago", count, step.unit, if count > 1 then "s" else "")
		end
	end
	return string.format("%d seconds ago", math.floor(elapsed))
end

return Util
