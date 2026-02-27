---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- Native VO Whitelist Popup
-- Shown after user pauses addon VO while NPC speech was detected.
-- Lists recently speaking NPCs and lets the user add them to the auto-pause
-- whitelist so future speech from those NPCs pauses the addon automatically.
-- ============================================================================

local POPUP_ROW_HEIGHT = 28
local POPUP_WIDTH = 340
local MAX_ROWS = 6
local POPUP_PADDING = 14

--- Show the whitelist popup with a list of un-asked NPCs.
---@param npcs table[] Array of { npcId, npcName, text }
function ReplayFrame:ShowNativeVOWhitelistPopup(npcs)
    if not npcs or #npcs == 0 then return end
    -- Don't show during combat
    if InCombatLockdown and InCombatLockdown() then return end
    -- Close any existing popup
    if self._voWhitelistPopup then self._voWhitelistPopup:Hide() end

    local rowCount = math.min(#npcs, MAX_ROWS)
    -- Header(title+subtitle ~44) + rows + separator(8) + buttons(32) + footer link(20) + padding
    local totalH = 44 + rowCount * POPUP_ROW_HEIGHT + 8 + 32 + 20 + POPUP_PADDING * 2

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(POPUP_WIDTH, totalH)
    f:SetPoint("TOP", UIParent, "TOP", 0, -100)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.25, 0.22, 0.20, 0.7)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Fade in
    f:SetAlpha(0)
    local fadeStart = GetTime and GetTime() or 0
    f:SetScript("OnUpdate", function(self)
        local elapsed = ((GetTime and GetTime()) or 0) - fadeStart
        if elapsed >= 0.2 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
        else
            self:SetAlpha(elapsed / 0.2)
        end
    end)

    -- Close (X) button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetSize(20, 20)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -POPUP_PADDING)
    title:SetText("Voiced NPCs Detected")
    title:SetTextColor(1.0, 0.82, 0.0)

    -- Subtitle
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Select NPCs whose native voice should pause addon playback.")
    sub:SetTextColor(0.65, 0.65, 0.65)
    sub:SetWidth(POPUP_WIDTH - POPUP_PADDING * 2 - 20)
    sub:SetJustifyH("CENTER")
    if sub.SetWordWrap then sub:SetWordWrap(true) end

    -- Separator line below subtitle
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -10, -6)
    sep:SetPoint("TOPRIGHT", sub, "BOTTOMRIGHT", 10, -6)
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- NPC rows with checkboxes
    local checks = {}
    local yOfs = -(44 + 8 + POPUP_PADDING)
    for i = 1, rowCount do
        local npc = npcs[i]

        -- Row highlight background
        local rowBg = f:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, yOfs + 2)
        rowBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, yOfs + 2)
        rowBg:SetHeight(POPUP_ROW_HEIGHT)
        if i % 2 == 0 then
            rowBg:SetColorTexture(1, 1, 1, 0.03)
        else
            rowBg:SetColorTexture(0, 0, 0, 0)
        end

        local row = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        row:SetPoint("TOPLEFT", f, "TOPLEFT", POPUP_PADDING, yOfs)
        row:SetSize(22, 22)
        row:SetChecked(true)
        row._npcData = npc

        -- NPC name (prominent)
        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("LEFT", row, "RIGHT", 6, 0)
        nameLabel:SetTextColor(1, 1, 1)
        nameLabel:SetText(npc.npcName or "Unknown")

        -- Text preview (subdued, right-aligned)
        local preview = npc.text or ""
        if #preview > 40 then preview = preview:sub(1, 37) .. "..." end
        local previewLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewLabel:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
        previewLabel:SetPoint("RIGHT", f, "RIGHT", -POPUP_PADDING, 0)
        previewLabel:SetJustifyH("RIGHT")
        previewLabel:SetTextColor(0.5, 0.5, 0.5)
        if previewLabel.SetWordWrap then previewLabel:SetWordWrap(false) end
        if previewLabel.SetMaxLines then previewLabel:SetMaxLines(1) end
        previewLabel:SetText(preview)

        checks[i] = row
        yOfs = yOfs - POPUP_ROW_HEIGHT
    end

    -- Button area
    local btnY = POPUP_PADDING + 20 + 4 -- above the footer link
    local btnWidth = 120

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(btnWidth, 26)
    addBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, btnY)
    addBtn:SetText("Add Selected")
    addBtn:SetScript("OnClick", function()
        self:OnWhitelistPopupAccept(checks)
        f:Hide()
        self:TryAutoResumeAfterWhitelist()
    end)

    local dismissBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dismissBtn:SetSize(btnWidth, 26)
    dismissBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, btnY)
    dismissBtn:SetText("Dismiss")
    dismissBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    -- "Don't show again" footer link
    local neverBtn = CreateFrame("Button", nil, f)
    neverBtn:SetSize(POPUP_WIDTH - POPUP_PADDING * 2, 16)
    neverBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, POPUP_PADDING - 2)
    local neverText = neverBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    neverText:SetAllPoints()
    neverText:SetText("|cff666666Don't ask about these NPCs again|r")
    neverText:SetJustifyH("CENTER")
    neverBtn:SetScript("OnEnter", function()
        neverText:SetText("|cffaaaaaaDon't ask about these NPCs again|r")
    end)
    neverBtn:SetScript("OnLeave", function()
        neverText:SetText("|cff666666Don't ask about these NPCs again|r")
    end)
    neverBtn:SetScript("OnClick", function()
        -- Mark all listed NPCs as permanently dismissed
        if not CLN.db.profile.nativeVODismissed then CLN.db.profile.nativeVODismissed = {} end
        local dismissed = CLN.db.profile.nativeVODismissed
        for _, cb in ipairs(checks) do
            local npc = cb._npcData
            if npc then
                if npc.npcName then dismissed[npc.npcName] = true end
                local ids = npc.npcIds or {}
                for _, id in ipairs(ids) do dismissed[id] = true end
            end
        end
        f:Hide()
    end)

    f:Show()
    self._voWhitelistPopup = f
