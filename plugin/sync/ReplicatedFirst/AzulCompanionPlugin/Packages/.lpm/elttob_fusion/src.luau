--!strict
--!nolint LocalUnused
--!nolint LocalShadow
local task = nil -- Disable usage of Roblox's task scheduler
--[[
	The entry point for the Fusion library.
]]

local Types = require("./src/Types")
local External = require("./src/External")

type Fusion = Types.Fusion

export type Animatable = Types.Animatable
export type UsedAs<T> = Types.UsedAs<T>
export type Child = Types.Child
export type Computed<T> = Types.Computed<T>
export type Contextual<T> = Types.Contextual<T>
export type GraphObject = Types.GraphObject
export type For<KO, VO> = Types.For<KO, VO>
export type Observer = Types.Observer
export type PropertyTable = Types.PropertyTable
export type Scope<Constructors = Fusion> = Types.Scope<Constructors>
export type ScopedObject = Types.ScopedObject
export type SpecialKey = Types.SpecialKey
export type Spring<T> = Types.Spring<T>
export type StateObject<T> = Types.StateObject<T>
export type Task = Types.Task
export type Tween<T> = Types.Tween<T>
export type Use = Types.Use
export type Value<T, S = T> = Types.Value<T, S>
export type Version = Types.Version

-- Down the line, this will be conditional based on whether Fusion is being
-- compiled for Roblox.
do
	local RobloxExternal = require("./src/RobloxExternal")
	External.setExternalProvider(RobloxExternal)
end

local Fusion: Fusion = table.freeze {
	-- General
	version = {major = 0, minor = 3, isRelease = true},
	Contextual = require("./src/Utility/Contextual"),
	Safe = require("./src/Utility/Safe"),

	-- Memory
	cleanup = require("./src/Memory/legacyCleanup"),
	deriveScope = require("./src/Memory/deriveScope"),
	doCleanup = require("./src/Memory/doCleanup"),
	innerScope = require("./src/Memory/innerScope"),
	scoped = require("./src/Memory/scoped"),
	
	-- Graph
	Observer = require("./src/Graph/Observer"),

	-- State
	Computed = require("./src/State/Computed"),
	ForKeys = require("./src/State/ForKeys") :: Types.ForKeysConstructor,
	ForPairs = require("./src/State/ForPairs") :: Types.ForPairsConstructor,
	ForValues = require("./src/State/ForValues") :: Types.ForValuesConstructor,
	peek = require("./src/State/peek"),
	Value = require("./src/State/Value"),

	-- Roblox API
	Attribute = require("./src/Instances/Attribute"),
	AttributeChange = require("./src/Instances/AttributeChange"),
	AttributeOut = require("./src/Instances/AttributeOut"),
	Child = require("./src/Instances/Child"),
	Children = require("./src/Instances/Children"),
	Hydrate = require("./src/Instances/Hydrate"),
	New = require("./src/Instances/New"),
	OnChange = require("./src/Instances/OnChange"),
	OnEvent = require("./src/Instances/OnEvent"),
	Out = require("./src/Instances/Out"),

	-- Animation
	Tween = require("./src/Animation/Tween"),
	Spring = require("./src/Animation/Spring"),
}

return Fusion
