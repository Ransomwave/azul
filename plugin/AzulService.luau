--!strict
local AzulService = {}

local ScriptEditorService = game:GetService("ScriptEditorService")

-- Services

-- Modules
local CONFIG = require(script.Parent.Config)
local Enums = require(script.Parent.Enums)
local HttpService = game:GetService("HttpService")

-- Logging helpers
local function debugPrint(...)
	if CONFIG.SILENT_MODE or not CONFIG.DEBUG_MODE then return end
	print(`[🐛 AzulService]:`, ...)
end

local function infoPrint(...)
	if CONFIG.SILENT_MODE then return end
	print(`[AzulService]:`, ...)
end

local function isScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

--[=[
	Utility: Rebuild service set from config
	@param serviceSet { [string]: boolean } - The service set to rebuild
]=]
function AzulService.rebuildServiceSet(serviceSet)
	table.clear(serviceSet)
	for _, name in ipairs(CONFIG.SERVICE_LIST) do
		serviceSet[name] = true
	end
end

--- Utility: Clear all GUID attributes
--- This is for legacy support; we now use :GetDebugId() for stable GUIDs
function AzulService.clearAllGUIDAttributes()
	local guidAttributeName = plugin:GetSetting("GUID_ATTRIBUTE") or "AzulSyncGUID"

	for _, instance in game:GetDescendants() do
		if instance:GetAttribute(guidAttributeName) then instance:SetAttribute(guidAttributeName, nil) end
	end
	infoPrint("Cleared all legacy GUID attributes from instances.")
end

--- Utility: Check if instance should be excluded from sync
function AzulService.isExcluded(instance: Instance, serviceSet: { [string]: boolean })
	if not instance then return true end

	local fullName = instance:GetFullName()
	for _, ancestorName in CONFIG.EXCLUDED_PARENTS do
		if fullName:find(ancestorName) then return true end
	end

	-- Walk up to the service
	local current: Instance? = instance
	while current do
		if current.Parent == game then
			local inList = serviceSet[current.Name] ~= nil

			if CONFIG.LIST_TYPE == Enums.listType.WHITELIST then
				-- Whitelist: only allow services in the list
				-- debugPrint(`Included {instance} in whitelist`)
				return not inList
			else
				-- Blacklist: exclude services in the list
				-- debugPrint(`Excluded {instance} in blacklist`)
				return inList
			end
		end
		current = current.Parent
	end

	-- Not under DataModel
	return true
end

--- Utility: Get or create instance by path segments
function AzulService.getOrCreatePath(pathSegments: { string }): Instance
	local current: Instance = game
	for index, segment in ipairs(pathSegments) do
		local nextNode: Instance? = current:FindFirstChild(segment)

		if not nextNode then
			if index == 1 then
				local ok, service = pcall(function()
					return game:GetService(segment)
				end)
				if ok and service then nextNode = service end
			end

			if not nextNode then
				local newFolder = Instance.new("Folder")
				newFolder.Name = segment
				newFolder.Parent = current
				nextNode = newFolder
			end
		end

		current = nextNode :: Instance
	end

	return current
end

function AzulService.isProtectedRobloxContainer(instance: Instance?): boolean
	if not instance then return false end

	-- Top-level services cannot be destroyed or reparented
	local okService = pcall(function()
		return game:GetService(instance.Name)
	end)
	if instance.Parent == game and okService then return true end

	-- Certain StarterPlayer children are locked (StarterPlayerScripts, StarterCharacterScripts, StarterGear)
	local parent = instance.Parent
	if parent and parent.ClassName == "StarterPlayer" then
		local name = instance.Name
		if name == "StarterPlayerScripts" or name == "StarterCharacterScripts" or name == "StarterGear" then
			return true
		end
	end

	return false
end

--- Utility: Generate or retrieve GUID for instance (use Roblox debug IDs to avoid attribute churn)
function AzulService.getOrCreateGUID(
	instance,
	trackedInstances: { [Instance]: string },
	guidMap: { [string]: Instance },
	usedGuids: { [string]: boolean }
): string
	local cached = trackedInstances[instance]
	if cached then return cached end

	local guid = instance:GetDebugId(0)
	trackedInstances[instance] = guid
	guidMap[guid] = instance
	usedGuids[guid] = true
	return guid
