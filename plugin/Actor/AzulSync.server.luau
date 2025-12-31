--[[
	Azul - Roblox Studio Plugin.
	Companion plugin for Azul to sync scripts between Roblox Studio and external editors.

	Ransomwave 2025
]]

-- Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")

-- Prevent from running if the game is being Playtested
if RunService:IsRunning() then return end

local azulPluginFolder = script.Parent.Parent

-- Modules
local WebSocketClient = require(azulPluginFolder.WebSocketClient)
local CollapsibleTitledSection = require(azulPluginFolder.StudioWidgets.Components.CollapsibleTitledSection)
local CustomTextButton = require(azulPluginFolder.StudioWidgets.Components.CustomTextButton)
local LabeledCheckbox = require(azulPluginFolder.StudioWidgets.Components.LabeledCheckbox)
local LabeledMultiChoice = require(azulPluginFolder.StudioWidgets.Components.LabeledMultiChoice)
local LabeledTextInput = require(azulPluginFolder.StudioWidgets.Components.LabeledTextInput)
local VerticalScrollingFrame = require(azulPluginFolder.StudioWidgets.Components.VerticalScrollingFrame)

local enum = {
	listType = {
		WHITELIST = "WHITELIST",
		BLACKLIST = "BLACKLIST",
	},
}

-- Configuration
local CONFIG = {
	WS_URL = "ws://localhost:8080",
	HEARTBEAT_INTERVAL = 30,
	LIST_TYPE = enum.listType.WHITELIST, -- or BLACKLIST
	SERVICE_LIST = {
		"Workspace",
		"Lighting",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"SoundService",
	},

	EXCLUDED_PARENTS = {
		"ServerStorage.RecPlugins", -- Folder managed by "Eye" plugin. It updates the sourcemap thousands of times. We don't need to track this.
		"Workspace.Surface Converter Storage", -- Folder managed by "Surface Converter" plugin. We don't need to track it.
	},

	DEBUG_MODE = false,
	SILENT_MODE = false,
}

-- Save settings
local function saveSettings()
	for key, value in pairs(CONFIG) do
		plugin:SetSetting(key, value)
	end
end

local function loadSettings()
	for key, _ in pairs(CONFIG) do
		local value = plugin:GetSetting(key)
		if value == nil then continue end
		CONFIG[key] = value
	end
end

loadSettings()

-- Logging helpers
local function debugPrint(...)
	if CONFIG.SILENT_MODE or not CONFIG.DEBUG_MODE then return end
	print(...)
end

local function infoPrint(...)
	if CONFIG.SILENT_MODE then return end
	print(...)
end

local LOGO = "rbxassetid://134336592598474" -- Azul logo asset ID
local LOGO_SYNCED = "rbxassetid://103599828888609" -- Sync icon asset ID

-- Plugin state
local plugin = plugin
local toolbar = plugin:CreateToolbar("Azul")
local connectButton = toolbar:CreateButton("Azul", "Connect/disconnect from sync daemon", LOGO)

-- Sync state
local syncEnabled = false
local wsClient = nil
local trackedInstances = {}
local guidMap = {}
local usedGuids = {}
local lastHeartbeat = 0
local batchAccumulator = 0
local applyingPatch = false
local lastPatchTime = {} -- Track last patch time per GUID to prevent loops
local recentPatches = {} -- Track which scripts were recently patched from daemon
local lastInstanceUpdate = {} -- Deduplicate identical rapid instanceUpdated payloads per GUID
local connections = {}
local suppressOutbound = false -- Prevent emitting events while applying inbound patches
local pendingInstanceUpdates = {}
local pendingScriptChanges = {}

local BATCH_INTERVAL = 0.2 -- Seconds between outbound batch flushes

-- Utility: Clear all GUID attributes
-- This is for legacy support; we now use :GetDebugId() for stable GUIDs
local function clearAllGUIDAttributes()
	for instance, _ in pairs(trackedInstances) do
		if instance and instance:GetAttribute(CONFIG.GUID_ATTRIBUTE) then
			instance:SetAttribute(CONFIG.GUID_ATTRIBUTE, nil)
		end
	end
end

