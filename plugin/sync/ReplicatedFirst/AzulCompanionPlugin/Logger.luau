local Logger = {}

local LogService = game:GetService("LogService")
local Config = require("./Config")

function Logger.info(...)
	if Config.SILENT_MODE then return end

	local length = select("#", ...)
	local args = { ... }

	-- Convert every item to a string
	for i = 1, length do
		args[i] = tostring(args[i])
	end

	-- Combine them with spaces and print
	local finalString = table.concat(args, " ", 1, length)
	LogService:Info(finalString)
end

-- Keep debug printing inside each script
-- If they were to use this Logger they'd lose the context of the script that called it

return Logger
