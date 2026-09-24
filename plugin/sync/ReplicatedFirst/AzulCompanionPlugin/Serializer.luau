--!strict
--[[
	Serializer for Roblox data types and instances

	Encodes to the rbx-dom format using the vendored reflection database to decide 
	which properties are worth sending and what type each one carries.

	Decoding additionally accepts the legacy Azul format (pack version 1) so that
	projects packed before the migration stay pushable.

	Ransomwave 2026
]]

local Serializer = {}

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local rbxDom = require("./Vendor/rbx_dom_lua")
local database = require("./Vendor/rbx_dom_lua/database")
local Config = require("./Config")

local EncodedValue = rbxDom.EncodedValue

--[=[
	rbx-dom resolves instance references inside its Rust DOM, so rbx_dom_lua's Ref
	handlers intentionally raise. 328 properties in the database are Ref-typed, so
	Azul resolves them in-band instead: the pod payload carries a GUID and a path.
	This is the one place the wire format diverges from upstream rbx-dom.
]=]
local REF_TYPE = "Ref"

-- Handled structurally by AzulService (name, parent, script source) or sent as
-- their own fields on the instance payload (attributes, tags).
local EXCLUDED_PROPERTIES: { [string]: boolean } = {
	Name = true,
	Parent = true,
	Source = true,
	Attributes = true,
	Tags = true,
}

-- Read-only properties are collected because some round-trip through dedicated
-- paths, such as MeshPart.MeshContent driving InsertService. Writing them back
-- is rejected by the descriptor, which is harmless.
local COLLECTABLE_SCRIPTABILITY: { [string]: boolean } = {
	ReadWrite = true,
	Read = true,
	Custom = true,
}

-- Every rbx-dom type name the database refers to. Used to tell a fully qualified
-- record, `{ Vector3 = { 4, 1.2, 2 } }`, from an ambiguous payload that happens
-- to be a table, such as a Font's `{ family = ..., weight = ... }`.
-- Seeded with the encoder's types that no property declares: Enum and EnumItem
-- cover enum properties and enum-valued attributes, Vector2int16 has an encoder
-- but no declaring property.
local POD_TYPE_NAMES: { [string]: boolean } = {
	Enum = true,
	EnumItem = true,
	Vector2int16 = true,
}
for _, classInfo in database.Classes do
	for _, propertyData in classInfo.Properties do
		local valueType = propertyData.DataType.Value
		if valueType then POD_TYPE_NAMES[valueType] = true end
	end
end

--[=[
	A property descriptor from rbx_dom_lua. The vendored module is untyped, so
	this names the shape rather than checking it: `name`, `dataType` and
	`scriptability` fields, plus `read` and `write` methods.
]=]
export type PropertyDescriptor = any

--[=[
	Supplies the GUID and path that describe an instance reference on the wire.
]=]
export type SerializeOptions = {
	getInstanceRefData: ((Instance) -> { guid: string?, path: { string }? }?)?,
}

--[=[
	Resolvers that turn an encoded instance reference back into a live instance.
]=]
export type DeserializeOptions = {
	resolveInstanceByGuid: ((string) -> Instance?)?,
	resolveInstanceByPath: (({ string }) -> Instance?)?,
}

local serializingDescriptorsByClass: { [string]: { [string]: PropertyDescriptor } } = {}
local writableDescriptorsByClass: { [string]: { [string]: PropertyDescriptor } } = {}
local defaultsByClass: { [string]: { [string]: any } } = {}

-- Logging helpers
local function debugPrint(...)
	if Config.SILENT_MODE or not Config.DEBUG_MODE then return end
	print(`[🐛 {script}]:`, ...)
end

--[=[
	Builds the path from the DataModel down to an instance.
	@param instance Instance - The instance to locate
	@return { string }? - Path segments, or nil when the instance is not parented
	under the DataModel
]=]
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

