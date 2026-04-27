--!strict

--[[
    SyncSession - Class for managing a sync session between the Azul plugin and the daemon.

    Ransomwave 2026
]]

local SyncSession = {}
SyncSession.__index = SyncSession

-- Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Modules
local AzulService = require("../AzulService")
local Enums = require("../Enums")
local SettingsStore = require("../SettingsStore")
local WebSocketClient = require("../WebSocketClient")

export type SyncSession = {
	-- Constructor fields
	plugin: Plugin,
	settingsStore: SettingsStore.SettingsStore,
	config: any,
	ui: any?,

	-- State fields
	syncEnabled: boolean,
	wsClient: any,
	trackedInstances: { [Instance]: string },
	guidMap: { [string]: Instance },
	usedGuids: { [string]: boolean },
	lastHeartbeat: number,
	applyingPatch: boolean,
	lastPatchTime: { [string]: number },
	recentPatches: { [string]: boolean },
	lastInstanceUpdate: { [string]: { key: string, t: number } },
	connections: { RBXScriptConnection },
	suppressOutbound: boolean,
	pendingInstanceUpdates: { [string]: any },
	pendingScriptChanges: { [string]: any },
	pendingScriptChangeReady: { [string]: boolean },
	scriptChangeDebounceTokenByGuid: { [string]: number },
	pendingDeletes: { [string]: boolean },
	batchingEnabled: boolean,
	batchFlushToken: number,
	batchAccumulator: number,
	serviceSet: { [string]: boolean },

	-- Methods
	startSync: (self: SyncSession) -> (),
	stopSync: (self: SyncSession, dontRelayDisconnect: boolean?) -> (),
	reloadSourcemap: (self: SyncSession) -> (),
	onSettingsScopeChanged: (self: SyncSession, newScope: string) -> (),
	setUI: (self: SyncSession, ui: any) -> (),
	debugPrint: (self: SyncSession, ...any) -> (),
	infoPrint: (self: SyncSession, ...any) -> (),
	rebuildServiceSet: (self: SyncSession) -> (),
}

-- Constants
local PUSH_CONFIG_PATH = {
	"ServerStorage",
	"Azul",
	"Config",
}

-- Legacy! Does not get used after initial snapshot!
local INITIAL_BATCH_INTERVAL = 0.2 -- Seconds between outbound batch flushes

local function safeGetNumber(value: any, default: number)
	if type(value) == "number" and value > 0 then return value end
	return default
end

function SyncSession:debugPrint(...)
	if self.config.SILENT_MODE or not self.config.DEBUG_MODE then return end
	print(`[🐛 Azul]:`, ...)
end

function SyncSession:infoPrint(...)
	if self.config.SILENT_MODE then return end
	print(`[Azul]:	`, ...)
end

function SyncSession:rebuildServiceSet()
	AzulService.rebuildServiceSet(self.serviceSet)
end

function SyncSession:setUI(ui)
	self.ui = ui
end

