--!strict
--[[
	Serializer for Roblox data types and instances
	
	Handles conversion of complex Roblox types to plain tables for JSON serialization,
	and back from those tables to Roblox types. Also manages which properties of instances
	should be serialized based on ReflectionService metadata.

	Ransomwave 2026
]]

local Serializer = {}

local ReflectionService = game:GetService("ReflectionService")
local CollectionService = game:GetService("CollectionService")

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
	"MetalnessMap",
	"NormalMap",
	"RoughnessMap",
	"ColorMap",
}

local FALLBACK_SERIALIZABLE_PROPERTY_SET: { [string]: boolean } = {}
for _, propertyName in ipairs(FALLBACK_SERIALIZABLE_PROPERTIES) do
	FALLBACK_SERIALIZABLE_PROPERTY_SET[propertyName] = true
end

local SERIALIZABLE_PROPERTIES_CACHE: { string }? = nil
local SERIALIZABLE_PROPERTY_SET_CACHE: { [string]: boolean }? = nil
local writablePropertiesByClass: { [string]: { [string]: boolean } } = {}
local defaultSerializedPropertiesByClass: { [string]: { [string]: any } } = {}
local canonicalPropertyByLowerByClass: { [string]: { [string]: string } } = {}

local function enumItemFromNumber(enumItems: { any }, value: number): any
	for _, item in ipairs(enumItems) do
		if item.Value == value then return item end
	end
	return nil
end

local function enumItemFromName(enumItems: { any }, name: string): any
	for _, item in ipairs(enumItems) do
		if item.Name == name then return item end
	end
	return nil
end

local function parseCFrameFromValue(recordValue: any): CFrame?
	if type(recordValue) ~= "table" then return nil end

	if type(recordValue.position) == "table" and type(recordValue.rotation) == "table" then
		local position = recordValue.position
		local rotation = recordValue.rotation
		if #position == 3 and #rotation == 9 then
			return CFrame.new(
				position[1],
				position[2],
				position[3],
				rotation[1],
				rotation[2],
				rotation[3],
				rotation[4],
				rotation[5],
				rotation[6],
				rotation[7],
				rotation[8],
				rotation[9]
			)
		end
	end

	if type(recordValue.components) == "table" then return CFrame.new(unpack(recordValue.components)) end

	return nil
end

local function getInstancePathSegments(instance: Instance): { string }?
	local path = {}
	local current: Instance? = instance

	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	if current ~= game then return nil end
	return path
end

local function findInstanceByPath(pathSegments: { string }): Instance?
	local current: Instance = game
	for index, segment in ipairs(pathSegments) do
		local nextNode: Instance? = nil

		if index == 1 then
			local ok, service = pcall(function()
				return game:GetService(segment)
			end)
			if ok and service then nextNode = service end
		end

		if not nextNode then nextNode = current:FindFirstChild(segment) end
		if not nextNode then return nil end
		current = nextNode
	end

	return current
end

--[=[
	Serializes a value into a format suitable for JSON encoding, handling Roblox-specific types.
	@param value any - The value to serialize
	@param options table? - Optional parameters for serialization
	@return any - The serialized representation of the value
]=]
function Serializer.serializeValue(
	value: any,
	options: { getInstanceRefData: ((Instance) -> { guid: string?, path: { string }? }?)? }?
): any
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

	if kind == "Vector2int16" then
		local vector = value :: Vector2int16
		return { __type = "Vector2int16", x = vector.X, y = vector.Y }
	end

	if kind == "Vector3" then
		local vector = value :: Vector3
		return { __type = "Vector3", x = vector.X, y = vector.Y, z = vector.Z }
	end

	if kind == "Vector3int16" then
		local vector = value :: Vector3int16
		return { __type = "Vector3int16", x = vector.X, y = vector.Y, z = vector.Z }
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
				color = Serializer.serializeValue(keypoint.Value, options),
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

	if kind == "Axes" then
		local axes = value :: Axes
		return { __type = "Axes", x = axes.X, y = axes.Y, z = axes.Z }
	end

	if kind == "Faces" then
		local faces = value :: Faces
		return {
			__type = "Faces",
			top = faces.Top,
			bottom = faces.Bottom,
			left = faces.Left,
			right = faces.Right,
			front = faces.Front,
			back = faces.Back,
		}
	end

	if kind == "Ray" then
		local ray = value :: Ray
		return {
			__type = "Ray",
			origin = Serializer.serializeValue(ray.Origin, options),
			direction = Serializer.serializeValue(ray.Direction, options),
		}
	end

	if kind == "Instance" then
		local instanceValue = value :: Instance
		local guid: string? = nil
		local path: { string }? = nil

		if options and options.getInstanceRefData then
			local ok, refData = pcall(function()
				return options.getInstanceRefData(instanceValue)
			end)
			if ok and type(refData) == "table" then
				if type(refData.guid) == "string" then guid = refData.guid end
				if type(refData.path) == "table" then path = refData.path end
			end
		end

		if not guid then
			local okGuid, debugId = pcall(function()
				return instanceValue:GetDebugId(0)
			end)
			if okGuid and type(debugId) == "string" and debugId ~= "" then guid = debugId end
		end

		if not path then path = getInstancePathSegments(instanceValue) end

		return {
			__type = "InstanceRef",
			guid = guid,
			path = path,
		}
	end

	if kind == "Region3" then
		local cframe = value.CFrame
		local size = value.Size
		return {
			__type = "Region3",
			min = { x = cframe.X - size.X / 2, y = cframe.Y - size.Y / 2, z = cframe.Z - size.Z / 2 },
			max = { x = cframe.X + size.X / 2, y = cframe.Y + size.Y / 2, z = cframe.Z + size.Z / 2 },
		}
	end

	if kind == "Region3int16" then
		local region = value :: Region3int16
		return {
			__type = "Region3int16",
			min = { x = region.Min.X, y = region.Min.Y, z = region.Min.Z },
			max = { x = region.Max.X, y = region.Max.Y, z = region.Max.Z },
		}
	end

	return nil