-- Utility: Check if instance is a script
local function isScript(instance)
	return instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript")
end

-- Utility: Check if instance should be excluded from sync
local serviceSet = {}
for _, name in ipairs(CONFIG.SERVICE_LIST) do
	serviceSet[name] = true
end

local function isExcluded(instance: Instance)
	if not instance then return true end

	local fullName = instance:GetFullName()
	for _, ancestorName in CONFIG.EXCLUDED_PARENTS do
		if fullName:find(ancestorName) then return true end
	end

	-- Walk up to the service
	local current = instance
	while current do
		if current.Parent == game then
			local inList = serviceSet[current.Name] ~= nil

			if CONFIG.LIST_TYPE == enum.listType.WHITELIST then
				-- Whitelist: only allow services in the list
				-- debugPrint(`[🐛 Azul]: Included {instance} in whitelist`)
				return not inList
			else
				-- Blacklist: exclude services in the list
				-- debugPrint(`[🐛 Azul]: Excluded {instance} in blacklist`)
				return inList
			end
		end
		current = current.Parent
	end

	-- Not under DataModel
	return true
end

local function getOrCreatePath(pathSegments: { string }): Instance
	local current: Instance = game
	for index, segment in ipairs(pathSegments) do
		local nextNode = current:FindFirstChild(segment)

		if not nextNode then
			if index == 1 then
				local ok, service = pcall(function()
					return game:GetService(segment)
				end)
				if ok and service then nextNode = service end
			end

			if not nextNode then
				nextNode = Instance.new("Folder")
				nextNode.Name = segment
				nextNode.Parent = current
			end
		end

		current = nextNode
	end

	return current
end

local function isProtectedRobloxContainer(instance: Instance?): boolean
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

--- @deprecated Utility: Check if an instance lives inside a package (any ancestor has a PackageLink)
-- local function isInPackage(instance: Instance): boolean
-- 	local current = instance
-- 	while current do
-- 		if current:FindFirstChildWhichIsA("PackageLink") or current:FindFirstAncestorWhichIsA("PackageLink") then
-- 			return true
-- 		end
-- 		current = current.Parent
-- 	end
-- 	return false
-- end

-- Utility: Check if instance should be included in snapshot (all instances)
local function shouldIncludeInSnapshot(instance)
	if not instance then return false end

	return not isExcluded(instance)
end

-- Utility: Generate or retrieve GUID for instance (use Roblox debug IDs to avoid attribute churn)
local function getOrCreateGUID(instance)
	local cached = trackedInstances[instance]
	if cached then return cached end

	local guid = instance:GetDebugId(0)
	trackedInstances[instance] = guid
	guidMap[guid] = instance
	usedGuids[guid] = true
	return guid
end

-- Utility: Get instance path
local function getInstancePath(instance)
	local path = {}
	local current = instance

	while current and current ~= game do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	-- If current became nil, the instance is no longer under DataModel
	if current ~= game then return nil end

	return path
end

-- Convert instance to data format
local function instanceToData(instance)
	local guid = getOrCreateGUID(instance)
	local path = getInstancePath(instance)
	if not path then return nil end

	local data = {
		guid = guid,
		className = instance.ClassName,
		name = instance.Name,
		path = path,
	}

	if isScript(instance) then data.source = instance.Source end

	return data
end

-- Send message to daemon
local function sendMessage(messageType, data)
	if not wsClient or not wsClient.connected then return false end

	local message = {
		type = messageType,
	}

	-- Merge data into message
	for k, v in pairs(data or {}) do
		message[k] = v
	end

	debugPrint(`[🐛 Azul]: Sending message: {messageType}`)

	local json = HttpService:JSONEncode(message)
	return wsClient:send(json)
end

-- Toggle outbound emission (used while applying inbound patches)
local function setOutboundSuppressed(suppressed: boolean)
	suppressOutbound = suppressed
	if suppressed then
		-- Drop any pending outbound changes to avoid echoing daemon writes
		table.clear(pendingInstanceUpdates)
		table.clear(pendingScriptChanges)
	end
end

