-- LogsView.lua - Filters and draws the lines shown in the logs window.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local LW = ReplayFrame.LogsWindow
local Shared = LW._shared
local Widgets = CLN.Widgets
local SEV, SEV_COLORS, SEV_LETTERS = Shared.SEV, Shared.SEV_COLORS, Shared.SEV_LETTERS
local TABLE_ROW_HEIGHT = Shared.TABLE_ROW_HEIGHT
local now = Shared.now

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
    -- 5. Text search (prefix with ! to exclude matches)
    if LW._textFilter and LW._textFilter ~= "" then
        local raw = LW._textFilter
        local exclude = false
        if raw:sub(1, 1) == "!" and #raw > 1 then
            exclude = true
            raw = raw:sub(2)
        end
        local needle = raw
        local hay = tostring(line.m)
        if not LW._filterCaseSensitive then
            needle = string.lower(needle)
            hay = string.lower(hay)
        end
        local found = string.find(hay, needle, 1, true) ~= nil
        if exclude then
            if found then return false end
        else
            if not found then return false end
        end
    end
    return true
end

function LW:_RebuildCategoryList()
    -- Gather all categories from buffer + known LogCategories
    local set = {}
    for k, _ in pairs(CLN._AnimLogBuffer.cats or {}) do set[k] = true end
    for _, v in pairs(CLN.Utils.LogCategories) do set[v] = true end
    if not self._catContainer then return end
    for i = 1, #(self._catButtons or {}) do if self._catButtons[i] then self._catButtons[i]:Hide() end end
    self._catButtons = {}
    -- Initialize local category filter (default: show all)
    if not self._catFilter then self._catFilter = { all = true } end
    local cf = self._catFilter
    local y = -4
    local function addCheck(text, getter, setter)
        local cb = Widgets.CreateCheckButton(self._catContainer, text, "GameFontHighlightSmall")
        cb:SetPoint("TOPLEFT", self._catContainer, "TOPLEFT", 0, y)
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
    for i = 1, #CLN._AnimLogBuffer.lines do
        local L = CLN._AnimLogBuffer.lines[i]
        if L.mark then
            -- Render bookmark as a visible separator
            count = count + 1
            local ts = self._showTime ~= false and fmtTime(L.t) or ""
            out[#out + 1] = "|cffffff00════ " .. tostring(L.m) .. (ts ~= "" and (" (" .. ts .. ")") or "") .. " ════|r"
        elseif lineMatchesFilters(L) then
            count = count + 1
            local sevColor = SEV_COLORS[L.lvl] or "|cffcccccc"
            local sevLetter = SEV_LETTERS[L.lvl] or "I"
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
            local sess = L.s and ("|cff888888sess:" .. tostring(L.s) .. "|r ") or ""
            out[#out + 1] = timeStr .. sevTag .. tag .. sess .. tostring(L.m)
        end
    end
    return table.concat(out, "\n"), count
end

function LW:_GetFilteredLines()
    local filtered = {}
    for i = 1, #CLN._AnimLogBuffer.lines do
        local L = CLN._AnimLogBuffer.lines[i]
        if L.mark or lineMatchesFilters(L) then
            filtered[#filtered + 1] = L
        end
    end
    return filtered
end

function LW:_RefreshTable()
    if not self._tableContainer or not self._tableContainer:IsShown() then return end
    local rows = self._tableRows
    if not rows or not self._tableRowContainer then return end
    local filtered = self:_GetFilteredLines()
    local totalLines = #filtered
    self._lastFilteredCount = totalLines
    -- Calculate visible rows from container height
    local containerH = self._tableRowContainer:GetHeight()
    local visibleRows = math.max(1, math.floor(containerH / TABLE_ROW_HEIGHT))
    -- Auto-scroll to end if enabled and not scroll-paused
    if self._autoScroll ~= false and not self._scrollPaused then
        local maxOff = math.max(0, totalLines - visibleRows)
        self._tableScrollOffset = maxOff
    end
    -- Clamp scroll offset
    local maxOffset = math.max(0, totalLines - visibleRows)
    if (self._tableScrollOffset or 0) > maxOffset then self._tableScrollOffset = maxOffset end
    if (self._tableScrollOffset or 0) < 0 then self._tableScrollOffset = 0 end
    local offset = self._tableScrollOffset or 0
    for i = 1, #rows do
        local row = rows[i]
        local dataIdx = offset + i
        if dataIdx <= totalLines and i <= visibleRows then
            local L = filtered[dataIdx]
            row._lineData = L
            if L.mark then
                for j = 1, #row.cols do row.cols[j]:Hide() end
                row.markLabel:SetText("|cffffff00════ " .. tostring(L.m) .. " ════|r")
                row.markLabel:Show()
                row.bg:SetColorTexture(1, 0.8, 0, 0.08)
            else
                row.markLabel:Hide()
                for j = 1, #row.cols do row.cols[j]:Show() end
                row.cols[1]:SetText("|cff999999" .. fmtTime(L.t) .. "|r")
                local sevColor = SEV_COLORS[L.lvl] or "|cffcccccc"
                row.cols[2]:SetText(sevColor .. (SEV_LETTERS[L.lvl] or "I") .. "|r")
                row.cols[3]:SetText("|cff888888" .. (L.r or "") .. "|r")
                row.cols[4]:SetText("|cff888888" .. (L.c or "") .. "|r")
                row.cols[5]:SetText(tostring(L.m))
                row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
            end
            row:Show()
        else
            row._lineData = nil
            row:Hide()
        end
    end
    if self._lineCountLabel then
        self._lineCountLabel:SetText(totalLines .. " / " .. #CLN._AnimLogBuffer.lines .. " lines")
    end
end

function LW:_Refresh(force)
    if not self._frame or not self._frame:IsShown() then return end
    local filterChanged = (self._lastBufVersion == nil)
    if not force and not filterChanged and not self._auto then return end
    local t = now()
    if not force and not filterChanged then
        local throttle = self._throttleSec or 0.25
        if self._lastRefresh and (t - self._lastRefresh) < throttle then return end
    end
    self._lastRefresh = t
    local curVer = CLN._AnimLogBuffer.version or 0
    if self._lastBufVersion == curVer then return end
    -- Branch on view mode
    if self._viewMode == "table" then
        self._lastBufVersion = curVer
        self:_RefreshTable()
    else
        if not self._edit then return end
        -- When scroll-paused and not forced (e.g. filter change), skip the
        -- text update entirely.  Calling SetText() on a multiline EditBox
        -- inside a ScrollFrame causes WoW to scroll to the cursor (pos 0 =
        -- top), which fights the user's scroll position.  Leaving
        -- _lastBufVersion stale ensures we catch up as soon as the user
        -- scrolls back to the bottom and _scrollPaused clears.
        if self._scrollPaused and not force then
            return
        end
        self._lastBufVersion = curVer
        local txt, count = self:_FormatLines()
        -- Save scroll position before SetText for forced refresh while paused
        if self._scrollPaused and self._scrollFrame then
            self._restoreScrollPos = self._scrollFrame:GetVerticalScroll()
        end
        self._edit:SetText(txt)
        if self._lineCountLabel then
            self._lineCountLabel:SetText(count .. " / " .. #CLN._AnimLogBuffer.lines .. " lines")
        end
        if self._autoScroll ~= false and not self._scrollPaused then
            local n = (self._edit.GetNumLetters and self._edit:GetNumLetters()) or string.len(txt)
            if self._edit.SetCursorPosition and n then self._edit:SetCursorPosition(n) end
        end
    end
end

Shared.lineMatchesFilters = lineMatchesFilters