end

--[=[
	Deserializes a value from the format produced by serializeValue, reconstructing Roblox-specific types.
	@param value any - The value to deserialize
	@param options table? - Optional parameters for deserialization, such as instance resolution functions
	@return any - The deserialized Roblox type, or the original value if it cannot be deserialized
]=]
function Serializer.deserializeValue(
	value: any,
	options: {
		resolveInstanceByGuid: ((string) -> Instance?)?,
		resolveInstanceByPath: (({ string }) -> Instance?)?,
	}?
): any
	if type(value) ~= "table" then return value end

	local record = value :: { [string]: any }
	local valueType = record.__type
	local payload = record

	if type(valueType) ~= "string" then
		if type(record.type) ~= "string" then return value end
		valueType = record.type
		payload = record.value
	end

	if valueType == "Ref" then
		local guidFromRef = if type(payload) == "string" then payload else nil
		valueType = "InstanceRef"
		payload = {
			guid = guidFromRef,
			path = nil,
		}
	end

	if valueType == "nil" then return nil end
	if valueType == "Color3" then
		local source = if type(payload) == "table" then payload else record
		return Color3.new(source.r, source.g, source.b)
	end
	if valueType == "Color3uint8" then
		local source = if type(payload) == "table" then payload else record
		return Color3.fromRGB(source.r, source.g, source.b)
	end
	if valueType == "Vector2" then
		local source = if type(payload) == "table" then payload else record
		return Vector2.new(source.x, source.y)
	end
	if valueType == "Vector2int16" then
		local source = if type(payload) == "table" then payload else record
		return Vector2int16.new(source.x, source.y)
	end
	if valueType == "Vector3" then
		local source = if type(payload) == "table" then payload else record
		return Vector3.new(source.x, source.y, source.z)
	end
	if valueType == "Vector3int16" then
		local source = if type(payload) == "table" then payload else record
		return Vector3int16.new(source.x, source.y, source.z)
	end
	if valueType == "UDim" then
		local source = if type(payload) == "table" then payload else record
		return UDim.new(source.scale, source.offset)
	end
	if valueType == "UDim2" then
		if type(payload) == "table" and type(payload.x) == "table" and type(payload.y) == "table" then
			return UDim2.new(payload.x.scale, payload.x.offset, payload.y.scale, payload.y.offset)
		end
		return UDim2.new(record.xScale, record.xOffset, record.yScale, record.yOffset)
	end
	if valueType == "Rect" then
		if type(payload) == "table" and type(payload.min) == "table" and type(payload.max) == "table" then
			return Rect.new(payload.min.x, payload.min.y, payload.max.x, payload.max.y)
		end
		return Rect.new(record.minX, record.minY, record.maxX, record.maxY)
	end
	if valueType == "CFrame" then
		if type(record.components) == "table" then return CFrame.new(unpack(record.components)) end
		return parseCFrameFromValue(payload)
	end
	if valueType == "OptionalCFrame" or valueType == "OptionalCoordinateFrame" then
		if payload == nil then return nil end
		return parseCFrameFromValue(payload)
	end
	if valueType == "BrickColor" then
		local source = if type(payload) == "number" then payload else record.number
		return BrickColor.new(source)
	end
	if valueType == "EnumItem" then
		if type(record.enumType) ~= "string" or type(record.name) ~= "string" then return nil end
		local enumName = record.enumType:match("Enum%.(.+)") or record.enumType
		local enum = Enum[enumName]
		if enum then return enum[record.name] end
		return nil
	end
	if valueType == "Enum" then
		if type(payload) ~= "table" then return nil end
		local enumName = payload.enumType
		if type(enumName) ~= "string" then return nil end
		local enum = Enum[enumName]
		if not enum then return nil end
		if type(payload.value) == "string" then return enum[payload.value] end
		if type(payload.value) == "number" then return enumItemFromNumber(enum:GetEnumItems(), payload.value) end
		return nil
	end
	if valueType == "NumberRange" then
		if type(payload) == "table" then return NumberRange.new(payload.min, payload.max) end
		return NumberRange.new(record.min, record.max)
	end
	if valueType == "NumberSequence" then
		local source = record.keypoints
		if type(payload) == "table" and type(payload.keypoints) == "table" then source = payload.keypoints end
		local keypoints = {}
		for _, keypoint in ipairs(source or {}) do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.time, keypoint.value, keypoint.envelope or 0))
		end
		if #keypoints > 0 then return NumberSequence.new(keypoints) end
		return nil
	end
	if valueType == "ColorSequence" then
		local source = record.keypoints
		if type(payload) == "table" and type(payload.keypoints) == "table" then source = payload.keypoints end
		local keypoints = {}
		for _, keypoint in ipairs(source or {}) do
			local color = keypoint.color
			if type(color) == "table" and color.r ~= nil and color.g ~= nil and color.b ~= nil then
				color = Color3.new(color.r, color.g, color.b)
			else
				color = Serializer.deserializeValue(color, options)
			end

			if typeof(color) == "Color3" then
				table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.time, color))
			end
		end
		if #keypoints > 0 then return ColorSequence.new(keypoints) end
		return nil
	end
	if valueType == "Font" then
		local source = if type(payload) == "table" then payload else record
		local weight = Enum.FontWeight.Regular
		local style = Enum.FontStyle.Normal

		if type(source.weight) == "number" then
			local matched = enumItemFromNumber(Enum.FontWeight:GetEnumItems(), source.weight)
			if matched then weight = matched end
		elseif type(source.weight) == "string" then
			local matched = enumItemFromName(Enum.FontWeight:GetEnumItems(), source.weight)
			if matched then weight = matched end
		end

		if type(source.style) == "number" then
			local matched = enumItemFromNumber(Enum.FontStyle:GetEnumItems(), source.style)
			if matched then style = matched end
		elseif type(source.style) == "string" then
			local matched = enumItemFromName(Enum.FontStyle:GetEnumItems(), source.style)
			if matched then style = matched end
		end

		return Font.new(source.family, weight, style)
	end
	if valueType == "PhysicalProperties" then
		if payload == nil then return nil end
		local source = if type(payload) == "table" then payload else record
		return PhysicalProperties.new(
			source.density,
			source.friction,
			source.elasticity,
			source.frictionWeight,
			source.elasticityWeight
		)
	end
	if valueType == "Axes" then
		local source = if type(payload) == "table" then payload else record
		return Axes.new(source.x, source.y, source.z)
	end
	if valueType == "Faces" then
		local source = if type(payload) == "table" then payload else record
		return Faces.new(source.top, source.bottom, source.left, source.right, source.front, source.back)
	end
	if valueType == "Ray" then
		local source = if type(payload) == "table" then payload else record
		local origin = Serializer.deserializeValue(source.origin, options)
		local direction = Serializer.deserializeValue(source.direction, options)
		if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then return Ray.new(origin, direction) end
		return nil
	end
	if valueType == "InstanceRef" then
		local source = if type(payload) == "table" then payload else record
		local guid = if type(source.guid) == "string" then source.guid else nil
		local path = if type(source.path) == "table" then source.path else nil

		if guid and options and options.resolveInstanceByGuid then
			local resolvedByGuid = options.resolveInstanceByGuid(guid)
			if resolvedByGuid then return resolvedByGuid end
		end

		if path then
			if options and options.resolveInstanceByPath then
				local resolvedByPath = options.resolveInstanceByPath(path)
				if resolvedByPath then return resolvedByPath end
			end

			local resolvedByDefaultPath = findInstanceByPath(path)
			if resolvedByDefaultPath then return resolvedByDefaultPath end
		end

		return nil
	end
	if valueType == "Region3" then
		local source = if type(payload) == "table" then payload else record
		if type(source.min) ~= "table" or type(source.max) ~= "table" then return nil end
		return Region3.new(
			Vector3.new(source.min.x, source.min.y, source.min.z),
			Vector3.new(source.max.x, source.max.y, source.max.z)
		)
	end
	if valueType == "Region3int16" then
		local source = if type(payload) == "table" then payload else record
		if type(source.min) ~= "table" or type(source.max) ~= "table" then return nil end
		return Region3int16.new(
			Vector3int16.new(source.min.x, source.min.y, source.min.z),
			Vector3int16.new(source.max.x, source.max.y, source.max.z)
		)
	end

	return nil
