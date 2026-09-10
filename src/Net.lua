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
	return decoded and decoded.message or "another Studio is already connected to this place"
end

-- Claims this Studio's place on the bridge, without waiting for a long-poll
-- response.
--
-- The claim carries the project binding this plugin has just validated: which
-- place this Studio holds, and every place the project declares. Only Sandblock
-- Code knows a project's config, so the bridge learns the allowlist here — and
-- an agent can then switch between those places and no others.
--
-- Returns (status, message) where status is "ok", "unreachable", or "busy".
function Net.claim(baseUrl: string, clientId: string, claim: any): (string, string?)
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = clientUrl(baseUrl, "/claim", clientId),
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(claim or {}),
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

-- Long-polls for the next command addressed to this Studio's place.
-- Returns (status, command, message) where status is one of:
--   "ok"          -- command may be nil (the poll simply timed out)
--   "unreachable" -- server down or errored; back off and retry
--   "busy"        -- another Studio holds this place; message explains it
--   "reclaim"     -- the bridge forgot us (restart, or a timed-out session)
function Net.poll(baseUrl: string, clientId: string): (string, any, string?)
	-- Report the place name so the gateway can pick the right Studio upstream,
	-- and our session id so the bridge can route this place's commands to us.
	local ok, response = pcall(function()
		return HttpService:RequestAsync({ Url = clientUrl(baseUrl, "/poll", clientId), Method = "GET" })
	end)
	if not ok then
		return "unreachable", nil, nil
	end
	if response.StatusCode == 409 then
		local decoded
		pcall(function()
			decoded = HttpService:JSONDecode(response.Body)
		end)
		if decoded and decoded.error == "reclaim_required" then
			return "reclaim", nil, nil
		end
		return "busy", nil, busyMessage(response)
	end
	if not response.Success then
		return "unreachable", nil, nil
	end
	local decoded = HttpService:JSONDecode(response.Body)
	return "ok", decoded.command, nil
end

-- Gives up this Studio's place so it can be reconnected right away.
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
