-- Creates an instance of `className` under `parent` (dotted path).
local Util = require(script.Parent.Parent.Util)

return function(args: any): any
	local className = args and args.className
	if type(className) ~= "string" then
		error("insert_instance requires a 'className' string")
	end
	local parent = Util.resolvePath(args.parent or "Workspace")
	if not parent then
		error("could not resolve parent path: " .. tostring(args.parent))
	end
	local inst = Instance.new(className)
	if args.name then
		inst.Name = args.name
	end
	inst.Parent = parent
	return { fullName = inst:GetFullName(), className = inst.ClassName }
end
