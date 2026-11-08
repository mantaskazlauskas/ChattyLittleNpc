-- LogsBuffer.lua - Collects log lines for the logs window and hooks the logging functions.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.LogsWindow = ReplayFrame.LogsWindow or {}
local LW = ReplayFrame.LogsWindow

-- Severity constants (matching Logger.Level)
local SEV = { ERROR = 0, WARN = 1, INFO = 2, DEBUG = 3 }
local SEV_COLORS = {
    [0] = "|cffff5555",
    [1] = "|cffffff55",
    [2] = "|cffcccccc",
    [3] = "|cff87CEEb",
}
local SEV_LETTERS = { [0] = "E", [1] = "W", [2] = "I", [3] = "D" }

-- Table view constants
local TABLE_ROW_HEIGHT = 16
local TABLE_ROW_POOL = 60
local TABLE_COL_DEFS = {
    { label = "Time",   width = 65 },
    { label = "S",      width = 14 },
    { label = "Source", width = 50 },
    { label = "Cat",    width = 75 },
    { label = "Message",width = 0 },  -- 0 = fill remaining
}

-- Persistent in-session buffer (shared across UI opens)
CLN._AnimLogBuffer = CLN._AnimLogBuffer or { lines = {}, max = 2000, cats = {}, version = 0 }

local function now()
    return (type(GetTime) == "function") and GetTime() or (C_Timer and C_Timer.GetTime and C_Timer.GetTime()) or 0
end

local function addCategory(cat)
    if not cat or cat == "" then
        CLN._AnimLogBuffer.cats["uncategorized"] = (CLN._AnimLogBuffer.cats["uncategorized"] or 0) + 1
        return
    end
    local cats = CLN._AnimLogBuffer.cats
    cats[cat] = (cats[cat] or 0) + 1
end

-- Detect severity from Logger's color-coded prefix embedded in message text
local function detectSeverity(msg)
    if not msg then return SEV.INFO end
    if string.find(msg, "[ERROR]", 1, true) then return SEV.ERROR end
    if string.find(msg, "[WARN]", 1, true) then return SEV.WARN end
    if string.find(msg, "[DEBUG]", 1, true) then return SEV.DEBUG end
    return SEV.INFO
end

-- Extract Logger category from message: "|cff...[LEVEL]|r[category] text" -> "category"
local function extractLoggerCategory(msg)
    if not msg then return nil end
    return msg:match("|c%x+%[%a+%]|r%[(%a+)%]")
end

-- Strip Logger's color-coded severity+category prefix from message text
local function stripLoggerPrefix(msg)
    if not msg then return msg end
    local stripped = msg:gsub("^|c%x+%[%a+%]|r%[%a+%] ", "")
    if stripped ~= msg then return stripped end
    return msg:gsub("^|c%x+%[%a+%]|r ", "")
end

local function pushLine(cat, text, sess, src, lvl)
    local buf = CLN._AnimLogBuffer
    local ts = now()
    if lvl == nil then
        if src == "anim" or src == "debug" then
            lvl = SEV.DEBUG
        elseif src == "addon" then
            lvl = detectSeverity(text)
        else
            lvl = SEV.INFO
        end
    end
    table.insert(buf.lines, { t = ts, c = cat, s = sess, m = text, r = src, lvl = lvl })
    if #buf.lines > (buf.max or 2000) then table.remove(buf.lines, 1) end
    addCategory(cat)
    buf.version = (buf.version or 0) + 1
    if LW._frame and LW._frame:IsShown() and LW._auto then LW:_Refresh() end
end

-- Expose pushLine so Logger can route to the buffer without going through CLN:Print
CLN._pushLogLine = pushLine

-- Insert a visible bookmark separator into the log buffer
LW._markCount = LW._markCount or 0
function LW:Mark(label)
    self._markCount = self._markCount + 1
    local tag = label or ("MARK " .. self._markCount)
    local buf = CLN._AnimLogBuffer
    local ts = now()
    table.insert(buf.lines, { t = ts, c = "mark", m = tag, r = "mark", lvl = SEV.INFO, mark = true })
    if #buf.lines > (buf.max or 2000) then table.remove(buf.lines, 1) end
    buf.version = (buf.version or 0) + 1
    if self._frame and self._frame:IsShown() then
        self._lastBufVersion = nil; self:_Refresh(true)
    end
end

