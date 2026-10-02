--!strict
-- What handlers may know about this Studio's Rojo sync.
--
-- Main owns the session; it records here the instance map Rojo hands back after
-- every patch (the initial sync included) and clears it when the sync stops.
-- A handler that is about to add instances asks whether Rojo will remove them
-- again on the next sync.

local RojoState = {}

type State = {
	baseUrl: string,
	instanceMap: any,
}

local current: State? = nil

function RojoState.set(baseUrl: string, instanceMap: any)
	current = { baseUrl = baseUrl, instanceMap = instanceMap }
end

function RojoState.clear()
	current = nil
end

-- The live sync, or nil while Rojo is not connected in this Studio.
function RojoState.get(): State?
	return current
end

return RojoState
