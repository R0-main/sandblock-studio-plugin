--!strict
-- Client for Sandblock Code's local runtime service.
--
-- The plugin never knows a repository path. It asks the desktop app which
-- projects are approved, then asks it to serve the place this Studio has open;
-- the app answers with the loopback route of the Rojo project that place syncs.

local HttpService = game:GetService("HttpService")

local Runtime = {}

-- A browser cannot add this header to a cross-origin request without a
-- preflight the service refuses, so a random page cannot enumerate the
-- developer's projects or spawn servers. Studio's HttpService can.
local HEADERS = { ["X-Sandblock-Runtime"] = "1", ["Content-Type"] = "application/json" }

-- The file name a Sandblock copy was opened from, kept on the DataModel.
--
-- Sandblock Code recognises a copy by the ticket in its file name, which Studio
-- uses as `game.Name` -- until Rojo's first sync renames the DataModel after its
-- project. Kept here, the name still identifies the copy afterwards: to the
-- service on a later hello, and in the fingerprint the gateway matches
-- against StudioMCP, where every copy would otherwise read `|0|<project name>`.
local COPY_FILE_ATTRIBUTE = "SandblockCopyFile"

function Runtime.copyFile(): string?
	local ok, value = pcall(game.GetAttribute, game, COPY_FILE_ATTRIBUTE)
	if ok and type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

type Result = {
	status: string, -- "ok" | "unreachable" | "error"
	runtimes: { any }?,
	runtime: any?,
	-- What `start` adds: the declared place this Studio matched, the Rojo
	-- project file it syncs, and that file's session.
	place: any?,
	projectFile: string?,
	rojo: any?,
	-- What `hello` adds: whether to connect, to which runtime, why, and the
	-- copy or scratch place descriptor when this Studio is one.
	connect: boolean?,
	runtimeId: string?,
	reason: string?,
	copy: any?,
	scratch: any?,
	-- The service's error code, e.g. "wrong_project" or "place_not_declared".
	code: string?,
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
			code = decoded and decoded.error,
			message = (decoded and decoded.message)
				or string.format("Runtime service replied %d.", response.StatusCode),
		}
	end
	return {
		status = "ok",
		runtimes = decoded and decoded.runtimes,
		runtime = decoded and decoded.runtime,
		place = decoded and decoded.place,
		projectFile = decoded and decoded.projectFile,
		rojo = decoded and decoded.rojo,
		connect = decoded and decoded.connect,
		runtimeId = decoded and decoded.runtimeId,
		reason = decoded and decoded.reason,
		copy = decoded and decoded.copy,
		scratch = decoded and decoded.scratch,
	}
end

-- A copy descriptor as Sandblock Code hands it out: `{ key, name, copyOf,
-- version }`. Anything else is not trusted as a copy.
local function readCopy(value: any): any?
	if type(value) ~= "table" or type(value.key) ~= "string" or value.key == "" then
		return nil
	end
	if type(value.copyOf) ~= "string" or value.copyOf == "" or type(value.version) ~= "number" then
		return nil
	end
	return {
		key = value.key,
		name = if type(value.name) == "string" and value.name ~= "" then value.name else value.key,
		copyOf = value.copyOf,
		version = value.version,
	}
end

-- A scratch place descriptor as Sandblock Code hands it out: `{ key, name }`.
-- A scratch place belongs to no project; its key is all that names it.
local function readScratch(value: any): any?
	if type(value) ~= "table" or type(value.key) ~= "string" or value.key == "" then
		return nil
	end
	return {
		key = value.key,
		name = if type(value.name) == "string" and value.name ~= "" then value.name else value.key,
	}
end

-- Lists the projects registered in Sandblock Code, most relevant first.
function Runtime.list(baseUrl: string): Result
	local result = requestJson(baseUrl .. "/runtimes", "GET")
	if result.status == "ok" and type(result.runtimes) ~= "table" then
		return { status = "error", message = "Sandblock Code returned an unexpected runtime list." }
	end
	return result
end

