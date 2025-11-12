---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = {}
CLN.ReplayFrame = ReplayFrame

-- Pure helpers namespace
ReplayFrame.Pure = ReplayFrame.Pure or {}

-- Lightweight debug logger (disabled unless profile.debugMode is true)
function ReplayFrame:Debug(...)
    local ok = CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode
    if not ok then return end
    local args = {...}
    local strs = {}
    for i, arg in ipairs(args) do
        strs[i] = tostring(arg)
    end
    CLN:Print("|cff87CEEb[DEBUG]|r |cff87CEEb" .. table.concat(strs, " "))
end

-- ============================================================================
-- INITIALIZATION AND BINDING
-- ============================================================================

-- Track if the user explicitly hid the window while audio is playing
ReplayFrame.userHidden = false

-- Defer binding to after addon init to ensure globals exist
local function CLN_InitEditModeBinding()
    if ReplayFrame and ReplayFrame.BindBlizzardEditMode then
        ReplayFrame:BindBlizzardEditMode()
    end
end

if CreateFrame then
    local binder = CreateFrame("Frame")
    binder:RegisterEvent("PLAYER_LOGIN")
    binder:SetScript("OnEvent", function()
        CLN_InitEditModeBinding()
    end)
end

-- ============================================================================
-- CORE REPLAY FRAME LOGIC
-- ============================================================================

-- Removed GetFirstLine; use ToSingleLine for UI strings