end

local function toSet(items: { string }): { [string]: boolean }
	local set = {}
	for _, item in ipairs(items) do
		set[item] = true
	end
	return set
end

local function buildSerializableProperties(): { string }
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

--[=[
	Returns a list of property names that should be considered for serialization when collecting instance properties.
	Uses ReflectionService metadata to determine which properties are marked as serialized, with a fallback list if ReflectionService is unavailable.
	@return { string } - An array of property names that are serializable
]=]
function Serializer.getSerializableProperties(): { string }
	local cached = SERIALIZABLE_PROPERTIES_CACHE
	if cached then return cached end

	local built = buildSerializableProperties()
	SERIALIZABLE_PROPERTIES_CACHE = built
	return built
end

local function getSerializablePropertySet(): { [string]: boolean }
	local cached = SERIALIZABLE_PROPERTY_SET_CACHE
	if cached then return cached end

	local built = toSet(Serializer.getSerializableProperties())
	SERIALIZABLE_PROPERTY_SET_CACHE = built
	return built
end

--[=[
	Returns a set of property names that are writable and should be serialized for a given class name.
	Uses ReflectionService to filter properties based on their Serialized attribute, with a fallback to a predefined list if ReflectionService is unavailable or does not provide information for the class.
	@param className string - The name of the class to get serializable properties for
	@return { [string]: boolean } - A set of property names that are writable and serializable for the class
]=]
function Serializer.getWritableSerializablePropertySetForClass(className: string): { [string]: boolean }
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

	local allowed = Serializer.getWritableSerializablePropertySetForClass(className)
	local byLower = {}
	for propertyName in pairs(allowed) do
		byLower[string.lower(propertyName)] = propertyName
	end

	canonicalPropertyByLowerByClass[className] = byLower
	return byLower