--[=[
	Walks a path from the DataModel down to an instance. The first segment is
	resolved as a service so that unloaded services are created rather than missed.
	@param pathSegments { string } - Path segments to follow
	@return Instance? - The instance at that path, or nil when any segment is missing
]=]
local function findInstanceByPath(pathSegments: { string }): Instance?
	local current: Instance = game
	for index, segment in pathSegments do
		local nextNode: Instance? = nil

		if index == 1 then
			local ok, service = pcall(function() return game:GetService(segment :: any) end)
			if ok and service then nextNode = service end
		end

		if not nextNode then nextNode = current:FindFirstChild(segment) end
		if not nextNode then return nil end
		current = nextNode
	end

	return current
end

--[=[
	Walks a class and its superclasses to find the properties worth serializing:
	canonical, script-writable, and not marked as non-serializing by the database.
	@param className string - The class to inspect
	@return { string } - Sorted property names
]=]
local function buildSerializingPropertyNames(className: string): { string }
	local names = {}
	local seen: { [string]: boolean } = {}
	local current: string? = className

	while current do
		local classInfo = database.Classes[current]
		if not classInfo then break end

		for propertyName, propertyData in classInfo.Properties do
			-- Subclass definitions shadow superclass ones, so the first sighting wins.
			if seen[propertyName] then continue end
			seen[propertyName] = true

			if EXCLUDED_PROPERTIES[propertyName] then continue end

			local canonical = propertyData.Kind.Canonical
			if not canonical then continue end

			-- Skip what the file format does not persist, and legacy names that
			-- rbx-dom migrates elsewhere (MeshId to MeshContent, BrickColor to
			-- Color). Collecting a migrated name writes the same state twice.
			local serialization = canonical.Serialization
			if serialization == "DoesNotSerialize" then continue end
			if type(serialization) == "table" and serialization.Migrate ~= nil then continue end

			if not COLLECTABLE_SCRIPTABILITY[propertyData.Scriptability] then continue end

			table.insert(names, propertyName)
		end

		current = classInfo.Superclass
	end

	table.sort(names)
	return names
end

--[=[
	Returns cached property descriptors for the properties Azul serializes.
	@param className string - The class to inspect
	@return { [string]: PropertyDescriptor } - Property name to its descriptor
]=]
local function getSerializingDescriptors(className: string): { [string]: PropertyDescriptor }
	local cached = serializingDescriptorsByClass[className]
	if cached then return cached end

	local descriptors = {}
	for _, propertyName in buildSerializingPropertyNames(className) do
		local ok, descriptor = pcall(rbxDom.findCanonicalPropertyDescriptor, className, propertyName)
		if ok and descriptor then descriptors[propertyName] = descriptor end
	end

	serializingDescriptorsByClass[className] = descriptors
	return descriptors
end

--[=[
	Looks up a descriptor for writing. Incoming data is accepted more liberally
	than outgoing data is produced, so properties Azul would not itself collect
	(a Rojo project file may set GuiObject.Transparency, for example) still apply.
	@param className string - The class being written to
	@param propertyName string - The property being written
	@return PropertyDescriptor? - The descriptor, or nil when the property is unknown
]=]
local function getWritableDescriptor(className: string, propertyName: string): PropertyDescriptor?
	local cached = writableDescriptorsByClass[className]
	if not cached then
		cached = {}
		writableDescriptorsByClass[className] = cached
	end

	local existing = cached[propertyName]
	if existing ~= nil then
		if existing == false then return nil end
		return existing
	end

	local ok, descriptor = pcall(rbxDom.findCanonicalPropertyDescriptor, className, propertyName)
	local resolved = if ok and descriptor then descriptor else false
	cached[propertyName] = resolved

	if resolved == false then return nil end
	return resolved
end

--[=[
	Re-encodes a stored default through its canonical encoder.
	The database records defaults using the serialized type, which can differ from
	the canonical one (BasePart.Color is Color3 but defaults to Color3uint8), and
	mismatched tags would never compare equal against a freshly read value.
	@param pod any - The default value in pod form
	@param dataType string - The canonical rbx-dom type name
	@return any - The normalized pod value
]=]
local function normalizeDefaultPod(pod: any, dataType: string): any
	local decodeCalled, decodeOk, value = pcall(EncodedValue.decode, pod)
	if not decodeCalled or not decodeOk or value == nil then return pod end

	local encodeCalled, encodeOk, encoded = pcall(EncodedValue.encode, value, dataType)
	if encodeCalled and encodeOk then return encoded end
	return pod
end

