--!strict
local AzulService = {}

local ScriptEditorService = game:GetService("ScriptEditorService")

-- Services

-- Modules
local parent = script.Parent
if not parent then error("AzulService: missing parent container") end
local CONFIG = require(parent:WaitForChild("Config"))
local Enums = require(parent:WaitForChild("Enums"))
local HttpService = game:GetService("HttpService")
local ReflectionService = nil

do
	local ok, service = pcall(function()
		return game:GetService("ReflectionService")
	end)
	if ok then ReflectionService = service end
end

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

local FALLBACK_SERIALIZABLE_PROPERTIES = {
	"Archivable",
	"Enabled",
	"RunContext",
	"LinkedSource",
	"Disabled",
	"Visible",
	"Active",
	"AutomaticSize",
	"AnchorPoint",
	"Position",
	"Rotation",
	"Size",
	"Text",
	"TextColor3",
	"TextSize",
	"BackgroundColor3",
	"BackgroundTransparency",
	"Image",
	"ImageColor3",
	"ImageTransparency",
	"LayoutOrder",
	"ZIndex",
	"AutoButtonColor",
	"RichText",
	"TextScaled",
	"TextWrapped",
	"FontFace",
	"Transparency",
	"Color",
	"Material",
	"Reflectance",
	"CanCollide",
	"CanTouch",
	"CanQuery",
	"CastShadow",
	"Locked",
	"Massless",
	"Shape",
	"SizeConstraint",
	"CFrame",
	"Orientation",
	"PivotOffset",
	"BrickColor",
	"TopSurface",
	"BottomSurface",
	"LeftSurface",
	"RightSurface",
	"FrontSurface",
	"BackSurface",
	"MeshId",
	"TextureID",
	"DoubleSided",
	"Offset",
	"Scale",
	"SoundId",
	"Volume",
	"PlaybackSpeed",
	"Looped",
	"RollOffMode",
	"RollOffMaxDistance",
	"RollOffMinDistance",
	"PlayOnRemove",
	"AnimationId",
	"Value",
	"CurrentCamera",
	"FieldOfView",
	"Ambient",
	"Brightness",
	"ClockTime",
	"FogColor",
	"FogEnd",
	"FogStart",
	"GlobalShadows",
	"OutdoorAmbient",
	"Technology",
	"PrimaryPart",
	"WorldPivot",
}

local FALLBACK_SERIALIZABLE_PROPERTY_SET: { [string]: boolean } = {}
for _, propertyName in ipairs(FALLBACK_SERIALIZABLE_PROPERTIES) do
	FALLBACK_SERIALIZABLE_PROPERTY_SET[propertyName] = true
end

local SERIALIZABLE_PROPERTIES_CACHE: { string }? = nil
local SERIALIZABLE_PROPERTY_SET_CACHE: { [string]: boolean }? = nil

local function buildSerializablePropertiesFromReflection(): { string }
	if not ReflectionService then return FALLBACK_SERIALIZABLE_PROPERTIES end

	local classOk, classes = pcall(function()
		return ReflectionService:GetClasses()
	end)

	if not classOk or type(classes) ~= "table" then return FALLBACK_SERIALIZABLE_PROPERTIES end

	local propertySet: { [string]: boolean } = {}

	for _, classInfo in ipairs(classes) do
		local className = classInfo.Name
		if type(className) ~= "string" then continue end

		local propsOk, reflectedProperties = pcall(function()
			return ReflectionService:GetPropertiesOfClass(className, {
				ExcludeDisplay = true,
			})
		end)

		if not propsOk or type(reflectedProperties) ~= "table" then continue end

		for _, reflected in ipairs(reflectedProperties) do
			local reflectedName = reflected.Name
			if type(reflectedName) ~= "string" then continue end

			if
				reflected.Serialized == true
				and reflectedName ~= "Name"
				and reflectedName ~= "Parent"
				and reflectedName ~= "Source"
			then
				propertySet[reflectedName] = true
			end
		end
	end

	for _, fallbackProperty in ipairs(FALLBACK_SERIALIZABLE_PROPERTIES) do
		propertySet[fallbackProperty] = true
	end

	local properties = {}
	for propertyName in pairs(propertySet) do
		table.insert(properties, propertyName)
	end

	table.sort(properties)

	if #properties == 0 then return FALLBACK_SERIALIZABLE_PROPERTIES end

	return properties
end