end

local function resolveWritablePropertyName(instance: Instance, propertyName: string): string?
	local allowed = Serializer.getWritableSerializablePropertySetForClass(instance.ClassName)
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

local function readAndSerializeProperty(
	instance: Instance,
	propertyName: string,
	options: {
		getInstanceRefData: ((Instance) -> { guid: string?, path: { string }? }?)?,
	}?
)
	local ok, value = pcall(function()
		return (instance :: any)[propertyName]
	end)
	if not ok then return nil end

	return Serializer.serializeValue(value, options)
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

	local allowedProperties = Serializer.getWritableSerializablePropertySetForClass(className)
	for propertyName in pairs(allowedProperties) do
		local serialized = readAndSerializeProperty(tempInstance, propertyName)
		if serialized ~= nil then defaults[propertyName] = serialized end
	end

	tempInstance:Destroy()
	defaultSerializedPropertiesByClass[className] = defaults
	return defaults
end

--[=[
	Collects the properties of an instance that should be serialized, based on the set of writable and serializable properties for the instance's class.
	Compares each property's serialized value to the default serialized value for that property on a new instance of the same class, and only includes it in the result if it differs from the default.
	@param instance Instance - The instance to collect properties from
	@param options table? - Optional parameters for serialization, such as a function to get reference data for instances
	@return { [string]: any } - A table mapping property names to their serialized values for properties that should be serialized
]=]
function Serializer.collectSerializedProperties(
	instance: Instance,
	options: {
		getInstanceRefData: ((Instance) -> { guid: string?, path: { string }? }?)?,
	}?
): { [string]: any }
	local properties = {}
	local className = instance.ClassName
	local allowedProperties = Serializer.getWritableSerializablePropertySetForClass(className)
	local defaultProperties = getDefaultSerializedPropertiesForClass(className)
	local serializableProperties = Serializer.getSerializableProperties()

	for _, propertyName in ipairs(serializableProperties) do
		if not allowedProperties[propertyName] then continue end

		if propertyName == "Name" or propertyName == "Parent" then continue end
		if propertyName == "Transparency" and instance:IsA("GuiObject") then continue end

		local serialized = readAndSerializeProperty(instance, propertyName, options)
		if serialized ~= nil then
			local defaultSerialized = defaultProperties[propertyName]
			if defaultSerialized == nil or not serializedValuesEqual(serialized, defaultSerialized) then
				properties[propertyName] = serialized
			end
		end
	end

	return properties