--[=[
	Returns the cached default property values for a class, in pod form.
	@param className string - The class to inspect
	@return { [string]: any } - Property name to normalized pod default
]=]
local function getDefaultsForClass(className: string): { [string]: any }
	local cached = defaultsByClass[className]
	if cached then return cached end

	local defaults = {}
	local classInfo = database.Classes[className]
	local descriptors = getSerializingDescriptors(className)

	if classInfo and classInfo.DefaultProperties then
		for propertyName, defaultPod in classInfo.DefaultProperties do
			local descriptor = descriptors[propertyName]
			if descriptor then defaults[propertyName] = normalizeDefaultPod(defaultPod, descriptor.dataType) end
		end
	end

	defaultsByClass[className] = defaults
	return defaults
end

--[=[
	Encodes an instance reference as a pod-shaped record carrying a GUID and a path.
	@param instance Instance - The referenced instance
	@param options table? - Optional resolver supplying GUID and path data
	@return any - The encoded reference
]=]
local function encodeInstanceRef(instance: Instance, options: SerializeOptions?): any
	local guid: string? = nil
	local path: { string }? = nil

	if options and options.getInstanceRefData then
		local ok, refData = pcall(function() return (options :: any).getInstanceRefData(instance) end)
		if ok and type(refData) == "table" then
			if type(refData.guid) == "string" then guid = refData.guid end
			if type(refData.path) == "table" then path = refData.path end
		elseif not ok then
			warn("[Serializer]: getInstanceRefData failed for", instance:GetFullName(), "Error:", refData)
		end
	end

	if not guid then
		local ok, debugId = pcall(function() return instance:GetDebugId(0) end)
		if ok and type(debugId) == "string" and debugId ~= "" then guid = debugId end
	end

	if not path then path = getInstancePathSegments(instance) end

	return { [REF_TYPE] = { guid = guid, path = path } }
end

--[=[
	Resolves an encoded instance reference back to a live instance.
	@param payload any - The reference payload holding a GUID and/or path
	@param options table? - Optional resolvers keyed by GUID or path
	@return Instance? - The resolved instance, or nil when it cannot be found
]=]
local function resolveInstanceRef(payload: any, options: DeserializeOptions?): Instance?
	if type(payload) ~= "table" then return nil end

	local guid = if type(payload.guid) == "string" then payload.guid else nil
	local path = if type(payload.path) == "table" then payload.path else nil

	if guid and options and options.resolveInstanceByGuid then
		local resolved = options.resolveInstanceByGuid(guid)
		if resolved then return resolved end
	end

	if path then
		if options and options.resolveInstanceByPath then
			local resolved = options.resolveInstanceByPath(path)
			if resolved then return resolved end
		end

		local resolved = findInstanceByPath(path)
		if resolved then return resolved end
	end

	return nil
end

--[=[
	Finds an enum item by its numeric value.
	@param enumItems { any } - Items from Enum.X:GetEnumItems()
	@param value number - The value to match
	@return any - The matching EnumItem, or nil
]=]
local function enumItemFromNumber(enumItems: { any }, value: number): any
	for _, item in enumItems do
		if item.Value == value then return item end
	end
	return nil
end

--[=[
	Finds an enum item by its name.
	@param enumItems { any } - Items from Enum.X:GetEnumItems()
	@param name string - The name to match
	@return any - The matching EnumItem, or nil
]=]
local function enumItemFromName(enumItems: { any }, name: string): any
	for _, item in enumItems do
		if item.Name == name then return item end
	end
	return nil
end

--[=[
	Reads a pack version 1 CFrame, which was written either as a position and a
	nine element rotation, or as a flat list of twelve components.
	@param recordValue any - The legacy CFrame payload
	@return CFrame? - The CFrame, or nil when the payload matches neither shape
]=]
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

