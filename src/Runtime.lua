--!strict
-- Client for Sandblock Code's local runtime service.
--
-- The plugin never knows a repository path. It asks the desktop app which
-- projects are approved, then asks it to serve one; the app answers with the
-- loopback URL its own Rojo process is listening on.

local HttpService = game:GetService("HttpService")

local Runtime = {}

-- A browser cannot add this header to a cross-origin request without a
-- preflight the service refuses, so a random page cannot enumerate the
-- developer's projects or spawn servers. Studio's HttpService can.
local HEADERS = { ["X-Sandblock-Runtime"] = "1", ["Content-Type"] = "application/json" }

type Result = {
	status: string, -- "ok" | "unreachable" | "error"
	runtimes: { any }?,
	runtime: any?,
	message: string?,
}

local function decode(body: string?): any
	if type(body) ~= "string" or body == "" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	return ok and decoded or nil
end

local function requestJson(url: string, method: string, body: any?): Result
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = method,
			Headers = HEADERS,
			Body = if body ~= nil then HttpService:JSONEncode(body) else nil,
		})
	end)
	if not ok then
		return {
			status = "unreachable",
			message = "Sandblock Code is not answering. Open the app, or check the runtime URL in Settings.",
		}
	end
	local decoded = decode(response.Body)
	if not response.Success then
		return {
			status = "error",
			message = (decoded and decoded.message)
				or string.format("Runtime service replied %d.", response.StatusCode),
		}
	end
	return { status = "ok", runtimes = decoded and decoded.runtimes, runtime = decoded and decoded.runtime }
end

-- Lists the projects registered in Sandblock Code, most relevant first.
function Runtime.list(baseUrl: string): Result
	local result = requestJson(baseUrl .. "/runtimes", "GET")
	if result.status == "ok" and type(result.runtimes) ~= "table" then
		return { status = "error", message = "Sandblock Code returned an unexpected runtime list." }
	end
	return result
end

-- Asks Sandblock Code to serve a project with the pinned Rojo build.
function Runtime.start(baseUrl: string, runtimeId: string): Result
	local url = baseUrl .. "/runtimes/" .. HttpService:UrlEncode(runtimeId) .. "/start"
	local result = requestJson(url, "POST")
	if result.status == "ok" and type(result.runtime) ~= "table" then
		return { status = "error", message = "Sandblock Code did not return a runtime descriptor." }
	end
	return result
end

-- Stops the project's Rojo server again.
function Runtime.stop(baseUrl: string, runtimeId: string): Result
	return requestJson(baseUrl .. "/runtimes/" .. HttpService:UrlEncode(runtimeId) .. "/stop", "POST")
end

-- Reports what Studio just did with this runtime so Sandblock Code can show a
-- sync history beside its tool history. Failing to report is never worth
-- interrupting a sync over, so the result is returned but usually ignored.
function Runtime.report(baseUrl: string, runtimeId: string, event: any): Result
	local payload = table.clone(event)
	payload.place = game.Name
	payload.placeId = game.PlaceId
	return requestJson(baseUrl .. "/runtimes/" .. HttpService:UrlEncode(runtimeId) .. "/events", "POST", payload)
end

-- The places a project declares, newest contract first.
--
-- A project written before places existed carries only `mainPlaceId`; reading
-- it back as a single main place is exactly how that project behaved.
local function declaredPlaces(runtime: any): { any }
	local places = runtime and runtime.places
	if type(places) == "table" and #places > 0 then
		return places
	end
	local main = tonumber(runtime and runtime.mainPlaceId)
	if main == nil then
		return {}
	end
	return { { key = "main", name = tostring(runtime.displayName), placeId = main, main = true } }
end

Runtime.declaredPlaces = declaredPlaces

-- Names the declared places, for a message that has to say what *is* allowed.
local function placeSummary(places: { any }): string
	local names = {}
	for _, place in places do
		table.insert(names, string.format("%s (%s)", tostring(place.name), tostring(place.placeId)))
	end
	return table.concat(names, ", ")
end

-- Matches this Studio place against the ones the project declares.
--
-- The declared list is an allowlist: connecting from a place that is not in it
-- would let an agent edit a place nobody approved, so the plugin refuses rather
-- than connecting and hoping.
--
-- Returns (state, place, message) where state is "verified", "unbound" or
-- "mismatch", and `place` is the matched declaration when verified.
function Runtime.resolvePlace(runtime: any): (string, any?, string?)
	local places = declaredPlaces(runtime)
	local current = game.PlaceId
	if #places == 0 then
		return "unbound",
			nil,
			"No place is declared for this project yet. Declare its Roblox places in Sandblock Code to enable validation."
	end
	if current == 0 then
		return "unbound", nil, "This place has never been published, so Studio reports no PlaceId to validate."
	end
	for _, place in places do
		if tonumber(place.placeId) == current then
			return "verified", place, nil
		end
	end
	return "mismatch",
		nil,
		string.format(
			"This Studio place (%d) is not one of %s's declared places: %s. Open a declared place, or add this one in Sandblock Code.",
			current,
			tostring(runtime.displayName),
			placeSummary(places)
		)
end

return Runtime