-- Queue and batch outbound messages to reduce chatter
local function flushOutboundQueues()
	for _, data in pairs(pendingInstanceUpdates) do
		sendMessage("instanceUpdated", { data = data })
	end
	for _, payload in pairs(pendingScriptChanges) do
		sendMessage("scriptChanged", payload)
	end

	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)
end

local function queueInstanceUpdate(data)
	if suppressOutbound or not syncEnabled then return end
	if not data or not data.guid then return end

	pendingInstanceUpdates[data.guid] = data
end

local function queueScriptChange(payload)
	if suppressOutbound or not syncEnabled then return end
	if not payload or not payload.guid then return end

	pendingScriptChanges[payload.guid] = payload
end

-- Deduped instance update sender (used for adds, renames, reparent)
local function sendInstanceUpdateDedup(instance)
	if suppressOutbound or not syncEnabled then return end

	local data = instanceToData(instance)
	if not data then return end

	local guid = data.guid
	local key = table.concat(data.path, "/") .. "|" .. data.className .. "|" .. data.name
	local now = tick()
	local last = lastInstanceUpdate[guid]
	if last and last.key == key and now - last.t < 0.05 then
		-- Ignore duplicate bursts from multiple property signals firing at once
		return
	end
	lastInstanceUpdate[guid] = { key = key, t = now }

	trackedInstances[instance] = guid
	guidMap[guid] = instance

	queueInstanceUpdate(data)
end

-- Utility: Check if instance should be synced (scripts only)
local function shouldSync(instance)
	if not instance then return false end

	-- Only sync scripts
	if not isScript(instance) then return false end

	return not isExcluded(instance)
end

-- Handle script change
local function onScriptChanged(changedScript: Script | LocalScript | ModuleScript)
	if suppressOutbound or not shouldSync(changedScript) then return end

	local guid = getOrCreateGUID(changedScript)

	-- Don't send changes if this was just patched from daemon
	if recentPatches[guid] then
		debugPrint(
			"[🐛 Azul]: Ignoring change (was just patched from daemon):",
			`{changedScript.Parent}.{changedScript.Name}`
		)
		recentPatches[guid] = nil
		return
	end

	-- Don't send changes if we're applying a patch from daemon
	if applyingPatch then return end

	-- Don't send changes within 1 second of receiving a patch (debounce)
	local lastPatch = lastPatchTime[guid] or 0
	local now = tick()
	if now - lastPatch < 1 then
		debugPrint(
			"[🐛 Azul]: Ignoring change (too soon after patch):",
			`{changedScript.Parent}.{changedScript.Name}`
		)
		return
	end

	local path = getInstancePath(changedScript)
	if not path then return end

	queueScriptChange({
		guid = guid,
		path = path,
		className = changedScript.ClassName,
		source = changedScript.Source,
	})
end

-- Utility: register change listeners on an instance for name/parent/source updates
local function attachListeners(instance)
	if not shouldIncludeInSnapshot(instance) then return end

	-- Name changes should propagate to daemon (renames / path changes)
	local nameConnnection = instance:GetPropertyChangedSignal("Name"):Connect(function()
		sendInstanceUpdateDedup(instance)
	end)

	table.insert(connections, nameConnnection)

	-- Parent changes (reparent/move) also change path
	local parentConnection = instance:GetPropertyChangedSignal("Parent"):Connect(function()
		-- If parent is nil (destroy in progress), rely on DescendantRemoving -> deleted
		if instance.Parent == nil then return end
		sendInstanceUpdateDedup(instance)
	end)

	table.insert(connections, parentConnection)

	-- Source changes (scripts only)
	if isScript(instance) then
		local sourceConnection = instance:GetPropertyChangedSignal("Source"):Connect(function()
			if syncEnabled then onScriptChanged(instance) end
		end)
		table.insert(connections, sourceConnection)
	end
end