-- Install a single global hook on Utils to capture all anim logs
local function ensureHook()
    local U = CLN.Utils
    if not U or U._animLogHooked then return end
    U._animLogHooked = true
    U._origLogAnimDebug = U._origLogAnimDebug or U.LogAnimDebug
    U._origLogAnimDebugEx = U._origLogAnimDebugEx or U.LogAnimDebugEx
    U._origLogDebug = U._origLogDebug or U.LogDebug
    U.LogAnimDebug = function(utils, a, b)
        CLN._insideUtilsLogHook = true
        if U._origLogAnimDebug then pcall(U._origLogAnimDebug, utils, a, b) end
        CLN._insideUtilsLogHook = false
        local hasCat = (b ~= nil)
        local cat = hasCat and tostring(a) or nil
        local msg = hasCat and tostring(b) or tostring(a)
        pushLine(cat, msg, nil, "anim")
    end
    U.LogAnimDebugEx = function(utils, a, b, session)
        CLN._insideUtilsLogHook = true
        if U._origLogAnimDebugEx then pcall(U._origLogAnimDebugEx, utils, a, b, session) end
        CLN._insideUtilsLogHook = false
        local cat, msg, sess
        if b ~= nil then
            cat = tostring(a); msg = tostring(b); sess = session and tostring(session) or nil
        else
            cat = nil; msg = tostring(a); sess = b and tostring(b) or nil
        end
        pushLine(cat, msg, sess, "anim")
    end
    if type(U.LogDebug) == "function" then
        U.LogDebug = function(utils, text)
            CLN._insideUtilsLogHook = true
            if U._origLogDebug then pcall(U._origLogDebug, utils, text) end
            CLN._insideUtilsLogHook = false
            pushLine("debug", tostring(text), nil, "debug")
        end
    end
    -- Hook addon Print (CLN:Print) to capture app logs that don't go through Utils
    if CLN and type(CLN.Print) == "function" and not CLN._origAddonPrint then
        CLN._origAddonPrint = CLN.Print
        CLN.Print = function(self, ...)
            -- Reentrancy guard: Utils hooks (LogAnimDebug, LogDebug) already push
            -- to LogsWindow directly, then call Logger:debug which calls CLN:Print.
            -- Skip the pushLine here when we're already inside a Utils hook to avoid
            -- duplicate entries.
            if not CLN._insideUtilsLogHook then
                local parts = {}
                for i = 1, select('#', ...) do parts[#parts+1] = tostring(select(i, ...)) end
                local msg = table.concat(parts, " ")
                local lvl = detectSeverity(msg)
                local cat = extractLoggerCategory(msg) or "app"
                local clean = stripLoggerPrefix(msg)
                pushLine(cat, clean, nil, "addon", lvl)
            end
            -- Always call the original Print so messages reach the chat frame
            if CLN._origAddonPrint then
                CLN._origAddonPrint(self, ...)
            end
        end
    end
    -- Hook global print — deferred until log window is first shown
    -- (see LW:Show / LW:Hide in LogsWindow.lua for install/restore)
end

local _printHookInstalled = false

local function installPrintHook()
    if _printHookInstalled then return end
    _printHookInstalled = true
    if not _G.__CLN_ORIG_PRINT then
        _G.__CLN_ORIG_PRINT = _G.print
        _G.print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts+1] = tostring(select(i, ...)) end
            local msg = table.concat(parts, " ")
            pushLine("print", msg, nil, "print")
            if _G.__CLN_ORIG_PRINT then _G.__CLN_ORIG_PRINT(...) end
            return
        end
    end
end

local function uninstallPrintHook()
    if not _printHookInstalled then return end
    _printHookInstalled = false
    if _G.__CLN_ORIG_PRINT then
        _G.print = _G.__CLN_ORIG_PRINT
        _G.__CLN_ORIG_PRINT = nil
    end
end

-- Install hooks as soon as this file loads so early logs are captured
pcall(function()
    if CLN and CLN.Utils then
        ensureHook()
    else
        if C_Timer and C_Timer.After then C_Timer.After(0, ensureHook) end
    end
end)

-- Shared with LogsView.lua and LogsWindow.lua, which load after this file.
LW._shared = {
    SEV = SEV,
    SEV_COLORS = SEV_COLORS,
    SEV_LETTERS = SEV_LETTERS,
    TABLE_ROW_HEIGHT = TABLE_ROW_HEIGHT,
    TABLE_ROW_POOL = TABLE_ROW_POOL,
    TABLE_COL_DEFS = TABLE_COL_DEFS,
    now = now,
    ensureHook = ensureHook,
    installPrintHook = installPrintHook,
    uninstallPrintHook = uninstallPrintHook,
}
