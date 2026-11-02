---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Quest Info Panel
-- Small collapsible panel under (or above) the open quest dialog showing the
-- quest ID, dialog stage, NPC ID and whether the installed packs voice this stage.
-- Lives on UIParent and follows the dialog frame through PlayButton's anchor
-- helpers, like the play button does, so it works with DialogueUI as well.
-- ============================================================================

local Widgets = CLN.Widgets
local C, rgba = Widgets.Colors, Widgets.rgba

---@class QuestInfoPanel
local QuestInfoPanel = {}
CLN.QuestInfoPanel = QuestInfoPanel

local PANEL_WIDTH = 168
local HEADER_H    = 20
local ROW_H       = 18
local PAD         = 6
local LABEL_W     = 62
local GAP         = 4 -- between the panel and the dialog frame
local EXPANDED_H  = HEADER_H + PAD * 2 + ROW_H * 4

-- Same retry schedule as the play button: the dialog frame may show a little
-- after the quest event fires.
local ANCHOR_RECHECK_DELAYS = { 0, 0.1, 0.3, 0.6 }

local _frame = nil ---@type table|nil
local _gen = 0 -- bumped on every show/hide so stale anchor rechecks bail out

local function stageName(phase)
    local P = CLN.Utils.QuestPhases
    if phase == P.DESC then return "Description" end
    if phase == P.PROG then return "Progress" end
    if phase == P.COMP then return "Completion" end
    return tostring(phase)
end

--- What the panel shows for the open quest dialog, or nil when there is no quest.
---@return table|nil info { questId, stage, npcLabel, npcId, hasVoiceover }
function QuestInfoPanel:Collect(phase)
    local questId = GetQuestID and GetQuestID()
    if not questId or questId == 0 then return nil end

    local _, _, _, _, unitType, unitId = CLN:GetUnitInfo("npc")
    return {
        questId = questId,
        stage = stageName(phase),
        npcLabel = (unitType == "GameObject") and "Object ID" or "NPC ID",
        npcId = unitId,
        hasVoiceover = CLN:HasQuestVoiceover(questId, phase) and true or false,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame
-- ─────────────────────────────────────────────────────────────────────────────

local function setCopyValue(eb, value)
    eb._value = value
    eb:SetText(value)
    eb:SetCursorPosition(0)
end

local function createRow(f, label, copyable)
    local fs = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetWidth(LABEL_W)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(rgba(C.textMuted))
    fs:SetText(label)

    local value
    if copyable then
        value = Widgets.CreateCopyBox(f.body, "", PANEL_WIDTH - LABEL_W - PAD * 2, ROW_H - 2)
        value:SetFontObject("GameFontHighlightSmall")
        value:SetTextInsets(4, 4, 0, 0)
        -- CreateCopyBox restores the text it was made with; ours changes per quest
        value:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self._value or "")
                self:HighlightText()
            end
        end)
    else
        value = f.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetJustifyH("LEFT")
        value:SetHeight(ROW_H - 2)
    end
    table.insert(f.rows, { label = fs, value = value })
    return fs, value
end

--- Header on the side touching the dialog, rows on the far side, so the
--- panel opens away from the dialog whichever way it grows.
local function layout(f, growUp)
    f.growUp = growUp
    local header, sep = f.header, f.sep
    header:ClearAllPoints()
    sep:ClearAllPoints()
    if growUp then
        header:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        header:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        sep:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, HEADER_H)
        sep:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, HEADER_H)
    else
        header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        sep:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -HEADER_H)
        sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -HEADER_H)
    end

    local first = growUp and PAD or (HEADER_H + PAD)
    for i, row in ipairs(f.rows) do
        local top = -(first + (i - 1) * ROW_H)
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top - 3)
        row.value:ClearAllPoints()
        row.value:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + LABEL_W, top)
        row.value:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    end
end

local function applyCollapsed(f)
    local collapsed = CLN.db.profile.questInfoPanelCollapsed and true or false
    f.toggle:SetText(collapsed and "+" or "-")
    f.body:SetShown(not collapsed)
    f:SetHeight(collapsed and HEADER_H or EXPANDED_H)
end

