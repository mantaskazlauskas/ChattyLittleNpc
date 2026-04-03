---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class Logger
local Logger = {}
CLN.Logger = Logger

-- Severity levels
Logger.Level = {
	ERROR = 0,
	WARN = 1,
	INFO = 2,
	DEBUG = 3,
}

-- Default minimum level for console/chat output
Logger.minConsoleLevel = Logger.Level.INFO

-- Category set comes from Utils if present; fallback basic categories
local function getCategories()
	local U = CLN and CLN.Utils
	if U and U.LogCategories then return U.LogCategories end
	return {
		app = "app",
		system = "system",
		ui = "ui",
		debug = "debug",
		misc = "misc",
	}
end

-- Normalize category to a known token; default to misc
local _loggerCategorySet = nil
local function normalizeCategory(cat)
	if type(cat) ~= "string" or cat == "" then return (getCategories().misc or "misc") end
	-- Build set lazily on first use (categories may not be available at file load time)
	if not _loggerCategorySet then
		_loggerCategorySet = {}
		local C = getCategories()
		for _, v in pairs(C) do _loggerCategorySet[v] = true end
	end
	if _loggerCategorySet[cat] then return cat end
	return getCategories().misc or "misc"
end

-- Should a message print to console based on severity and user prefs
local function shouldPrint(level, category)
	-- Always record in LogsWindow buffer via CLN.Print hook; decide chat mirroring here
	local prof = CLN and CLN.db and CLN.db.profile or {}
	local chatOn = prof.logToChat == true
	if not chatOn then return false end
	level = level or Logger.Level.INFO
	if level <= Logger.minConsoleLevel then return true end
	-- For DEBUG, also require debugMode
	if level == Logger.Level.DEBUG then
		return prof.debugMode == true
	end
	return false
end

-- Core log function
-- @param message string|table
-- @param includeInChat boolean|nil - mirror to chat if allowed by settings
-- @param category string|nil - category tag
-- @param level number|nil - Logger.Level.*
function Logger:log(message, includeInChat, category, level)
	local text
	if type(message) == "table" then
		local ok, json = pcall(function()
			local parts = {}
			for k, v in pairs(message) do parts[#parts+1] = tostring(k) .. ":" .. tostring(v) end
			return "{" .. table.concat(parts, ", ") .. "}"
		end)
		text = ok and json or tostring(message)
	else
		text = tostring(message)
	end
	local cat = normalizeCategory(category)
	local lvl = level or Logger.Level.INFO

	-- Format with simple tags; CLN.Print hook will route to LogsWindow, not chat
	local prefix
	if lvl == Logger.Level.ERROR then prefix = "|cffff5555[ERROR]|r"
	elseif lvl == Logger.Level.WARN then prefix = "|cffffff55[WARN]|r"
	elseif lvl == Logger.Level.DEBUG then prefix = "|cff87CEEb[DEBUG]|r"
	else prefix = "|cffcccccc[INFO]|r" end
	local line = string.format("%s[%s] %s", prefix, cat, text)

	-- Always send to addon print (captured by LogsWindow via hook).
	if CLN and CLN.Print then
		CLN:Print(line)
	end

	-- Optional chat mirroring when explicitly requested and allowed by prefs
	if includeInChat and shouldPrint(lvl, cat) then
		-- Bypass our CLN.Print hook by writing directly to DEFAULT_CHAT_FRAME
		if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
			DEFAULT_CHAT_FRAME:AddMessage("ChattyLittleNpc: " .. line)
		end
	end
end

function Logger:error(msg, includeInChat, category)
	self:log(msg, includeInChat, category or (getCategories().system or "system"), Logger.Level.ERROR)
end

function Logger:warn(msg, includeInChat, category)
	self:log(msg, includeInChat, category, Logger.Level.WARN)
end

function Logger:info(msg, includeInChat, category)
	self:log(msg, includeInChat, category, Logger.Level.INFO)
end

function Logger:debug(msg, includeInChat, category)
	-- Respect debugMode for debug level
	if CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
		self:log(msg, includeInChat, category or (getCategories().debug or "debug"), Logger.Level.DEBUG)
	end
end

-- Convenience: standardized API requested by user
-- Parameters: logMessage (string), includeInChat (boolean), category (string)
function Logger:Log(logMessage, includeInChat, category)
	self:info(logMessage, includeInChat, category)
end

return Logger