-- Send full snapshot
local function sendFullSnapshot()
	infoPrint("[Azul]: Sending full snapshot...")

	-- Reset tracking to ensure fresh GUID deduping
	trackedInstances = {}
	guidMap = {}
	usedGuids = {}

	local instances = {}
	local scriptCount = 0
	local batchSize = 400 -- Yield periodically to avoid plugin thread timeouts

	-- Build a queue to iterate without deep recursion
	local queue = {}
	for _, service in ipairs(game:GetChildren()) do
		if shouldIncludeInSnapshot(service) then table.insert(queue, service) end
	end

	local index = 1
	while index <= #queue do
		if not syncEnabled then
			infoPrint("[Azul]: Snapshot aborted - sync disabled")
			return
		end

		local instance = queue[index]

		if shouldIncludeInSnapshot(instance) then
			local data = instanceToData(instance)
			if data then
				table.insert(instances, data)

				trackedInstances[instance] = data.guid
				guidMap[data.guid] = instance

				if isScript(instance) then
					scriptCount += 1
				end
			end

			-- Enqueue children that are eligible for snapshot
			for _, child in ipairs(instance:GetChildren()) do
				if shouldIncludeInSnapshot(child) then table.insert(queue, child) end
			end
		end

		-- Yield periodically to avoid hitting Studio's execution time limit
		if index % batchSize == 0 then task.wait() end

		index += 1
	end

	-- Send snapshot
	sendMessage("fullSnapshot", { data = instances })
	infoPrint("[Azul]: Snapshot sent:", #instances, "instances (", scriptCount, "scripts )")
end

-- Handle instance added
local function onInstanceAdded(instance: Instance)
	if suppressOutbound then return end
	-- Include all non-excluded instances (scripts + containers) so sourcemap stays accurate
	if not shouldIncludeInSnapshot(instance) then return end

	local data = instanceToData(instance)
	if not data then return end
	-- local guid = data.guid
	sendInstanceUpdateDedup(instance)

	-- Track subsequent changes (rename/reparent/source)
	attachListeners(instance)

	-- Watch for source changes (scripts only)
	-- (handled inside attachListeners)
end

-- Handle instance removed
local function onInstanceRemoved(instance)
	if suppressOutbound then return end
	if not shouldIncludeInSnapshot(instance) then return end

	local guid = trackedInstances[instance]

	-- Fallback: if we never tracked this instance (edge cases), use debug id directly
	if not guid then guid = instance:GetDebugId(0) end

	if not guid then return end

	trackedInstances[instance] = nil
	guidMap[guid] = nil
	usedGuids[guid] = nil

	sendMessage("deleted", { guid = guid })
end

-- Process incoming daemon message
local function processMessage(message)
	debugPrint("[🐛 Azul]: Processing message type:", message.type)

	if message.type == "patchScript" then
		debugPrint("[🐛 Azul]: Patch requested for GUID:", message.guid)
		-- Update script source
		local instance = guidMap[message.guid]
		if instance and isScript(instance) then
			setOutboundSuppressed(true)
			-- Mark this script as recently patched from daemon
			recentPatches[message.guid] = true

			-- Record patch time BEFORE applying to prevent echo
			lastPatchTime[message.guid] = tick()

			-- Update source
			applyingPatch = true
			instance.Source = message.source

			-- Keep flag set longer to cover any async events
			task.delay(0.2, function()
				applyingPatch = false
				setOutboundSuppressed(false)
			end)

			infoPrint("[Azul]: Updated script:", `{instance.Parent}.{instance.Name}`)

			-- Refresh the script editor if the script is currently open
			-- This ensures VSCode changes are visible immediately
			local success, scriptDocument = pcall(function()
				return ScriptEditorService:FindScriptDocument(instance)
			end)

			if success and scriptDocument then
				-- Close and reopen the document to refresh the editor
				task.spawn(function()
					pcall(function()
						scriptDocument:CloseAsync()
					end)
					task.wait(0.1)
					pcall(function()
						ScriptEditorService:OpenScriptDocumentAsync(instance)
					end)
					-- Clear the patch marker after editor refresh completes
					task.wait(0.2)
					recentPatches[message.guid] = nil
				end)
			end
		else
			warn("[Azul]: Cannot apply patch - instance not found for GUID:", message.guid)
			local count = 0
			for _ in pairs(guidMap) do
				count = count + 1
			end
			warn("[Azul]: Total tracked instances:", count)
		end
	elseif message.type == "requestSnapshot" then
		-- Daemon is requesting a full snapshot
		infoPrint("[Azul]: Snapshot requested by daemon")
		sendFullSnapshot()
	elseif message.type == "buildSnapshot" then
		-- One-time push from filesystem into Studio
		infoPrint("[Azul]: Applying build snapshot from daemon")
		setOutboundSuppressed(true)
		local ok, err = pcall(function()
			table.sort(message.data, function(a, b)
				return #a.path < #b.path
			end)

			local lockedContainerParents = {
				StarterPlayerScripts = "StarterPlayer",
				StarterCharacterScripts = "StarterPlayer",
				StarterGear = "StarterPlayer",
			}

			local created = 0
			for _, item in ipairs(message.data) do
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

				local parent = getOrCreatePath(parentPath)
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
						-- For script targets, enforce the correct class (replace unless protected container)
						if isProtectedRobloxContainer(existing) then
							instance = existing
						else
							existing:Destroy()
							instance = nil
						end
					else
						-- For containers, reuse the existing instance even if class differs (e.g., Part instead of Folder)
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
					if not serviceCandidate and not isProtectedRobloxContainer(instance) then
						instance.Name = adjustedPath[#adjustedPath]
					end
				end

				trackedInstances[instance] = item.guid
				guidMap[item.guid] = instance
				usedGuids[item.guid] = true

				if isScriptClass(item.className) and item.source then
					local okSource, errSource = pcall(function()
						(instance :: Script).Source = item.source
					end)
					if not okSource then warn("[Azul]: Failed to set source for", item.name, errSource) end
				end

				attachListeners(instance)
			end

			infoPrint(`[Azul]: Build snapshot applied ({created} created/updated)`)
		end)

		setOutboundSuppressed(false)
		if not ok then warn("[Azul]: Error applying build snapshot", err) end
	elseif message.type == "error" then
		warn("[Azul]: Daemon error:", message.message)
	elseif message.type == "pong" then
		-- Heartbeat response
		debugPrint("[🐛 Azul]: Received pong")
	else
		warn("[Azul]: Unknown message type:", message.type)
	end
end

-- Start sync
local function startSync()
	if syncEnabled then return end

	infoPrint("[Azul]: Starting sync...")
	syncEnabled = true
	connectButton:SetActive(true)
	connectButton.Icon = LOGO_SYNCED

	-- Create and connect WebSocket client
	wsClient = WebSocketClient.new(CONFIG.WS_URL, {
		debugMode = CONFIG.DEBUG_MODE,
		silentMode = CONFIG.SILENT_MODE,
	})

	-- Set up message handler
	wsClient:on("message", function(message)
		processMessage(message)
	end)

	-- Set up connection handler
	wsClient:on("connect", function()
		infoPrint("[Azul]: Connected to daemon")
		-- Send initial snapshot after connection
	end)

	-- Set up disconnect handler
	wsClient:on("disconnect", function()
		infoPrint("[Azul]: Disconnected from daemon")
		stopSync()
	end)

	-- Set up error handler
	wsClient:on("error", function(error)
		warn("[Azul]: Connection error:", error)
	end)

	-- Connect to daemon
	local connected = wsClient:connect()

	if not connected then
		warn("[Azul]: Failed to connect to daemon")
		stopSync()
		return
	end

	-- Defer listener setup to avoid blocking
	task.defer(function()
		-- Setup listeners for existing instances
		local function setupListeners(parent)
			for _, child in ipairs(parent:GetChildren()) do
				attachListeners(child)
				setupListeners(child)
			end
		end

		for _, service in ipairs(game:GetChildren()) do
			setupListeners(service)
			task.wait() -- Yield between services
		end
	end)

	-- Listen for new instances
	local descendantAddedConnection = game.DescendantAdded:Connect(function(instance)
		if syncEnabled then onInstanceAdded(instance) end
	end)
	table.insert(connections, descendantAddedConnection)

	-- Listen for removed instances
	local descendantRemovingConnection = game.DescendantRemoving:Connect(function(instance)
		if syncEnabled then onInstanceRemoved(instance) end
	end)
	table.insert(connections, descendantRemovingConnection)

	-- Start heartbeat
	local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if syncEnabled then
			-- Send heartbeat periodically
			local now = os.time()
			if now - lastHeartbeat > CONFIG.HEARTBEAT_INTERVAL then
				sendMessage("ping", {})
				lastHeartbeat = now
			end

			-- Flush outbound batches on a timer
			batchAccumulator += dt
			if batchAccumulator >= BATCH_INTERVAL then
				batchAccumulator -= BATCH_INTERVAL
				flushOutboundQueues()
			end
		end
	end)
	table.insert(connections, heartbeatConnection)

	infoPrint("[Azul]: Sync enabled")
end

-- Stop sync
function stopSync()
	if not syncEnabled then return end

	sendMessage("clientDisconnect", {})

	infoPrint("[Azul]: Stopping sync...")
	syncEnabled = false
	connectButton:SetActive(false)
	connectButton.Icon = LOGO

	-- Close WebSocket connection
	if wsClient then
		wsClient:disconnect()
		wsClient = nil
	end

	-- Clear GUID attributes if configured
	if CONFIG.CLEAR_GUIDS_ON_EXIT then
		clearAllGUIDAttributes()
		infoPrint("[Azul]: Cleared all GUID attributes")
	end

	trackedInstances = {}
	guidMap = {}
	batchAccumulator = 0
	table.clear(pendingInstanceUpdates)
	table.clear(pendingScriptChanges)

	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}

	infoPrint("[Azul]: Sync stopped")