end

--- Utility: Get instance path
function AzulService.getInstancePath(instance: Instance): { string }?
	local path = {}
	local current: Instance? = instance

	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	-- If current became nil, the instance is no longer under DataModel
	if current ~= game then return nil end

	return path
end

--- Convert instance to data format
function AzulService.instanceToData(
	instance,
	trackedInstances: { [Instance]: string },
	guidMap: { [string]: Instance },
	usedGuids: { [string]: boolean }
): { [string]: any }?
	local guid = AzulService.getOrCreateGUID(instance, trackedInstances, guidMap, usedGuids)
	local path = AzulService.getInstancePath(instance)
	if not path then return nil end

	local parentGuid: string? = nil
	local parent = instance.Parent
	if parent then
		if parent == game then
			parentGuid = "root"
		else
			parentGuid = AzulService.getOrCreateGUID(parent, trackedInstances, guidMap, usedGuids)
		end
	end

	local data: { [string]: any } = {
		guid = guid,
		className = instance.ClassName,
		name = instance.Name,
		path = path,
		parentGuid = parentGuid,
	}

	if isScript(instance) then data.source = (instance :: Script).Source end

	return data
end

-- Utility: set script source safely (handles large sources via ScriptEditorService)
function AzulService.setScriptSource(scriptInstance: Script | LocalScript | ModuleScript, source: string)
	local ok, err = pcall(function()
		if ScriptEditorService and ScriptEditorService.UpdateSourceAsync then
			ScriptEditorService:UpdateSourceAsync(scriptInstance, function(...)
				return source
			end)
		else
			(scriptInstance :: Script).Source = source
		end
	end)

	if not ok then warn("[AzulService]: Failed to set script source", err) end

	return ok
end

--- Create/update instance data with dedup tracking (returns data if changed, nil if duplicate)
function AzulService.instanceToDataDedup(
	instance: Instance,
	trackedInstances: { [Instance]: string },
	guidMap: { [string]: Instance },
	usedGuids: { [string]: boolean },
	lastInstanceUpdate: { [string]: { key: string, t: number } }
): { [string]: any }?
	local data = AzulService.instanceToData(instance, trackedInstances, guidMap, usedGuids)
	if not data then return nil end

	local guid = data.guid :: string
	local parentKey = (data.parentGuid :: string?) or ""
	local key = table.concat(data.path :: { string }, "/")
		.. "|"
		.. (data.className :: string)
		.. "|"
		.. (data.name :: string)
		.. "|"
		.. parentKey
	local now = tick()
	local last = lastInstanceUpdate[guid]
	if last and last.key == key and now - last.t < 0.05 then
		-- Ignore duplicate bursts from multiple property signals firing at once
		return nil
	end
	lastInstanceUpdate[guid] = { key = key, t = now }

	return data
end

