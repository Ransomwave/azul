--!strict
local AzulService = {}
AzulService.VERSION = 40

-- Services
local ScriptEditorService = game:GetService("ScriptEditorService")
local HttpService = game:GetService("HttpService")

-- Modules
local parent = script.Parent
if not parent then error("AzulService: missing parent container") end

local Serializer = require("./Serializer")
local CONFIG = require("./Config")
local Enums = require("./Enums")

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
	usedGuids: { [string]: boolean },
	options: { includeProperties: boolean? }?
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

	if options and options.includeProperties then
		local properties = Serializer.collectSerializedProperties(instance, {
			getInstanceRefData = function(referenceInstance: Instance)
				local referencePath = AzulService.getInstancePath(referenceInstance)
				if not referencePath then return nil end

				local referenceGuid =
					AzulService.getOrCreateGUID(referenceInstance, trackedInstances, guidMap, usedGuids)
				return {
					guid = referenceGuid,
					path = referencePath,
				}
			end,
		})
		if next(properties) ~= nil then data.properties = properties end

		local attributes = instance:GetAttributes()
		if next(attributes) ~= nil then data.attributes = attributes end

		local tags = Serializer.collectSerializedTags(instance)
		if #tags > 0 then data.tags = tags end
	end

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

	if not ok then warn(`[AzulService]: Failed to set script source for {scriptInstance}`, err) end

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

type InstanceData = {
	guid: string,
	className: string,
	name: string,
	path: { string }, -- ["ReplicatedStorage", "Modules", "Foo"]
	parentGuid: string?, -- parent instance GUID
	source: string?, -- Only present for Script/LocalScript/ModuleScript
	properties: { [string]: any }?, -- Record<string, unknown>;
	attributes: { [string]: any }?, -- Record<string, unknown>;
	tags: { string }?,
}

