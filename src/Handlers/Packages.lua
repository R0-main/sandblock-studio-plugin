-- Studio side of moving models between places through Roblox packages.
--
-- The gateway orchestrates (docs/CROSS_PLACE_MODEL_TRANSFER.md at the
-- workspace root): it decides the order, owns the publication queue, retries
-- and idempotency, and sends each step here as its own command. Each handler
-- does one Studio-side step and answers `{ ok = true, ... }`, or
-- `{ ok = false, code, message, retryable }` for a refusal the agent can act on.
--
-- Every command carries the PlaceId the gateway resolved, and nothing is read
-- or changed in a Studio holding another place.
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local AssetService = game:GetService("AssetService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Util = require(script.Parent.Parent.Util)
local RojoState = require(script.Parent.Parent.RojoState)

-- Must match TRANSFER_PACKAGE_NAME in sandblock-code/src/packages.ts.
local TRANSFER_NAME = "SandblockTransferPackage"
local PAYLOAD_NAME = "Payload"
local TRANSFER_ID_ATTRIBUTE = "SandblockTransferId"
-- The documented ceiling of a model upload.
local MAX_UPLOAD_BYTES = 20 * 1024 * 1024
-- How long to wait for Roblox to list the version just published.
local VERSION_LOOKUP_ATTEMPTS = 10

-- A refusal travels as an error table so the steps below stay linear;
-- `handler` turns it back into a reply.
local function refuse(code: string, message: string, retryable: boolean?)
	error({ packageRefusal = true, code = code, message = message, retryable = retryable == true }, 0)
end

local function handler(step: (args: any) -> any): (args: any) -> any
	return function(args: any): any
		local ok, result = pcall(step, args or {})
		if ok then
			result.ok = true
			return result
		end
		if type(result) == "table" and result.packageRefusal then
			return { ok = false, code = result.code, message = result.message, retryable = result.retryable }
		end
		return { ok = false, code = "studio_error", message = tostring(result), retryable = false }
	end
end

local function assertPlace(args: any)
	local expected = tonumber(args.expectedPlaceId)
	if expected == nil or game.PlaceId ~= expected then
		refuse(
			"place_mismatch",
			string.format(
				"This Studio has place %d open, not place %s. Nothing was changed.",
				game.PlaceId,
				tostring(args.expectedPlaceId)
			)
		)
	end
end

local function creatorOf(): { type: string, id: number }
	if game.CreatorId <= 0 then
		refuse("place_not_published", "This place has no Roblox owner yet. Publish it before moving models.")
	end
	return {
		type = if game.CreatorType == Enum.CreatorType.Group then "Group" else "User",
		id = game.CreatorId,
	}
end

local function resolveModel(path: any): Instance
	if type(path) ~= "string" or path == "" then
		refuse("invalid_arguments", "modelPath must be a full instance path, e.g. 'Workspace.Map.House'.")
	end
	local instance = Util.resolvePath(path)
	if not instance then
		refuse("model_not_found", "No instance at " .. path .. " in this place.")
	end
	local model = instance :: Instance
	if model == game or model.Parent == game then
		refuse("invalid_model", path .. " is a service; move the model inside it instead.")
	end
	if not model.Archivable then
		refuse("invalid_model", path .. " has Archivable off, so Roblox cannot copy it.")
	end
	return model
end

local function resolveDestination(path: any): Instance
	if type(path) ~= "string" or path == "" then
		refuse("invalid_arguments", "destinationPath must be a full instance path, e.g. 'Workspace.Map'.")
	end
	local destination = Util.resolvePath(path)
	if not destination or destination == game then
		refuse("destination_not_found", "No instance at " .. tostring(path) .. " in this place.")
	end
	return destination :: Instance
end

-- Rojo's own metadata for one synced instance: whether the next sync keeps
-- children Rojo does not know about.
local function readRojoMetadata(baseUrl: string, id: string): any
	local ok, body = pcall(function()
		return HttpService:GetAsync(baseUrl .. "/api/read/" .. id, true)
	end)
	if not ok then
		refuse(
			"rojo_metadata_unavailable",
			"Could not ask Rojo whether the destination is synced from files: " .. tostring(body),
			true
		)
	end
	local decoded = HttpService:JSONDecode(body)
	local entry = decoded and decoded.instances and decoded.instances[id]
	if not entry then
		refuse("rojo_metadata_unavailable", "Rojo did not describe the synced instance above the destination.", true)
	end
	return entry.Metadata or {}
end

-- Refuses a destination whose new children the next Rojo sync would delete.
--
-- The nearest synced instance at or above the destination decides it: when
-- Rojo ignores unknown children there (a project node without `$path`, such
-- as most services), an inserted model survives; under a `$path` tree it would
-- be removed, so nothing is inserted at all.
local function checkRojo(destination: Instance, rojoProject: any): any
	local state = RojoState.get()
	if state == nil then
		if type(rojoProject) == "string" then
			refuse(
				"rojo_not_connected",
				string.format(
					"This place syncs %s with Rojo, but Rojo is not connected in this Studio, so nobody can tell whether %s would be overwritten. Connect the place from the Sandblock panel and retry.",
					rojoProject,
					destination:GetFullName()
				)
			)
		end
		return { synced = false }
	end
	local current: Instance? = destination
	while current and current ~= game do
		local id = state.instanceMap.fromInstances[current]
		if id ~= nil then
			local metadata = readRojoMetadata(state.baseUrl, id)
			if metadata.ignoreUnknownInstances ~= true then
				refuse(
					"rojo_owned_destination",
					string.format(
						"%s is synced from files by Rojo, which would delete anything inserted under %s on the next sync. Choose a destination outside the Rojo tree, or add the model to the project files instead.",
						current:GetFullName(),
						destination:GetFullName()
					)
				)
			end
			return { synced = true, syncedAncestor = current:GetFullName() }
		end
		current = current.Parent
	end
	return { synced = true }
end

local function countDescendants(instance: Instance): number
	return #instance:GetDescendants() + 1
end

-- Refuses a model over the upload limit before anything is sent. A Studio
-- without SerializationService skips the check and lets Roblox refuse it.
local function checkSize(object: Instance)
	local ok, serialized = pcall(function()
		return game:GetService("SerializationService"):SerializeInstancesAsync({ object })
	end)
	if ok and typeof(serialized) == "buffer" and buffer.len(serialized) > MAX_UPLOAD_BYTES then
		refuse(
			"package_too_large",
			string.format("The model is %.1f MB; Roblox accepts at most 20 MB.", buffer.len(serialized) / 1024 / 1024)
		)
	end
end

local function packageIdOf(link: Instance): number?
	local ok, value = pcall(function()
		return (link :: any).PackageId
	end)
	if not ok then
		return nil
	end
	return tonumber(string.match(tostring(value), "(%d+)%s*$"))
end

-- Runs `change` as one undoable Studio step.
local function recorded(name: string, change: () -> any): any
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, result = pcall(change)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		error(result, 0)
	end
	return result
end

local function classifyPublishError(message: string)
	local lower = string.lower(message)
	if
		string.find(lower, "429")
		or string.find(lower, "throttl")
		or string.find(lower, "too many")
		or string.find(lower, "rate limit")
	then
		refuse("package_publish_throttled", "Roblox throttled the upload: " .. message, true)
	elseif string.find(lower, "moderat") then
		refuse("package_moderated", "Roblox moderation refused the upload: " .. message)
	elseif
		string.find(lower, "timeout")
		or string.find(lower, "timed out")
		or string.find(lower, "503")
		or string.find(lower, "502")
		or string.find(lower, "500")
	then
		refuse("package_service_unavailable", "Roblox did not complete the upload: " .. message, true)
	end
	refuse("package_publish_failed", "Roblox refused the upload: " .. message)
end

local function checkPublishResult(result: any)
	if result == Enum.CreateAssetResult.Success then
		return
	end
	local name = if typeof(result) == "EnumItem" then result.Name else tostring(result)
	if name == "PermissionDenied" then
		refuse(
			"package_permission_denied",
			"Roblox refused the upload: the creator does not allow this account to publish it."
		)
	elseif name == "UploadFailed" then
		refuse("package_upload_failed", "Roblox could not store the upload.", true)
	end
	refuse("package_publish_failed", "Roblox refused the upload (" .. name .. ").", true)
end

local function latestVersionId(assetId: number): number?
	local ok, id = pcall(function()
		return InsertService:GetLatestAssetVersionAsync(assetId)
	end)
	if ok and type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

-- The asset version Roblox lists once the upload lands. The gateway holds the
-- owner's publication lock meanwhile, so no other Sandblock publication of
-- this asset can come in between; the destination verifies the transfer id
-- anyway.
local function awaitNewVersion(assetId: number, previous: number?): number?
	for _ = 1, VERSION_LOOKUP_ATTEMPTS do
		local latest = latestVersionId(assetId)
		if latest ~= nil and latest ~= previous then
			return latest
		end
		task.wait(1)
	end
	return nil
end

local Packages = {}

Packages.package_inspect_source = handler(function(args)
	assertPlace(args)
	local model = resolveModel(args.modelPath)
	return {
		creator = creatorOf(),
		universeId = game.GameId,
		name = model.Name,
		className = model.ClassName,
		descendantCount = countDescendants(model),
	}
end)

Packages.package_inspect_destination = handler(function(args)
	assertPlace(args)
	local destination = resolveDestination(args.destinationPath)
	return {
		creator = creatorOf(),
		universeId = game.GameId,
		destination = destination:GetFullName(),
		rojo = checkRojo(destination, args.rojoProject),
	}
end)

-- Publishes the model: as the next version of the universe's transfer shuttle
-- (`transfer`), as a new permanent package (`dedicated`), or as the next
-- version of a package the agent named (`version`).
Packages.package_publish = handler(function(args)
	assertPlace(args)
	local model = resolveModel(args.modelPath)
	local creator = creatorOf()
	local mode = args.mode
	if mode ~= "transfer" and mode ~= "dedicated" and mode ~= "version" then
		refuse("invalid_arguments", "Unknown publication mode " .. tostring(mode) .. ".")
	end
	local assetId = tonumber(args.assetId)
	if mode == "version" and assetId == nil then
		refuse("invalid_arguments", "Publishing a version needs the package's asset id.")
	end

	local copy = model:Clone()
	local object: Instance
	if mode == "transfer" then
		if type(args.transferId) ~= "string" then
			refuse("invalid_arguments", "A transfer needs its transfer id.")
		end
		-- Each version is one snapshot: the envelope, its id, and one payload.
		local envelope = Instance.new("Model")
		envelope.Name = TRANSFER_NAME
		envelope:SetAttribute(TRANSFER_ID_ATTRIBUTE, args.transferId)
		envelope:SetAttribute("SandblockSourcePlaceId", game.PlaceId)
		local payload = Instance.new("Folder")
		payload.Name = PAYLOAD_NAME
		payload.Parent = envelope
		copy.Parent = payload
		object = envelope
	else
		object = copy
	end

	local ok, published = pcall(function()
		checkSize(object)
		local creatorType = if creator.type == "Group" then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User
		if assetId == nil then
			local name = if type(args.name) == "string" and args.name ~= "" then args.name else model.Name
			local result, newId = AssetService:CreateAssetAsync(object, Enum.AssetType.Model, {
				Name = name,
				Description = if type(args.description) == "string" then args.description else "",
				CreatorId = creator.id,
				CreatorType = creatorType,
				IsPackage = mode == "dedicated",
			})
			checkPublishResult(result)
			return { assetId = newId, versionNumber = 1, assetVersionId = awaitNewVersion(newId, nil), created = true }
		end
		local previous = latestVersionId(assetId)
		local result, versionNumber = AssetService:CreateAssetVersionAsync(object, Enum.AssetType.Model, assetId, {
			CreatorId = creator.id,
			CreatorType = creatorType,
		})
		checkPublishResult(result)
		return {
			assetId = assetId,
			versionNumber = versionNumber,
			assetVersionId = awaitNewVersion(assetId, previous),
			created = false,
		}
	end)
	object:Destroy()
	if not ok then
		if type(published) == "table" and published.packageRefusal then
			error(published, 0)
		end
		classifyPublishError(tostring(published))
	end
	return published
end)

local function loadContainer(assetId: number?, assetVersionId: number?): Instance
	local ok, container = pcall(function()
		if assetVersionId ~= nil then
			return InsertService:LoadAssetVersion(assetVersionId)
		end
		return InsertService:LoadAsset(assetId :: number)
	end)
	if not ok or container == nil then
		refuse(
			"package_load_failed",
			string.format(
				"Roblox did not load asset %s%s: %s",
				tostring(assetId),
				if assetVersionId then " version " .. tostring(assetVersionId) else "",
				tostring(container)
			),
			true
		)
	end
	return container
end

-- Takes the transferred model out of the shuttle, and refuses a version that
-- is not the one this transfer published.
local function extractPayload(container: Instance, transferId: any): Instance
	local envelope = container:FindFirstChild(TRANSFER_NAME)
	if not envelope or envelope:GetAttribute(TRANSFER_ID_ATTRIBUTE) ~= transferId then
		refuse(
			"transfer_version_mismatch",
			"The loaded version of the transfer package does not carry this transfer. Nothing was inserted."
		)
	end
	local payload = (envelope :: Instance):FindFirstChild(PAYLOAD_NAME)
	local roots = if payload then payload:GetChildren() else {}
	if #roots ~= 1 then
		refuse("transfer_version_mismatch", "The transfer package version holds no single model. Nothing was inserted.")
	end
	return roots[1]
end

Packages.package_insert = handler(function(args)
	assertPlace(args)
	local destination = resolveDestination(args.destinationPath)
	checkRojo(destination, args.rojoProject)
	local assetId = tonumber(args.assetId)
	local assetVersionId = tonumber(args.assetVersionId)
	if assetId == nil then
		refuse("invalid_arguments", "Inserting a package needs its asset id.")
	end

	local container = loadContainer(assetId, assetVersionId)
	local ok, result = pcall(function()
		local roots: { Instance }
		if args.extractPayload == true then
			local root = extractPayload(container, args.transferId)
			-- Detach: the copy keeps no link to the shuttle. A package the model
			-- itself was a copy of keeps its own link.
			for _, child in ipairs(root:GetChildren()) do
				if child:IsA("PackageLink") and packageIdOf(child) == assetId then
					child:Destroy()
				end
			end
			roots = { root }
		else
			roots = container:GetChildren()
			if #roots == 0 then
				refuse("package_load_failed", "The loaded package version is empty.")
			end
		end

		return recorded("Sandblock: insert package", function()
			local paths = {}
			for _, root in ipairs(roots) do
				root.Parent = destination
				table.insert(paths, root:GetFullName())
			end
			local first = roots[1]
			local link = first:FindFirstChildOfClass("PackageLink")
			return {
				insertedPath = paths[1],
				-- A package with several roots inserts them all.
				insertedPaths = if #paths > 1 then paths else nil,
				className = first.ClassName,
				remainsLinkedToPackage = link ~= nil,
				ownPackageId = if link then packageIdOf(link) else nil,
			}
		end)
	end)
	container:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end)

-- A source and destination in the same place: an ordinary clone.
Packages.package_clone_local = handler(function(args)
	assertPlace(args)
	local model = resolveModel(args.modelPath)
	local destination = resolveDestination(args.destinationPath)
	checkRojo(destination, args.rojoProject)
	return recorded("Sandblock: copy model", function()
		local copy = model:Clone()
		copy.Parent = destination
		return { insertedPath = copy:GetFullName(), className = copy.ClassName }
	end)
end)

-- Replaces one package copy with the package's latest version, in place.
Packages.package_update_copy = handler(function(args)
	assertPlace(args)
	if type(args.path) ~= "string" or args.path == "" then
		refuse("invalid_arguments", "path must be the full path of a package copy.")
	end
	local copy = Util.resolvePath(args.path)
	if not copy or copy == game or copy.Parent == game then
		refuse("model_not_found", "No package copy at " .. tostring(args.path) .. " in this place.")
	end
	local current = copy :: Instance
	local link = current:FindFirstChildOfClass("PackageLink")
	local packageId = if link then packageIdOf(link) else nil
	if packageId == nil then
		refuse("not_a_package_copy", current:GetFullName() .. " has no package link, so it is not a package copy.")
	end
	local parent = current.Parent :: Instance
	checkRojo(parent, args.rojoProject)

	local container = loadContainer(packageId, nil)
	local ok, result = pcall(function()
		local roots = container:GetChildren()
		if #roots ~= 1 then
			refuse("package_load_failed", "The latest package version does not hold a single root.")
		end
		local replacement = roots[1]
		return recorded("Sandblock: update package copy", function()
			replacement.Name = current.Name
			if replacement:IsA("PVInstance") and current:IsA("PVInstance") then
				(replacement :: PVInstance):PivotTo((current :: PVInstance):GetPivot())
			end
			replacement.Parent = parent
			-- Unparented rather than destroyed, so Studio's undo brings it back.
			current.Parent = nil
			local newLink = replacement:FindFirstChildOfClass("PackageLink")
			return {
				path = replacement:GetFullName(),
				packageId = packageId,
				remainsLinkedToPackage = newLink ~= nil,
			}
		end)
	end)
	container:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end)

return Packages
