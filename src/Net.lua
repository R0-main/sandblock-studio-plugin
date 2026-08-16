-- Networking against the local MCP bridge.
local HttpService = game:GetService("HttpService")

local Net = {}

-- Identifies this Studio session in a way the *upstream* StudioMCP can also
-- read (via `execute_luau`), which is what lets the gateway pick the Studio our
-- plugin lives in when several are open. JobId alone is a per-session GUID but
-- is empty for a place that was never published, so we fall back on PlaceId and
-- the place name to keep the string as discriminating as possible.
local function fingerprint(): string
	return string.format("%s|%s|%s", game.JobId, tostring(game.PlaceId), game.Name)
end

local function clientUrl(baseUrl: string, path: string, clientId: string): string
	return baseUrl
		.. path
		.. "?client="
		.. HttpService:UrlEncode(clientId)
		.. "&place="
		.. HttpService:UrlEncode(game.Name)
		.. "&fp="
		.. HttpService:UrlEncode(fingerprint())
end

local function busyMessage(response: any): string
	local decoded
	pcall(function()
		decoded = HttpService:JSONDecode(response.Body)
	end)
	return decoded and decoded.message or "another Studio is already connected"
end

-- Claims the single Studio slot without waiting for a long-poll response.
-- Returns (status, message) where status is "ok", "unreachable", or "busy".
function Net.claim(baseUrl: string, clientId: string): (string, string?)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = clientUrl(baseUrl, "/claim", clientId),
			Method = "POST",
		})
	end)
	if not ok then
		return "unreachable", nil
	end
	if response.StatusCode == 409 then
		return "busy", busyMessage(response)
	end
	if not response.Success then
		return "unreachable", nil
	end
	return "ok", nil
end

-- Long-polls for the next command.
-- Returns (status, command, message) where status is one of:
--   "ok"          -- command may be nil (the poll simply timed out)
--   "unreachable" -- server down or errored; back off and retry
--   "busy"        -- another Studio holds the bridge; message explains it
function Net.poll(baseUrl: string, clientId: string): (string, any, string?)
	-- Report the place name so the gateway can pick the right Studio upstream,
	-- and our session id so the bridge can tell us apart from another Studio.
	local ok, response = pcall(function()
		return HttpService:RequestAsync({ Url = clientUrl(baseUrl, "/poll", clientId), Method = "GET" })
	end)
	if not ok then
		return "unreachable", nil, nil
	end
	if response.StatusCode == 409 then
		return "busy", nil, busyMessage(response)
	end
	if not response.Success then
		return "unreachable", nil, nil
	end
	local decoded = HttpService:JSONDecode(response.Body)
	return "ok", decoded.command, nil
end

-- Gives up the single plugin slot so another Studio can connect right away.
function Net.release(baseUrl: string, clientId: string)
	pcall(function()
		HttpService:RequestAsync({
			Url = baseUrl .. "/release?client=" .. HttpService:UrlEncode(clientId),
			Method = "POST",
		})
	end)
end

-- Posts a command's result back to the bridge.
function Net.postResponse(baseUrl: string, id: string, ok: boolean, payload: any)
	pcall(function()
		HttpService:RequestAsync({
			Url = baseUrl .. "/response",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ id = id, ok = ok, payload = payload }),
		})
	end)
end

return Net
