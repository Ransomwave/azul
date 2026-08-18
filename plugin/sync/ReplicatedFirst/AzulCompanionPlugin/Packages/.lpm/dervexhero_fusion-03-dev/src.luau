--!strict

--[[
	The entry point for the Fusion library.
]]

local PubTypes = require("@self/PubTypes")
local External = require("@self/External")
local restrictRead = require("@self/Utility/restrictRead")

-- Down the line, this will be conditional based on whether Fusion is being
-- compiled for Roblox.
do
	local RobloxExternal = require("@self/RobloxExternal")
	External.setExternalScheduler(RobloxExternal)
end

local Fusion = restrictRead("Fusion", {
	version = {major = 0, minor = 3, isRelease = false},

	New = require("@self/Instances/New"),
	Hydrate = require("@self/Instances/Hydrate"),
	Ref = require("@self/Instances/Ref"),
	Out = require("@self/Instances/Out"),
	Cleanup = require("@self/Instances/Cleanup"),
	Children = require("@self/Instances/Children"),
	OnEvent = require("@self/Instances/OnEvent"),
	OnChange = require("@self/Instances/OnChange"),
	Attribute = require("@self/Instances/Attribute"),
	AttributeChange = require("@self/Instances/AttributeChange"),
	AttributeOut = require("@self/Instances/AttributeOut"),

	Value = require("@self/State/Value"),
	Computed = require("@self/State/Computed"),
	ForPairs = require("@self/State/ForPairs"),
	ForKeys = require("@self/State/ForKeys"),
	ForValues = require("@self/State/ForValues"),
	Observer = require("@self/State/Observer"),

	Tween = require("@self/Animation/Tween"),
	Spring = require("@self/Animation/Spring"),

	Contextual = require("@self/Utility/Contextual"),
	cleanup = require("@self/Utility/cleanup"),
	doNothing = require("@self/Utility/doNothing"),
	peek = require("@self/State/peek")
}) :: Fusion

export type StateObject<T> = PubTypes.StateObject<T>
export type CanBeState<T> = PubTypes.CanBeState<T>
export type Symbol = PubTypes.Symbol
export type Value<T> = PubTypes.Value<T>
export type Computed<T> = PubTypes.Computed<T>
export type ForPairs<KO, VO> = PubTypes.ForPairs<KO, VO>
export type ForKeys<KI, KO> = PubTypes.ForKeys<KI, KO>
export type ForValues<VI, VO> = PubTypes.ForKeys<VI, VO>
export type Observer = PubTypes.Observer
export type Tween<T> = PubTypes.Tween<T>
export type Spring<T> = PubTypes.Spring<T>
export type Use = PubTypes.Use
export type Contextual<T> = PubTypes.Contextual<T>

type Fusion = {
	version: PubTypes.Version,

	New: (className: string) -> ((propertyTable: PubTypes.PropertyTable) -> Instance),
	Hydrate: (target: Instance) -> ((propertyTable: PubTypes.PropertyTable) -> Instance),
	Ref: PubTypes.SpecialKey,
	Cleanup: PubTypes.SpecialKey,
	Children: PubTypes.SpecialKey,
	Out: (propertyName: string) -> PubTypes.SpecialKey,
	OnEvent: (eventName: string) -> PubTypes.SpecialKey,
	OnChange: (propertyName: string) -> PubTypes.SpecialKey,
	Attribute: (attributeName: string) -> PubTypes.SpecialKey,
	AttributeChange: (attributeName: string) -> PubTypes.SpecialKey,
	AttributeOut: (attributeName: string) -> PubTypes.SpecialKey,

	Value: <T>(initialValue: T) -> Value<T>,
	Computed: <T>(callback: (Use) -> T, destructor: (T) -> ()?) -> Computed<T>,
	ForPairs: <KI, VI, KO, VO, M>(inputTable: CanBeState<{[KI]: VI}>, processor: (Use, KI, VI) -> (KO, VO, M?), destructor: (KO, VO, M?) -> ()?) -> ForPairs<KO, VO>,
	ForKeys: <KI, KO, M>(inputTable: CanBeState<{[KI]: any}>, processor: (Use, KI) -> (KO, M?), destructor: (KO, M?) -> ()?) -> ForKeys<KO, any>,
	ForValues: <VI, VO, M>(inputTable: CanBeState<{[any]: VI}>, processor: (Use, VI) -> (VO, M?), destructor: (VO, M?) -> ()?) -> ForValues<any, VO>,
	Observer: (watchedState: StateObject<any>) -> Observer,

	Tween: <T>(goalState: StateObject<T>, tweenInfo: TweenInfo?) -> Tween<T>,
	Spring: <T>(goalState: StateObject<T>, speed: CanBeState<number>?, damping: CanBeState<number>?) -> Spring<T>,

	Contextual: <T>(defaultValue: T) -> Contextual<T>,
	cleanup: (...any) -> (),
	doNothing: (...any) -> (),
	peek: Use
}

return Fusion