end

--- Handle "Add Selected" — add checked NPCs to whitelist, unchecked to dismissed.
function ReplayFrame:OnWhitelistPopupAccept(checks)
    if not CLN.db.profile.nativeVOWhitelist then CLN.db.profile.nativeVOWhitelist = {} end
    if not CLN.db.profile.nativeVODismissed then CLN.db.profile.nativeVODismissed = {} end
    local wl = CLN.db.profile.nativeVOWhitelist
    local dismissed = CLN.db.profile.nativeVODismissed

    for _, cb in ipairs(checks) do
        local npc = cb._npcData
        if npc then
            if cb:GetChecked() then
                -- Add to whitelist by name and all known IDs
                if npc.npcName then wl[npc.npcName] = true end
                local ids = npc.npcIds or {}
                for _, id in ipairs(ids) do wl[id] = true end
                -- Contribute to global collection for community baking
                if CLN.ContributeVoicedNpc then
                    CLN:ContributeVoicedNpc(npc.npcName, ids)
                end
                if CLN.Logger then
                    local idStr = #ids > 0 and table.concat(ids, ",") or "nil"
                    CLN.Logger:info("Whitelisted NPC: " .. tostring(npc.npcName) .. " (ids=" .. idStr .. ")", false, CLN.Utils.LogCategories.loader)
                end
            else
                -- Unchecked = dismiss (don't ask again)
                if npc.npcName then dismissed[npc.npcName] = true end
                local ids = npc.npcIds or {}
                for _, id in ipairs(ids) do dismissed[id] = true end
            end
        end
    end
end

--- Handle "Dismiss" — mark all listed NPCs as dismissed.
--- Reset dismissed NPCs so the popup will ask about them again.
function ReplayFrame:ResetDismissedNpcs()
    if CLN.db.profile then
        CLN.db.profile.nativeVODismissed = {}
    end
    if CLN.Logger then
        CLN.Logger:info("Cleared dismissed NPC list — popup will ask about all NPCs again.", false, CLN.Utils.LogCategories.loader)
    end
end

--- Remove a specific NPC from the whitelist (by name or ID).
function ReplayFrame:RemoveFromVOWhitelist(npcKey)
    if not npcKey then return end
    local wl = CLN.db.profile.nativeVOWhitelist
    if wl then wl[npcKey] = nil end
    -- Also clear from dismissed so they can be re-asked
    local dismissed = CLN.db.profile.nativeVODismissed
    if dismissed then dismissed[npcKey] = nil end
end

--- Auto-resume playback after whitelist popup if no NPC is still talking.
--- Waits a short moment to let any ongoing speech settle.
function ReplayFrame:TryAutoResumeAfterWhitelist()
    local vp = CLN and CLN.VoiceoverPlayer
    if not (vp and vp:IsPaused()) then return end
    -- Check if any NPC is still talking (recent speech within last 3 seconds)
    local eh = CLN and CLN.EventHandler
    local buf = eh and eh._recentNpcSpeeches
    local now = GetTime and GetTime() or 0
    local stillTalking = false
    if buf then
        for i = #buf, 1, -1 do
            local entry = buf[i]
            -- If an NPC spoke within the last 3 seconds, assume still talking
            if (now - (entry.timestamp or 0)) < 3 then
                stillTalking = true
                break
            end
        end
    end
    if stillTalking then
        -- Wait a bit and try again
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if vp:IsPaused() then
                    self:TryAutoResumeAfterWhitelist()
                end
            end)
        end
    else
        -- No one is talking — resume
        vp:ResumePlayback()
        if CLN.Logger then
            CLN.Logger:debug("Auto-resumed after whitelist popup (no active NPC speech)", false, CLN.Utils.LogCategories.loader)
        end
    end
end