function SyncSession.new(plugin: Plugin, settingsStore: SettingsStore.SettingsStore, config: any): SyncSession
	local self = (setmetatable({}, SyncSession) :: any) :: SyncSession

	self.plugin = plugin
	self.settingsStore = settingsStore
	self.config = config
	self.ui = nil

	self.syncEnabled = false
	self.wsClient = nil
	self.trackedInstances = {}
	self.guidMap = {}
	self.usedGuids = {}
	self.lastHeartbeat = 0
	self.applyingPatch = false
	self.lastPatchTime = {}
	self.recentPatches = {}
	self.lastInstanceUpdate = {}
	self.connections = {}
	self.suppressOutbound = false

	self.pendingInstanceUpdates = {}
	self.pendingScriptChanges = {}
	self.pendingScriptChangeReady = {}
	self.scriptChangeDebounceTokenByGuid = {}
	self.pendingDeletes = {}

	self.batchingEnabled = false
	self.batchFlushToken = 0
	self.batchAccumulator = 0
	self.serviceSet = {}

	self:rebuildServiceSet()

	local function shouldIncludeInSnapshot(instance)
		if not instance then return false end
		return not AzulService.isExcluded(instance, self.serviceSet)
	end

	local function sendMessage(messageTypeOrPayload: string | { any }, data: any?)
		if not self.wsClient or not self.wsClient.connected then return false end

		local message

		-- If the caller provided a string, wrap it in a message object with the string as the "type" field and the data as the "data" field.
		-- If the caller provided a table, use it directly as the message object.
		if type(messageTypeOrPayload) == "table" then
			message = {}
			for key, value in pairs(messageTypeOrPayload) do
				message[key] = value
			end
		else
			message = {
				type = messageTypeOrPayload,
			}
			for key, value in pairs(data or {}) do
				message[key] = value
			end
		end

		self:debugPrint(`Sending message: {message.type}`)
		local json = HttpService:JSONEncode(message)
		return self.wsClient:send(json)
	end

	local function flushOutboundQueues()
		local messages: { [number]: { type: string, data: any } } = {}

		for _, data in pairs(self.pendingInstanceUpdates) do
			table.insert(messages, {
				type = "instanceUpdated",
				data = data,
			})
		end

		for _, payload in pairs(self.pendingScriptChanges) do
			if self.pendingScriptChangeReady[payload.guid] == true then
				table.insert(messages, {
					type = "scriptChanged",
					data = {
						guid = payload.guid,
						path = payload.path,
						className = payload.className,
						source = payload.source,
					},
				})
				self.pendingScriptChanges[payload.guid] = nil
				self.pendingScriptChangeReady[payload.guid] = nil
				self.scriptChangeDebounceTokenByGuid[payload.guid] = nil
			end
		end

		for guid, shouldSend in pairs(self.pendingDeletes) do
			if shouldSend then
				table.insert(messages, {
					type = "deleted",
					data = {
						guid = guid,
					},
				})
			end
		end

		table.clear(self.pendingInstanceUpdates)
		table.clear(self.pendingDeletes)

		if #messages == 0 then return end

		if self.batchingEnabled and #messages > 1 then
			if #messages > 200 then
				self:debugPrint(`Too many messages ({#messages}) in batch, sending full snapshot instead.`)
				self:reloadSourcemap()
			else
				sendMessage("batch", { messages = messages })
			end
		else
			for _, message in messages do
				sendMessage(message)
			end
		end
	end

	local function scheduleBatchFlush()
		if not self.batchingEnabled then return end

		self.batchFlushToken += 1
		local token = self.batchFlushToken

		task.delay(safeGetNumber(self.config.BATCH_IDLE_WINDOW, 0.1), function()
			if token ~= self.batchFlushToken then return end
			flushOutboundQueues()
		end)
	end

	local function queueInstanceUpdate(data)
		if self.suppressOutbound or not self.syncEnabled then return end
		if not data or not data.guid then return end

		self.pendingInstanceUpdates[data.guid] = data
		scheduleBatchFlush()
	end

	local function queueScriptChange(payload)
		if self.suppressOutbound or not self.syncEnabled then return end
		if not payload or not payload.guid then return end

		self.pendingScriptChangeReady[payload.guid] = false
		self.pendingScriptChanges[payload.guid] = payload

		local token = (self.scriptChangeDebounceTokenByGuid[payload.guid] or 0) + 1
		self.scriptChangeDebounceTokenByGuid[payload.guid] = token

		task.delay(safeGetNumber(self.config.SCRIPT_CHANGE_DEBOUNCE, 0.35), function()
			if not self.syncEnabled or self.suppressOutbound then return end
			if self.scriptChangeDebounceTokenByGuid[payload.guid] ~= token then return end
			if not self.pendingScriptChanges[payload.guid] then return end

			self.pendingScriptChangeReady[payload.guid] = true
			scheduleBatchFlush()
		end)
	end

	local function queueDeletion(guid: string)
		if self.suppressOutbound or not self.syncEnabled then return end
		if not guid or guid == "" then return end

		self.pendingDeletes[guid] = true
		scheduleBatchFlush()
	end

	local function setOutboundSuppressed(suppressed: boolean)
		self.suppressOutbound = suppressed
		if suppressed then
			table.clear(self.pendingInstanceUpdates)
			table.clear(self.pendingScriptChanges)
			table.clear(self.pendingScriptChangeReady)
			table.clear(self.scriptChangeDebounceTokenByGuid)
			table.clear(self.pendingDeletes)
		end
	end

	local function sendInstanceUpdateDedup(instance)
		if self.suppressOutbound or not self.syncEnabled then return end

		local data = AzulService.instanceToDataDedup(
			instance,
			self.trackedInstances,
			self.guidMap,
			self.usedGuids,
			self.lastInstanceUpdate
		)
		if not data then return end

		local guid = data.guid
		self.trackedInstances[instance] = guid
		self.guidMap[guid] = instance

		queueInstanceUpdate(data)
	end

	local function shouldSync(instance)
		if not instance then return false end
		if not AzulService.isScript(instance) then return false end
		return not AzulService.isExcluded(instance, self.serviceSet)
	end

	local function onScriptChanged(changedScript: Script | LocalScript | ModuleScript)
		if self.suppressOutbound or not shouldSync(changedScript) then return end

		local guid = AzulService.getOrCreateGUID(changedScript, self.trackedInstances, self.guidMap, self.usedGuids)

		if self.recentPatches[guid] then
			self:debugPrint(
				"Ignoring change (was just patched from daemon):",
				`{changedScript.Parent}.{changedScript.Name}`
			)
			self.recentPatches[guid] = nil
			return
		end

		if self.applyingPatch then return end

		local lastPatch = self.lastPatchTime[guid] or 0
		local now = tick()
		if now - lastPatch < 1 then
			self:debugPrint("Ignoring change (too soon after patch):", `{changedScript.Parent}.{changedScript.Name}`)
			return
		end

		local path = AzulService.getInstancePath(changedScript)
		if not path then return end

		queueScriptChange({
			guid = guid,
			path = path,
			className = changedScript.ClassName,
			source = changedScript.Source,
		})
	end

	local function attachListeners(instance)
		if not shouldIncludeInSnapshot(instance) then return end

		local nameConnnection = instance:GetPropertyChangedSignal("Name"):Connect(function()
			sendInstanceUpdateDedup(instance)
		end)
		table.insert(self.connections, nameConnnection)

		local parentConnection = instance:GetPropertyChangedSignal("Parent"):Connect(function()
			if instance.Parent == nil then return end
			sendInstanceUpdateDedup(instance)
		end)
		table.insert(self.connections, parentConnection)

		if AzulService.isScript(instance) then
			local sourceConnection = (instance :: Script):GetPropertyChangedSignal("Source"):Connect(function()
				if self.syncEnabled then onScriptChanged(instance :: Script) end
			end)
			table.insert(self.connections, sourceConnection)
		end
	end

	local function wipeChildren(container: Instance)
		for _, child in ipairs(container:GetChildren()) do
			if AzulService.isProtectedRobloxContainer(child) then continue end
			local ok, err = pcall(function()
				child:Destroy()
			end)
			if not ok then warn(`[Azul]: Cannot destroy '{child.Name}': {err}`) end
		end
	end

	local function wipeBuildRoots(instances: { any })
		local rootsSeen = {}

		for _, item in ipairs(instances) do
			local path = item.path
			if type(path) == "table" and #path >= 1 then
				local rootName = path[1]
				if type(rootName) == "string" and rootName ~= "" then rootsSeen[rootName] = true end
			end
		end

		for rootName in pairs(rootsSeen) do
			local rootInstance: Instance? = nil

			local okService, service = pcall(function()
				return game:GetService(rootName)
			end)
			if okService and service then
				rootInstance = service
			else
				rootInstance = game:FindFirstChild(rootName)
			end

			if rootInstance then
				local ok, err = pcall(function()
					wipeChildren(rootInstance)
				end)
				if not ok then warn(`[Azul]: Failed to wipe children for root container '{rootName}': {err}`) end
			else
				warn(`[Azul]: Destructive build could not find root container '{rootName}', skipping wipe`)
			end
		end
	end

	local function sendDaemonConfig(warnOnFail: boolean?)
		local configPayload, err = AzulService.readPushConfig(PUSH_CONFIG_PATH)
		if not configPayload then
			if warnOnFail then
				warn(`[Azul]: daemon config unavailable: {err}`)
			else
				self:debugPrint(`daemon config unavailable: {err}`)
			end
			return false
		end

		return sendMessage("pushConfig", {
			config = configPayload,
		})
	end

	local function onInstanceAdded(instance: Instance)
		if self.suppressOutbound then return end
		if not shouldIncludeInSnapshot(instance) then return end

		local data = AzulService.instanceToData(instance, self.trackedInstances, self.guidMap, self.usedGuids)
		if not data then return end
		sendInstanceUpdateDedup(instance)
		attachListeners(instance)
	end

	local function onInstanceRemoved(instance)
		if self.suppressOutbound then return end
		if not self.trackedInstances[instance] then return end

		local guid = self.trackedInstances[instance]
		if not guid then guid = instance:GetDebugId(0) end
		if not guid then return end

		self.trackedInstances[instance] = nil
		self.guidMap[guid] = nil
		self.usedGuids[guid] = nil

		queueDeletion(guid)
	end

	local sendFullSnapshot
	local function processMessage(message)
		self:debugPrint("Processing message type:", message.type)

		if message.type == "patchScript" then
			self:debugPrint("Patch requested for GUID:", message.guid)
			local instance = self.guidMap[message.guid]
			if instance and AzulService.isScript(instance) then
				setOutboundSuppressed(true)
				self.recentPatches[message.guid] = true
				self.lastPatchTime[message.guid] = tick()

				self.applyingPatch = true
				AzulService.setScriptSource(instance :: Script, message.source)

				task.delay(0.2, function()
					self.applyingPatch = false
					setOutboundSuppressed(false)
				end)

				self:infoPrint("Updated script:", `{instance.Parent}.{instance.Name}`)

				task.delay(0.2, function()
					task.wait(0.2)
					self.recentPatches[message.guid] = nil
				end)
			else
				warn("[Azul]: Cannot apply patch - instance not found for GUID:", message.guid)
				local count = 0
				for _ in pairs(self.guidMap) do
					count += 1
				end
				warn("[Azul]: Total tracked instances:", count)
			end
		elseif message.type == "requestSnapshot" then
			self:infoPrint("Snapshot requested by daemon")
			sendFullSnapshot(message.options)
		elseif message.type == "buildSnapshot" then
			self:infoPrint("Applying build snapshot from daemon")
			setOutboundSuppressed(true)

			local ok, err = pcall(function()
				if message.destructive == true then wipeBuildRoots(message.data or {}) end

				local created, updated, appliedGuidMap = AzulService.applySnapshotInstances(message.data)
				for guid, instance in pairs(appliedGuidMap) do
					self.guidMap[guid] = instance
					self.trackedInstances[instance] = guid
					attachListeners(instance)
				end
				self:infoPrint(`Build snapshot applied ({created} created, {updated} updated)`)
			end)

			setOutboundSuppressed(false)
			if not ok then warn("[Azul]: Error applying build snapshot: ", err) end

			task.delay(0.5, function()
				self:stopSync()
			end)
		elseif message.type == "pushSnapshot" then
			self:infoPrint("Applying push snapshot from daemon")
			setOutboundSuppressed(true)

			local ok, err = pcall(function()
				for _, mapping in ipairs(message.mappings or {}) do
					local destination = mapping.destination or {}
					if #destination == 0 then
						warn("[Azul]: Push mapping missing destination; skipping")
						continue
					end

					self:debugPrint(
						`Destination for push snapshot: {table.concat(destination, "/")}, destructive: {tostring(
							mapping.destructive
						)}`
					)

					local targetContainer = AzulService.getOrCreatePath(destination)
					if mapping.destructive then wipeChildren(targetContainer) end

					local created, updated, appliedGuidMap =
						AzulService.applySnapshotInstances(mapping.instances or {}, mapping.destination)
					for guid, instance in pairs(appliedGuidMap) do
						self.guidMap[guid] = instance
						self.trackedInstances[instance] = guid
						attachListeners(instance)
					end
					self:infoPrint(
						`Push applied to {table.concat(destination, "/")} ({created} created, {updated} updated)`
					)
				end
			end)

			setOutboundSuppressed(false)
			if not ok then warn("[Azul]: Error applying push snapshot", err) end

			task.delay(0.5, function()
				self:stopSync()
			end)
		elseif message.type == "requestPushConfig" then
			sendDaemonConfig(true)
		elseif message.type == "daemonDisconnect" then
			self:infoPrint("Daemon is shutting down; disconnecting plugin")
			self:stopSync(true)
		elseif message.type == "error" then
			warn("[Azul]: Daemon error:", message.message)
		elseif message.type == "pong" then
			self:debugPrint("Received pong")
		else
			warn("[Azul]: Unknown message type:", message.type)
		end
	end

	sendFullSnapshot = function(options: { includeProperties: boolean, scriptsAndDescendantsOnly: boolean }?)
		self:infoPrint("Sending full snapshot...")

		local includeProperties = options and options.includeProperties == true
		local scriptsAndDescendantsOnly = options and options.scriptsAndDescendantsOnly == true
		local includeAncestorsOfScripts: { [Instance]: boolean } = {}

		if scriptsAndDescendantsOnly then
			for _, descendant in ipairs(game:GetDescendants()) do
				if AzulService.isScript(descendant) and shouldIncludeInSnapshot(descendant) then
					local current: Instance? = descendant
					while current and current ~= game do
						if shouldIncludeInSnapshot(current) then includeAncestorsOfScripts[current] = true end
						current = current.Parent
					end
				end
			end
		end

		self.trackedInstances = {}
		self.guidMap = {}
		self.usedGuids = {}

		local instances = {}
		local scriptCount = 0
		local batchSize = 400

		local queue = {}
		for _, service in ipairs(game:GetChildren()) do
			if shouldIncludeInSnapshot(service) then
				table.insert(queue, {
					instance = service,
					hasScriptAncestor = false,
				})
			end
		end

		local index = 1
		while index <= #queue do
			if not self.syncEnabled then
				self:infoPrint("Snapshot aborted - sync disabled")
				return
			end

			local queued = queue[index]
			local instance = queued.instance
			local hasScriptAncestor = queued.hasScriptAncestor == true

			local includeByMode = true
			if scriptsAndDescendantsOnly then
				includeByMode = AzulService.isScript(instance)
					or hasScriptAncestor
					or includeAncestorsOfScripts[instance] == true
			end

			if shouldIncludeInSnapshot(instance) and includeByMode then
				local data = AzulService.instanceToData(instance, self.trackedInstances, self.guidMap, self.usedGuids, {
					includeProperties = includeProperties,
				})
				if data then
					table.insert(instances, data)

					self.trackedInstances[instance] = data.guid
					self.guidMap[data.guid] = instance

					if AzulService.isScript(instance) then
						scriptCount += 1
					end
				end
			end

			for _, child in ipairs(instance:GetChildren()) do
				if shouldIncludeInSnapshot(child) then
					table.insert(queue, {
						instance = child,
						hasScriptAncestor = hasScriptAncestor or AzulService.isScript(instance),
					})
				end
			end

			if index % batchSize == 0 then task.wait() end
			index += 1
		end

		sendMessage("fullSnapshot", { data = instances })
		self:infoPrint("Snapshot sent:", #instances, "instances (", scriptCount, "scripts )")

		if self.syncEnabled then
			if includeProperties or scriptsAndDescendantsOnly then
				self:debugPrint(
					`Snapshot sent with options (includeProperties={tostring(includeProperties)}, scriptsAndDescendantsOnly={tostring(
						scriptsAndDescendantsOnly
					)}) - stopping sync since "pack" is one-shot.`
				)
				self:stopSync()
			end

			self.batchingEnabled = true
			self.batchFlushToken += 1
			self.batchAccumulator = 0
		end
	end

	function self:reloadSourcemap()
		sendFullSnapshot()
	end

	function self:startSync()
		if self.syncEnabled then return end

		self:infoPrint("Starting sync...")
		self.syncEnabled = true
		self.batchingEnabled = false
		self.batchFlushToken += 1

		if self.ui then self.ui:UpdateSyncState(true) end

		self.wsClient = WebSocketClient.new(self.config.WS_URL, {
			debugMode = self.config.DEBUG_MODE,
			silentMode = self.config.SILENT_MODE,
		})

		self.wsClient:on("message", function(message)
			processMessage(message)
		end)

		self.wsClient:on("connect", function()
			self:infoPrint("Connected to daemon")
			sendDaemonConfig()
		end)

		self.wsClient:on("disconnect", function()
			self:infoPrint("Disconnected from daemon")
			self:stopSync()
		end)

		self.wsClient:on("error", function(error)
			warn("[Azul]: Connection error:", error)
		end)

		local connected = self.wsClient:connect()
		if not connected then
			warn("[Azul]: Failed to connect to daemon")
			self:stopSync()
			return
		end

		task.defer(function()
			local ok, err = pcall(function()
				local function setupListeners(parent)
					for _, child in ipairs(parent:GetChildren()) do
						attachListeners(child)
						setupListeners(child)
					end
				end

				for _, service in ipairs(game:GetChildren()) do
					setupListeners(service)
					task.wait()
				end
			end)
			if not ok then
				warn("[Azul]: Error during listener setup:", err)
				self:stopSync()
			end
		end)

		local descendantAddedConnection = game.DescendantAdded:Connect(function(instance)
			if self.syncEnabled then onInstanceAdded(instance) end
		end)
		table.insert(self.connections, descendantAddedConnection)

		local descendantRemovingConnection = game.DescendantRemoving:Connect(function(instance)
			if self.syncEnabled then onInstanceRemoved(instance) end
		end)
		table.insert(self.connections, descendantRemovingConnection)

		local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
			if self.syncEnabled then
				local now = os.time()
				if now - self.lastHeartbeat > safeGetNumber(self.config.HEARTBEAT_INTERVAL, 30) then
					if not sendMessage("ping", {}) then
						warn("[Azul]: Lost connection to daemon")
						self:stopSync()
						return
					end
					self.lastHeartbeat = now
				end

				if self.batchingEnabled then
					-- Batch flush uses an idle timer; heartbeat just keeps the client alive
				else
					self.batchAccumulator += dt
					if self.batchAccumulator >= INITIAL_BATCH_INTERVAL then
						self.batchAccumulator -= INITIAL_BATCH_INTERVAL
						flushOutboundQueues()
					end
				end
			end
		end)
		table.insert(self.connections, heartbeatConnection)

		self:infoPrint("Sync enabled")
	end

	function self:stopSync(dontRelayDisconnect: boolean?)
		if not self.syncEnabled then return end

		if not dontRelayDisconnect then sendMessage("clientDisconnect", {}) end

		self:infoPrint("Stopping sync...")
		self.syncEnabled = false

		if self.ui then self.ui:UpdateSyncState(false) end

		if self.wsClient then self.wsClient:disconnect() end
		self.wsClient = nil

		self.trackedInstances = {}
		self.guidMap = {}
		self.batchAccumulator = 0
		table.clear(self.pendingInstanceUpdates)
		table.clear(self.pendingScriptChanges)
		table.clear(self.pendingScriptChangeReady)
		table.clear(self.scriptChangeDebounceTokenByGuid)
		table.clear(self.pendingDeletes)

		self.batchingEnabled = false
		self.batchFlushToken += 1

		for _, conn in ipairs(self.connections) do
			conn:Disconnect()
		end
		self.connections = {}

		self:infoPrint("Sync stopped")
	end

	function self:onSettingsScopeChanged(newScope: string)
		if newScope == self.settingsStore:getScope() then return end

		self.settingsStore:setScope(newScope)
		if self.ui then
			self.ui:SetSettingsScope(self.settingsStore:getScope())
			self.ui:UpdateConfig()
		end
		self:rebuildServiceSet()

		local scopeLabel = if self.settingsStore:getScope() == Enums.scope.GLOBAL then "Global" else "Project"
		self:infoPrint(`Settings scope set to {scopeLabel}`)
	end

	return self :: SyncSession
end

return SyncSession