end

-- -- Toggle button handler
-- connectButton.Click:Connect(function()
-- 	if syncEnabled then
-- 		stopSync()
-- 	else
-- 		startSync()
-- 	end
-- end)

-- Cleanup on plugin unload
plugin.Unloading:Connect(function()
	saveSettings()
	stopSync()
end)

infoPrint("[Azul]: Plugin loaded. Click on the 'Azul' button to connect.")
debugPrint("[🐛 Azul]: Debug mode is enabled!")
debugPrint(`[🐛 Azul]: Service list type is set to: "{CONFIG.LIST_TYPE}"`)

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	true, -- Widget will be initially enabled
	true, -- Don't override the previous enabled state
	345, -- Default width of the floating window
	640, -- Default height of the floating window
	300, -- Minimum width of the floating window
	300 -- Minimum height of the floating window
)

-- Create new widget GUI
local azulWidget = plugin:CreateDockWidgetPluginGuiAsync("azulWidget", widgetInfo) :: DockWidgetPluginGui
azulWidget.Name = "AzulCompanionPlugin"
azulWidget.Title = "Azul" -- Optional widget title

local mainScrollFrame = VerticalScrollingFrame.new("main")
mainScrollFrame:GetContentsFrame().Parent = azulWidget

--local uiListLayout = Instance.new("UIListLayout")
--uiListLayout.Parent = mainScrollFrame:GetContentsFrame()
--uiListLayout.Padding = UDim.new(0, 10)