-- Asks Sandblock Code whether this Studio should connect, and to what.
--
-- Sandblock Code decides from the PlaceId and the place name: a copy or a
-- scratch place it opened (the ticket is in the file name, which Studio uses
-- as `game.Name`), a place it launched moments ago, or a place exactly one
-- open project declares. The plugin only follows the answer.
--
-- Returns a result whose `connect` is true with a `runtimeId` (and a `copy`
-- when `reason` is "copy", a `scratch` when it is "scratch"), or false. A
-- scratch place's `runtimeId` names no project: it is the bridge scope that
-- only Sandblock Code's scratch endpoint reaches.
function Runtime.hello(baseUrl: string): Result
	local placeName = Runtime.copyFile() or game.Name
	local result = requestJson(baseUrl .. "/studios/hello", "POST", { placeId = game.PlaceId, placeName = placeName })
	if result.status ~= "ok" then
		return result
	end
	if result.connect ~= true then
		return { status = "ok", connect = false, reason = result.reason }
	end
	local copy = if result.reason == "copy" then readCopy(result.copy) else nil
	local scratch = if result.reason == "scratch" then readScratch(result.scratch) else nil
	if
		type(result.runtimeId) ~= "string"
		or result.runtimeId == ""
		or (result.reason == "copy" and copy == nil)
		or (result.reason == "scratch" and scratch == nil)
	then
		return { status = "error", message = "Sandblock Code returned an unexpected connection answer." }
	end
	if copy ~= nil then
		pcall(game.SetAttribute, game, COPY_FILE_ATTRIBUTE, placeName)
	end
	return {
		status = "ok",
		connect = true,
		runtimeId = result.runtimeId,
		reason = result.reason,
		copy = copy,
		scratch = scratch,
	}
end

-- Asks Sandblock Code to serve the place this Studio has open, with the
-- pinned Rojo build.
--
-- The PlaceId is what picks the Rojo project: places of one experience can
-- each sync their own tree, and the app refuses a place the project does not
-- declare rather than handing it the main place's. A copy has no PlaceId of
-- its own, so it names itself with its copy key and syncs the tree of the
-- place it copies.
function Runtime.start(baseUrl: string, runtimeId: string, copyKey: string?): Result
	local url = baseUrl .. "/runtimes/" .. HttpService:UrlEncode(runtimeId) .. "/start"
	local result = requestJson(url, "POST", { placeId = game.PlaceId, copy = copyKey })
	if result.status == "ok" and (type(result.runtime) ~= "table" or type(result.rojo) ~= "table") then
		return { status = "error", message = "Sandblock Code did not return this place's Rojo session." }
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
-- A copy adds its copy key, since its PlaceId (0) names no place.
function Runtime.report(baseUrl: string, runtimeId: string, event: any, copyKey: string?): Result
	local payload = table.clone(event)
	payload.place = game.Name
	payload.placeId = game.PlaceId
	payload.copy = copyKey
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
-- A copy is checked the same way, by what it copies: Sandblock Code recognised
-- it, but it must still be a local file (PlaceId 0) of a place the project
-- declares.
--
-- Returns (state, place, message) where state is "verified", "copy",
-- "unbound" or "mismatch", and `place` is the matched declaration when
-- verified, or the copy as this Studio holds it.
function Runtime.resolvePlace(runtime: any, copy: any?): (string, any?, string?)
	local places = declaredPlaces(runtime)
	local current = game.PlaceId
	if copy ~= nil then
		if current ~= 0 then
			return "mismatch",
				nil,
				string.format(
					"This Studio has place %d open, so it cannot be a Sandblock copy. Reopen the copy from Sandblock Code.",
					current
				)
		end
		for _, place in places do
			if place.key == copy.copyOf then
				return "copy",
					{
						key = copy.key,
						name = copy.name,
						main = false,
						copyOf = copy.copyOf,
						version = copy.version,
						-- A copy syncs the Rojo project of the place it copies.
						projectFile = place.projectFile,
					},
					nil
			end
		end
		return "mismatch",
			nil,
			string.format(
				"This copy is of place %s, which is not one of %s's declared places: %s.",
				tostring(copy.copyOf),
				tostring(runtime.displayName),
				placeSummary(places)
			)
	end
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