--[=[
	Decodes a value written by pack version 1, which tagged records with `__type`.
	Retained so projects packed before the rbx-dom migration remain pushable.
	@param value any - The legacy record
	@param options table? - Optional instance resolvers
	@return any - The decoded Roblox value, or nil when it cannot be decoded
]=]
local function decodeLegacyValue(value: any, options: DeserializeOptions?): any
	local record = value :: { [string]: any }
	local valueType = record.__type
	local payload: any = record

	if type(valueType) ~= "string" then
		if type(record.type) ~= "string" then return value end
		valueType = record.type
		payload = record.value
	end

	if valueType == "Ref" then
		valueType = "InstanceRef"
		payload = { guid = if type(payload) == "string" then payload else nil, path = nil }
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
		local enum = (Enum :: any)[enumName]
		if enum then return enum[record.name] end
		return nil
	end
	if valueType == "Enum" then
		if type(payload) ~= "table" then return nil end
		local enumName = payload.enumType
		if type(enumName) ~= "string" then return nil end
		local enum = (Enum :: any)[enumName]
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
		for _, keypoint in source or {} do
			table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.time, keypoint.value, keypoint.envelope or 0))
		end
		if #keypoints > 0 then return NumberSequence.new(keypoints) end
		return nil
	end
	if valueType == "ColorSequence" then
		local source = record.keypoints
		if type(payload) == "table" and type(payload.keypoints) == "table" then source = payload.keypoints end
		local keypoints = {}
		for _, keypoint in source or {} do
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
		return resolveInstanceRef(source, options)
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

--[=[
	Serializes a standalone value into pod form, inferring the type from the value
	itself. Properties are encoded through their descriptor instead, which is more
	precise; this is for values carrying no declared type, such as attributes.
	@param value any - The value to serialize
	@param options table? - Optional parameters for serialization
	@return any - The pod representation, or nil when the value cannot be encoded
]=]
function Serializer.serializeValue(value: any, options: SerializeOptions?): any
	if typeof(value) == "Instance" then return encodeInstanceRef(value, options) end

	local called, ok, encoded = pcall(EncodedValue.encodeNaive, value)
	if called and ok then return encoded end
	return nil
end

--[=[
	Deserializes a value produced by serializeValue or by a Rojo project file,
	falling back to the pack version 1 decoder for legacy records.
	@param value any - The value to deserialize
	@param options table? - Optional instance resolvers
	@return any - The decoded Roblox value, or nil when it cannot be decoded
]=]
function Serializer.deserializeValue(value: any, options: DeserializeOptions?): any
	if type(value) ~= "table" then return value end

	-- Pack version 1 tagged every record with `__type` (or a `type`/`value` pair);
	-- pod records are single-key tables keyed by the rbx-dom type name.
	if value.__type ~= nil or type(value.type) == "string" then return decodeLegacyValue(value, options) end

	if next(value) == REF_TYPE then return resolveInstanceRef(value[REF_TYPE], options) end

	local called, ok, decoded = pcall(EncodedValue.decode, value)
	if called and ok then return decoded end
	return nil
end

--[=[
	Reshapes a payload that carries the right data in a shape rbx-dom does not
	expect. Rojo project files and pack version 1 both write flat component lists
	and capitalised keys where rbx-dom uses nested pairs and lowercase ones.
	@param payload any - The untagged payload
	@param dataType string - The declared rbx-dom type of the target property
	@return any - The payload in the shape EncodedValue expects
]=]
local function coercePodPayload(payload: any, dataType: string): any
	if type(payload) ~= "table" then return payload end

	if dataType == "CFrame" and #payload == 12 then
		return {
			position = { payload[1], payload[2], payload[3] },
			orientation = {
				{ payload[4], payload[5], payload[6] },
				{ payload[7], payload[8], payload[9] },
				{ payload[10], payload[11], payload[12] },
			},
		}
	end

	if dataType == "UDim2" and #payload == 4 then return { { payload[1], payload[2] }, { payload[3], payload[4] } } end

	if dataType == "PhysicalProperties" and payload.Density ~= nil then
		return {
			density = payload.Density,
			friction = payload.Friction,
			elasticity = payload.Elasticity,
			frictionWeight = payload.FrictionWeight,
			elasticityWeight = payload.ElasticityWeight,
		}
	end

	if dataType == "NumberSequence" or dataType == "ColorSequence" then
		local isColor = dataType == "ColorSequence"
		local source = if type(payload.keypoints) == "table" then payload.keypoints else payload
		if type(source) ~= "table" then return payload end

		local keypoints = {}
		for index, keypoint in source do
			if type(keypoint) ~= "table" then return payload end

			if #keypoint > 0 then
				-- Flat list form: [time, value] or [time, r, g, b]
				keypoints[index] = if isColor
					then { time = keypoint[1], color = { keypoint[2], keypoint[3], keypoint[4] } }
					else { time = keypoint[1], value = keypoint[2], envelope = keypoint[3] or 0 }
			elseif isColor then
				keypoints[index] = { time = keypoint.time, color = keypoint.color or keypoint.value }
			else
				keypoints[index] = { time = keypoint.time, value = keypoint.value, envelope = keypoint.envelope or 0 }
			end
		end

		return { keypoints = keypoints }
	end

	return payload