--- Apply snapshot instances to the workspace
function AzulService.applySnapshotInstances(instances: { any }): number
	table.sort(instances, function(a, b)
		return #a.path < #b.path
	end)

	local lockedContainerParents = {
		StarterPlayerScripts = "StarterPlayer",
		StarterCharacterScripts = "StarterPlayer",
		StarterGear = "StarterPlayer",
	}

	local created = 0
	for _, item in ipairs(instances) do
		local adjustedPath = {}
		for i, segment in ipairs(item.path) do
			adjustedPath[i] = segment
		end

		local protectedContainerName: string? = nil
		local first = adjustedPath[1]
		local maybeParent = lockedContainerParents[first]
		if maybeParent and maybeParent ~= first then
			table.insert(adjustedPath, 1, maybeParent)
			protectedContainerName = adjustedPath[2]
		end

		if not protectedContainerName and #adjustedPath >= 2 then
			local second = adjustedPath[2]
			if lockedContainerParents[second] == adjustedPath[1] then protectedContainerName = second end
		end

		local serviceCandidate: Instance? = nil
		if #adjustedPath == 1 then
			local okService, service = pcall(function()
				return game:GetService(adjustedPath[1])
			end)
			if okService then serviceCandidate = service end
		end

		local parentPath = {}
		for i = 1, #adjustedPath - 1 do
			parentPath[i] = adjustedPath[i]
		end

		local parent = AzulService.getOrCreatePath(parentPath)
		local existing = if serviceCandidate
			then serviceCandidate
			else parent:FindFirstChild(adjustedPath[#adjustedPath])
		local instance = existing

		local function isScriptClass(className: string)
			return className == "Script" or className == "LocalScript" or className == "ModuleScript"
		end

		if existing and existing.ClassName ~= item.className then
			local targetIsScript = isScriptClass(item.className)
			if targetIsScript then
				if AzulService.isProtectedRobloxContainer(existing) then
					instance = existing
				else
					existing:Destroy()
					instance = nil
				end
			else
				instance = existing
			end
		end

		if not instance and protectedContainerName then
			local protectedParentName = lockedContainerParents[protectedContainerName]
			if protectedParentName then
				local okParent, protectedParent = pcall(function()
					return game:GetService(protectedParentName)
				end)
				if okParent and protectedParent then
					local protectedExisting = protectedParent:FindFirstChild(protectedContainerName)
					if protectedExisting then instance = protectedExisting end
				end
			end
		end

		if not instance then
			local newInstance
			local okNew, createdInstance = pcall(function()
				return Instance.new(item.className)
			end)
			if okNew and createdInstance then
				newInstance = createdInstance
			else
				newInstance = Instance.new("Folder")
			end
			newInstance.Name = adjustedPath[#adjustedPath]
			newInstance.Parent = parent
			instance = newInstance
			created += 1
		else
			if not serviceCandidate and not AzulService.isProtectedRobloxContainer(instance) then
				instance.Name = adjustedPath[#adjustedPath]
			end
		end

		if isScriptClass(item.className) and item.source and instance then
			AzulService.setScriptSource(instance :: Script, item.source)
		end
	end

	return created
end

--- Find the push config ModuleScript
function AzulService.findPushConfigModule(pushConfigPath: { string }): ModuleScript?
	local current: Instance = game
	for index, segment in ipairs(pushConfigPath) do
		if index == 1 then
			local ok, service = pcall(function()
				return game:GetService(segment)
			end)
			if not ok or not service then return nil end
			current = service
		else
			local nextNode = current:FindFirstChild(segment)
			if not nextNode then return nil end
			current = nextNode
		end
	end

	if current and current:IsA("ModuleScript") then return current :: ModuleScript end

	return nil
end

--- Read and validate push config from ModuleScript
function AzulService.readPushConfig(pushConfigPath: { string }): ({ [string]: any }?, string?)
	local module = AzulService.findPushConfigModule(pushConfigPath)
	if not module then return nil, "Push config ModuleScript not found" end

	-- Clone module to force require to refresh data
	local moduleClone = module:Clone()
	moduleClone.Parent = module.Parent
	module:Destroy()
	module = moduleClone
	--

	local ok, data = pcall(require, module)
	if not ok then return nil, `Failed to require push config: {data}` end

	if type(data) ~= "table" then return nil, "Push config is not a table" end

	debugPrint(`Push config loaded from {module}: {HttpService:JSONEncode(data)}`)

	local mappings = {}
	if type(data.pushMappings) == "table" then
		for _, entry in ipairs(data.pushMappings) do
			if type(entry) == "table" and type(entry.source) == "string" and type(entry.destination) == "table" then
				local dest = {}
				for _, seg in ipairs(entry.destination) do
					if type(seg) == "string" and seg ~= "" then table.insert(dest, seg) end
				end

				if #dest > 0 then
					table.insert(mappings, {
						source = entry.source,
						destination = dest,
						destructive = entry.destructive == true,
						rojoMode = entry.rojoMode == true,
					})
				end
			end
		end
	end

	local configPayload = {
		mappings = mappings,
		port = data.port,
		debugMode = data.debugMode,
		deleteOrphansOnConnect = data.deleteOrphansOnConnect,
	}

	return configPayload, nil
end

return AzulService