local function createFrame()
    -- On UIParent, not the dialog frame: see the gamepad taint note in PlayButton.lua
    local f = CreateFrame("Frame", "ChattyLittleQuestInfoPanel", UIParent, "BackdropTemplate")
    f:SetWidth(PANEL_WIDTH)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    Widgets.ApplyBackdrop(f, C.windowBg, C.windowBorder)

    local header = CreateFrame("Button", nil, f)
    header:SetHeight(HEADER_H - 2)
    f.header = header
    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(rgba(C.rowHover))

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", header, "LEFT", PAD - 1, 0)
    title:SetTextColor(rgba(C.textHeader))
    title:SetText("Quest Info")

    local toggle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toggle:SetPoint("RIGHT", header, "RIGHT", -PAD, 0)
    toggle:SetTextColor(rgba(C.textMuted))
    f.toggle = toggle

    header:SetScript("OnClick", function()
        local collapsed = not CLN.db.profile.questInfoPanelCollapsed
        CLN.db.profile.questInfoPanelCollapsed = collapsed
        Widgets.PlayClick(not collapsed)
        applyCollapsed(f)
    end)
    header:SetScript("OnEnter", function(self)
        toggle:SetTextColor(rgba(C.accent))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Quest Info", 1, 1, 1)
        GameTooltip:AddLine("Click to " .. (CLN.db.profile.questInfoPanelCollapsed and "expand" or "collapse") .. ".", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click an ID to select it, then Ctrl+C to copy.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        toggle:SetTextColor(rgba(C.textMuted))
        GameTooltip:Hide()
    end)

    local body = CreateFrame("Frame", nil, f)
    body:SetAllPoints()
    f.body = body

    local sep = body:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(rgba(C.cardBorder))
    f.sep = sep

    f.rows = {}
    local _
    _, f.questId = createRow(f, "Quest ID", true)
    _, f.stage = createRow(f, "Stage", false)
    f.npcLabel, f.npcId = createRow(f, "NPC ID", true)
    _, f.voiceover = createRow(f, "Voiceover", false)

    layout(f, false)
    applyCollapsed(f)
    f:Hide()
    return f
end

local function fill(f, info)
    setCopyValue(f.questId, tostring(info.questId))
    f.stage:SetText(info.stage)
    f.npcLabel:SetText(info.npcLabel)
    setCopyValue(f.npcId, info.npcId and tostring(info.npcId) or "-")
    if info.hasVoiceover then
        f.voiceover:SetText("Available")
        f.voiceover:SetTextColor(0.35, 0.85, 0.35)
    else
        f.voiceover:SetText("Missing")
        f.voiceover:SetTextColor(1, 0.45, 0.35)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anchoring
-- ─────────────────────────────────────────────────────────────────────────────

--- Hang below the dialog's bottom-left corner and grow down, or sit on its
--- top-left corner and grow up when the expanded panel would run off the
--- bottom of the screen. Decided on the expanded height, so expanding never
--- needs to flip sides.
local function placeBeside(f, anchor)
    f:ClearAllPoints()
    local bottom = anchor:GetBottom()
    local scale = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local growUp = bottom and (bottom - EXPANDED_H - GAP) * scale < 0 or false
    if f.growUp ~= growUp then layout(f, growUp) end
    if growUp then
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, GAP)
    else
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -GAP)
    end
end

local function attach(f, anchor)
    CLN.PlayButton:ReleaseButton(f)
    placeBeside(f, anchor)
    f:Show() -- FollowAnchor takes the shown state as "wants to be shown"
    CLN.PlayButton:FollowAnchor(f, anchor)
end

local function recheckAnchor(f, gen, attempt)
    local delay = ANCHOR_RECHECK_DELAYS[attempt]
    if not delay then return end
    C_Timer.After(delay, function()
        if gen ~= _gen then return end -- shown for another quest page, or hidden
        local anchor, visible = CLN.PlayButton:ResolveDialogAnchor("quest")
        if not visible then
            recheckAnchor(f, gen, attempt + 1)
        elseif anchor ~= f._clnAnchor then
            attach(f, anchor)
        else
            placeBeside(f, anchor) -- the frame may have moved into place by now
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- Show the panel for the open quest dialog page (QUEST_DETAIL/PROGRESS/COMPLETE).
function QuestInfoPanel:ShowForQuest(phase)
    _gen = _gen + 1
    if CLN.db.profile.showQuestInfoPanel == false then
        self:Hide()
        return
    end
    local info = self:Collect(phase)
    local anchor, visible = CLN.PlayButton:ResolveDialogAnchor("quest")
    if not info or not anchor then
        self:Hide()
        return
    end

    _frame = _frame or createFrame()
    fill(_frame, info)
    applyCollapsed(_frame)
    attach(_frame, anchor)
    if not visible then
        recheckAnchor(_frame, _gen, 1)
    end
end

function QuestInfoPanel:Hide()
    _gen = _gen + 1
    if _frame then
        CLN.PlayButton:ReleaseButton(_frame)
    end
end