end

--[=[
	Decodes a property value, accepting fully qualified records, the ambiguous
	bare forms Rojo project files use ("Size": [4, 1.2, 2]), and pack version 1
	records. A bare form is the pod payload with its type tag left off, so the
	property's declared type supplies the tag. Scalars need no tag at all: Roblox
	coerces strings and numbers assigned to enum properties.
	@param encoded any - The incoming value
	@param dataType string - The declared rbx-dom type of the target property
	@param options table? - Optional instance resolvers
	@return any - The decoded Roblox value, or nil when it cannot be decoded
]=]
local function decodePropertyValue(encoded: any, dataType: string, options: DeserializeOptions?): any
	-- Legacy records and references describe their own type.
	if type(encoded) == "table" and (encoded.__type ~= nil or type(encoded.type) == "string") then
		return decodeLegacyValue(encoded, options)
	end
	if dataType == REF_TYPE then return Serializer.deserializeValue(encoded, options) end

	-- Scalars need no tag: Roblox coerces strings and numbers on assignment.
	if type(encoded) ~= "table" then return encoded end

	-- Coercion has to happen before decoding rather than as a fallback, because
	-- some constructors accept a wrong-shaped payload instead of failing.
	-- PhysicalProperties.new(nil, ...) yields a density of 0.0001 rather than
	-- raising, so a capitalised payload would decode to silent garbage.
	local tag = next(encoded)
	if type(tag) == "string" and POD_TYPE_NAMES[tag] then
		local called, ok, resolved = pcall(EncodedValue.decode, { [tag] = coercePodPayload(encoded[tag], tag) })
		if called and ok then return resolved end
	end

	local called, ok, resolved = pcall(EncodedValue.decode, { [dataType] = coercePodPayload(encoded, dataType) })
	if called and ok then return resolved end
	return nil
end

--[=[
	Compares two encoded values structurally, so a freshly read property can be
	tested against its class default without decoding either side.
	@param left any - An encoded value
	@param right any - An encoded value
	@return boolean - Whether the two describe the same value
]=]
local function serializedValuesEqual(left: any, right: any): boolean
	if type(left) ~= type(right) then return false end

	if type(left) ~= "table" then return left == right end

	for key, value in left do
		if not serializedValuesEqual(value, right[key]) then return false end
	end

	for key in right do
		if left[key] == nil then return false end
	end

	return true
end

--[=[
	Collects the properties of an instance that differ from its class defaults,
	encoded in pod form.
	@param instance Instance - The instance to read
	@param options table? - Optional parameters for serialization
	@return { [string]: any } - Property name to pod value
]=]
function Serializer.collectSerializedProperties(instance: Instance, options: SerializeOptions?): { [string]: any }
	local className = instance.ClassName
	local descriptors = getSerializingDescriptors(className)
	local defaults = getDefaultsForClass(className)
	local properties = {}

	for propertyName, descriptor in descriptors do
		-- Custom descriptors can throw (e.g. a missing custom property mapping)
		local readCalled, readOk, value = pcall(descriptor.read, descriptor, instance)
		if not readCalled or not readOk or value == nil then
			debugPrint(
				`Failed to read {className}.{propertyName}: {if readCalled then tostring(value) else tostring(readOk)}`
			)
			continue
		end

		local encoded
		if descriptor.dataType == REF_TYPE then
			if typeof(value) ~= "Instance" then continue end
			encoded = encodeInstanceRef(value, options)
		else
			local called, ok, result = pcall(EncodedValue.encode, value, descriptor.dataType)
			encoded = if called and ok then result else nil
		end

		if encoded == nil then continue end

		local default = defaults[propertyName]
		if default == nil or not serializedValuesEqual(encoded, default) then properties[propertyName] = encoded end
	end

	debugPrint(`Collected properties for {instance:GetFullName()}: {HttpService:JSONEncode(properties)}`)

	return properties