local function getSerializableProperties(): { string }
	local cached = SERIALIZABLE_PROPERTIES_CACHE
	if cached then return cached end

	local built = buildSerializablePropertiesFromReflection()
	SERIALIZABLE_PROPERTIES_CACHE = built
	return built
end

local writablePropertiesByClass: { [string]: { [string]: boolean } } = {}
local defaultSerializedPropertiesByClass: { [string]: { [string]: any } } = {}
local canonicalPropertyByLowerByClass: { [string]: { [string]: string } } = {}

local function toSet(items: { string }): { [string]: boolean }
	local set = {}
	for _, item in ipairs(items) do
		set[item] = true
	end
	return set
end

local function getSerializablePropertySet(): { [string]: boolean }
	local cached = SERIALIZABLE_PROPERTY_SET_CACHE
	if cached then return cached end

	local built = toSet(getSerializableProperties())
	SERIALIZABLE_PROPERTY_SET_CACHE = built
	return built
end

local function getWritableSerializablePropertySetForClass(className: string): { [string]: boolean }
	local cached = writablePropertiesByClass[className]
	if cached then return cached end

	local serializablePropertySet = getSerializablePropertySet()
	local fallback = {}
	for propertyName in pairs(serializablePropertySet) do
		fallback[propertyName] = true
	end

	if not ReflectionService then
		writablePropertiesByClass[className] = fallback
		return fallback
	end

	local ok, reflectedProperties = pcall(function()
		return ReflectionService:GetPropertiesOfClass(className)
	end)

	if not ok or type(reflectedProperties) ~= "table" then
		writablePropertiesByClass[className] = fallback
		return fallback
	end

	local filtered = {}
	for _, reflected in ipairs(reflectedProperties) do
		local reflectedName = reflected.Name
		if type(reflectedName) ~= "string" then continue end

		if not serializablePropertySet[reflectedName] then continue end

		local includedByFallback = FALLBACK_SERIALIZABLE_PROPERTY_SET[reflectedName] == true
		if reflected.Serialized ~= true and not includedByFallback then continue end

		filtered[reflectedName] = true
	end

	if next(filtered) == nil then filtered = fallback end

	writablePropertiesByClass[className] = filtered
	return filtered
end

local function getCanonicalPropertyByLowerForClass(className: string): { [string]: string }
	local cached = canonicalPropertyByLowerByClass[className]
	if cached then return cached end

	local allowed = getWritableSerializablePropertySetForClass(className)
	local byLower = {}
	for propertyName in pairs(allowed) do
		byLower[string.lower(propertyName)] = propertyName
	end

	canonicalPropertyByLowerByClass[className] = byLower
	return byLower
end

local function resolveWritablePropertyName(instance: Instance, propertyName: string): string?
	local allowed = getWritableSerializablePropertySetForClass(instance.ClassName)
	if allowed[propertyName] then return propertyName end

	local canonicalByLower = getCanonicalPropertyByLowerForClass(instance.ClassName)
	return canonicalByLower[string.lower(propertyName)]
end

local function serializedValuesEqual(left, right): boolean
	if type(left) ~= type(right) then return false end

	if type(left) ~= "table" then return left == right end

	for key, value in pairs(left) do
		if not serializedValuesEqual(value, right[key]) then return false end
	end

	for key in pairs(right) do
		if left[key] == nil then return false end
	end

	return true
end

local serializeValue

local function readAndSerializeProperty(instance: Instance, propertyName: string)
	local ok, value = pcall(function()
		return (instance :: any)[propertyName]
	end)
	if not ok then return nil end

	return serializeValue(value)
end

local function getDefaultSerializedPropertiesForClass(className: string): { [string]: any }
	local cached = defaultSerializedPropertiesByClass[className]
	if cached then return cached end

	local defaults = {}
	local ok, tempInstance = pcall(function()
		return Instance.new(className)
	end)

	if not ok or not tempInstance then
		defaultSerializedPropertiesByClass[className] = defaults
		return defaults
	end

	local allowedProperties = getWritableSerializablePropertySetForClass(className)
	for propertyName in pairs(allowedProperties) do
		local serialized = readAndSerializeProperty(tempInstance, propertyName)
		if serialized ~= nil then defaults[propertyName] = serialized end
	end

	tempInstance:Destroy()
	defaultSerializedPropertiesByClass[className] = defaults
	return defaults
end