local mainSectionListLayout = Instance.new("UIListLayout")
mainSectionListLayout.Parent = mainScrollFrame:GetSectionFrame()
mainSectionListLayout.Padding = UDim.new(0, 0)
mainSectionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainSectionListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local mainSection = CollapsibleTitledSection.new(
	"mainSection", -- name suffix of the gui object
	"Azul Companion Plugin", -- the text displayed beside the collapsible arrow
	true, -- have the content frame auto-update its size?
	false, -- minimizable?
	false -- minimized by default?
)
mainSection:GetSectionFrame().LayoutOrder = 0
mainSection:GetSectionFrame().Parent = mainScrollFrame:GetContentsFrame()

local function createInfoLabel(text: string)
	local label = Instance.new("TextLabel")
	label.Name = "InfoLabel"
	label.RichText = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.Size = UDim2.new(1, 0, 0, 15)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(0.5, 0.5, 0.5)
	label.Font = Enum.Font.SourceSans
	label.TextSize = 15
	label.Text = `{text}<br/>`
	label.TextXAlignment = Enum.TextXAlignment.Left

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 30)
	padding.PaddingRight = UDim.new(0, 30)
	padding.Parent = label

	return label
end

-- Title
-- local titleLabel = Instance.new("TextLabel")
-- titleLabel.Size = UDim2.new(1, 0, 0, 50)
-- titleLabel.BackgroundTransparency = 1
-- titleLabel.Text = "Azul"
-- titleLabel.TextColor3 = Color3.new(1, 1, 1)
-- titleLabel.Font = Enum.Font.SourceSansBold
-- titleLabel.TextScaled = true
-- mainSection:AddChild(titleLabel, 0)