end

--[=[
	Applies serialized properties to an instance.
	@param instance Instance - The instance to write to
	@param properties table? - Property name to encoded value
	@param options table? - Optional instance resolvers
]=]
function Serializer.applySerializedProperties(
	instance: Instance,
	properties: { [string]: any }?,
	options: DeserializeOptions?
)
	if type(properties) ~= "table" then return end

	local className = instance.ClassName

	for propertyName, encoded in properties do
		if EXCLUDED_PROPERTIES[propertyName] then continue end

		local descriptor = getWritableDescriptor(className, propertyName)
		if not descriptor then continue end

		local value = decodePropertyValue(encoded, descriptor.dataType, options)
		if value == nil then continue end

		-- Custom descriptors can throw, so one rejected property must not abort the rest
		local called, writeOk, err = pcall(descriptor.write, descriptor, instance, value)
		if not called or not writeOk then
			debugPrint(
				`Failed to write {className}.{propertyName}: {if called then tostring(err) else tostring(writeOk)}`
			)
		end
	end
end

--[=[
	Collects an instance's attributes in pod form. Encoding each value keeps
	non-primitive attributes (Vector3, Color3, UDim2) intact across JSON, which
	pack version 1 turned into nulls.
	@param instance Instance - The instance to read
	@return { [string]: any } - Attribute name to pod value
]=]
function Serializer.collectSerializedAttributes(instance: Instance): { [string]: any }
	local attributes = {}

	for key, value in instance:GetAttributes() do
		local called, ok, encoded = pcall(EncodedValue.encodeNaive, value)
		if called and ok then attributes[key] = encoded end
	end

	return attributes
end

--[=[
	Applies serialized attributes to an instance.
	@param instance Instance - The instance to write to
	@param attributes table? - Attribute name to encoded or raw value
]=]
function Serializer.applySerializedAttributes(instance: Instance, attributes: { [string]: any }?)
	if type(attributes) ~= "table" then return end

	for key, encoded in attributes do
		-- Pod values arrive as single-key tables; pack version 1 sent JSON primitives.
		local value = if type(encoded) == "table" then Serializer.deserializeValue(encoded) else encoded
		if value ~= nil then pcall(function() instance:SetAttribute(key, value) end) end
	end
end

--[=[
	Collects the tags of an instance as a sorted array of strings.
	@param instance Instance - The instance to read
	@return { string } - Tag names applied to the instance
]=]
function Serializer.collectSerializedTags(instance: Instance): { string }
	if not CollectionService then return {} end

	local ok, tags = pcall(function() return CollectionService:GetTags(instance) end)

	if not ok or type(tags) ~= "table" then return {} end

	if #tags > 1 then table.sort(tags) end
	return tags
end

--[=[
	Applies serialized tags to an instance, adding and removing as needed so the
	instance ends up with exactly the incoming set.
	@param instance Instance - The instance to write to
	@param tags table? - Tag names to apply
]=]
function Serializer.applySerializedTags(instance: Instance, tags: { string }?)
	if type(tags) ~= "table" or not CollectionService then return end

	local existingTagSet: { [string]: boolean } = {}
	local okExisting, existing = pcall(function() return CollectionService:GetTags(instance) end)
	if okExisting and type(existing) == "table" then
		for _, tagName in existing do
			existingTagSet[tagName] = true
		end
	end

	local incomingTagSet: { [string]: boolean } = {}
	for _, tagName in tags do
		if type(tagName) == "string" and tagName ~= "" then
			incomingTagSet[tagName] = true
			if not existingTagSet[tagName] then pcall(function() CollectionService:AddTag(instance, tagName) end) end
		end
	end

	for existingTagName in existingTagSet do
		if not incomingTagSet[existingTagName] then
			pcall(function() CollectionService:RemoveTag(instance, existingTagName) end)
		end
	end
end

return Serializer
