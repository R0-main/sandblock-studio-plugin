-- Returns the instances currently selected in Studio.
local Selection = game:GetService("Selection")

return function(_args: any): any
	local out = {}
	for _, inst in ipairs(Selection:Get()) do
		table.insert(out, {
			fullName = inst:GetFullName(),
			className = inst.ClassName,
			name = inst.Name,
		})
	end
	return out
end