--- Apply snapshot instances to the workspace
function AzulService.applySnapshotInstances(instances: { InstanceData }): (number, number, { [string]: Instance })
	table.sort(instances, function(a, b)
		return #a.path < #b.path
	end)

	local function isScriptClass(className: string): boolean
		return className == "Script" or className == "LocalScript" or className == "ModuleScript"
	end

	local function computeAdjustedPath(
		pathSegments: { string },
		lockedContainerParentsMap: { [string]: string }
	): ({ string }, string?)
		local adjustedPath = {}
		for i, segment in ipairs(pathSegments) do
			adjustedPath[i] = segment
		end

		local protectedContainerName: string? = nil
		local first = adjustedPath[1]
		local maybeParent = lockedContainerParentsMap[first]
		if maybeParent and maybeParent ~= first then table.insert(adjustedPath, 1, maybeParent) end

		-- Only treat as a protected-container target when the path points to the
		-- container itself (StarterPlayer/<LockedContainer>), not its descendants.
		if #adjustedPath == 2 then
			local second = adjustedPath[2]
			if lockedContainerParentsMap[second] == adjustedPath[1] then protectedContainerName = second end
		end

		return adjustedPath, protectedContainerName
	end

	local siblingOrdinalByPathClass: { [string]: number } = {}
	local existingInstancesByGuid: { [string]: Instance } = {}
	local initialStudioGuids: { [string]: boolean } = {}
	local resolvedInstancesByGuid: { [string]: Instance } = {}
	local deferredPropertyApplications: { { instance: Instance, properties: { [string]: any }? } } = {}

	local lockedContainerParents = {
		StarterPlayerScripts = "StarterPlayer",
		StarterCharacterScripts = "StarterPlayer",
		StarterGear = "StarterPlayer",
	}

	local created = 0
	local updated = 0
	local guidMatchCount = 0
	local fallbackMatchCount = 0

	for _, existing in ipairs(game:GetDescendants()) do
		local guid = existing:GetDebugId(0)
		if type(guid) == "string" and guid ~= "" then
			existingInstancesByGuid[guid] = existing
			initialStudioGuids[guid] = true
		end
	end

	local function findInstanceByPath(pathSegments: { string }): Instance?
		local current: Instance = game
		for index, segment in ipairs(pathSegments) do
			local nextNode: Instance? = nil

			if index == 1 then
				local okService, service = pcall(function()
					return game:GetService(segment)
				end)
				if okService and service then nextNode = service end
			end

			if not nextNode then nextNode = current:FindFirstChild(segment) end
			if not nextNode then return nil end
			current = nextNode
		end

		return current
	end

	for _, item in instances do
		local adjustedPath, protectedContainerName = computeAdjustedPath(item.path, lockedContainerParents)

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

		local parent: Instance? = nil
		if type(item.parentGuid) == "string" and item.parentGuid ~= "" and item.parentGuid ~= "root" then
			parent = resolvedInstancesByGuid[item.parentGuid] or existingInstancesByGuid[item.parentGuid]
		end
		if not parent then parent = AzulService.getOrCreatePath(parentPath) end

		local targetName = adjustedPath[#adjustedPath]
		if isScriptClass(item.className) then
			local sameNameChildren = {}
			local hasPreExistingSameNamed = false

			for _, child in ipairs((parent :: Instance):GetChildren()) do
				if child.Name == targetName and child.ClassName == item.className then
					table.insert(sameNameChildren, child)
					local childGuid = child:GetDebugId(0)
					if type(childGuid) == "string" and childGuid ~= "" and initialStudioGuids[childGuid] then
						hasPreExistingSameNamed = true
					end
				end
			end

			if hasPreExistingSameNamed then
				for _, child in ipairs(sameNameChildren) do
					if not AzulService.isProtectedRobloxContainer(child) then
						local childGuid = child:GetDebugId(0)
						if type(childGuid) == "string" and childGuid ~= "" then
							existingInstancesByGuid[childGuid] = nil
							resolvedInstancesByGuid[childGuid] = nil
						end
						child:Destroy()
					end
				end
			end
		end

		local existing: Instance? = nil
		if type(item.guid) == "string" and item.guid ~= "" then
			existing = existingInstancesByGuid[item.guid]
			if existing then
				guidMatchCount += 1
			end
		end

		if not existing then
			existing = serviceCandidate
			if existing then
				fallbackMatchCount += 1
			end
		end

		if not existing then
			local targetClassName = item.className
			local occurrenceKey = table.concat(adjustedPath, "\u{1F}") .. "::" .. tostring(targetClassName)
			local occurrenceOrdinal = (siblingOrdinalByPathClass[occurrenceKey] or 0) + 1
			siblingOrdinalByPathClass[occurrenceKey] = occurrenceOrdinal

			local sameNameChildren = {}
			for _, child in ipairs((parent :: Instance):GetChildren()) do
				if child.Name == targetName then table.insert(sameNameChildren, child) end
			end

			existing = sameNameChildren[occurrenceOrdinal]
			if existing then
				fallbackMatchCount += 1
			end
		end

		local instance = existing

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
				debugPrint(`Failed to create instance of class "{item.className}", created Folder placeholder instead.`)
			end
			newInstance.Name = adjustedPath[#adjustedPath]
			newInstance.Parent = parent :: Instance
			instance = newInstance
			created += 1
		else
			if parent and instance.Parent ~= parent and not AzulService.isProtectedRobloxContainer(instance) then
				local okReparent = pcall(function()
					instance.Parent = parent :: Instance
				end)
				if not okReparent then
					debugPrint(`Failed to reparent instance "{instance.Name}" ({instance.ClassName}) to target parent.`)
				end
			end

			if not serviceCandidate and not AzulService.isProtectedRobloxContainer(instance) then
				instance.Name = adjustedPath[#adjustedPath]
			end
		end

		if instance then
			if type(item.guid) == "string" and item.guid ~= "" then
				existingInstancesByGuid[item.guid] = instance
				resolvedInstancesByGuid[item.guid] = instance
			end

			table.insert(deferredPropertyApplications, {
				instance = instance,
				properties = item.properties,
			})

			Serializer.applySerializedAttributes(instance, item.attributes)
			Serializer.applySerializedTags(instance, item.tags)
		end

		if isScriptClass(item.className) and item.source and instance then
			if isScript(instance) then
				AzulService.setScriptSource(instance :: Script, item.source)
				updated += 1
			else
				debugPrint(
					`Skipped source apply for non-script instance "{instance.Name}" ({instance.ClassName}) targeting class "{item.className}".`
				)
			end
		end
	end

	for _, pending in ipairs(deferredPropertyApplications) do
		Serializer.applySerializedProperties(pending.instance, pending.properties, {
			resolveInstanceByGuid = function(guid: string): Instance?
				return resolvedInstancesByGuid[guid]
			end,
			resolveInstanceByPath = function(pathSegments: { string }): Instance?
				return findInstanceByPath(pathSegments)
			end,
		})
	end

	debugPrint(
		`Snapshot resolve summary: {guidMatchCount} guid matches, {fallbackMatchCount} fallback matches, {created} created, {updated} scripts updated`
	)

	return created, updated, resolvedInstancesByGuid
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
