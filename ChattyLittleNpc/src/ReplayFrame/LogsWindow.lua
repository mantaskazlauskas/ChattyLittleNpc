---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- LogsWindow: standalone viewer for animation/debug logs with native filters.
-- Integrates with Utils.ShouldLogAnimDebug and CLN.db.profile.debugAnimCategories.

ReplayFrame = ReplayFrame or {}
ReplayFrame.LogsWindow = ReplayFrame.LogsWindow or {}
local LW = ReplayFrame.LogsWindow

-- Persistent in-session buffer (shared across UI opens)
CLN._AnimLogBuffer = CLN._AnimLogBuffer or { lines = {}, max = 2000, cats = {} }

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

local function pushLine(cat, text, sess, src)
    local buf = CLN._AnimLogBuffer
    local ts = now()
    table.insert(buf.lines, { t = ts, c = cat, s = sess, m = text, r = src })
    if #buf.lines > (buf.max or 2000) then table.remove(buf.lines, 1) end
    addCategory(cat)
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
        -- Call original for printing/legacy behavior
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
    -- Hook Utils.LogDebug
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
            -- Avoid double-capturing lines already handled via Utils hooks
            if not (string.find(msg, "[ANIM]", 1, true) or string.find(msg, "[DEBUG]", 1, true)) then
                pushLine("app", msg, nil, "addon")
            end
            -- Always suppress chat mirroring; logs live in LogsWindow only
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
            -- Do not double-capture Utils:LogAnimDebug; it already uses CLN:Print, not raw print.
            pushLine("print", msg, nil, "print")
            -- Do not echo to chat; suppress global print output now that LogsWindow captures it
            return
        end
    end
end

