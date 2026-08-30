--!strict

--[[
	The entry point for the Fusion library.
]]

local PubTypes = require("./src/PubTypes")
local External = require("./src/External")
local restrictRead = require("./src/Utility/restrictRead")

-- Down the line, this will be conditional based on whether Fusion is being
-- compiled for Roblox.
do
	local RobloxExternal = require("./src/RobloxExternal")
	External.setExternalScheduler(RobloxExternal)
end

local Fusion = restrictRead("Fusion", {
	version = {major = 0, minor = 3, isRelease = false},

	New = require("./src/Instances/New"),
	Hydrate = require("./src/Instances/Hydrate"),
	Ref = require("./src/Instances/Ref"),
	Out = require("./src/Instances/Out"),
	Cleanup = require("./src/Instances/Cleanup"),
	Children = require("./src/Instances/Children"),
	OnEvent = require("./src/Instances/OnEvent"),
	OnChange = require("./src/Instances/OnChange"),
	Attribute = require("./src/Instances/Attribute"),
	AttributeChange = require("./src/Instances/AttributeChange"),
	AttributeOut = require("./src/Instances/AttributeOut"),

	Value = require("./src/State/Value"),
	Computed = require("./src/State/Computed"),
	ForPairs = require("./src/State/ForPairs"),
	ForKeys = require("./src/State/ForKeys"),
	ForValues = require("./src/State/ForValues"),
	Observer = require("./src/State/Observer"),

	Tween = require("./src/Animation/Tween"),
	Spring = require("./src/Animation/Spring"),

	Contextual = require("./src/Utility/Contextual"),
	cleanup = require("./src/Utility/cleanup"),
	doNothing = require("./src/Utility/doNothing"),
	peek = require("./src/State/peek")
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