local titleImageLabel = Instance.new("ImageLabel")
titleImageLabel.Size = UDim2.new(1, 0, 0, 50)
titleImageLabel.BackgroundTransparency = 1
titleImageLabel.Image = LOGO
titleImageLabel.ScaleType = Enum.ScaleType.Fit
mainSection:AddChild(titleImageLabel, 0)

-- Connect/Disconnect button
local syncButton = CustomTextButton.new("toggleSync", "Connect", false)
syncButton.Parent = mainScrollFrame:GetContentsFrame()

syncButton:SetSize(UDim2.fromScale(1, 0.25))

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0.1, 0)
padding.PaddingRight = UDim.new(0.1, 0)
padding.Parent = syncButton:GetFrame()

syncButton:SetClickedFunction(function()
	if syncEnabled then
		syncButton:GetButton().Text = "Stopping..."
		stopSync()
		syncButton:GetButton().Text = "Connect"
		titleImageLabel.Image = LOGO
	else
		syncButton:GetButton().Text = "Connecting..."
		startSync()
		syncButton:GetButton().Text = "Disconnect"
		titleImageLabel.Image = LOGO_SYNCED
	end
end)
mainSection:AddChild(syncButton:GetFrame())

-- Quick settings
local debugModeCheckbox = LabeledCheckbox.new("debugMode", "Debug Mode", CONFIG.DEBUG_MODE, false)

debugModeCheckbox:SetValue(CONFIG.DEBUG_MODE)

debugModeCheckbox:SetValueChangedFunction(function(newValue)
	CONFIG.DEBUG_MODE = newValue
	debugPrint("[🐛 Azul]: Debug mode set to:", newValue)
end)
mainSection:AddChild(debugModeCheckbox:GetFrame())
mainSection:AddChild(createInfoLabel("Debug mode enables verbose logging to the output console."))

local silentModeCheckbox = LabeledCheckbox.new("silentMode", "Silent Mode", CONFIG.SILENT_MODE, false)

silentModeCheckbox:SetValue(CONFIG.SILENT_MODE)
silentModeCheckbox:SetValueChangedFunction(function(newValue)
	CONFIG.SILENT_MODE = newValue
	debugPrint("[🐛 Azul]: Silent mode set to:", newValue)
end)
mainSection:AddChild(silentModeCheckbox:GetFrame())
mainSection:AddChild(createInfoLabel("Silent mode suppresses all console output except errors."))

-- Settings section
local settingsSection = CollapsibleTitledSection.new(
	"settings", -- name suffix of the gui object
	"Plugin Settings", -- the text displayed beside the collapsible arrow
	true, -- have the content frame auto-update its size?
	true, -- minimizable?
	true -- minimized by default?
)
settingsSection:GetSectionFrame().LayoutOrder = 1
settingsSection:GetSectionFrame().Parent = mainScrollFrame:GetContentsFrame()

-- WebSocket URL setting
local websocketUrlLabel = LabeledTextInput.new(
	"websocketUrl", -- name suffix of the gui object
	"WebSocket URL:", -- the text displayed beside the input box
	CONFIG.WS_URL -- initial text in the input box
)
websocketUrlLabel:SetValue("ws://localhost:8080")
websocketUrlLabel:SetValueChangedFunction(function(newValue)
	CONFIG.WS_URL = newValue
	debugPrint("[🐛 Azul]: WebSocket URL updated to:", newValue)
end)

settingsSection:AddChild(websocketUrlLabel:GetFrame())