serializeValue = function(value: any): any
	local kind = typeof(value)

	if kind == "nil" then return nil end
	if kind == "boolean" or kind == "string" or kind == "number" then return value end

	if kind == "Color3" then
		local color = value :: Color3
		return { __type = "Color3", r = color.R, g = color.G, b = color.B }
	end

	if kind == "Vector2" then
		local vector = value :: Vector2
		return { __type = "Vector2", x = vector.X, y = vector.Y }
	end

	if kind == "Vector3" then
		local vector = value :: Vector3
		return { __type = "Vector3", x = vector.X, y = vector.Y, z = vector.Z }
	end

	if kind == "UDim" then
		local u = value :: UDim
		return { __type = "UDim", scale = u.Scale, offset = u.Offset }
	end

	if kind == "UDim2" then
		local u = value :: UDim2
		return {
			__type = "UDim2",
			xScale = u.X.Scale,
			xOffset = u.X.Offset,
			yScale = u.Y.Scale,
			yOffset = u.Y.Offset,
		}
	end

	if kind == "Rect" then
		local rect = value :: Rect
		return {
			__type = "Rect",
			minX = rect.Min.X,
			minY = rect.Min.Y,
			maxX = rect.Max.X,
			maxY = rect.Max.Y,
		}
	end

	if kind == "CFrame" then
		local cf = value :: CFrame
		return { __type = "CFrame", components = { cf:GetComponents() } }
	end

	if kind == "BrickColor" then
		local brick = value :: BrickColor
		return { __type = "BrickColor", number = brick.Number }
	end

	if kind == "EnumItem" then
		local enumItem = value :: EnumItem
		return {
			__type = "EnumItem",
			enumType = tostring(enumItem.EnumType),
			name = enumItem.Name,
		}
	end

	if kind == "NumberRange" then
		local range = value :: NumberRange
		return { __type = "NumberRange", min = range.Min, max = range.Max }
	end

	if kind == "NumberSequence" then
		local sequence = value :: NumberSequence
		local keypoints = {}
		for _, keypoint in ipairs(sequence.Keypoints) do
			table.insert(keypoints, {
				time = keypoint.Time,
				value = keypoint.Value,
				envelope = keypoint.Envelope,
			})
		end
		return { __type = "NumberSequence", keypoints = keypoints }
	end

	if kind == "ColorSequence" then
		local sequence = value :: ColorSequence
		local keypoints = {}
		for _, keypoint in ipairs(sequence.Keypoints) do
			table.insert(keypoints, {
				time = keypoint.Time,
				color = serializeValue(keypoint.Value),
			})
		end
		return { __type = "ColorSequence", keypoints = keypoints }
	end

	if kind == "Font" then
		local font = value :: Font
		return {
			__type = "Font",
			family = font.Family,
			weight = font.Weight and font.Weight.Value or nil,
			style = font.Style and font.Style.Value or nil,
		}
	end

	if kind == "PhysicalProperties" then
		local props = value :: PhysicalProperties
		return {
			__type = "PhysicalProperties",
			density = props.Density,
			friction = props.Friction,
			elasticity = props.Elasticity,
			frictionWeight = props.FrictionWeight,
			elasticityWeight = props.ElasticityWeight,
		}
	end

	return nil
end

