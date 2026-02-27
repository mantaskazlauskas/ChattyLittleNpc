---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- LogsWindow: standalone viewer for animation/debug logs with severity and category
-- filters, resize support, and improved layout.

ReplayFrame = ReplayFrame or {}
ReplayFrame.LogsWindow = ReplayFrame.LogsWindow or {}
local LW = ReplayFrame.LogsWindow

-- Severity constants (matching Logger.Level)
local SEV = { ERROR = 0, WARN = 1, INFO = 2, DEBUG = 3 }
local SEV_NAMES = { [0] = "ERROR", [1] = "WARN", [2] = "INFO", [3] = "DEBUG" }
local SEV_COLORS = {
    [0] = "|cffff5555",
    [1] = "|cffffff55",
    [2] = "|cffcccccc",
    [3] = "|cff87CEEb",
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

-- Install a single global hook on Utils to capture all anim logs
local function ensureHook()
    local U = CLN and CLN.Utils
    if not U or U._animLogHooked then return end
    U._animLogHooked = true
    U._origLogAnimDebug = U._origLogAnimDebug or U.LogAnimDebug
    U._origLogAnimDebugEx = U._origLogAnimDebugEx or U.LogAnimDebugEx
    U._origLogDebug = U._origLogDebug or U.LogDebug
    U.LogAnimDebug = function(utils, a, b)
        if U._origLogAnimDebug then pcall(U._origLogAnimDebug, utils, a, b) end
        local hasCat = (b ~= nil)
        local cat = hasCat and tostring(a) or nil
        local msg = hasCat and tostring(b) or tostring(a)
        pushLine(cat, msg, nil, "anim")
    end
    U.LogAnimDebugEx = function(utils, a, b, session)
        if U._origLogAnimDebugEx then pcall(U._origLogAnimDebugEx, utils, a, b, session) end
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
            if U._origLogDebug then pcall(U._origLogDebug, utils, text) end
            pushLine("debug", tostring(text), nil, "debug")
        end
    end
    -- Hook addon Print (CLN:Print) to capture app logs that don't go through Utils
    if CLN and type(CLN.Print) == "function" and not CLN._origAddonPrint then
        CLN._origAddonPrint = CLN.Print
        CLN.Print = function(self, ...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts+1] = tostring(select(i, ...)) end
            local msg = table.concat(parts, " ")
            if not (string.find(msg, "[ANIM]", 1, true) or string.find(msg, "[DEBUG]", 1, true)) then
                -- Detect severity before stripping the color-coded prefix
                local lvl = detectSeverity(msg)
                -- Extract the real Logger category (e.g. "ui", "system") from the prefix
                local cat = extractLoggerCategory(msg) or "app"
                -- Strip the redundant color-coded severity+category prefix
                local clean = stripLoggerPrefix(msg)
                pushLine(cat, clean, nil, "addon", lvl)
            end
            return
        end
    end
    -- Hook global print to capture instrumentation
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

-- Install hooks as soon as this file loads so early logs are captured
pcall(function()
    if CLN and CLN.Utils then
        ensureHook()
    else
        if C_Timer and C_Timer.After then C_Timer.After(0, ensureHook) end
    end
end)

local function getActiveSessionId()
    local rf = ReplayFrame
    local host = rf and rf.NpcModelFrame or nil
    if host then
        if host._sessionId then return tostring(host._sessionId) end
        local s = host._lastCamSnapshot
        if s and s.sessionId then return tostring(s.sessionId) end
    end
    return nil
end

local function fmtTime(t)
    local secs = t or 0
    return string.format("%06.3f", secs)
end

local function lineMatchesFilters(line)
    -- 1. Severity
    local lvl = line.lvl or SEV.INFO
    if lvl == SEV.ERROR and LW._showError == false then return false end
    if lvl == SEV.WARN  and LW._showWarn  == false then return false end
    if lvl == SEV.INFO  and LW._showInfo  == false then return false end
    if lvl == SEV.DEBUG and LW._showDebug == false then return false end
    -- 2. Source type
    local src = line.r or "addon"
    if src == "addon" and LW._showSrcAddon == false then return false end
    if src == "anim"  and LW._showSrcAnim  == false then return false end
    if src == "debug" and LW._showSrcDebug == false then return false end
    if src == "print" and LW._showSrcPrint == false then return false end
    -- 3. Category (local to LogsWindow, never reads profile)
    local cf = LW._catFilter
    if cf and cf.all ~= true then
        local key = line.c and string.lower(line.c) or "uncategorized"
        if cf[key] ~= true then return false end
    end
    -- 4. Session
    if LW._followSession then
        local cur = getActiveSessionId()
        if cur and line.s and tostring(line.s) ~= tostring(cur) then return false end
    elseif LW._sessionFilter and LW._sessionFilter ~= "" then
        local sf = tostring(LW._sessionFilter)
        local sess = line.s and tostring(line.s) or ""
        if not string.find(sess, sf, 1, true) then return false end
    end
    -- 5. Text search
    if LW._textFilter and LW._textFilter ~= "" then
        local needle = LW._textFilter
        local hay = tostring(line.m)
        if not LW._filterCaseSensitive then
            needle = string.lower(needle)
            hay = string.lower(hay)
        end
        if not string.find(hay, needle, 1, true) then return false end
    end
    return true
end

function LW:_RebuildCategoryList()
    -- Gather all categories from buffer + known LogCategories
    local set = {}
    for k, _ in pairs(CLN._AnimLogBuffer.cats or {}) do set[k] = true end
    local U = CLN and CLN.Utils
    if U and U.LogCategories then
        for _, v in pairs(U.LogCategories) do set[v] = true end
    end
    if not self._catContainer then return end
    for i = 1, #(self._catButtons or {}) do if self._catButtons[i] then self._catButtons[i]:Hide() end end
    self._catButtons = {}
    -- Initialize local category filter (default: show all)
    if not self._catFilter then self._catFilter = { all = true } end
    local cf = self._catFilter
    local y = -4
    local function addCheck(text, getter, setter)
        local cb = CreateFrame("CheckButton", nil, self._catContainer, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", self._catContainer, "TOPLEFT", 0, y)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(text)
        local get = getter
        local set = setter
        cb:SetScript("OnShow", function(self) if get then self:SetChecked(get()) end end)
        cb:SetScript("OnClick", function(self) if set then set(self:GetChecked()) end end)
        if get then cb:SetChecked(get()) end
        table.insert(self._catButtons, cb)
        y = y - 22
    end
    -- "All" toggle
    addCheck("All", function()
        return cf.all == true
    end, function(v)
        cf.all = v and true or false
        if v then
            for k, _ in pairs(set) do cf[string.lower(k)] = true end
        end
        LW._lastBufVersion = nil; LW:_RebuildCategoryList()
    end)
    -- Individual categories, sorted alphabetically
    local sorted = {}
    for name, _ in pairs(set) do sorted[#sorted + 1] = tostring(name) end
    table.sort(sorted)
    for _, key in ipairs(sorted) do
        local lk = string.lower(key)
        addCheck(key, function()
            return cf.all == true or cf[lk] == true
        end, function(v)
            cf.all = false
            cf[lk] = v and true or nil
            LW._lastBufVersion = nil; LW:_Refresh()
        end)
    end
    local h = math.max(100, -y + 8)
    self._catContainer:SetHeight(h)
end

function LW:_FormatLines()
    local out = {}
    local count = 0
    local sevLetters = { [0] = "E", [1] = "W", [2] = "I", [3] = "D" }
    for i = 1, #CLN._AnimLogBuffer.lines do
        local L = CLN._AnimLogBuffer.lines[i]
        if lineMatchesFilters(L) then
            count = count + 1
            local sevColor = SEV_COLORS[L.lvl] or "|cffcccccc"
            local sevLetter = sevLetters[L.lvl] or "I"
            local timeStr = self._showTime ~= false and ("|cff999999" .. fmtTime(L.t) .. "|r ") or ""
            local sevTag = sevColor .. sevLetter .. "|r "
            -- Build [source:category] or [source] tag
            local src = L.r or "addon"
            local cat = L.c or ""
            local tag
            if cat ~= "" and cat ~= src then
                tag = "|cff888888[" .. src .. ":" .. cat .. "]|r "
            elseif cat ~= "" then
                tag = "|cff888888[" .. cat .. "]|r "
            else
                tag = "|cff888888[" .. src .. "]|r "
            end
            local sess = L.s and ("|cff666666sess:" .. tostring(L.s) .. "|r ") or ""
            out[#out + 1] = timeStr .. sevTag .. tag .. sess .. tostring(L.m)
        end
    end
    return table.concat(out, "\n"), count
end

function LW:_Refresh(force)
    if not self._frame or not self._frame:IsShown() then return end
    -- A nil _lastBufVersion means a filter changed and needs re-render even if paused
    local filterChanged = (self._lastBufVersion == nil)
    if not force and not filterChanged and not self._auto then return end
    if not self._edit then return end
    local t = now()
    if not force and not filterChanged then
        local throttle = self._throttleSec or 0.25
        if self._lastRefresh and (t - self._lastRefresh) < throttle then return end
    end
    self._lastRefresh = t
    -- Skip if buffer unchanged since last render
    local curVer = CLN._AnimLogBuffer.version or 0
    if self._lastBufVersion == curVer then return end
    self._lastBufVersion = curVer
    local txt, count = self:_FormatLines()
    self._edit:SetText(txt)
    if self._lineCountLabel then
        self._lineCountLabel:SetText(count .. " / " .. #CLN._AnimLogBuffer.lines .. " lines")
    end
    if self._autoScroll ~= false then
        local n = (self._edit.GetNumLetters and self._edit:GetNumLetters()) or string.len(txt)
        if self._edit.SetCursorPosition and n then self._edit:SetCursorPosition(n) end
    end
end

-- Persist window position and size
local function saveFrameLayout(f)
    if not (CLN and CLN.db and CLN.db.profile) then return end
    local p, _, rp, x, y = f:GetPoint(1)
    CLN.db.profile.logsWindow = CLN.db.profile.logsWindow or {}
    local lw = CLN.db.profile.logsWindow
    lw.point, lw.relPoint, lw.x, lw.y = p, rp, x, y
    local w, h = f:GetSize()
    lw.width, lw.height = w, h
end

function LW:Create()
    if self._frame then return self._frame end
    ensureHook()

    local f = CreateFrame("Frame", "CLN_AnimLogsWindow", UIParent, "BackdropTemplate")
    f:SetClampedToScreen(true)
    local prof = CLN and CLN.db and CLN.db.profile or nil
    local cfg = prof and (prof.logsWindow or {}) or {}
    local ww, hh = tonumber(cfg.width) or 900, tonumber(cfg.height) or 600
    f:SetSize(ww, hh)
    if cfg.point and cfg.relPoint and cfg.x and cfg.y then
        pcall(f.ClearAllPoints, f)
        pcall(f.SetPoint, f, cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:Hide()

    -- Movable + resizable
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(700, 520, 1600, 1000)
    else
        if f.SetMinResize then f:SetMinResize(700, 520) end
        if f.SetMaxResize then f:SetMaxResize(1600, 1000) end
    end

    -- Drag bar (title region)
    local dragBar = CreateFrame("Frame", nil, f)
    dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(28)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() f:StartMoving() end)
    dragBar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); saveFrameLayout(f) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("Chatty Little NPC — Logs")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    close:SetScript("OnClick", function() f:Hide() end)

    -- Resize grip (bottom-right corner)
    local grip = CreateFrame("Frame", nil, f)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:SetSize(16, 16)
    grip:EnableMouse(true)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        saveFrameLayout(f)
        if LW._edit and LW._rightPanel then
            LW._edit:SetWidth(math.max(200, LW._rightPanel:GetWidth() - 24))
        end
    end)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnEnter", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight") end)
    grip:SetScript("OnLeave", function() gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up") end)

    -- ════════════════ LEFT PANEL ════════════════
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    left:SetWidth(210)
    left:SetFrameLevel(f:GetFrameLevel() + 1)

    -- ════════════════ RIGHT PANEL ════════════════
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    right:SetFrameLevel(f:GetFrameLevel() + 1)
    LW._rightPanel = right

    -- All left-panel elements are chained via relative anchors to avoid overlap.

    -- ── Enable debug toggle ──
    local enableDbg = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    enableDbg:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
    enableDbg.text = enableDbg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    enableDbg.text:SetPoint("LEFT", enableDbg, "RIGHT", 2, 0)
    enableDbg.text:SetText("Enable debug + anim logs")
    enableDbg:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Turns on debugMode and debugAnimations in settings.")
        GameTooltip:Show()
    end)
    enableDbg:SetScript("OnLeave", function() GameTooltip:Hide() end)
    enableDbg:SetScript("OnShow", function(self)
        local on = CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode and CLN.db.profile.debugAnimations
        self:SetChecked(on and true or false)
    end)
    enableDbg:SetScript("OnClick", function(self)
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugMode = self:GetChecked() and true or false
            CLN.db.profile.debugAnimations = self:GetChecked() and true or false
        end
    end)

    -- ── Severity section ──
    local sevLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sevLabel:SetPoint("TOPLEFT", enableDbg, "BOTTOMLEFT", 0, -8)
    sevLabel:SetText("Severity")

    local sevErrChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    sevErrChk:SetPoint("TOPLEFT", sevLabel, "BOTTOMLEFT", 0, -2)
    sevErrChk.text = sevErrChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sevErrChk.text:SetPoint("LEFT", sevErrChk, "RIGHT", 0, 0)
    sevErrChk.text:SetText("|cffff5555ERROR|r")
    sevErrChk:SetScript("OnShow", function(self) self:SetChecked(LW._showError ~= false) end)
    sevErrChk:SetScript("OnClick", function(self) LW._showError = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local sevWarnChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    sevWarnChk:SetPoint("LEFT", sevErrChk, "RIGHT", 60, 0)
    sevWarnChk.text = sevWarnChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sevWarnChk.text:SetPoint("LEFT", sevWarnChk, "RIGHT", 0, 0)
    sevWarnChk.text:SetText("|cffffff55WARN|r")
    sevWarnChk:SetScript("OnShow", function(self) self:SetChecked(LW._showWarn ~= false) end)
    sevWarnChk:SetScript("OnClick", function(self) LW._showWarn = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local sevInfoChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    sevInfoChk:SetPoint("TOPLEFT", sevErrChk, "BOTTOMLEFT", 0, -2)
    sevInfoChk.text = sevInfoChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sevInfoChk.text:SetPoint("LEFT", sevInfoChk, "RIGHT", 0, 0)
    sevInfoChk.text:SetText("|cffccccccINFO|r")
    sevInfoChk:SetScript("OnShow", function(self) self:SetChecked(LW._showInfo ~= false) end)
    sevInfoChk:SetScript("OnClick", function(self) LW._showInfo = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local sevDbgChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    sevDbgChk:SetPoint("LEFT", sevInfoChk, "RIGHT", 60, 0)
    sevDbgChk.text = sevDbgChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sevDbgChk.text:SetPoint("LEFT", sevDbgChk, "RIGHT", 0, 0)
    sevDbgChk.text:SetText("|cff87CEEbDEBUG|r")
    sevDbgChk:SetScript("OnShow", function(self) self:SetChecked(LW._showDebug ~= false) end)
    sevDbgChk:SetScript("OnClick", function(self) LW._showDebug = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    -- ── Source section ──
    local srcLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    srcLabel:SetPoint("TOPLEFT", sevInfoChk, "BOTTOMLEFT", 0, -8)
    srcLabel:SetText("Source")

    local srcAddonChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    srcAddonChk:SetPoint("TOPLEFT", srcLabel, "BOTTOMLEFT", 0, -2)
    srcAddonChk.text = srcAddonChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcAddonChk.text:SetPoint("LEFT", srcAddonChk, "RIGHT", 0, 0)
    srcAddonChk.text:SetText("Addon")
    srcAddonChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Log lines from the addon's Logger (CLN:Print).")
        GameTooltip:Show()
    end)
    srcAddonChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    srcAddonChk:SetScript("OnShow", function(self) self:SetChecked(LW._showSrcAddon ~= false) end)
    srcAddonChk:SetScript("OnClick", function(self) LW._showSrcAddon = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local srcAnimChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    srcAnimChk:SetPoint("LEFT", srcAddonChk, "RIGHT", 60, 0)
    srcAnimChk.text = srcAnimChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcAnimChk.text:SetPoint("LEFT", srcAnimChk, "RIGHT", 0, 0)
    srcAnimChk.text:SetText("Anim")
    srcAnimChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Animation debug lines (camera, framing, etc.).")
        GameTooltip:Show()
    end)
    srcAnimChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    srcAnimChk:SetScript("OnShow", function(self) self:SetChecked(LW._showSrcAnim ~= false) end)
    srcAnimChk:SetScript("OnClick", function(self) LW._showSrcAnim = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local srcDebugChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    srcDebugChk:SetPoint("TOPLEFT", srcAddonChk, "BOTTOMLEFT", 0, -2)
    srcDebugChk.text = srcDebugChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcDebugChk.text:SetPoint("LEFT", srcDebugChk, "RIGHT", 0, 0)
    srcDebugChk.text:SetText("Debug")
    srcDebugChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("General debug lines from Utils:LogDebug.")
        GameTooltip:Show()
    end)
    srcDebugChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    srcDebugChk:SetScript("OnShow", function(self) self:SetChecked(LW._showSrcDebug ~= false) end)
    srcDebugChk:SetScript("OnClick", function(self) LW._showSrcDebug = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local srcPrintChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    srcPrintChk:SetPoint("LEFT", srcDebugChk, "RIGHT", 60, 0)
    srcPrintChk.text = srcPrintChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcPrintChk.text:SetPoint("LEFT", srcPrintChk, "RIGHT", 0, 0)
    srcPrintChk.text:SetText("Print")
    srcPrintChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Raw print() output from Lua / other addons.")
        GameTooltip:Show()
    end)
    srcPrintChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    srcPrintChk:SetScript("OnShow", function(self) self:SetChecked(LW._showSrcPrint ~= false) end)
    srcPrintChk:SetScript("OnClick", function(self) LW._showSrcPrint = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    -- ── Session section ──
    local sessLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessLabel:SetPoint("TOPLEFT", srcDebugChk, "BOTTOMLEFT", 0, -8)
    sessLabel:SetText("Session")

    local followChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    followChk:SetPoint("TOPLEFT", sessLabel, "BOTTOMLEFT", 0, -2)
    followChk.text = followChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    followChk.text:SetPoint("LEFT", followChk, "RIGHT", 2, 0)
    followChk.text:SetText("Follow active session")
    followChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show only logs from the current model session.")
        GameTooltip:Show()
    end)
    followChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    followChk:SetScript("OnShow", function(self) self:SetChecked(LW._followSession == true) end)
    followChk:SetScript("OnClick", function(self) LW._followSession = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local sessBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    sessBox:SetPoint("TOPLEFT", followChk, "BOTTOMLEFT", 4, -2)
    sessBox:SetSize(190, 20)
    sessBox:SetAutoFocus(false)
    sessBox:SetScript("OnShow", function(self) self:SetText(LW._sessionFilter or "") end)
    sessBox:SetScript("OnTextChanged", function(self) LW._sessionFilter = self:GetText() or ""; LW._lastBufVersion = nil; LW:_Refresh() end)
    sessBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- ── Search section ──
    local searchLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", sessBox, "BOTTOMLEFT", -4, -8)
    searchLabel:SetText("Search")

    local searchBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    searchBox:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 4, -2)
    searchBox:SetSize(190, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnShow", function(self) self:SetText(LW._textFilter or "") end)
    searchBox:SetScript("OnTextChanged", function(self) LW._textFilter = self:GetText() or ""; LW._lastBufVersion = nil; LW:_Refresh() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local csChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    csChk:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -2)
    csChk.text = csChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    csChk.text:SetPoint("LEFT", csChk, "RIGHT", 2, 0)
    csChk.text:SetText("Case sensitive")
    csChk:SetScript("OnShow", function(self) self:SetChecked(LW._filterCaseSensitive == true) end)
    csChk:SetScript("OnClick", function(self) LW._filterCaseSensitive = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    -- ── Categories section ──
    local catLabel = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catLabel:SetPoint("TOPLEFT", csChk, "BOTTOMLEFT", 0, -8)
    catLabel:SetText("Categories")

    local catScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
    catScroll:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", 0, -4)
    catScroll:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 36)
    catScroll:SetWidth(190)
    local catPanel = CreateFrame("Frame", nil, catScroll)
    catPanel:SetPoint("TOPLEFT")
    catPanel:SetWidth(170)
    catPanel:SetHeight(200)
    catScroll:SetScrollChild(catPanel)
    LW._catContainer = catPanel
    LW._catButtons = {}

    -- ── Left bottom controls ──
    local refreshBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    refreshBtn:SetSize(68, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 4)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() LW:_RebuildCategoryList(); LW._lastBufVersion = nil; LW:_Refresh(true) end)

    local clearBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    clearBtn:SetSize(52, 22)
    clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 4, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        CLN._AnimLogBuffer.lines = {}
        CLN._AnimLogBuffer.cats = {}
        CLN._AnimLogBuffer.version = (CLN._AnimLogBuffer.version or 0) + 1
        LW._lastBufVersion = nil; LW:_Refresh(true)
    end)

    -- ════════════════ RIGHT PANEL CONTENT ════════════════

    -- ── Presets row (top) ──
    local presets = CreateFrame("Frame", nil, right)
    presets:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    presets:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
    presets:SetHeight(24)
    presets:SetFrameLevel(right:GetFrameLevel() + 2)

    local function setCats(tbl)
        LW._catFilter = tbl
        LW:_RebuildCategoryList(); LW._lastBufVersion = nil; LW:_Refresh()
    end
    local bAll = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bAll:SetSize(50, 20); bAll:SetPoint("LEFT", presets, "LEFT", 0, 0)
    bAll:SetText("All")
    bAll:SetScript("OnClick", function() setCats({ all = true }) end)

    local bCam = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bCam:SetSize(90, 20); bCam:SetPoint("LEFT", bAll, "RIGHT", 4, 0)
    bCam:SetText("Cam+Frame")
    bCam:SetScript("OnClick", function() setCats({ all = false, camera = true, framing = true }) end)

    local bHost = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bHost:SetSize(90, 20); bHost:SetPoint("LEFT", bCam, "RIGHT", 4, 0)
    bHost:SetText("Host+Load")
    bHost:SetScript("OnClick", function() setCats({ all = false, host = true, loader = true }) end)

    local bNone = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bNone:SetSize(50, 20); bNone:SetPoint("LEFT", bHost, "RIGHT", 4, 0)
    bNone:SetText("None")
    bNone:SetScript("OnClick", function() setCats({ all = false }) end)

    -- Buffer + Export (right-aligned on presets row)
    local exportBtn = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 20)
    exportBtn:SetPoint("RIGHT", presets, "RIGHT", 0, 0)
    exportBtn:SetText("Export JSON")
    exportBtn:SetScript("OnClick", function()
        if not LW._edit then return end
        local function esc(s)
            s = tostring(s)
            s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
            return s
        end
        local arr = {}
        for i = 1, #CLN._AnimLogBuffer.lines do
            local L = CLN._AnimLogBuffer.lines[i]
            if lineMatchesFilters(L) then
                arr[#arr + 1] = string.format('{"t":%s,"c":%s,"s":%s,"r":%s,"lvl":%s,"m":"%s"}',
                    tostring(L.t or 0),
                    L.c and ('"' .. esc(L.c) .. '"') or 'null',
                    L.s and ('"' .. esc(L.s) .. '"') or 'null',
                    L.r and ('"' .. esc(L.r) .. '"') or 'null',
                    tostring(L.lvl or 2),
                    esc(L.m))
            end
        end
        local json = "[" .. table.concat(arr, ",") .. "]"
        LW._edit:SetText(json)
        LW._edit:HighlightText(0, -1)
        LW._edit:SetFocus()
    end)

    local bufBox = CreateFrame("EditBox", nil, presets, "InputBoxTemplate")
    bufBox:SetAutoFocus(false)
    bufBox:SetSize(50, 20)
    bufBox:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
    bufBox:SetScript("OnShow", function(self) self:SetText(tostring(CLN._AnimLogBuffer.max or 2000)) end)
    bufBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText() or "")
        if v and v >= 100 and v <= 20000 then CLN._AnimLogBuffer.max = math.floor(v) end
        self:ClearFocus()
    end)
    bufBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local bufLabel = presets:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bufLabel:SetPoint("RIGHT", bufBox, "LEFT", -4, 0)
    bufLabel:SetText("Buf:")

    -- ── Scrollable log text area ──
    local sf = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", presets, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -24, 30)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal or SystemFont_Small or GameFontHighlightSmall)
    eb:SetAutoFocus(false)
    eb:SetWidth(math.max(200, right:GetWidth() - 24))
    sf:SetScrollChild(eb)
    LW._edit = eb

    right:SetScript("OnSizeChanged", function()
        if LW._edit and right:GetWidth() then
            LW._edit:SetWidth(math.max(200, right:GetWidth() - 24))
        end
    end)

    -- ── Bottom row ──
    local row = CreateFrame("Frame", nil, right)
    row:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 0)
    row:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    row:SetHeight(26)
    row:SetFrameLevel(right:GetFrameLevel() + 2)

    local copyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copyBtn:SetSize(70, 22)
    copyBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    copyBtn:SetText("Copy All")
    copyBtn:SetScript("OnClick", function()
        if LW._edit then LW._edit:HighlightText(0, -1); LW._edit:SetFocus() end
    end)

    local copyVisBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copyVisBtn:SetSize(76, 22)
    copyVisBtn:SetPoint("LEFT", copyBtn, "RIGHT", 4, 0)
    copyVisBtn:SetText("Copy Vis")
    copyVisBtn:SetScript("OnClick", function()
        if LW._edit then
            local txt = LW:_FormatLines()
            LW._edit:SetText(txt)
            LW._edit:HighlightText(0, -1)
            LW._edit:SetFocus()
        end
    end)

    local pauseChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    pauseChk:SetPoint("LEFT", copyVisBtn, "RIGHT", 10, 0)
    pauseChk.text = pauseChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pauseChk.text:SetPoint("LEFT", pauseChk, "RIGHT", 2, 0)
    pauseChk.text:SetText("Pause")
    pauseChk:SetScript("OnShow", function(self) self:SetChecked(LW._auto == false) end)
    pauseChk:SetScript("OnClick", function(self)
        LW._auto = not self:GetChecked()
        if LW._auto then LW._lastBufVersion = nil; LW:_Refresh() end
    end)

    local showTimeChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    showTimeChk:SetPoint("LEFT", pauseChk, "RIGHT", 12, 0)
    showTimeChk.text = showTimeChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showTimeChk.text:SetPoint("LEFT", showTimeChk, "RIGHT", 2, 0)
    showTimeChk.text:SetText("Time")
    showTimeChk:SetScript("OnShow", function(self) self:SetChecked(LW._showTime ~= false) end)
    showTimeChk:SetScript("OnClick", function(self) LW._showTime = self:GetChecked() and true or false; LW._lastBufVersion = nil; LW:_Refresh() end)

    local autoScrollChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    autoScrollChk:SetPoint("LEFT", showTimeChk, "RIGHT", 12, 0)
    autoScrollChk.text = autoScrollChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoScrollChk.text:SetPoint("LEFT", autoScrollChk, "RIGHT", 2, 0)
    autoScrollChk.text:SetText("Scroll")
    autoScrollChk:SetScript("OnShow", function(self) self:SetChecked(LW._autoScroll ~= false) end)
    autoScrollChk:SetScript("OnClick", function(self) LW._autoScroll = self:GetChecked() and true or false end)

    -- Line count (right-aligned)
    local lineCount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lineCount:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    lineCount:SetText("0 / 0 lines")
    lineCount:SetTextColor(0.6, 0.6, 0.6)
    LW._lineCountLabel = lineCount

    -- ════════════════ FRAME SCRIPTS ════════════════
    f:SetScript("OnShow", function()
        LW._auto = (LW._auto ~= false)
        LW:_RebuildCategoryList()
        LW._lastBufVersion = nil
        LW:_Refresh()
    end)
    f:SetScript("OnUpdate", function()
        if not f:IsShown() then return end
        if LW._auto then LW:_Refresh() end
    end)

    LW._frame = f
    return f
end

function LW:Show()
    local f = self:Create()
    f:Show()
end

function LW:Hide()
    if self._frame then self._frame:Hide() end
end

-- Slash command
SLASH_CLNLOGS1 = "/clnlogs"
SlashCmdList["CLNLOGS"] = function()
    if not LW._frame or not LW._frame:IsShown() then LW:Show() else LW:Hide() end
end
