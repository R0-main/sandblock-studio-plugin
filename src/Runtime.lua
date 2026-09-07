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

-- Describes how this Studio place relates to a runtime's configured place.
-- Returns (state, message) where state is "verified", "unbound" or "mismatch".
function Runtime.checkPlace(runtime: any): (string, string?)
	local expected = tonumber(runtime and runtime.mainPlaceId)
	local current = game.PlaceId
	if expected == nil then
		return "unbound",
			"No main place is bound to this project yet. Bind this Studio place from Sandblock Code to enable validation."
	end
	if current == 0 then
		return "unbound", "This place has never been published, so Studio reports no PlaceId to validate."
	end
	if expected ~= current then
		return "mismatch",
			string.format(
				"This Studio place (%d) is not %s's main place (%d). Open the project's place, or rebind it in Sandblock Code.",
				current,
				tostring(runtime.displayName),
				expected
			)
	end
	return "verified", nil
end

return Runtime