-- Heartbeat Interval setting
local heartbeatIntervalLabel = LabeledTextInput.new(
	"heartbeatInterval", -- name suffix of the gui object
	"Heartbeat Interval (s):", -- the text displayed beside the input box
	tostring(CONFIG.HEARTBEAT_INTERVAL) -- initial text in the input box
)
heartbeatIntervalLabel:SetValue(tostring(CONFIG.HEARTBEAT_INTERVAL))
heartbeatIntervalLabel:SetValueChangedFunction(function(newValue)
	local interval = tonumber(newValue)
	if interval and interval > 0 then
		CONFIG.HEARTBEAT_INTERVAL = interval
		debugPrint("[🐛 Azul]: Heartbeat Interval updated to:", interval)
	end
end)
settingsSection:AddChild(heartbeatIntervalLabel:GetFrame())
settingsSection:AddChild(createInfoLabel("Interval in seconds between heartbeat pings to the daemon."))

local listTypeLabel = LabeledMultiChoice.new(
	"listType", -- name suffix of the gui object
	"Service List Type:", -- the text displayed beside the input box
	{
		{ Id = "WHITELIST", Text = "Whitelist" },
		{ Id = "BLACKLIST", Text = "Blacklist" },
	}, -- choices
	if CONFIG.LIST_TYPE == enum.listType.WHITELIST then 1 else 2 -- initial choice
)

listTypeLabel:SetValueChangedFunction(function(newIndex)
	if newIndex == 1 then
		CONFIG.LIST_TYPE = enum.listType.WHITELIST
	else
		CONFIG.LIST_TYPE = enum.listType.BLACKLIST
	end
	debugPrint("[🐛 Azul]: Service List Type updated to:", CONFIG.LIST_TYPE)
end)

settingsSection:AddChild(listTypeLabel:GetFrame())
settingsSection:AddChild(
	createInfoLabel(
		"Whitelist: only services in the list are synced.<br />Blacklist: services in the list are excluded."
	)
)

-- Service List setting
local serviceListLabel = LabeledTextInput.new(
	"serviceList", -- name suffix of the gui object
	"Service List:", -- the text displayed beside the input box
	table.concat(CONFIG.SERVICE_LIST, ", ") -- initial text in the input box
)
serviceListLabel:SetMaxGraphemes(9999)
serviceListLabel:SetValue(table.concat(CONFIG.SERVICE_LIST, ", "))
serviceListLabel:SetValueChangedFunction(function(newValue)
	local services = {}
	for serviceName in string.gmatch(newValue, "([^,%s]+)") do
		table.insert(services, serviceName)
	end
	CONFIG.SERVICE_LIST = services
	-- Update serviceSet
	serviceSet = {}
	for _, name in ipairs(CONFIG.SERVICE_LIST) do
		serviceSet[name] = true
	end
	debugPrint("[🐛 Azul]: Service List updated to:", newValue)
	debugPrint("[🐛 Azul]: New Service List:", CONFIG.SERVICE_LIST)
end)
settingsSection:AddChild(serviceListLabel:GetFrame())
settingsSection:AddChild(createInfoLabel("List of services to include/exclude based on the selected List Type."))

-- Excluded Parents setting
local excludedParentsLabel = LabeledTextInput.new(
	"excludedParents", -- name suffix of the gui object
	"Excluded Parents:", -- the text displayed beside the input box
	table.concat(CONFIG.EXCLUDED_PARENTS, ", ") -- initial text in the input box
)
excludedParentsLabel:SetValue(table.concat(CONFIG.EXCLUDED_PARENTS, ", "))
excludedParentsLabel:SetValueChangedFunction(function(newValue)
	local excluded = {}
	for parentName in string.gmatch(newValue, "([^,%s]+)") do
		table.insert(excluded, parentName)
	end
	CONFIG.EXCLUDED_PARENTS = excluded
	debugPrint("[🐛 Azul]: Excluded Parents updated to:", newValue)
	debugPrint("[🐛 Azul]: New Excluded Parents list:", CONFIG.EXCLUDED_PARENTS)
end)
settingsSection:AddChild(excludedParentsLabel:GetFrame())
settingsSection:AddChild(createInfoLabel("List of parent paths to exclude from syncing, separated by commas."))

connectButton.Click:Connect(function()
	azulWidget.Enabled = not azulWidget.Enabled
end)