-- Convert any multi-line WoW-formatted string to a clean single line suitable for headers (pure)
function ReplayFrame.Pure.ToSingleLine(text)
    if not text or type(text) ~= "string" then return text end
    local s = text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|H.-|h", ""):gsub("|h", "")
    s = s:gsub("|n", " ")
    s = s:gsub("\r\n", " "):gsub("\r", " "):gsub("\n", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

function ReplayFrame:ToSingleLine(text)
    return ReplayFrame.Pure.ToSingleLine(text)
end

-- Pure: choose header text given state
function ReplayFrame.Pure.BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
    local total = (playingTitle and 1 or 0) + (qcount or 0)
    if total <= 0 then
        return "Conversations"
    end
    if collapsed then
        local title = ReplayFrame.Pure.ToSingleLine(playingTitle or "")
        if title == nil or title == "" then title = "Conversations" end
        if npcName and not isQuest and title ~= "" then
            title = npcName .. ": " .. title
        end
        return string.format("%s (%d)", title, total)
    else
        return string.format("Conversations (%d)", total)
    end
end

-- Pure: label/tooltip formatting for queue entries
function ReplayFrame.Pure.FormatEntryLabel(npcName, content, isQuest)
    local safeContent = content or ""
    if isQuest then
        if safeContent ~= "" then
            return npcName and (npcName .. " — " .. safeContent) or safeContent
        end
        return npcName or "Unknown"
    else
        local single = ReplayFrame.Pure.ToSingleLine(safeContent)
        if npcName and single ~= "" then
            return npcName .. ": " .. single
        elseif npcName then
            return npcName
        else
            return (single ~= "" and single) or "Unknown"
        end
    end
end

function ReplayFrame.Pure.FormatEntryTooltip(npcName, content)
    local safeContent = content or ""
    if npcName and safeContent ~= "" then
        return npcName .. ": " .. safeContent
    end
    return safeContent ~= "" and safeContent or (npcName or "")
end

-- Header truncation: compute max width once and truncate consistently
function ReplayFrame:ApplyHeaderTruncation(fs, text)
    if not (fs and text) then return end
    -- Set desired text first so fs:GetWidth() reflects the anchored region width
    fs:SetText(text)
    local maxW = 0
    if fs.GetWidth then maxW = fs:GetWidth() or 0 end
    maxW = math.max(40, maxW)
    if self.TruncateToWidth then
        self:TruncateToWidth(fs, text, maxW)
    end
end

-- Pure: choose talk animation id based on punctuation proportions; rng optional
function ReplayFrame.Pure.ChooseTalkAnimIdForText(text, rng)
    local s = ReplayFrame.Pure.ToSingleLine(text or "") or ""
    -- Count sentences (rough): split on . ! ?
    local total = 0
    local _ = s:gsub("[%.%!%?]+", function() total = total + 1 end)
    if total == 0 then total = 1 end
    local q = 0; _ = s:gsub("%?", function() q = q + 1 end)
    local e = 0; _ = s:gsub("%!", function() e = e + 1 end)
    local pQ = math.min(1, math.max(0, q / total))
    local pE = math.min(1, math.max(0, e / total))
    local sum = pQ + pE
    if sum > 1 then pQ = pQ / sum; pE = pE / sum end
    local remaining = math.max(0, 1 - (pQ + pE))
    -- subdued maps to 60 as well; kept for conceptual parity
    local pSubdued = remaining * 0.75
    local pNormal = remaining * 0.25
    local draw = (type(rng) == "function") and rng() or math.random()
    if draw < pE then
        return 64
    elseif draw < (pE + pQ) then
        return 65
    else
        return 60
    end
end

-- Helper: Try to resolve an NPC name from saved DB by npcId
function ReplayFrame:GetNpcNameById(npcId)
    if not npcId then return nil end
    self._npcNameCache = self._npcNameCache or {}
    local loc = CLN.locale or "enUS"
    local byLoc = self._npcNameCache[loc]
    if byLoc and byLoc[npcId] ~= nil then return byLoc[npcId] end
    local db = type(NpcInfoDB) == "table" and NpcInfoDB or nil
    local name = nil
    if db and db[npcId] and db[npcId][loc] and db[npcId][loc].name then
        name = db[npcId][loc].name
    end
    if not self._npcNameCache[loc] then self._npcNameCache[loc] = {} end
    self._npcNameCache[loc][npcId] = name -- cache misses as nil to avoid re-lookup churn
    return name
end

-- Build a normalized list of entries for the queue view
-- Each entry: { isPlaying=bool, queueIndex=number|nil, label=string, tooltip=string }
function ReplayFrame:BuildQueueEntries()
    local entries = {}
    local now = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    if now and (now.title or now.questId) then
    local isQuest = not not now.questId
    local npcName = self:GetNpcNameById(now.npcId)
    local content = now.title
    local label = ReplayFrame.Pure.FormatEntryLabel(npcName, content, isQuest)
    local tooltip = ReplayFrame.Pure.FormatEntryTooltip(npcName, content)

        table.insert(entries, { isPlaying = true, label = label, tooltip = tooltip })
    end

    if CLN.questsQueue then
        for i, q in ipairs(CLN.questsQueue) do
            local npcName = self:GetNpcNameById(q.npcId)
            local questTitle = q.title
            local label = ReplayFrame.Pure.FormatEntryLabel(npcName, questTitle, true)
            local tooltip = ReplayFrame.Pure.FormatEntryTooltip(npcName, questTitle)
            table.insert(entries, { queueIndex = i, label = label, tooltip = tooltip })
        end
    end

    return entries
end

-- Build or refresh the queue data provider used by the ScrollBox
function ReplayFrame:RefreshQueueDataProvider()
    if not (self.SetQueueData and self.QueueListFrame) then return end

    local entries = self:BuildQueueEntries()
    local nowPlayingIndex = (entries[1] and entries[1].isPlaying) and 1 or nil

    -- Compute how many rows fit, and keep the latest that fit (always include now playing)
    local rowsFit = 6
    if self.ContentFrame and self.ContentFrame.GetHeight then
        local h = self.ContentFrame:GetHeight() or 0
        rowsFit = math.max(1, math.floor((h - 36 - 8) / 24))
    end
    local selected = {}
    if #entries <= rowsFit then
        selected = entries
    else
        if nowPlayingIndex then
            -- Always include now playing, plus most recent others from the end
            table.insert(selected, entries[nowPlayingIndex])
            local needed = rowsFit - 1
            for idx = #entries, 1, -1 do
                if needed <= 0 then break end
                if idx ~= nowPlayingIndex then
                    table.insert(selected, entries[idx])
                    needed = needed - 1
                end
            end
            -- Keep selected in a sensible order: now playing first, rest newest last
            -- Reverse tail so newest appears at bottom
            if #selected > 1 then
                local head = selected[1]
                local tail = {}
                for i = 2, #selected do table.insert(tail, selected[i]) end
                local rev = {}
                for i = #tail, 1, -1 do table.insert(rev, tail[i]) end
                selected = { head }
                for _, v in ipairs(rev) do table.insert(selected, v) end
            end
        else
            -- No now playing: just take the last rowsFit items in order
            for i = math.max(1, #entries - rowsFit + 1), #entries do
                table.insert(selected, entries[i])
            end
        end
    end

    -- Feed directly to manual list (no scrolling)
    self:SetQueueData(selected)
end

-- Mark queue data dirty; coalesce refreshes to avoid churn during bursts
function ReplayFrame:MarkQueueDirty()
    self._queueDirty = true
    local nowT = (type(GetTime) == "function") and GetTime() or 0
    self._queueDirtyAt = nowT
    -- Optionally schedule a near-future refresh if frame is visible
    if C_Timer and C_Timer.After then
        -- Use a very short delay to coalesce multiple marks in the same frame
        C_Timer.After(0.05, function()
            -- Only refresh if still dirty and frame exists
            if self._queueDirty then
                self._queueDirty = false
                self:RefreshQueueDataProvider()
                if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
            end
        end)
    end
end

-- =============================
-- Visibility and header helpers
-- =============================

-- Centralized header builder (wraps pure version)
function ReplayFrame:BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
    return ReplayFrame.Pure.BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
end

-- Show/hide frame, user-hidden/minimized handling; returns true if visible and should continue
function ReplayFrame:UpdateVisibility()
    if (not self._forceShow) and (not self:IsShowReplayFrameToggleIsEnabled() or not CLN.VoiceoverPlayer.currentlyPlaying) then
        if (self.DisplayFrame) then self.DisplayFrame:Hide() end
        return false
    end

    if (not self._forceShow) and (not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty()) then
        if (self.DisplayFrame) then self.DisplayFrame:Hide() end
        if self.MinButton then self.MinButton:Hide() end
        self.userHidden = false
        return false
    end

    if (not self._forceShow) and (self:IsDisplayFrameHideNeeded()) then
        if self.DisplayFrame then self.DisplayFrame:Hide() end
        return false
    end

    -- Respect user-hidden during playback: keep minimized indicator instead of reopening
    if (not self._forceShow) and self.userHidden and self:IsVoiceoverCurrenltyPlaying() then
        self:EnsureMinimizedButton()
        if self.MinButton then self.MinButton:Show() end
        return false
    end

    self:UpdateParent()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    if self.MinButton then self.MinButton:Hide() end
    self:CheckAndShowModel()
    self.userHidden = false
    return true
end

-- List refresh debounce/dirty handling
function ReplayFrame:RefreshListIfNeeded(sig, nowT)
    local needRefresh = false
    if self._lastDisplaySig == sig then
        local dt = nowT - (self._lastDisplaySigT or 0)
        if dt >= 0.25 then
            needRefresh = true
        end
    else
        needRefresh = true
    end
    if self._queueDirty then
        needRefresh = true
        self._queueDirty = false
    end
    if needRefresh then
        self:RefreshQueueDataProvider()
        if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
        self._lastDisplaySig = sig
        self._lastDisplaySigT = nowT
    end
end

-- Visible + playing animation update helper
function ReplayFrame:UpdateAnimationsIfNeeded()
    if self:IsVoiceoverCurrenltyPlaying() and self.NpcModelFrame and self.NpcModelFrame:IsShown()
        and self.UpdateConversationAnimation then
        CLN.Utils:LogAnimDebug("UpdateDisplayFrame - calling UpdateConversationAnimation (visible+playing)")
        self:UpdateConversationAnimation()
    else
        CLN.Utils:LogAnimDebug("UpdateDisplayFrame - skipping UpdateConversationAnimation (not visible or not playing)")
    end
end

-- Main update function for the display frame
function ReplayFrame:UpdateDisplayFrame()
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
    local collapsed = self.CollapseButton and self.CollapseButton._collapsed or false
    local w = self.DisplayFrame and self.DisplayFrame.GetWidth and math.floor((self.DisplayFrame:GetWidth() or 0) + 0.5) or 0
    local h = self.DisplayFrame and self.DisplayFrame.GetHeight and math.floor((self.DisplayFrame:GetHeight() or 0) + 0.5) or 0
    local handle = cur and cur.soundHandle or nil
    local title = cur and cur.title or nil
    local playing = cur and cur.isPlaying and cur:isPlaying() or false
    local sig = table.concat({ tostring(handle), tostring(title or ""), qcount, collapsed and 1 or 0, w, h, playing and 1 or 0 }, ":")
    local nowT = GetTime and GetTime() or 0

    -- Early visibility checks and show/min logic
    if not self:UpdateVisibility() then return end
    if (self.HeaderText) then
        local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
        local cur2 = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        local playingTitle = cur2 and cur2.title or nil
        local npcName = cur2 and self:GetNpcNameById(cur2.npcId) or nil
        local isQuest = cur2 and cur2.questId or nil
        local collapsed2 = self.CollapseButton and self.CollapseButton._collapsed
        local header = self:BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed2)
        self:ApplyHeaderTruncation(self.HeaderText, header)
    end

    -- Refresh the ScrollBox list from current state
    -- Refresh list if needed
    self:RefreshListIfNeeded(sig, nowT)

    -- Animation updates gated by visibility and playback
    self:UpdateAnimationsIfNeeded()

end

-- Update display frame state
function ReplayFrame:UpdateDisplayFrameState()
    if self._editMode or self._isDragging then return end
    self:GetDisplayFrame()
    self:UpdateDisplayFrame()
end

-- ============================================================================
-- ACCESSIBILITY AND SCALING
-- ============================================================================

-- Get accessibility text scale from CVars
function ReplayFrame:GetAccessibilityTextScale()
    if C_CVar and C_CVar.GetCVar then
        local keys = { "uiTextScale", "textScale", "uiTextSize" }
        for _, key in ipairs(keys) do
            local ok, val = pcall(C_CVar.GetCVar, key)
            if ok and val then
                local num = tonumber(val)
                if num and num > 0 then
                    return num
                end
            end
        end
    end
    return 1
end

-- Apply text scaling to queue and header text
function ReplayFrame:ApplyQueueTextScale()
    local userScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
    local a11y = self:GetAccessibilityTextScale() or 1
    local finalScale = math.max(0.5, math.min(2.0, userScale * a11y))

    -- Skip if effectively unchanged (epsilon)
    if self._lastQueueTextScale and math.abs((self._lastQueueTextScale or 0) - finalScale) < 0.001 then
        return
    end
    self._lastQueueTextScale = finalScale

    -- Header
    if self.HeaderText and self.DisplayFrame then
        local h = self.DisplayFrame:GetHeight() or 165
        local base = math.max(10, math.min(20, math.floor(h / 8)))
        self.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", base * finalScale, "")
    end

    -- Active rows only
    if self.QueueScrollBox then
        local baseHeight = 12
        -- Manual rows only
        if self.QueueRows and #self.QueueRows > 0 then
            for _, row in ipairs(self.QueueRows) do
                if row:IsShown() and row.text then
                    local _, _, flags = row.text:GetFont()
                    row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)
                    -- Re-fit the text to the new size/scale
                    if self.FitRowText then self:FitRowText(row) end
                end
                if row:IsShown() and row.bulletTex and row.bulletTex.SetSize then
                    local sz = math.max(3, math.floor((baseHeight * finalScale) * 0.33))
                    row.bulletTex:SetSize(sz, sz)
                end
            end
        end
    end
end

-- Modules are loaded via .toc; dev-time loadfile fallbacks removed for clarity.