end

--[=[
	Applies serialized properties to an instance, using the set of writable and serializable properties for the instance's class to determine which properties can be set.
	Skips certain properties like "Name" and "Parent", and also handles a special case for "Transparency" on GuiObjects.
	@param instance Instance - The instance to apply properties to
	@param properties table? - A table mapping property names to their serialized values
	@param options table? - Optional parameters for deserialization, such as functions to resolve instances by GUID or path
]=]
function Serializer.applySerializedProperties(
	instance: Instance,
	properties: { [string]: any }?,
	options: {
		resolveInstanceByGuid: ((string) -> Instance?)?,
		resolveInstanceByPath: (({ string }) -> Instance?)?,
	}?
)
	if type(properties) ~= "table" then return end

	for propertyName, serialized in pairs(properties) do
		if propertyName ~= "Name" and propertyName ~= "Parent" and propertyName ~= "Source" then
			local targetPropertyName = propertyName
			if propertyName == "Transparency" and instance:IsA("GuiObject") then
				targetPropertyName = "BackgroundTransparency"
			end

			local resolvedProperty = resolveWritablePropertyName(instance, targetPropertyName)
			if not resolvedProperty then continue end

			local deserialized = Serializer.deserializeValue(serialized, options)
			if deserialized ~= nil then
				pcall(function()
					(instance :: any)[resolvedProperty] = deserialized
				end)
			end
		end
	end
end

--[=[
	Applies serialized attributes to an instance by calling SetAttribute for each key-value pair in the attributes table.
	@param instance Instance - The instance to apply attributes to
	@param attributes table? - A table mapping attribute names to their values
]=]
function Serializer.applySerializedAttributes(instance: Instance, attributes: { [string]: any }?)
	if type(attributes) ~= "table" then return end

	for key, value in pairs(attributes) do
		pcall(function()
			instance:SetAttribute(key, value)
		end)
	end
end

--[=[
	Collects the tags of an instance using CollectionService:GetTags, returning them as a sorted array of strings.
	Returns an empty array if CollectionService is unavailable or if GetTags fails.
	@param instance Instance - The instance to collect tags from
	@return { string } - An array of tag names applied to the instance
]=]
function Serializer.collectSerializedTags(instance: Instance): { string }
	if not CollectionService then return {} end

	local ok, tags = pcall(function()
		return CollectionService:GetTags(instance)
	end)

	if not ok or type(tags) ~= "table" then return {} end

	if #tags > 1 then table.sort(tags) end
	return tags
end

--[=[
	Applies serialized tags to an instance by comparing the incoming tags to the existing tags on the instance and adding or removing tags as necessary using CollectionService:AddTag and CollectionService:RemoveTag.
	@param instance Instance - The instance to apply tags to
	@param tags table? - An array of tag names to apply to the instance
]=]
function Serializer.applySerializedTags(instance: Instance, tags: { string }?)
	if type(tags) ~= "table" or not CollectionService then return end

	local existingTagSet: { [string]: boolean } = {}
	local okExisting, existing = pcall(function()
		return CollectionService:GetTags(instance)
	end)
	if okExisting and type(existing) == "table" then
		for _, tagName in ipairs(existing) do
			existingTagSet[tagName] = true
		end
	end

	local incomingTagSet: { [string]: boolean } = {}
	for _, tagName in ipairs(tags) do
		if type(tagName) == "string" and tagName ~= "" then
			incomingTagSet[tagName] = true
			if not existingTagSet[tagName] then
				pcall(function()
					CollectionService:AddTag(instance, tagName)
				end)
			end
		end
	end

	for existingTagName in pairs(existingTagSet) do
		if not incomingTagSet[existingTagName] then
			pcall(function()
				CollectionService:RemoveTag(instance, existingTagName)
			end)
		end
	end
end

return Serializer