-- Install hooks as soon as this file loads so early logs are captured
pcall(function()
    -- Delay slightly if addon not fully initialized
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

-- Formatting helpers
local function fmtTime(t)
    local secs = t or 0
    return string.format("%06.3f", secs)
end

local function lineMatchesFilters(line)
    -- Pause only affects refresh cadence
    -- Apply session filter
    if LW._followSession then
        local cur = getActiveSessionId()
        if cur and line.s and tostring(line.s) ~= tostring(cur) then return false end
    elseif LW._sessionFilter and LW._sessionFilter ~= "" then
        local sf = tostring(LW._sessionFilter)
        local sess = line.s and tostring(line.s) or ""
        if not string.find(sess, sf, 1, true) then return false end
    end
    -- Category filters: use global Utils.ShouldLogAnimDebug by default
    local U = CLN and CLN.Utils
    local useGlobal = (LW._useGlobal ~= false)
    -- Always allow raw print/debug/addon lines regardless of global anim categories
    local src = line.r
    local bypassCats = (src == "print" or src == "debug" or src == "addon")
    if (not bypassCats) and useGlobal and U and U.ShouldLogAnimDebug then
        local ok, pass = pcall(U.ShouldLogAnimDebug, U, line.c)
        if ok and not pass then return false end
    else
        -- Local overrides via LW._localCats map: { all=true } or { camera=true, host=true }
        local cats = LW._localCats
        if cats then
            if cats.all == true then
                -- Always allow
            else
                local key = line.c and string.lower(line.c) or "uncategorized"
                if cats[key] ~= true then return false end
            end
        end
    end
    -- Include/exclude uncategorized if requested
    if (line.c == nil or line.c == "") and LW._includeUncat == false then return false end
    -- Text search (plain by default)
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
    -- Build dynamic category set from buffer and from config
    local set = {}
    for k,_ in pairs(CLN._AnimLogBuffer.cats or {}) do set[k] = true end
    local profCats = CLN.db and CLN.db.profile and CLN.db.profile.debugAnimCategories
    if type(profCats) == "table" then
        for k,v in pairs(profCats) do if v == true and k ~= "all" then set[k] = true end end
    elseif type(profCats) == "string" then
        for token in string.lower(profCats):gmatch("[^,%s]+") do set[token] = true end
    end
    -- Render into UI list
    if not self._catContainer then return end
    for i = 1, #self._catButtons or 0 do if self._catButtons[i] then self._catButtons[i]:Hide() end end
    self._catButtons = {}
    local y = -4
    local function addCheck(text, getter, setter)
        local cb = CreateFrame("CheckButton", nil, self._catContainer, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", self._catContainer, "TOPLEFT", 0, y)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(text)
        cb:SetScript("OnShow", function(self) if getter then self:SetChecked(getter()) end end)
        cb:SetScript("OnClick", function(self) if setter then setter(self:GetChecked()) end end)
        table.insert(self._catButtons, cb)
        y = y - 20
    end
    -- "All" toggle operates on global profile cats
    addCheck("All", function()
        local cats = CLN.db and CLN.db.profile and CLN.db.profile.debugAnimCategories
        return type(cats) == "table" and cats.all == true or (type(cats) == "string" and string.lower(cats) == "all")
    end, function(v)
        CLN.db.profile.debugAnimCategories = { all = v and true or false }
        LW:_Refresh()
    end)
    for name,_ in pairs(set) do
        local key = tostring(name)
        addCheck(key, function()
            local cats = CLN.db and CLN.db.profile and CLN.db.profile.debugAnimCategories
            if type(cats) == "table" then return cats[key] == true end
            if type(cats) == "string" then return string.find("," .. string.lower(cats) .. ",", "," .. string.lower(key) .. ",", 1, true) ~= nil end
            return true -- default allow
        end, function(v)
            -- Normalize into table form for precise control
            local cats = CLN.db.profile.debugAnimCategories
            if type(cats) ~= "table" then cats = {}; CLN.db.profile.debugAnimCategories = cats end
            cats.all = false
            cats[key] = v and true or nil
            LW:_Refresh()
        end)
    end
    local h = math.max(140, -y + 8)
    self._catContainer:SetHeight(h)
end

function LW:_FormatLines()
    local out = {}
    for i = 1, #CLN._AnimLogBuffer.lines do
        local L = CLN._AnimLogBuffer.lines[i]
        if lineMatchesFilters(L) then
            local timeStr = self._showTime ~= false and (fmtTime(L.t) .. " ") or ""
            local cat = L.c and ("[" .. tostring(L.c) .. "] ") or (self._includeUncat == false and "" or "[uncategorized] ")
            local sess = L.s and ("[sess:" .. tostring(L.s) .. "] ") or ""
            table.insert(out, string.format("%s%s%s%s", timeStr, cat, sess, tostring(L.m)))
        end
    end
    return table.concat(out, "\n")
end

function LW:_Refresh()
    if not self._frame or not self._frame:IsShown() then return end
    if not self._auto then return end
    if not self._edit then return end
    -- Throttle refresh to reduce churn
    local t = now()
    local throttle = self._throttleSec or 0.2
    if self._lastRefresh and (t - self._lastRefresh) < throttle then return end
    self._lastRefresh = t
    local txt = self:_FormatLines()
    self._edit:SetText(txt)
    if self._autoScroll ~= false then
        local n = (self._edit.GetNumLetters and self._edit:GetNumLetters()) or string.len(txt)
        if self._edit.SetCursorPosition and n then self._edit:SetCursorPosition(n) end
    end
end

local function addLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    fs:SetText(text)
    return fs
end

function LW:Create()
    if self._frame then return self._frame end
    ensureHook()

    local f = CreateFrame("Frame", "CLN_AnimLogsWindow", UIParent, "BackdropTemplate")
    -- Restore persisted placement if available
    local prof = CLN and CLN.db and CLN.db.profile or nil
    local cfg = prof and (prof.logsWindow or {}) or {}
    local ww, hh = tonumber(cfg.width) or 880, tonumber(cfg.height) or 520
    f:SetSize(ww, hh)
    if cfg.point and cfg.relPoint and cfg.x and cfg.y then
        pcall(f.ClearAllPoints, f)
        pcall(f.SetPoint, f, cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:Hide()
    -- Move window by dragging the title bar
    f:SetMovable(true)
    f:EnableMouse(true)
    local dragBar = CreateFrame("Frame", nil, f)
    dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(28)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() f:StartMoving() end)
    dragBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- Persist position and size
        local p, rel, rp, x, y = f:GetPoint(1)
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.logsWindow = CLN.db.profile.logsWindow or {}
            local lw = CLN.db.profile.logsWindow
            lw.point, lw.relPoint, lw.x, lw.y = p, rp, x, y
            local w2, h2 = f:GetSize()
            lw.width, lw.height = w2, h2
        end
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("Chatty Little NPC — Animation Logs")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    close:SetScript("OnClick", function() f:Hide() end)

    -- Left controls panel
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    left:SetWidth(240)
    -- Ensure controls draw above backdrop
    left:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Right logs view
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    right:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Enable toggles
    local enableDbg = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    enableDbg:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -4)
    enableDbg.text = enableDbg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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

    -- Use global filter toggle
    local useGlobal = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    useGlobal:SetPoint("TOPLEFT", enableDbg, "BOTTOMLEFT", 0, -6)
    useGlobal.text = useGlobal:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    useGlobal.text:SetPoint("LEFT", useGlobal, "RIGHT", 2, 0)
    useGlobal.text:SetText("Use global category filter")
    useGlobal:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Respect Utils.ShouldLogAnimDebug categories from Options.")
        GameTooltip:Show()
    end)
    useGlobal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    useGlobal:SetScript("OnShow", function(self) self:SetChecked(LW._useGlobal ~= false) end)
    useGlobal:SetScript("OnClick", function(self) LW._useGlobal = self:GetChecked() and true or false; LW:_Refresh() end)

    -- Session filter controls
    addLabel(left, "Session filter", 0, -56)
    local follow = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    follow:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -74)
    follow.text = follow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    follow.text:SetPoint("LEFT", follow, "RIGHT", 2, 0)
    follow.text:SetText("Follow active model session")
    follow:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show only logs tagged with the current model session.")
        GameTooltip:Show()
    end)
    follow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    follow:SetScript("OnShow", function(self) self:SetChecked(LW._followSession == true) end)
    follow:SetScript("OnClick", function(self) LW._followSession = self:GetChecked() and true or false; LW:_Refresh() end)

    local sessBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    sessBox:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -100)
    sessBox:SetSize(200, 22)
    sessBox:SetAutoFocus(false)
    sessBox:SetScript("OnShow", function(self) self:SetText(LW._sessionFilter or "") end)
    sessBox:SetScript("OnTextChanged", function(self) LW._sessionFilter = self:GetText() or ""; LW:_Refresh() end)

    -- Text search
    addLabel(left, "Search", 0, -132)
    local searchBox = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    searchBox:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -150)
    searchBox:SetSize(200, 22)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnShow", function(self) self:SetText(LW._textFilter or "") end)
    searchBox:SetScript("OnTextChanged", function(self) LW._textFilter = self:GetText() or ""; LW:_Refresh() end)
    local csChk = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    csChk:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -176)
    csChk.text = csChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    csChk.text:SetPoint("LEFT", csChk, "RIGHT", 2, 0)
    csChk.text:SetText("Case sensitive")
    csChk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("When enabled, search matches letter case.")
        GameTooltip:Show()
    end)
    csChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    csChk:SetScript("OnShow", function(self) self:SetChecked(LW._filterCaseSensitive == true) end)
    csChk:SetScript("OnClick", function(self) LW._filterCaseSensitive = self:GetChecked() and true or false; LW:_Refresh() end)

    -- Category checkboxes container
    addLabel(left, "Categories (global)", 0, -204)
    local catScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
    catScroll:SetPoint("TOPLEFT", left, "TOPLEFT", 0, -222)
    catScroll:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -28, 60)
    local catPanel = CreateFrame("Frame", nil, catScroll)
    catPanel:SetPoint("TOPLEFT", catScroll, "TOPLEFT", 0, 0)
    catPanel:SetWidth(200)
    catPanel:SetHeight(200)
    catScroll:SetScrollChild(catPanel)
    LW._catContainer = catPanel
    LW._catButtons = {}

    -- Bottom controls
    local refreshBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, 10)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() LW:_RebuildCategoryList(); LW:_Refresh() end)

    local clearBtn = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() CLN._AnimLogBuffer.lines = {}; LW:_Refresh() end)

    local includeUncat = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
    includeUncat:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    includeUncat.text = includeUncat:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    includeUncat.text:SetPoint("LEFT", includeUncat, "RIGHT", 2, 0)
    includeUncat.text:SetText("Uncategorized")
    includeUncat:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Include lines with no category tag.")
        GameTooltip:Show()
    end)
    includeUncat:SetScript("OnLeave", function() GameTooltip:Hide() end)
    includeUncat:SetScript("OnShow", function(self) self:SetChecked(LW._includeUncat ~= false) end)
    includeUncat:SetScript("OnClick", function(self) LW._includeUncat = self:GetChecked() and true or false; LW:_Refresh() end)

    -- Right side: Logs view and controls
    -- Presets row (top of right panel)
    local presets = CreateFrame("Frame", nil, right)
    presets:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -2)
    presets:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, -2)
    presets:SetSize(400, 24)
    presets:SetFrameLevel(right:GetFrameLevel() + 2)

    local function setCats(tbl)
        if not (CLN and CLN.db and CLN.db.profile) then return end
        CLN.db.profile.debugAnimCategories = tbl
        LW:_RebuildCategoryList(); LW:_Refresh()
    end
    local bAll = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bAll:SetSize(70, 20); bAll:SetPoint("LEFT", presets, "LEFT", 0, 0)
    bAll:SetText("All")
    bAll:SetScript("OnClick", function() setCats({ all = true }) end)
    local bCam = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bCam:SetSize(100, 20); bCam:SetPoint("LEFT", bAll, "RIGHT", 6, 0)
    bCam:SetText("Camera+Frame")
    bCam:SetScript("OnClick", function() setCats({ all = false, camera = true, framing = true }) end)
    local bHost = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bHost:SetSize(100, 20); bHost:SetPoint("LEFT", bCam, "RIGHT", 6, 0)
    bHost:SetText("Host+Loader")
    bHost:SetScript("OnClick", function() setCats({ all = false, host = true, loader = true }) end)
    local bNone = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    bNone:SetSize(70, 20); bNone:SetPoint("LEFT", bHost, "RIGHT", 6, 0)
    bNone:SetText("None")
    bNone:SetScript("OnClick", function() setCats({ all = false }) end)

    -- Buffer size and Export, aligned to right on presets row
    local bufLabel = presets:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bufLabel:SetPoint("RIGHT", presets, "RIGHT", -160, 0)
    bufLabel:SetText("Buffer")
    local bufBox = CreateFrame("EditBox", nil, presets, "InputBoxTemplate")
    bufBox:SetAutoFocus(false)
    bufBox:SetPoint("LEFT", bufLabel, "RIGHT", 4, 0)
    bufBox:SetSize(60, 20)
    bufBox:SetScript("OnShow", function(self) self:SetText(tostring(CLN._AnimLogBuffer.max or 2000)) end)
    bufBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText() or "")
        if v and v >= 100 and v <= 20000 then CLN._AnimLogBuffer.max = math.floor(v) end
        self:ClearFocus()
    end)

    local exportBtn = CreateFrame("Button", nil, presets, "UIPanelButtonTemplate")
    exportBtn:SetSize(90, 20)
    exportBtn:SetPoint("LEFT", bufBox, "RIGHT", 8, 0)
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
                arr[#arr+1] = string.format('{"t":%s,"c":%s,"s":%s,"r":%s,"m":"%s"}',
                    tostring(L.t or 0),
                    L.c and ('"'..esc(L.c)..'"') or 'null',
                    L.s and ('"'..esc(L.s)..'"') or 'null',
                    L.r and ('"'..esc(L.r)..'"') or 'null',
                    esc(L.m))
            end
        end
        local json = "[" .. table.concat(arr, ",") .. "]"
        LW._edit:SetText(json)
        LW._edit:HighlightText(0, -1)
        LW._edit:SetFocus()
    end)

    -- Scrollable text area below presets
    local sf = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", presets, "BOTTOMLEFT", 0, 6)
    sf:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -24, 32)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal or SystemFont_Small or GameFontHighlightSmall)
    eb:SetAutoFocus(false)
    eb:SetWidth(right:GetWidth() - 24)
    sf:SetScrollChild(eb)
    LW._edit = eb

    -- Keep edit box width in sync with container
    right:SetScript("OnSizeChanged", function()
        if LW._edit and right:GetWidth() then
            LW._edit:SetWidth(math.max(200, right:GetWidth() - 24))
        end
    end)

    local row = CreateFrame("Frame", nil, right)
    row:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 0)
    row:SetSize(400, 28)
    row:SetFrameLevel(right:GetFrameLevel() + 2)
    local copyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copyBtn:SetSize(80, 22)
    copyBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    copyBtn:SetText("Copy All")
    copyBtn:SetScript("OnClick", function()
        if LW._edit then LW._edit:HighlightText(0, -1); LW._edit:SetFocus() end
    end)
    local copyVisBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    copyVisBtn:SetSize(90, 22)
    copyVisBtn:SetPoint("LEFT", copyBtn, "RIGHT", 6, 0)
    copyVisBtn:SetText("Copy Visible")
    copyVisBtn:SetScript("OnClick", function()
        if LW._edit then LW._edit:SetText(LW:_FormatLines()); LW._edit:HighlightText(0, -1); LW._edit:SetFocus() end
    end)
    local autoChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    autoChk:SetPoint("LEFT", copyVisBtn, "RIGHT", 8, 0)
    autoChk.text = autoChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoChk.text:SetPoint("LEFT", autoChk, "RIGHT", 2, 0)
    autoChk.text:SetText("Auto")
    autoChk:SetScript("OnShow", function(self) self:SetChecked(LW._auto ~= false) end)
    autoChk:SetScript("OnClick", function(self) LW._auto = self:GetChecked() and true or false; LW:_Refresh() end)
    local pauseChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    pauseChk:SetPoint("LEFT", autoChk, "RIGHT", 14, 0)
    pauseChk.text = pauseChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pauseChk.text:SetPoint("LEFT", pauseChk, "RIGHT", 2, 0)
    pauseChk.text:SetText("Pause")
    pauseChk:SetScript("OnShow", function(self) self:SetChecked(LW._auto == false) end)
    pauseChk:SetScript("OnClick", function(self) LW._auto = (not self:GetChecked()) end)

    local showTimeChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    showTimeChk:SetPoint("LEFT", pauseChk, "RIGHT", 14, 0)
    showTimeChk.text = showTimeChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    showTimeChk.text:SetPoint("LEFT", showTimeChk, "RIGHT", 2, 0)
    showTimeChk.text:SetText("Time")
    showTimeChk:SetScript("OnShow", function(self) self:SetChecked(LW._showTime ~= false) end)
    showTimeChk:SetScript("OnClick", function(self) LW._showTime = self:GetChecked() and true or false; LW:_Refresh() end)

    local autoScrollChk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    autoScrollChk:SetPoint("LEFT", showTimeChk, "RIGHT", 12, 0)
    autoScrollChk.text = autoScrollChk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    autoScrollChk.text:SetPoint("LEFT", autoScrollChk, "RIGHT", 2, 0)
    autoScrollChk.text:SetText("Auto-scroll")
    autoScrollChk:SetScript("OnShow", function(self) self:SetChecked(LW._autoScroll ~= false) end)
    autoScrollChk:SetScript("OnClick", function(self) LW._autoScroll = self:GetChecked() and true or false end)

    -- (moved) presets/buffer/export now live above the scroll area

    -- Frame scripts
    f:SetScript("OnShow", function()
        LW._auto = (LW._auto ~= false)
        LW:_RebuildCategoryList()
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
