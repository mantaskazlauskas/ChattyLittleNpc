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

local POPUP_ROW_HEIGHT = 22
local POPUP_WIDTH = 320
local MAX_ROWS = 6

--- Show the whitelist popup with a list of un-asked NPCs.
---@param npcs table[] Array of { npcId, npcName, text }
function ReplayFrame:ShowNativeVOWhitelistPopup(npcs)
    if not npcs or #npcs == 0 then return end
    -- Don't show during combat
    if InCombatLockdown and InCombatLockdown() then return end
    -- Close any existing popup
    if self._voWhitelistPopup then self._voWhitelistPopup:Hide() end

    local f = CreateFrame("Frame", "CLN_VOWhitelistPopup", UIParent, "BackdropTemplate")
    local rowCount = math.min(#npcs, MAX_ROWS)
    local totalH = 70 + rowCount * POPUP_ROW_HEIGHT + 36
    f:SetSize(POPUP_WIDTH, totalH)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
    f:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.6)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("Add voiced NPCs?")
    title:SetTextColor(1.0, 0.82, 0.0)

    -- Subtitle
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("These NPCs spoke recently. Check to auto-pause for them.")
    sub:SetTextColor(0.8, 0.8, 0.8)
    sub:SetWidth(POPUP_WIDTH - 20)
    sub:SetJustifyH("CENTER")
    if sub.SetWordWrap then sub:SetWordWrap(true) end

    -- NPC rows with checkboxes
    local checks = {}
    local yOfs = -60
    for i = 1, rowCount do
        local npc = npcs[i]
        local row = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, yOfs)
        row:SetSize(22, 22)
        row:SetChecked(true)
        row._npcData = npc

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", row, "RIGHT", 4, 0)
        label:SetWidth(POPUP_WIDTH - 50)
        label:SetJustifyH("LEFT")
        if label.SetWordWrap then label:SetWordWrap(false) end
        if label.SetMaxLines then label:SetMaxLines(1) end
        -- Show NPC name and truncated text
        local preview = npc.text or ""
        if #preview > 50 then preview = preview:sub(1, 47) .. "..." end
        label:SetText("|cffffffff" .. (npc.npcName or "Unknown") .. "|r |cff888888— " .. preview .. "|r")

        checks[i] = row
        yOfs = yOfs - POPUP_ROW_HEIGHT
    end

    -- Buttons
    local btnWidth = 110
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(btnWidth, 24)
    addBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
    addBtn:SetText("Add Selected")
    addBtn:SetScript("OnClick", function()
        self:OnWhitelistPopupAccept(checks)
        f:Hide()
        -- Auto-resume if user had paused and no NPC is still talking
        self:TryAutoResumeAfterWhitelist()
    end)

    local dismissBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dismissBtn:SetSize(btnWidth, 24)
    dismissBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
    dismissBtn:SetText("Not Now")
    dismissBtn:SetScript("OnClick", function()
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