local function deserializeValue(value: any): any
	if type(value) ~= "table" then return value end

	local record = value :: { [string]: any }
	local valueType = record.__type
	if type(valueType) ~= "string" then return value end

	if valueType == "Color3" then return Color3.new(record.r, record.g, record.b) end
	if valueType == "Vector2" then return Vector2.new(record.x, record.y) end
	if valueType == "Vector3" then return Vector3.new(record.x, record.y, record.z) end
	if valueType == "UDim" then return UDim.new(record.scale, record.offset) end
	if valueType == "UDim2" then return UDim2.new(record.xScale, record.xOffset, record.yScale, record.yOffset) end
	if valueType == "Rect" then return Rect.new(record.minX, record.minY, record.maxX, record.maxY) end
	if valueType == "CFrame" and type(record.components) == "table" then
		return CFrame.new(unpack(record.components))
	end
	if valueType == "BrickColor" then return BrickColor.new(record.number) end
	if valueType == "EnumItem" then
		if type(record.enumType) ~= "string" or type(record.name) ~= "string" then return nil end
		local enumName = record.enumType:match("Enum%.(.+)") or record.enumType
		local enum = Enum[enumName]
		if enum then return enum[record.name] end
		return nil
	end
	if valueType == "NumberRange" then return NumberRange.new(record.min, record.max) end
	if valueType == "NumberSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(record.keypoints or {}) do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.time, keypoint.value, keypoint.envelope or 0))
		end
		if #keypoints > 0 then return NumberSequence.new(keypoints) end
		return nil
	end
	if valueType == "ColorSequence" then
		local keypoints = {}
		for _, keypoint in ipairs(record.keypoints or {}) do
			local color = deserializeValue(keypoint.color)
			if typeof(color) == "Color3" then
				table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.time, color))
			end
		end
		if #keypoints > 0 then return ColorSequence.new(keypoints) end
		return nil
	end
	if valueType == "Font" then
		local weight = Enum.FontWeight.Regular
		local style = Enum.FontStyle.Normal
		if type(record.weight) == "number" then
			for _, item in ipairs(Enum.FontWeight:GetEnumItems()) do
				if item.Value == record.weight then
					weight = item
					break
				end
			end
		end
		if type(record.style) == "number" then
			for _, item in ipairs(Enum.FontStyle:GetEnumItems()) do
				if item.Value == record.style then
					style = item
					break
				end
			end
		end
		return Font.new(record.family, weight, style)
	end
	if valueType == "PhysicalProperties" then
		return PhysicalProperties.new(
			record.density,
			record.friction,
			record.elasticity,
			record.frictionWeight,
			record.elasticityWeight
		)
	end

	return nil
end

local function collectSerializedProperties(instance: Instance): { [string]: any }
	local properties = {}
	local className = instance.ClassName
	local allowedProperties = getWritableSerializablePropertySetForClass(className)
	local defaultProperties = getDefaultSerializedPropertiesForClass(className)
	local serializableProperties = getSerializableProperties()

	for _, propertyName in ipairs(serializableProperties) do
		if not allowedProperties[propertyName] then continue end

		if propertyName == "Name" or propertyName == "Parent" then continue end

		local serialized = readAndSerializeProperty(instance, propertyName)
		if serialized ~= nil then
			local defaultSerialized = defaultProperties[propertyName]
			if defaultSerialized == nil or not serializedValuesEqual(serialized, defaultSerialized) then
				properties[propertyName] = serialized
			end
		end
	end

	return properties
end

local function applySerializedProperties(instance: Instance, properties: { [string]: any }?)
	if type(properties) ~= "table" then return end

	for propertyName, serialized in pairs(properties) do
		if propertyName ~= "Name" and propertyName ~= "Parent" and propertyName ~= "Source" then
			local resolvedProperty = resolveWritablePropertyName(instance, propertyName)
			if not resolvedProperty then continue end

			local deserialized = deserializeValue(serialized)
			if deserialized ~= nil then
				pcall(function()
					(instance :: any)[resolvedProperty] = deserialized
				end)
			end
		end
	end
end

local function applySerializedAttributes(instance: Instance, attributes: { [string]: any }?)
	if type(attributes) ~= "table" then return end

	for key, value in pairs(attributes) do
		pcall(function()
			instance:SetAttribute(key, value)
		end)
	end
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
		local properties = collectSerializedProperties(instance)
		if next(properties) ~= nil then data.properties = properties end

		local attributes = instance:GetAttributes()
		if next(attributes) ~= nil then data.attributes = attributes end
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

--- Apply snapshot instances to the workspace
function AzulService.applySnapshotInstances(instances: { any }): number
	table.sort(instances, function(a, b)
		return #a.path < #b.path
	end)

	local siblingOrdinalByPathClass: { [string]: number } = {}

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
		local existing: Instance? = serviceCandidate
		if not existing then
			local targetName = adjustedPath[#adjustedPath]
			local targetClassName = item.className
			local occurrenceKey = table.concat(adjustedPath, "\u{1F}") .. "::" .. tostring(targetClassName)
			local occurrenceOrdinal = (siblingOrdinalByPathClass[occurrenceKey] or 0) + 1
			siblingOrdinalByPathClass[occurrenceKey] = occurrenceOrdinal

			local sameNameChildren = {}
			for _, child in ipairs(parent:GetChildren()) do
				if child.Name == targetName then table.insert(sameNameChildren, child) end
			end

			existing = sameNameChildren[occurrenceOrdinal]
		end
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

		if instance then
			applySerializedProperties(instance, item.properties)
			applySerializedAttributes(instance, item.attributes)
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
