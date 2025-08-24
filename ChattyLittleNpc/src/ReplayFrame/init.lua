---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = {}
CLN.ReplayFrame = ReplayFrame

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

-- Build or refresh the queue data provider used by the ScrollBox
function ReplayFrame:RefreshQueueDataProvider()
    if not self.QueueScrollBox then return end
    local provider = CreateDataProvider()

    -- Build a list of entries (now playing first, then queued)
    local entries = {}
    local nowPlayingIndex = nil
    if CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.title then
        local title = CLN.VoiceoverPlayer.currentlyPlaying.title
        table.insert(entries, { isPlaying = true, label = title, tooltip = title })
        nowPlayingIndex = 1
    end

    if CLN.questsQueue then
        for i, quest in ipairs(CLN.questsQueue) do
            if quest.title then
                table.insert(entries, { queueIndex = i, label = quest.title, tooltip = quest.title })
            end
        end
    end

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

    for _, item in ipairs(selected) do
        provider:Insert(item)
    end

    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition or nil
    self.QueueScrollBox:SetDataProvider(provider, retain)
end

-- Main update function for the display frame
function ReplayFrame:UpdateDisplayFrame()
    if (not self._forceShow) and (not self:IsShowReplayFrameToggleIsEnabled() or not CLN.VoiceoverPlayer.currentlyPlaying) then
        if (self.DisplayFrame) then
            self.DisplayFrame:Hide()
        end
        return
    end

    -- Hide Frame if there are no actively playing voiceover and no quests in queue
    if (not self._forceShow) and (not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty()) then
        if (self.DisplayFrame) then
            self.DisplayFrame:Hide()
        end
        if self.MinButton then self.MinButton:Hide() end
        self.userHidden = false
        return
    end

    if (not self._forceShow) and (self:IsDisplayFrameHideNeeded()) then
        self.DisplayFrame:Hide()
        return
    end

    if (not CLN.VoiceoverPlayer.currentlyPlaying.title) then
        CLN.VoiceoverPlayer.currentlyPlaying.title = CLN:GetTitleForQuestID(CLN.VoiceoverPlayer.currentlyPlaying.questId)

        if (CLN.db.profile.debugMode) then
            CLN:Print(
            "Getting missing title for quest id:",
            CLN.VoiceoverPlayer.currentlyPlaying.questId,
            ", title found is:",
            CLN.VoiceoverPlayer.currentlyPlaying.title)
        end
    end

    if (self.HeaderText) then
        local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
        local playingTitle = CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying.title or nil
        local playingCount = playingTitle and 1 or 0
        local total = playingCount + qcount
        local collapsed = self.CollapseButton and self.CollapseButton._collapsed
        if total > 0 then
            if collapsed and playingTitle then
                self.HeaderText:SetText(string.format("%s (%d)", playingTitle, total))
            else
                self.HeaderText:SetText(string.format("Conversation Queue (%d)", total))
            end
        else
            self.HeaderText:SetText("Conversation Queue")
        end
    end

    -- Refresh the ScrollBox list from current state
    self:RefreshQueueDataProvider()
    if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end

    -- Respect user-hidden during playback: keep minimized indicator instead of reopening
    if (not self._forceShow) and self.userHidden and self:IsVoiceoverCurrenltyPlaying() then
        self:EnsureMinimizedButton()
        self.MinButton:Show()
        return
    end

    self:UpdateParent()
    self.DisplayFrame:Show()
    if self.MinButton then self.MinButton:Hide() end
    self:CheckAndShowModel()
    self.userHidden = false
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

    -- Header
    if self.HeaderText and self.DisplayFrame then
        local h = self.DisplayFrame:GetHeight() or 165
        local base = math.max(10, math.min(20, math.floor(h / 8)))
        self.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", base * finalScale, "")
    end

    -- Active rows only
    if self.QueueScrollBox then
        local baseHeight = 12
        if ScrollUtil and ScrollUtil.IterateToActive then
            for _, row in ScrollUtil.IterateToActive(self.QueueScrollBox) do
                if row.text then
                    local _, _, flags = row.text:GetFont()
                    row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)
                end
                if row.bulletTex and row.bulletTex.SetSize then
                    local sz = math.max(3, math.floor((baseHeight * finalScale) * 0.33))
                    row.bulletTex:SetSize(sz, sz)
                end
            end
        end
    end
end

-- ============================================================================
-- MODULE LOADING
-- Load all other ReplayFrame modules
-- ============================================================================

-- Load Position management module
local positionModule = {}
local positionFile = CLN and CLN.GetAddonPath and CLN.GetAddonPath() .. "\\src\\ReplayFrame\\Position.lua"
if positionFile and loadfile and pcall(loadfile, positionFile) then
    -- Position module loaded
else
    -- Fallback: inline loading (for development)
    -- This would load the Position.lua functions if the file loading fails
end

-- Load UI creation module
local uiModule = {}
local uiFile = CLN and CLN.GetAddonPath and CLN.GetAddonPath() .. "\\src\\ReplayFrame\\UI.lua"
if uiFile and loadfile and pcall(loadfile, uiFile) then
    -- UI module loaded
else
    -- Fallback: inline loading (for development)
end

-- Load EditMode module
local editModeModule = {}
local editModeFile = CLN and CLN.GetAddonPath and CLN.GetAddonPath() .. "\\src\\ReplayFrame\\EditMode.lua"
if editModeFile and loadfile and pcall(loadfile, editModeFile) then
    -- EditMode module loaded
else
    -- Fallback: inline loading (for development)
end

-- Note: Since WoW addons use a different loading mechanism, the above file loading
-- won't work in practice. The modules will be loaded by the addon system through
-- the .toc file includes. The functions defined in the separate files will be
-- available because they all extend the same ReplayFrame table.
